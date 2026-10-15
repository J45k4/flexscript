from pathlib import Path
import subprocess,socket,ssl,time,os,select,json,argparse,struct
# Independent OpenSSL peer; UART is only the emulator test transport.
p=argparse.ArgumentParser()
p.add_argument('--case',choices=['tls13-ecdsa','tls12-rsa','wrong-host','expired','future','untrusted-ca','tampered-record','truncated-stream','backpressure','tcp-refused','native-no-memory','scheduler-progress'],default='tls13-ecdsa')
p.add_argument('--compiler',required=True);p.add_argument('--builder',required=True);p.add_argument('--qemu',required=True);p.add_argument('--prefix',required=True);p.add_argument('--vendor',required=True);p.add_argument('--rom',required=True);p.add_argument('--tls',required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--certificates',type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];build=root/'build';qemu=a.qemu;prefix=a.prefix;certs=a.certificates.resolve();out=a.work.resolve();out.mkdir(parents=True,exist_ok=True)
cases={'tls13-ecdsa':(0,'ecdsa',ssl.TLSVersion.TLSv1_3),'tls12-rsa':(0,'rsa',ssl.TLSVersion.TLSv1_2),'wrong-host':(1,'ecdsa',ssl.TLSVersion.TLSv1_3),'expired':(2,'ecdsa',ssl.TLSVersion.TLSv1_3),'future':(3,'ecdsa',ssl.TLSVersion.TLSv1_3),'untrusted-ca':(4,'ecdsa',ssl.TLSVersion.TLSv1_3),'tampered-record':(5,'ecdsa',ssl.TLSVersion.TLSv1_3),'truncated-stream':(6,'ecdsa',ssl.TLSVersion.TLSv1_3),'backpressure':(7,'ecdsa',ssl.TLSVersion.TLSv1_3),'tcp-refused':(8,'ecdsa',ssl.TLSVersion.TLSv1_3),'native-no-memory':(9,'ecdsa',ssl.TLSVersion.TLSv1_3),'scheduler-progress':(10,'ecdsa',ssl.TLSVersion.TLSv1_3)};mode,kind,version=cases[a.case];case=out/a.case;case.mkdir(exist_ok=True)
ca=(certs/('ca-untrusted.der' if mode==4 else 'ca.der')).read_bytes();source=case/'firmware.flex';source.write_text('import "'+str(root/'tests/esp32/tls-uart-oracle.flex')+'";\nfn to_mode(){return '+str(mode)+';}\nfn to_ca_size(){return '+str(len(ca))+';}\nfn to_ca(){let h="'+ca.hex()+'";let p=alloc('+str(len(ca))+');let i=0;while i<'+str(len(ca))+'{let a=load8(h+i*2);let b=load8(h+i*2+1);if a<=57{a=a-48;}else{a=a-87;}if b<=57{b=b-48;}else{b=b-87;}store8(p+i,(a<<4)|b);i=i+1;}return p;}\n')
with (case/'build.log').open('w') as log:subprocess.run([a.builder,'--compiler',a.compiler,'--source',str(source),'--vendor',a.vendor,'--rom',a.rom,'--output',str(case/'firmware.bin'),'--ld',prefix+'ld','--gcc',prefix+'gcc','--tls',a.tls],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
image=bytearray(b'\xff'*4194304);data=(case/'firmware.bin').read_bytes();image[4096:4096+len(data)]=data;(case/'flash.bin').write_bytes(image)
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.minimum_version=version;ctx.maximum_version=version;ctx.load_cert_chain(certs/(kind+'.pem'),certs/(kind+'.key'));rx=ssl.MemoryBIO();tx=ssl.MemoryBIO();server=ctx.wrap_bio(rx,tx,server_side=True);request=bytearray();established=False;response_sent=False;buf=bytearray();lines=[];qmp=case/'qmp.sock';qmp.unlink(missing_ok=True)
report={'case':a.case,'mode':mode,'server_certificate':kind,'openssl_version':ssl.OPENSSL_VERSION,'peer_version':None,'application_request':False,'main_return':None,'passed':False}
with (case/'stderr.log').open('wb') as stderr:
 process=subprocess.Popen([qemu,'-M','esp32','-display','none','-monitor','none','-serial','stdio','-qmp','unix:'+str(qmp)+',server=on,wait=off','-drive','file='+str(case/'flash.bin')+',if=mtd,format=raw','-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr)
 try:
  deadline=time.monotonic()+45;remaining=None
  while time.monotonic()<deadline:
   if process.poll() is not None:raise RuntimeError('QEMU exited '+str(process.returncode))
   if remaining is not None:
    if len(buf)>=remaining:
     wire=bytes(buf[:remaining]);del buf[:remaining];remaining=None;rx.write(wire)
     try:
      if not established:server.do_handshake();established=True;report['peer_version']=server.version();report['cipher']=server.cipher()[0]
      if established:
       try:
        part=server.read(4096)
        if part:request.extend(part)
       except (ssl.SSLWantReadError,ssl.SSLZeroReturnError):pass
       if request and not response_sent:
        if bytes(request)!=b'Flexscript TLS request':raise RuntimeError('unexpected client plaintext '+repr(bytes(request)))
        report['application_request']=True;server.write(b'OpenSSL verified reply!');response_sent=True
     except ssl.SSLWantReadError:pass
     except ssl.SSLError as error:
      report['server_alert']=str(error)
      if mode in (0,7,10):raise
     pending=tx.read()
     if pending:
      if mode==5 and response_sent:pending=pending[:-1]+bytes([pending[-1]^1]);report['ciphertext_tampered']=True
      process.stdin.write(pending);process.stdin.flush()
     continue
   elif b'\n' in buf:
    line,_,tail=buf.partition(b'\n');buf=bytearray(tail);text=line.decode(errors='replace').strip();lines.append(text)
    if text.startswith('TLS TX '):remaining=int(text[7:],16)
    else:print(text,flush=True)
    if text=='PASS: TLS memory reclaimed':report['passed']=True;break
    if text.startswith('FAIL:'):break
    continue
   ready,_,_=select.select([process.stdout],[],[],.1)
   if ready:part=os.read(process.stdout.fileno(),65536);buf.extend(part)
  # Query the guest control block, so an early main return is visible even if
  # it never emitted a success marker. This is independent of UART assertions.
  with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as channel:
   channel.settimeout(3);channel.connect(str(qmp));f=channel.makefile('rwb',buffering=0);json.loads(f.readline());f.write(b'{"execute":"qmp_capabilities"}\n')
   while 'return' not in json.loads(f.readline()):pass
   f.write(b'{"execute":"human-monitor-command","arguments":{"command-line":"xp /4wx 0x3ffb0000"}}\n')
   while True:
    msg=json.loads(f.readline())
    if 'return' in msg:report['control_block']=msg['return'];break
  assert report['passed'],'firmware did not pass: '+report.get('control_block','')
  assert '0x444f4e45 0x00000000 0x00000000' in report['control_block'],'main did not return zero'
  if mode in (0,5,6,7,10):assert report['peer_version'],report
  if mode in (0,7,10):assert report['application_request'] and bytes(request)==b'Flexscript TLS request',report
 except BaseException as error:report['error']=str(error);raise
 finally:
  process.terminate()
  try:process.wait(timeout=3)
  except subprocess.TimeoutExpired:process.kill();process.wait()
  (case/'uart.log').write_text('\n'.join(lines)+'\n');(case/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS:',a.case,flush=True)
