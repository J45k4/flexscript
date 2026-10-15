from pathlib import Path
import subprocess,socket,ssl,time,os,select,json,argparse,re,io,http.client
p=argparse.ArgumentParser();p.add_argument('--case',choices=['transactions','bad-length','early-response','timeout','cancel'],required=True)
for name in ['compiler','builder','qemu','prefix','vendor','rom','tls']:p.add_argument('--'+name,required=True)
p.add_argument('--work',type=Path,required=True);p.add_argument('--certificates',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];out=a.work.resolve()/a.case;out.mkdir(parents=True,exist_ok=True);certs=a.certificates.resolve();mode=['transactions','bad-length','early-response','timeout','cancel'].index(a.case)
ca=(certs/'ca.der').read_bytes();src=out/'firmware.flex';src.write_text('import "'+str(root/'tests/esp32/http-tls-oracle.flex')+'";\nfn ht_mode(){return '+str(mode)+';}\nfn ht_body_length(){return '+('10000' if mode==2 else '0')+';}\nfn ht_ca_size(){return '+str(len(ca))+';}\nfn ht_ca(){let h="'+ca.hex()+'";let p=alloc('+str(len(ca))+');let i=0;while i<'+str(len(ca))+'{let a=nb_hex(load8(h+i*2));let b=nb_hex(load8(h+i*2+1));store8(p+i,(a<<4)|b);i=i+1;}return p;}\n')
with (out/'build.log').open('w') as log:subprocess.run([a.builder,'--compiler',a.compiler,'--source',str(src),'--vendor',a.vendor,'--rom',a.rom,'--output',str(out/'firmware.bin'),'--ld',a.prefix+'ld','--gcc',a.prefix+'gcc','--tls',a.tls],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
image=bytearray(b'\xff'*4194304);data=(out/'firmware.bin').read_bytes();image[4096:4096+len(data)]=data;(out/'flash.bin').write_bytes(image)
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=ssl.TLSVersion.TLSv1_3;ctx.maximum_version=ssl.TLSVersion.TLSv1_3;ctx.load_cert_chain(certs/'ecdsa.pem',certs/'ecdsa.key')
def new_server():
 rx=ssl.MemoryBIO();tx=ssl.MemoryBIO();return rx,tx,ctx.wrap_bio(rx,tx,server_side=True)
rx,tx,server=new_server();established=False;request=bytearray();requests=[];buf=bytearray();lines=[];closed=0;closing=False;second_server=False;report={'case':a.case,'passed':False,'requests':[],'tls_handshakes':0,'close_notify':0};qmp=out/'qmp.sock';qmp.unlink(missing_ok=True)
class Peer:
 def __init__(self,data):self.data=data
 def makefile(self,*args,**kwargs):return io.BytesIO(self.data)
def request_complete(data):
 end=data.find(b'\r\n\r\n')
 if end<0:return None
 head=data[:end+4];line,fields=head.split(b'\r\n',1);headers=http.client.parse_headers(io.BytesIO(fields));body=data[end+4:]
 if mode==2 and not requests:return len(head),line,headers,b''
 if headers.get('Transfer-Encoding','').lower()=='chunked':
  # The stdlib decodes the shared request/response chunked wire format.
  try:
   response=http.client.HTTPResponse(Peer(b'HTTP/1.1 200 OK\r\n'+fields+body));response.begin();decoded=response.read()
  except (http.client.IncompleteRead,ValueError):return None
  if not body.endswith(b'0\r\n\r\n'):return None
  return len(data),line,headers,decoded
 length=int(headers.get('Content-Length','0'))
 if len(body)<length:return None
 return end+4+length,line,headers,body[:length]
def handle_requests():
 global closing
 while True:
  parsed=request_complete(bytes(request))
  if parsed is None:return
  consumed,line,headers,body=parsed;del request[:consumed];index=len(requests);requests.append((line,body));report['requests'].append({'line':line.decode(),'bytes':len(body),'host':headers.get('Host'),'transfer_encoding':headers.get('Transfer-Encoding')})
  assert headers.get('Host')=='esp32.test:443'
  if mode==1:server.write(b'HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nx');return
  if mode==2:server.write(b'HTTP/1.1 413 Too Large\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n');return
  if mode==3:return
  if index==0:
   assert line==b'GET /first HTTP/1.1' and body==b'' and headers.get('X-Test')=='native';payload=bytes(i%251 for i in range(4200));wire=b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Sum\r\nConnection: keep-alive\r\n\r\n'
   for start in range(0,len(payload),333):part=payload[start:start+333];wire+=format(len(part),'x').encode()+b';x="ref"\r\n'+part+b'\r\n'
   server.write(wire+b'0\r\nX-Sum: ok\r\n\r\n')
  elif index==1:
   assert line==b'POST /fixed HTTP/1.1' and body==bytes(i%251 for i in range(137));server.write(b'HTTP/1.1 201 Created\r\nContent-Length: 3\r\nConnection: keep-alive\r\n\r\nyes')
  elif index==2:
   assert line==b'POST /chunked HTTP/1.1' and body==bytes(i%251 for i in range(3137));server.write(b'HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n');closing=True
  else:raise AssertionError('unexpected fourth request')
with (out/'stderr.log').open('wb') as stderr:
 proc=subprocess.Popen([a.qemu,'-M','esp32','-display','none','-monitor','none','-serial','stdio','-qmp','unix:'+str(qmp)+',server=on,wait=off','-drive','file='+str(out/'flash.bin')+',if=mtd,format=raw','-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr)
 try:
  remaining=None;deadline=time.monotonic()+45
  while time.monotonic()<deadline:
   if proc.poll() is not None:raise RuntimeError('QEMU exited')
   if remaining is not None and len(buf)>=remaining:
    wire=bytes(buf[:remaining]);del buf[:remaining];remaining=None
    if closed==1 and mode==0 and not established and not second_server:rx,tx,server=new_server();second_server=True
    rx.write(wire)
    try:
     if not established:server.do_handshake();established=True;report['tls_handshakes']+=1
     while established and not closing:
      try:
       data=server.read(8192)
       if not data:closing=True;break
       request.extend(data);handle_requests()
      except ssl.SSLWantReadError:break
      except ssl.SSLZeroReturnError:closing=True;break
     if closing:
      try:server.unwrap();closed+=1;report['close_notify']=closed;closing=False;established=False
      except ssl.SSLWantReadError:pass
    except ssl.SSLWantReadError:pass
    except ssl.SSLError:
     if mode==0:raise
    pending=tx.read()
    if pending:proc.stdin.write(pending);proc.stdin.flush()
    continue
   if remaining is None and b'\n' in buf:
    line,_,tail=buf.partition(b'\n');buf=bytearray(tail);text=line.decode(errors='replace').strip();lines.append(text)
    if text.startswith('TLS TX '):remaining=int(text[7:],16)
    elif text=='PASS: HTTP facade and TLS memory reclaimed':report['passed']=True;break
    else:print(text,flush=True)
    continue
   ready,_,_=select.select([proc.stdout],[],[],.05)
   if ready:buf.extend(os.read(proc.stdout.fileno(),65536))
  with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as channel:
   channel.settimeout(3);channel.connect(str(qmp));f=channel.makefile('rwb',buffering=0);json.loads(f.readline());f.write(b'{"execute":"qmp_capabilities"}\n')
   while 'return' not in json.loads(f.readline()):pass
   f.write(b'{"execute":"human-monitor-command","arguments":{"command-line":"xp /4wx 0x3ffb0000"}}\n')
   while True:
    msg=json.loads(f.readline())
    if 'return' in msg:report['control_block']=msg['return'];break
  assert report['passed'] and '0x444f4e45 0x00000000 0x00000000' in report['control_block'],report
  if mode==0:assert len(requests)==3 and report['tls_handshakes']==2 and closed==2,report
 finally:
  proc.terminate()
  try:proc.wait(timeout=3)
  except subprocess.TimeoutExpired:proc.kill();proc.wait()
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'uart.log').write_text('\n'.join(lines)+'\n')
print('PASS: HTTP/TLS',a.case)
