"""Native Monolith multipart parser and loopback transport contracts."""
import argparse,http.client,os,random,socket,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def run(compiler):
    with tempfile.TemporaryDirectory(prefix='monolith-multipart-') as directory:
        temp=Path(directory);env=os.environ|{'FLEXSCRIPT_LIB':str(ROOT/'libs')}
        for name in ('multipart-unit','multipart-driver','multipart-web'):
            subprocess.run([compiler,'--native-pipeline','direct',str(ROOT/'tests/monolith'/f'{name}.flex'),'-o',str(temp/name)],env=env,cwd=ROOT,check=True)
        subprocess.run([str(temp/'multipart-unit')],check=True)
        rng=random.Random(94)
        def parse(body,typ='multipart/form-data; boundary=foo'):
            return subprocess.run([str(temp/'multipart-driver'),typ],input=body,stdout=subprocess.PIPE,check=True).stdout.decode()
        def part(name,data):return b'--foo\r\nContent-Disposition: form-data; name="'+name.encode()+b'"; filename="f.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'+data+b'\r\n'
        def digest(data):
            h=0
            for c in data:h=(h*31+c)%1000000007
            return h
        for i in range(100):
            data=rng.randbytes(rng.randrange(0,5000))+b'\r\n--foox\x00\r\n--foo--junk'+rng.randbytes(30)
            body=part('file',data)+part('other',b'\0abc')+b'--foo--\r\n'
            assert parse(body)==f'file:{len(data)}:{digest(data)}\nother:4:{digest(b"\0abc")}\nDONE\n'
        assert parse(b'--foo--\r\n')=='DONE\n'
        assert parse(part('a',b'x')+b'--foo--\r\n','multipart/form-data; boundary="foo"')==f'a:1:{ord("x")}\nDONE\n'
        for typ in ('multipart/form-data; boundary=foo; boundary=foo','text/plain; boundary=foo','multipart/form-data; boundary=""'):
            assert parse(part('a',b'x')+b'--foo--\r\n',typ)=='ERROR\n'
        for bad in (b'', b'--foo\r\n\r\nx\r\n--foo--\r\n', b'--foo\r\nContent-Disposition: form-data; name="a"; name="b"\r\n\r\nx\r\n--foo--\r\n', b'--foo\r\nContent-Disposition: form-data; name="a"\r\n\r\nx', b'--foo\r\nContent-Disposition: form-data; name="a"\r\n\r\nx\r\n--foo--junk'):
            assert parse(bad).endswith('ERROR\n')
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        app=subprocess.Popen([str(temp/'multipart-web'),str(port)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        def req(data,headers):
            conn=http.client.HTTPConnection('127.0.0.1',port,timeout=3);conn.request('POST','/',body=data,headers=headers);response=conn.getresponse();result=(response.status,response.read());conn.close();return result
        try:
            for _ in range(100):
                try:
                    with socket.create_connection(('127.0.0.1',port),.2):break
                except OSError:time.sleep(.02)
            data=b'\0hello\xff';body=part('file',data)+b'--foo--\r\n'
            assert req(body,{'Content-Type':'multipart/form-data; boundary=foo'})==(200,f'{len(data)}:{digest(data)}'.encode())
            assert req(body[:-4],{'Content-Type':'multipart/form-data; boundary=foo'})[0]==400
            assert req(body,{'Content-Type':'multipart/form-data; boundary=foo','Origin':'https://evil.invalid'})[0]==403
            assert req(b'a=b',{'Content-Type':'application/x-www-form-urlencoded'})==(200,b'urlencoded')
        finally:app.terminate();app.wait(timeout=10)
    print('Monolith multipart passed: binary payloads, false boundaries, malformed input, HTTP, origin and existing forms')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--compiler',required=True);run(str(Path(parser.parse_args().compiler).resolve()))
