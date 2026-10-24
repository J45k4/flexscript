#!/usr/bin/env python3
"""Compile the shared CDP helper and test real isolated loopback transports."""
import argparse,json,os,signal,socket,subprocess,tempfile,threading,time
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True)
p.add_argument('--out',type=Path,default=Path('build/cdp-http'));a=p.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);binary=out/'fixture';checks=[]
subprocess.run([str(a.compiler.resolve()),'tests/monolith/cdp-http.flex','-o',str(binary)],check=True)

def run(label,serve,*,deadline=10000,expected=None,error=None,child=None):
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(1);listener.settimeout(15)
    port=listener.getsockname()[1];requests=[];server_errors=[]
    def server():
        try:
            with listener:
                conn,_=listener.accept()
                with conn:
                    conn.settimeout(15);request=bytearray()
                    while b'\r\n\r\n' not in request:
                        part=conn.recv(4096)
                        if not part:raise AssertionError('client closed before request')
                        request.extend(part);assert len(request)<=65536
                    requests.append(bytes(request));serve(conn)
        except (BrokenPipeError,ConnectionResetError):pass
        except BaseException as e:server_errors.append(repr(e))
    thread=threading.Thread(target=server,daemon=True);thread.start()
    command=[str(binary),str(port),str(deadline)]+([str(child)] if child else [])
    proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    start=time.monotonic()
    try:stdout,stderr=proc.communicate(timeout=15)
    finally:
        if proc.poll() is None:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
        thread.join(16)
    elapsed=time.monotonic()-start
    assert not thread.is_alive() and not server_errors,(label,server_errors)
    assert len(requests)==1 and requests[0].startswith(b'PUT /fixture HTTP/1.1\r\n'),(label,requests)
    if error:
        assert proc.returncode==1 and stdout==b'' and error.encode() in stderr and b'/fixture' in stderr and b'response bytes=' in stderr,(label,proc.returncode,stdout,stderr)
    else:assert proc.returncode==0 and stdout==expected,(label,proc.returncode,stdout,stderr)
    checks.append(dict(name=label,elapsed_seconds=round(elapsed,3),requests=1));print('PASS',label,flush=True)

def response(conn):conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok')
run('complete HTTP response',response,expected=b'ok')
def persistent(conn):
    response(conn)
    assert conn.recv(1)==b'', 'client waited for EOF after a complete Content-Length body'
run('Content-Length completes while the peer keeps its connection open',persistent,deadline=500,expected=b'ok')
def split_persistent(conn):
    for part in [b'HTTP/1.1 200 OK\r\ncOnTeNt-LeNgTh:\t2\t\r\n',b'\r',b'\no',b'k']:
        conn.sendall(part);time.sleep(.01)
    assert conn.recv(1)==b''
run('split headers/body and case-insensitive Content-Length preserve framing',split_persistent,deadline=500,expected=b'ok')
def delayed(conn):time.sleep(3.5);response(conn)
run('one delayed request beyond the old3s read window succeeds without replay',delayed,expected=b'ok')
run('empty EOF includes request context and byte count',lambda conn:None,error='invalid response or early EOF')
run('non-200 response is an explicit protocol failure',lambda conn:conn.sendall(b'HTTP/1.1 503 Busy\r\nContent-Length: 0\r\n\r\n'),error='invalid status/header')
run('HTTP-2000 is not HTTP-200',lambda conn:conn.sendall(b'HTTP/1.1 2000 Invalid\r\n\r\n'),error='invalid status/header')
run('early EOF never accepts a truncated declared body',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok'),error='truncated Content-Length body')
run('extra body bytes fail declared framing',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nok'),error='body exceeds Content-Length')
run('nonnumeric Content-Length is rejected',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: nope\r\n\r\n'),error='invalid Content-Length')
run('duplicate Content-Length is rejected',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n'),error='duplicate Content-Length')
run('unsupported transfer framing is explicit',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'),error='unsupported transfer encoding')
def stalled(conn):time.sleep(.6)
run('a read deadline differs from EOF and remains diagnostic',stalled,deadline=200,error='read timed out')
def drip(conn):
    conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n')
    for _ in range(100):conn.sendall(b'x');time.sleep(.01)
run('partial successful headers and dripping bytes do not reset the total deadline',drip,deadline=200,error='read timed out')
run('response size is bounded to1MiB',lambda conn:conn.sendall(b'HTTP/1.1 200 OK\r\n\r\n'+b'x'*1048576),error='response exceeds 1 MiB')
with tempfile.TemporaryDirectory(prefix='owned-child-',dir=out) as directory:
    root=Path(directory);marker=root/'drained';child=root/'writer'
    # A browser-like child must finish writing more than either pipe's capacity
    # before the HTTP peer can return. This is not a fake successful browser.
    child.write_text('#!/usr/bin/env python3\nimport os\nfrom pathlib import Path\nfor fd in [1,2]:\n for _ in range(128): os.write(fd,b"x"*4096)\nPath('+repr(str(marker))+').write_text("done")\n')
    child.chmod(0o700)
    def after_pipes(conn):
        end=time.monotonic()+4
        while not marker.exists() and time.monotonic()<end:time.sleep(.01)
        assert marker.read_text()=='done';response(conn)
    run('owned child stdout/stderr are drained during HTTP waits',after_pipes,expected=b'ok',child=child)
(out/'report.json').write_text(json.dumps(dict(count=len(checks),checks=checks),indent=2)+'\n')
