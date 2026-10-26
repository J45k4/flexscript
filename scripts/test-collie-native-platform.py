#!/usr/bin/env python3
"""Test actual Flexscript sockets/TLS/broker against private local servers."""
import argparse,http.server,json,os,socket,ssl,subprocess,tempfile,threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,default=ROOT/'build/collie-desktop');p.add_argument('--compiler',type=Path);a=p.parse_args();out=a.out.resolve();compiler=a.compiler.resolve() if a.compiler else out/'compiler'
class HTTPS(http.server.BaseHTTPRequestHandler):
 protocol_version='HTTP/1.1'
 def do_GET(self):
  if self.path=='/redirect':self.send_response(302);self.send_header('Location','/ok');self.send_header('Content-Length','0');self.end_headers();return
  if self.path=='/stream':
   self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Transfer-Encoding','chunked');self.end_headers()
   import time
   for body in (b'data: first\n\n',b'data: second\n\n'):
    self.wfile.write(f'{len(body):x}\r\n'.encode()+body+b'\r\n');self.wfile.flush();time.sleep(.05)
   self.wfile.write(b'0\r\n\r\n');return
  body=b'x'*100000 if self.path=='/large' else b'native TLS';self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers()
  try:self.wfile.write(body)
  except (ConnectionError,ssl.SSLError):pass
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length','0')));self.do_GET()
 def log_message(self,*args):pass
with tempfile.TemporaryDirectory(prefix='native-platform-',dir=out) as directory:
 work=Path(directory);cert=work/'cert.pem';key=work/'key.pem'
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],check=True,capture_output=True)
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),HTTPS);context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(cert,key);server.socket=context.wrap_socket(server.socket,server_side=True)
 threading.Thread(target=server.serve_forever,daemon=True).start()
 tcp=socket.socket();tcp.bind(('127.0.0.1',0));tcp.listen();tcp.settimeout(.2);udp=socket.socket(type=socket.SOCK_DGRAM);udp.bind(('127.0.0.1',0));udp.settimeout(.2);stop=threading.Event()
 def echo_tcp():
  while not stop.is_set():
   try:connection,_=tcp.accept()
   except socket.timeout:continue
   with connection:
    connection.settimeout(1)
    try:
     data=connection.recv(32768)
     if data:connection.sendall(data)
    except OSError:pass
 def echo_udp():
  while not stop.is_set():
   try:data,address=udp.recvfrom(32768);udp.sendto(data,address)
   except socket.timeout:continue
 threads=[threading.Thread(target=f,daemon=True) for f in (echo_tcp,echo_udp)]
 for thread in threads:thread.start()
 config=work/'config.json';config.write_text(json.dumps(dict(root=str(work/'data'),engine=str(out/'engine'),tcp=tcp.getsockname()[1],udp=udp.getsockname()[1],url=f'https://localhost:{server.server_port}')))
 try:
  binary=out/'test-native-host';subprocess.run([str(compiler),'--native-pipeline','direct',str(ROOT/'tests/collie/native-host.flex'),'-o',str(binary)],check=True)
  result=subprocess.run([str(binary),str(config)],env=dict(os.environ,SSL_CERT_FILE=str(cert),COLLIE_HEADLESS='1'),capture_output=True,timeout=30)
  print(result.stdout.decode(),end='');assert result.returncode==0,(result.returncode,result.stderr.decode())
 finally:
  stop.set();server.shutdown()
  for thread in threads:thread.join(timeout=2)
  tcp.close();udp.close();server.server_close()
