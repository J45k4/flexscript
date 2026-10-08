#!/usr/bin/env python3
"""Compile the Flexscript HTTP server and exercise real loopback TCP requests."""
import argparse
import http.client
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BODY = b'Hello, world!\n'


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def start(binary, port):
    process = subprocess.Popen([str(binary), str(port)], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    readable, _, _ = select.select([process.stdout], [], [], 5)
    line = process.stdout.readline() if readable else b''
    if not line.startswith(f'Listening on http://127.0.0.1:{port}/'.encode()):
        process.terminate()
        output = process.communicate(timeout=3)
        raise AssertionError((line, output))
    return process


def stop(process, sig=signal.SIGTERM):
    if process.poll() is None:
        process.send_signal(sig)
    output = process.communicate(timeout=3)
    assert process.returncode == -sig and output == (b'', b''), (process.returncode, output)


def raw(port, pieces, delay=0):
    with socket.create_connection(('127.0.0.1', port), timeout=4) as sock:
        sock.settimeout(4)
        for piece in pieces:
            sock.sendall(piece)
            if delay:
                time.sleep(delay)
        data = bytearray()
        while True:
            try:
                part = sock.recv(4096)
            except ConnectionResetError:
                # Rejected oversized requests can leave unread bytes on close.
                break
            if not part:
                break
            data.extend(part)
    return bytes(data)


def check_response(data, status, body=None, head=False):
    header, separator, payload = data.partition(b'\r\n\r\n')
    assert separator and header.startswith(f'HTTP/1.1 {status} '.encode()), data
    fields = {}
    for line in header.split(b'\r\n')[1:]:
        name, value = line.split(b':', 1)
        fields[name.lower()] = value.strip()
    assert fields[b'connection'] == b'close'
    assert fields[b'content-type'] == b'text/plain; charset=utf-8'
    if head:
        assert payload == b''
        if body is not None:
            assert int(fields[b'content-length']) == len(body)
    else:
        assert int(fields[b'content-length']) == len(payload), data
        if body is not None:
            assert payload == body
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'build/downloaded/flexscript-0.0.1-linux-x86_64')
    args = parser.parse_args()
    binary = ROOT / 'build/hello-http'
    binary.parent.mkdir(exist_ok=True)
    subprocess.run([str(args.compiler.resolve()), str(ROOT / 'examples/hello-http.flex'), '-o', str(binary)], check=True)
    assert b'127.0.0.1:8080' in subprocess.run([str(binary), '--help'], capture_output=True, check=True).stdout
    for port in ['', '0', '-1', '65536', 'abc', '80x', '9999999999999999999999999']:
        result = subprocess.run([str(binary), port], capture_output=True, timeout=3)
        assert result.returncode == 1 and b'Port must be' in result.stderr
    assert subprocess.run([str(binary), '8080', 'extra'], capture_output=True).returncode == 1
    port = free_port()
    process = start(binary, port)
    try:
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=4)
        connection.request('GET', '/')
        response = connection.getresponse()
        assert response.status == 200 and response.read() == BODY
        connection.close()
        check_response(raw(port, [b'HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n']), 200, BODY, head=True)
        check_response(raw(port, [b'GET /?hello=world HTTP/1.1\r\nHost: localhost\r\n\r\n']), 200, BODY)
        check_response(raw(port, [b'GET / HTTP/1.0\r\n\r\n']), 200, BODY)
        check_response(raw(port, [b'G', b'ET / HTTP/1.1\r\nHo', b'st: local', b'host\r\n', b'\r', b'\n'], 0.02), 200, BODY)
        check_response(raw(port, [b'GET /missing HTTP/1.1\r\nHost: localhost\r\n\r\n']), 404, b'Not Found\n')
        check_response(raw(port, [b'HEAD /missing HTTP/1.1\r\nHost: localhost\r\n\r\n']), 404, b'Not Found\n', head=True)
        fields = check_response(raw(port, [b'POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n']), 405)
        assert fields[b'allow'] == b'GET, HEAD'
        for request in [b'garbage\r\n\r\n', b'GET / HTTP/1.1\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: \r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nBroken\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\n folded: b\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nX-Test: \x00\r\n\r\n',
                        b'GET / HTTP/2.0\r\nHost: a\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nContent-Length: x\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n',
                        b'GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n']:
            check_response(raw(port, [request]), 400)
        check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\n\r\nx']), 413)
        check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n']), 501)
        for _ in range(5):
            check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: a\r\nX-Large: ' + b'x' * 8192]), 431)
        started = time.monotonic()
        check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: ']), 408)
        assert 1.5 <= time.monotonic() - started < 3.5
        # A disconnected client, including one reset during a response, must
        # leave the server ready for subsequent requests rather than SIGPIPE.
        with socket.create_connection(('127.0.0.1', port)) as sock:
            sock.sendall(b'GET / HTTP/1.1\r\nHost: a\r\n\r\n')
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
        with socket.create_connection(('127.0.0.1', port)):
            pass
        check_response(raw(port, [b'GET / HTTP/1.1\r\nhOsT: a\r\n\r\n']), 200, BODY)
        maps_before = Path(f'/proc/{process.pid}/maps').read_text()
        for _ in range(40):
            check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: a\r\n\r\n']), 200, BODY)
        assert Path(f'/proc/{process.pid}/maps').read_text() == maps_before, 'Mappings leaked'
        assert len(list(Path(f'/proc/{process.pid}/fd').iterdir())) == 4, 'Sockets leaked'
        conflict = subprocess.run([str(binary), str(port)], capture_output=True, timeout=3)
        assert conflict.returncode == 1 and b'Cannot listen' in conflict.stderr
        stop(process, signal.SIGINT)
        process = start(binary, port)
        check_response(raw(port, [b'GET / HTTP/1.1\r\nHost: a\r\n\r\n']), 200, BODY)
        stop(process)
    finally:
        if process.poll() is None:
            process.kill(); process.communicate()
    print('HTTP tests passed: GET/HEAD, framing, routes, fragmented requests, malformed/oversized headers,')
    print('timeouts, disconnects, repeated requests, no buffer/socket leaks, port conflicts and restart.')
    print(f'Native binary: {binary}')


if __name__ == '__main__':
    main()
