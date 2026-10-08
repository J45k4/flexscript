#!/usr/bin/env python3
"""Check TCP operations, HTTPS framing and certificate verification locally."""
import argparse
import json
import os
from pathlib import Path
import resource
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time

from tls_fixture import QuietHandler, TLSServer

ROOT = Path(__file__).resolve().parents[1]
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class HTTPHandler(QuietHandler):
    def do_GET(self):
        path = self.path
        body = b'hello https\n'
        if path == '/plain':
            self.payload(body)
            return
        if path == '/large':
            self.payload(bytes(range(256)) * 100)
            return
        if path == '/redirect':
            self.payload(b'', 302, [('Location', '/plain')])
            return
        if path == '/absolute':
            self.payload(b'', 307, [('Location', self.server.url + '/plain')])
            return
        if path == '/loop':
            self.payload(b'', 302, [('Location', '/loop')])
            return
        if path == '/downgrade':
            self.payload(b'', 302, [('Location', 'http://localhost/plain')])
            return
        if path == '/slow':
            time.sleep(.4)
            self.payload(body)
            return
        responses = {
            '/chunked': b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;extension=yes\r\nhello\r\n7\r\n https\n\r\n0\r\nTrailer: value\r\n\r\n',
            '/empty': b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n',
            '/close': b'HTTP/1.1 200 OK\r\n\r\n' + body,
            '/bad-status': b'NOT HTTP\r\n\r\n',
            '/missing': b'HTTP/1.1 404 Missing\r\nContent-Length: 0\r\n\r\n',
            '/truncate': b'HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort',
            '/duplicate': b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\nx',
            '/ambiguous': b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\nx',
            '/bad-length': b'HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n',
            '/huge-length': b'HTTP/1.1 200 OK\r\nContent-Length: 999999999999999999999\r\n\r\n',
            '/bad-chunk': b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n',
            '/truncate-chunk': b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10\r\nshort',
            '/bad-chunk-crlf': b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nxXX',
            '/compression': b'HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 0\r\n\r\n',
            '/bad-header': b'HTTP/1.1 200 OK\r\n bad folded header\r\n\r\n',
            '/long-header': b'HTTP/1.1 200 OK\r\nLong: ' + b'x' * 9000 + b'\r\n\r\n',
            '/headers-limit': b'HTTP/1.1 200 OK\r\n' + (b'X: ' + b'x' * 1000 + b'\r\n') * 70 + b'\r\n',
            '/fragmented': b'HTTP/1.1 200 OK\r\ncontent-length: 12\r\n\r\n' + body,
        }
        try:
            response = responses[path]
            if path == '/fragmented':
                for byte in response:
                    self.wfile.write(bytes([byte]))
                    self.wfile.flush()
            else:
                self.wfile.write(response)
                self.wfile.flush()
            if path == '/close':
                self.connection.settimeout(2)
                self.connection.unwrap()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError, TimeoutError):
            pass


class TCPHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data = self.request.recv(16)
        if data == b'slow':
            time.sleep(.3)
            return
        for byte in data:
            self.request.sendall(bytes([byte]))


class TCPServer(socketserver.ThreadingTCPServer):
    daemon_threads = True


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flex-network-') as temp:
        work = Path(temp)
        source = work / 'get.flex'
        source.write_text(f'''import "{ROOT / 'lib/http.flex'}";
fn main(argc,argv){{
    if !https_get(load64(argv+8),32768,http_decimal(load64(argv+16),10000)) {{return 1;}}
    let n=0;while n<http_size {{let sent=syscall(1,1,http_output+n,http_size-n,0,0,0);if sent<=0 {{return 2;}}n=n+sent;}}
    return 0;
}}
''')
        binary = work / 'get'
        result = subprocess.run([str(compiler), str(source), '-o', str(binary)], capture_output=True)
        assert result.returncode == 0, result.stderr
        server = TLSServer(work, HTTPHandler)
        env = {**os.environ, 'SSL_CERT_FILE': str(server.cert)}

        def check(path, expected=b'hello https\n', status=0, url=None, environment=env, timeout=1000):
            nonlocal count
            result = subprocess.run([str(binary), url or server.url + path, str(timeout)], capture_output=True,
                                    env=environment, timeout=5)
            assert (result.returncode, result.stdout) == (status, expected), (path, result.returncode, result.stdout, result.stderr)
            count += 1

        try:
            for path in ['/plain', '/redirect', '/absolute', '/chunked', '/close', '/fragmented']:
                check(path)
            check('/empty', b'')
            check('/large', bytes(range(256)) * 100)
            for path in ['/loop', '/downgrade', '/slow', '/bad-status', '/missing', '/truncate',
                         '/duplicate', '/ambiguous', '/bad-length', '/huge-length', '/bad-chunk',
                         '/truncate-chunk', '/bad-chunk-crlf', '/compression', '/bad-header',
                         '/long-header', '/headers-limit']:
                check(path, b'', 1, timeout=50 if path == '/slow' else 1000)
            check('/plain', b'', 1, environment={**os.environ, 'SSL_CERT_FILE': '/no/such/cert'})
            check('/plain', b'', 1, url=server.url.replace('localhost', '127.0.0.1') + '/plain')
            for url in ['http://localhost/', 'https://user@localhost/', 'https://localhost:0/',
                        'https://localhost:65536/', 'https://localhost/path\r\nInjected: x',
                        'https://localhost/#fragment', 'https://localhost:abc/']:
                check('', b'', 1, url=url)
            # Repeated downloads must release sockets and scratch/body mappings.
            repeat_source = work / 'repeat.flex'
            repeat_source.write_text('import "' + str(ROOT / 'lib/http.flex') + '";'+'''
fn main(argc,argv){
 let url=load64(argv+8);let bad=load64(argv+16);let i=0;
 while i<4 {if !https_get(url,32768,1000){return 1;}https_free();i=i+1;}
 syscall(1,1,"ready\\n",6,0,0,0);let trigger=alloc(1);syscall(0,0,trigger,1,0,0,0);
 i=0;while i<20 {
  if !https_get(url,32768,1000){return 2;}https_free();
  if https_get(bad,32768,1000){return 3;}if http_output || http_size {return 4;}
  i=i+1;
 }
 syscall(1,1,"done\\n",5,0,0,0);syscall(0,0,trigger,1,0,0,0);return 0;
}
''')
            repeat = work / 'repeat'
            result = subprocess.run([str(compiler), str(repeat_source), '-o', str(repeat)], capture_output=True)
            assert result.returncode == 0, result.stderr
            process = subprocess.Popen([str(repeat), server.url + '/plain', server.url + '/missing'],
                                       env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                assert process.stdout.readline() == b'ready\n'
                def footprint():
                    proc = Path('/proc') / str(process.pid)
                    fields = dict(line.split(':', 1) for line in (proc / 'status').read_text().splitlines())
                    return len(list((proc / 'fd').iterdir())), int(fields['VmSize'].split()[0])
                before = footprint()
                process.stdin.write(b'x')
                process.stdin.flush()
                assert process.stdout.readline() == b'done\n'
                after = footprint()
                assert before[0] == after[0], (before, after)
                assert after[1] - before[1] <= 256, (before, after)
                process.stdin.write(b'x')
                process.stdin.flush()
                stdout, stderr = process.communicate(timeout=5)
                assert process.returncode == 0, (stdout, stderr)
                count += 1
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        finally:
            server.close()

        tcp = TCPServer(('127.0.0.1', 0), TCPHandler)
        thread = threading.Thread(target=tcp.serve_forever, daemon=True)
        thread.start()
        source.write_text(f'''import "{ROOT / 'lib/net.flex'}";
fn main(argc,argv){{
    let fd=tcp_connect("localhost","{tcp.server_address[1]}",1000);if fd<0 {{return 1;}}
    let text=load64(argv+8);let n=net_length(text);let end=net_now()+100;
    if !tcp_write(fd,text,n,end) {{return 2;}}
    let p=alloc(n);let got=0;while got<n {{let k=tcp_read(fd,p+got,n-got,end);if k<=0 {{tcp_close(fd);return 3;}}got=got+k;}}
    tcp_close(fd);syscall(1,1,p,n,0,0,0);return 0;
}}
''')
        result = subprocess.run([str(compiler), str(source), '-o', str(binary)], capture_output=True)
        assert result.returncode == 0, result.stderr
        try:
            for text, status, stdout in [('tcp', 0, b'tcp'), ('slow', 3, b'')]:
                result = subprocess.run([str(binary), text], capture_output=True, timeout=5)
                assert (result.returncode, result.stdout) == (status, stdout), result
                count += 1
        finally:
            tcp.shutdown()
            tcp.server_close()
            thread.join(timeout=5)

        source.write_text(f'''import "{ROOT / 'lib/net.flex'}";
fn main(){{let fd=tcp_listen("127.0.0.1","0",8);if fd<0 {{return 1;}}
 let a=alloc(16);let n=alloc(4);store8(n,16);if syscall(51,fd,a,n,0,0,0)<0 {{return 2;}}
 let port=(load8(a+2)<<8)|load8(a+3);let out=alloc(32);let i=31;
 store8(out+i,10);while port>=10 {{i=i-1;store8(out+i,48+port%10);port=port/10;}}
 i=i-1;store8(out+i,48+port);syscall(1,1,out+i,32-i,0,0,0);
 let client=tcp_accept(fd,net_now()+3000);if client<0 {{return 3;}}
 let p=alloc(16);let got=tcp_read(client,p,16,net_now()+1000);
 if got<=0 || !tcp_write(client,p,got,net_now()+1000) {{return 4;}}
 tcp_close(client);tcp_close(fd);return 0;}}
''')
        result = subprocess.run([str(compiler), str(source), '-o', str(binary)], capture_output=True)
        assert result.returncode == 0, result.stderr
        process = subprocess.Popen([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            port = int(process.stdout.readline())
            with socket.create_connection(('127.0.0.1', port), timeout=2) as client:
                client.sendall(b'server')
                assert client.recv(16) == b'server'
            stdout, stderr = process.communicate(timeout=5)
            assert process.returncode == 0, (stdout, stderr)
            count += 1
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
    print(f'{compiler.name}: {count} networking checks passed', flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers', nargs='+', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = [{'compiler': str(p), 'checks': suite(p.resolve())} for p in args.compilers]
    total = sum(r['checks'] for r in results)
    if args.report:
        args.report.write_text(json.dumps({'results': results, 'total': total}, indent=2) + '\n')
    print(f'Total: {total} networking checks passed')


if __name__ == '__main__':
    main()
