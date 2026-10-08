"""Local TLS infrastructure used only by compiler integration tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import ssl
import subprocess
import threading


def certificate(directory):
    cert = directory / 'localhost.pem'
    key = directory / 'localhost.key'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                   check=True, capture_output=True, timeout=30)
    return cert, key


class TLSServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, directory, handler):
        self.cert, key = certificate(directory)
        super().__init__(('127.0.0.1', 0), handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, key)
        self.socket = context.wrap_socket(self.socket, server_side=True)
        self.url = f'https://localhost:{self.server_port}'
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        self.shutdown()
        self.server_close()
        self.thread.join(timeout=5)


class QuietHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def payload(self, content, status=200, headers=()):
        self.send_response(status)
        self.send_header('Content-Length', str(len(content)))
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass
