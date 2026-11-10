#!/usr/bin/env python3
"""Opt-in native WebSocket interoperability; Python provides disposable peers only."""
import os,socket,ssl,subprocess,tempfile,threading,time
from pathlib import Path
from websockets.sync.client import connect
from websockets.sync.server import serve
ROOT=Path(__file__).resolve().parent.parent

def port():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def main():
    compiler=os.environ.get('FLEX_COMPILER','flexscript')
    with tempfile.TemporaryDirectory(prefix='flexscript-websocket-') as directory:
        tmp=Path(directory);core=tmp/'core';peer=tmp/'peer'
        for source,target in [('libs/websocket/tests/core.flex',core),('libs/websocket/tests/peer.flex',peer)]:subprocess.run([compiler,'--native-pipeline','direct',source,'-o',str(target)],cwd=ROOT,check=True)
        subprocess.run([str(core)],check=True)
        def handler(ws):
            assert ws.recv()=='native 🐶';ws.ping(b'keepalive');ws.send(['hello ','native 🐶']);data=ws.recv();assert data==bytes(range(256))*273+bytes(range(112));ws.send(data)
            try:ws.recv()
            except Exception:pass
        def native_client(context=None,args=(),failure=False):
            selected=port()
            with serve(handler,'127.0.0.1',selected,ssl=context,compression=None,max_size=1048576) as server:
                thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
                result=subprocess.run([str(peer),'client','127.0.0.1',str(selected),*map(str,args)],capture_output=True,text=True,timeout=15)
                assert (result.returncode!=0) if failure else (result.returncode==0),(result.returncode,result.stdout,result.stderr)
                server.shutdown();thread.join(timeout=2)
        native_client()
        selected=port();server=subprocess.Popen([str(peer),'server','127.0.0.1',str(selected)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            assert server.stdout.readline().strip()=='WebSocket fixture listening'
            with connect(f'ws://127.0.0.1:{selected}/socket',compression=None,max_size=1048576) as ws:
                ws.send('Python 🐶');assert ws.recv()=='Python 🐶'
                ws.send([b'\0abc',bytes(range(256))*273],text=False);assert ws.recv()==b'\0abc'+bytes(range(256))*273
                assert ws.ping(b'ping').wait(2)
            out,err=server.communicate(timeout=5);assert server.returncode==0,(out,err)
        finally:
            if server.poll() is None:server.terminate();server.wait(timeout=5)
        def openssl(*args):subprocess.run(['openssl',*args],cwd=tmp,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout','ca.key','-out','ca.crt','-days','1','-subj','/CN=WebSocket test CA')
        for name,subject,extensions in [('server','/CN=localhost','subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n'),('client','/CN=client','extendedKeyUsage=clientAuth\n'),('wrong','/CN=wrong','subjectAltName=DNS:wrong.example\nextendedKeyUsage=serverAuth\n')]:
            openssl('req','-newkey','rsa:2048','-nodes','-keyout',name+'.key','-out',name+'.csr','-subj',subject);(tmp/(name+'.ext')).write_text(extensions);openssl('x509','-req','-in',name+'.csr','-CA','ca.crt','-CAkey','ca.key','-CAcreateserial','-out',name+'.crt','-days','1','-extfile',name+'.ext')
        def tls_context(name='server',mtls=False):
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(tmp/(name+'.crt'),tmp/(name+'.key'))
            if mtls:context.load_verify_locations(tmp/'ca.crt');context.verify_mode=ssl.CERT_REQUIRED
            return context
        native_client(tls_context(),[tmp/'ca.crt'])
        native_client(tls_context(mtls=True),[tmp/'ca.crt',tmp/'client.crt',tmp/'client.key'])
        native_client(tls_context(mtls=True),[tmp/'ca.crt'],failure=True)
        native_client(tls_context('wrong'),[tmp/'ca.crt'],failure=True)
        openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout','other.key','-out','other.crt','-days','1','-subj','/CN=Other CA')
        native_client(tls_context(),[tmp/'other.crt'],failure=True)
        print('Native WebSocket interoperability passed: client/server, fragmentation, ping/pong, binary bytes, verified TLS, mTLS, wrong CA/name and missing client certificate')
if __name__=='__main__':main()
