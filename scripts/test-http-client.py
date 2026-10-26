#!/usr/bin/env python3
"""Native HTTP/HTTPS framing, streaming, cancellation and ownership checks.

All peers and certificates are private local fixtures; no provider is contacted.
"""
import json
import os
from pathlib import Path
import socket
import socketserver
import ssl
import struct
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
COMPILER = Path(os.environ.get('FLEX_COMPILER', ROOT / 'build/flex')).resolve()
checks = 0
requests = []


def response(body=b'hello', status=200, headers=b''):
    return (f'HTTP/1.1 {status} Fixture\r\nContent-Length: {len(body)}\r\n'.encode()
            + headers + b'\r\n' + body)


class Peer(socketserver.BaseRequestHandler):
    def handle(self):
        connection = self.request
        connection.settimeout(2)
        try:
            if self.server.context:
                connection = self.server.context.wrap_socket(connection, server_side=True)
            data = b''
            while b'\r\n\r\n' not in data and len(data) < 131072:
                chunk = connection.recv(8192)
                if not chunk:
                    return
                data += chunk
            raw, body = data.split(b'\r\n\r\n', 1)
            lines = raw.split(b'\r\n')
            method, target, version = lines[0].decode().split(' ')
            headers = dict(line.decode().split(': ', 1) for line in lines[1:])
            if target == '/reset':
                connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
                connection.close()
                return
            length = int(headers.get('Content-Length', 0))
            while len(body) < length:
                part = connection.recv(min(16384, length - len(body)))
                if not part:
                    return
                body += part
            requests.append((method, target, headers, body))
            path = target.split('?', 1)[0]
            if path == '/stall':
                time.sleep(.3)
                return
            if path == '/slow':
                connection.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello')
                time.sleep(.2)
                connection.sendall(b' world')
                return
            if path == '/echo':
                wire = response(body, headers=b'X-Test: echoed\r\n')
            elif path in ('/length', '/a/length'):
                wire = response(headers=b'X-Test: value\r\n')
            elif path == '/binary':
                wire = response(b'a\x00b\xffc')
            elif path in ('/large', '/large-chunk'):
                payload = bytes(range(256)) * 256 + b'tail'
                wire = response(payload)
                if path == '/large-chunk':
                    wire = b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n' + f'{len(payload):x}\r\n'.encode() + payload + b'\r\n0\r\n\r\n'
            elif path == '/chunked':
                wire = (b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
                        b'2;name=value\r\nhe\r\n3\r\nllo\r\n0\r\nX-Trailer: yes\r\n\r\n')
            elif path == '/interim':
                wire = (b'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </x>\r\n\r\n'
                        + response(b'ok'))
            elif path == '/head':
                wire = b'HTTP/1.1 200 OK\r\nContent-Length: 100000\r\n\r\n'
            elif path in ('/204', '/304'):
                wire = f'HTTP/1.1 {path[1:]} Fixture\r\nContent-Length: 99\r\n\r\n'.encode()
            elif path == '/404':
                wire = response(b'missing', 404)
            elif path == '/empty':
                wire = response(b'')
            elif path == '/close':
                wire = b'HTTP/1.0 200 OK\r\n\r\nhello'
            elif path in ('/redirect', '/a/b/redirect'):
                wire = response(b'', 302, b'Location: ../length?x=1\r\n')
            elif path == '/query':
                wire = response() if '?done=1' in target else response(b'', 302, b'Location: ?done=1\r\n')
            elif path == '/root':
                wire = response(b'', 302, b'Location: /length\r\n')
            elif path == '/scheme':
                location = f'Location: //localhost:{self.server.server_address[1]}/length\r\n'.encode()
                wire = response(b'', 302, location)
            elif path == '/loop':
                wire = response(b'', 302, b'Location: /loop\r\n')
            elif path == '/downgrade':
                wire = response(b'', 302, f'Location: {plain_url}/length\r\n'.encode())
            else:
                bad = {
                    '/te-cl': b'Content-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n',
                    '/duplicate': b'Content-Length: 0\r\nContent-Length: 0\r\n\r\n',
                    '/negative': b'Content-Length: -1\r\n\r\n',
                    '/overflow': b'Content-Length: 9223372036854775808\r\n\r\n',
                    '/truncated': b'Content-Length: 5\r\n\r\nhi',
                    '/chunk-truncated': b'Transfer-Encoding: chunked\r\n\r\n5\r\nhi',
                    '/chunk-bad': b'Transfer-Encoding: chunked\r\n\r\nxyz\r\n',
                    '/chunk-crlf': b'Transfer-Encoding: chunked\r\n\r\n1\r\naXX',
                    '/trailer-framing': b'Transfer-Encoding: chunked\r\n\r\n1\r\na\r\n0\r\nContent-Length: 1\r\n\r\n',
                    '/encoding': b'Content-Encoding: gzip\r\nContent-Length: 0\r\n\r\n',
                    '/folded': b' folded: header\r\n\r\n',
                    '/header-control': b'X-Test: value\x01\r\n\r\n',
                    '/large-header': b'X-Test: ' + b'x' * 9000 + b'\r\n\r\n',
                    '/many-headers': b'X-Test: a\r\n' * 129 + b'\r\n',
                    '/bare-lf': b'Content-Length: 0\n\n',
                    '/te-http10': b'Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n',
                }
                if path == '/upgrade':
                    wire = b'HTTP/1.1 101 Switching Protocols\r\n\r\n'
                elif path == '/status':
                    wire = b'HTTP/1.1 999 Invalid\r\n\r\n'
                elif path == '/interim-loop':
                    wire = b'HTTP/1.1 100 Continue\r\n\r\n' * 10
                else:
                    wire = (b'HTTP/1.0 200 OK\r\n' if path == '/te-http10' else b'HTTP/1.1 200 OK\r\n') + bad[path]
            # Fragment successful chunk framing across every possible boundary.
            if path == '/chunked':
                for byte in wire:
                    connection.sendall(bytes([byte]))
                    time.sleep(.0005)
            else:
                connection.sendall(wire)
        except (OSError, ValueError, KeyError, ssl.SSLError):
            pass
        finally:
            if connection is not self.request:
                connection.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    request_queue_size = 128
    daemon_threads = True
    context = None


with tempfile.TemporaryDirectory(prefix='http-client-', dir=ROOT / 'build') as directory:
    work = Path(directory)
    binary = work / 'client'
    subprocess.run([str(COMPILER), str(ROOT / 'tests/tooling/http-client.flex'), '-o', str(binary)], check=True)
    servers = []

    def serve(context=None, ipv6=False):
        kind = Server
        if ipv6:
            class IPv6(Server):
                address_family = socket.AF_INET6
            kind = IPv6
        server = kind(('::1' if ipv6 else '127.0.0.1', 0), Peer)
        server.context = context
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
        return server.server_address[1]

    def certificate(name, san):
        cert, key = work / (name + '.pem'), work / (name + '.key')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key),
                        '-out', str(cert), '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=' + san],
                       capture_output=True, check=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        return cert, context

    def run(jobs, executable=binary):
        global checks
        config = work / 'jobs.json'
        config.write_text(json.dumps({'jobs': jobs}))
        result = subprocess.run([str(executable), str(config)], capture_output=True, timeout=15)
        assert result.returncode == 0, (result.returncode, result.stderr)
        packet = json.loads(result.stdout)
        assert packet['fds_before'] == packet['fds_after'], packet
        assert packet['children'] == -10, packet
        checks += len(jobs)
        return packet['jobs']

    try:
        plain_url = f'http://127.0.0.1:{serve()}'
        cert, context = certificate('dns', 'DNS:localhost')
        tls_port = serve(context)
        tls_url = f'https://localhost:{tls_port}'
        ip_cert, ip_context = certificate('ip', 'DNS:localhost,IP:127.0.0.1')
        ip_url = f'https://127.0.0.1:{serve(ip_context)}'
        good = ['/length', '/binary', '/chunked', '/interim', '/404', '/empty', '/close']
        expected = [b'hello', b'a\0b\xffc', b'hello', b'ok', b'missing', b'', b'hello']
        rows = run([dict(url=plain_url + path) for path in good])
        for row, body in zip(rows, expected):
            assert 'error' not in row and bytes.fromhex(row['body_hex']) == body, row
        assert rows[0]['header'] == 'value' and rows[4]['status'] == 404
        for base, options in [(plain_url, {}), (tls_url, {'ca': str(cert)})]:
            rows = run([dict(url=base + path, **options) for path in ['/large', '/large-chunk']])
            for row in rows:
                assert 'error' not in row and bytes.fromhex(row['body_hex']) == bytes(range(256)) * 256 + b'tail', (row.get('error'), row['size'])
        row = run([dict(url=plain_url + '/large-chunk', limit=32768, truncate=True)])[0]
        assert row['truncated'] and row['size'] == 32768 and bytes.fromhex(row['body_hex']) == bytes(range(256)) * 128
        rows = run([dict(url=plain_url + path, method=method, limit=1)
                    for path, method in [('/head', 'HEAD'), ('/204', 'GET'), ('/304', 'GET')]])
        assert all('error' not in row and row['size'] == 0 for row in rows), rows
        rows = run([dict(url=plain_url + '/echo', method='POST', headers='X-Test: upload\r\n', body_hex=b'a\0b\xff'.hex())])
        assert rows[0]['body_hex'] == b'a\0b\xff'.hex() and requests[-1][3] == b'a\0b\xff', rows
        print('PASS fragmented framing, chunk extensions/trailers, interim responses, binary uploads, HEAD and status handling', flush=True)

        bad = ['/te-cl', '/duplicate', '/negative', '/overflow', '/truncated', '/chunk-truncated', '/chunk-bad',
               '/chunk-crlf', '/trailer-framing', '/encoding', '/folded', '/header-control', '/large-header',
               '/many-headers', '/bare-lf', '/te-http10', '/upgrade', '/status', '/interim-loop']
        rows = run([dict(url=plain_url + path) for path in bad])
        assert all(row.get('error') for row in rows), rows
        rows = run([dict(url=plain_url + '/length', limit=4), dict(url=plain_url + '/length', limit=4, truncate=True),
                    dict(url=plain_url + '/length', limit=5), dict(url=plain_url + '/empty', limit=0)])
        assert rows[0].get('error') and rows[1]['truncated'] and rows[1]['body_hex'] == b'hell'.hex(), rows
        assert 'error' not in rows[2] and 'error' not in rows[3], rows
        print('PASS malformed/ambiguous/truncated responses and bounded body/header storage', flush=True)

        rows = run([dict(url=plain_url + path, redirects=3) for path in ['/root', '/redirect', '/a/b/redirect', '/query', '/scheme']])
        assert all('error' not in row and row['body_hex'] == b'hello'.hex() for row in rows), rows
        assert rows[2]['url'].endswith('/a/length?x=1') and rows[3]['url'].endswith('/query?done=1'), rows
        before = len(requests)
        rows = run([dict(url=plain_url + '/loop', redirects=2), dict(url=plain_url + '/root', headers='Authorization: synthetic\r\n', redirects=2),
                    dict(url=plain_url + '/root', method='POST', body_hex='', redirects=2), dict(url=plain_url + '/root')])
        assert all(row.get('error') for row in rows[:3]) and rows[3]['status'] == 302 and 'error' not in rows[3], rows
        assert not any(request[1] == '/length' for request in requests[before:]), requests[before:]
        print('PASS relative/query/scheme redirects, loop budgets and no credential/body forwarding', flush=True)

        rows = run([dict(url=tls_url + '/length', ca=str(cert)), dict(url=ip_url + '/length', ca=str(ip_cert)),
                    dict(url=tls_url + '/length'), dict(url=f'https://127.0.0.1:{tls_port}/length', ca=str(cert)),
                    dict(url=tls_url + '/downgrade', ca=str(cert), redirects=2)])
        assert all('error' not in row for row in rows[:2]) and all(row.get('error') for row in rows[2:]), rows
        row = run([dict(url=tls_url + '/reset', ca=str(cert), method='POST', body_hex=(b'x' * 262144).hex())])[0]
        assert row.get('error'), row
        print('PASS TLS trust, DNS/IP identity checks and HTTPS downgrade rejection', flush=True)

        invalid = ['file:///etc/passwd', 'http://user:pass@localhost/', 'http://localhost:0/', 'http://localhost:65536/',
                   'http://localhost/\r\nInjected: yes', 'http://localhost\\evil/', 'http://[invalid]/', 'http:///path']
        rows = run([dict(url=url) for url in invalid] + [dict(url=plain_url + '/length', https_only=True),
                    dict(url=plain_url + '/length', headers='Content-Length: 1\r\n'),
                    dict(url=plain_url + '/length', headers='X-Test: x\nInjected: yes\r\n'),
                    dict(url=plain_url + '/length', method='CONNECT')])
        assert all(row.get('error') for row in rows), rows
        rows = run([dict(url=plain_url + '/slow'), dict(url=plain_url + '/length'), dict(url=plain_url + '/stall', timeout=80),
                    dict(url=plain_url + '/slow', cancel_after=30), dict(url=plain_url + '/length', cancel_immediate=True)])
        assert rows[0]['streamed'] and rows[0]['body_hex'] == b'hello world'.hex(), rows
        assert rows[1]['elapsed'] < rows[0]['elapsed'] - 50 and 'error' not in rows[1], rows
        assert 'timed out' in rows[2]['error'] and 'cancelled' in rows[3]['error'] and 'cancelled' in rows[4]['error'], rows
        rows = run([dict(url=tls_url + '/slow', ca=str(cert)), dict(url=tls_url + '/length', ca=str(cert)),
                    dict(url=tls_url + '/stall', ca=str(cert), timeout=80),
                    dict(url=plain_url.replace('http://', 'https://') + '/length', ca=str(cert), timeout=80)])
        assert rows[0]['streamed'] and rows[0]['body_hex'] == b'hello world'.hex(), rows
        assert rows[1]['elapsed'] < rows[0]['elapsed'] - 50 and 'error' not in rows[1], rows
        assert all('timed out' in row.get('error', '') for row in rows[2:]), rows
        print('PASS nonblocking concurrent streams, independent deadlines, cancellation and resolver reaping', flush=True)

        if socket.has_ipv6:
            try:
                port = serve(ipv6=True)
            except OSError:
                pass
            else:
                row = run([dict(url=f'http://[::1]:{port}/length')])[0]
                assert 'error' not in row and row['body_hex'] == b'hello'.hex(), row
        direct = work / 'client-direct'
        subprocess.run([str(COMPILER), '--native-pipeline', 'direct', str(ROOT / 'tests/tooling/http-client.flex'), '-o', str(direct)], check=True)
        rows = run([dict(url=plain_url + '/chunked'), dict(url=tls_url + '/length', ca=str(cert))], direct)
        assert all('error' not in row for row in rows), rows
        for _ in range(3):
            rows = run([dict(url=plain_url + '/length') for _ in range(20)])
            assert all('error' not in row for row in rows), rows
        rows = run([dict(url=plain_url + '/length', cancel_immediate=True) for _ in range(20)])
        assert all('cancelled' in row.get('error', '') for row in rows), rows
        example = work / 'http-get'
        subprocess.run([str(COMPILER), str(ROOT / 'examples/http-client.flex'), '-o', str(example)], check=True)
        for url in (plain_url, tls_url):
            result = subprocess.run([str(example), url + '/length'], env=dict(os.environ, SSL_CERT_FILE=str(cert)), capture_output=True, timeout=5)
            assert result.returncode == 0 and result.stdout == b'hello', (result.returncode, result.stderr)
        print(f'PASS {checks} native HTTP/HTTPS requests; IR/direct output, IPv6, descriptor cleanup and child ownership', flush=True)
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
