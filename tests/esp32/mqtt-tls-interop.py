"""Run the actual Xtensa MQTT/TLS facade against an independent Mosquitto TLS broker.

Only QEMU's missing radio transport is replaced by UART BIO callbacks. This is
not physical Wi-Fi/TCP evidence. Mbed TLS verifies the generated CA and hostname.
"""
from pathlib import Path
import argparse, hashlib, json, os, select, socket, subprocess, time
p=argparse.ArgumentParser();p.add_argument('--case',choices=['transactions','auth-refused','wrong-host','cancel','retry-exhausted','reconnect','configuration','native-no-memory','retained-will','close-notify','close-reset','close-timeout'],required=True)
for name in ['compiler','builder','qemu','prefix','vendor','rom','tls','broker','password-tool']:p.add_argument('--'+name,required=True)
p.add_argument('--work',type=Path,required=True);p.add_argument('--certificates',type=Path,required=True);a=p.parse_args();root=Path(__file__).resolve().parents[2];out=a.work.resolve()/a.case;out.mkdir(parents=True,exist_ok=True);certs=a.certificates.resolve();mode=['transactions','auth-refused','wrong-host','cancel','retry-exhausted','reconnect','configuration','native-no-memory','retained-will','close-notify','close-reset','close-timeout'].index(a.case)
ca=(certs/'ca.der').read_bytes();src=out/'firmware.flex';src.write_text('import "'+str(root/'tests/esp32/mqtt-tls-oracle.flex')+'";\nfn mt_mode(){return '+str(mode)+';}\nfn mt_ca_size(){return '+str(len(ca))+';}\nfn mt_ca(){let h="'+ca.hex()+'";let p=alloc('+str(len(ca))+');let i=0;while i<'+str(len(ca))+'{store8(p+i,(nb_hex(load8(h+i*2))<<4)|nb_hex(load8(h+i*2+1)));i=i+1;}return p;}\n')
with (out/'build.log').open('w') as log:subprocess.run([a.builder,'--compiler',a.compiler,'--source',str(src),'--vendor',a.vendor,'--rom',a.rom,'--output',str(out/'firmware.bin'),'--ld',a.prefix+'ld','--gcc',a.prefix+'gcc','--tls',a.tls],cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
image=bytearray(b'\xff'*4194304);data=(out/'firmware.bin').read_bytes();image[4096:4096+len(data)]=data;(out/'flash.bin').write_bytes(image)
password_file=out/'passwords';subprocess.run([a.password_tool,'-b','-c',str(password_file),'test-user','test-password'],check=True,capture_output=True)
with socket.socket() as choose:choose.bind(('127.0.0.1',0));port=choose.getsockname()[1]
config=out/'mosquitto.conf';config.write_text(f'listener {port} 127.0.0.1\nallow_anonymous false\npassword_file {password_file}\npersistence false\nmax_inflight_messages 2\nlog_type all\ncertfile {certs/"ecdsa.pem"}\nkeyfile {certs/"ecdsa.key"}\ntls_version tlsv1.3\n')
report={'case':a.case,'passed':False,'scope':'Xtensa MQTT/TLS facade with UART BIO test transport; no physical radio','broker_sha256':hashlib.sha256(Path(a.broker).read_bytes()).hexdigest(),'connections':0,'drops':0,'tx_ciphertext_bytes':0,'rx_ciphertext_bytes':0};qmp=out/'qmp.sock';qmp.unlink(missing_ok=True);active=None;proc=None;lines=[];buf=bytearray();remaining=None
with (out/'broker.log').open('wb') as log,(out/'stderr.log').open('wb') as stderr:
 broker=subprocess.Popen([a.broker,'-c',str(config),'-v'],stdout=log,stderr=subprocess.STDOUT)
 try:
  deadline=time.monotonic()+5
  while True:
   if broker.poll() is not None:raise RuntimeError('broker exited; see broker.log')
   try:
    with socket.create_connection(('127.0.0.1',port),timeout=.1):break
   except OSError:
    if time.monotonic()>deadline:raise
    time.sleep(.02)
  proc=subprocess.Popen([a.qemu,'-M','esp32','-display','none','-monitor','none','-serial','stdio','-qmp','unix:'+str(qmp)+',server=on,wait=off','-drive','file='+str(out/'flash.bin')+',if=mtd,format=raw','-nic','none','-no-reboot'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=stderr)
  deadline=time.monotonic()+60
  while time.monotonic()<deadline:
   if proc.poll() is not None:raise RuntimeError('QEMU exited')
   if remaining is not None and len(buf)>=remaining:
    wire=bytes(buf[:remaining]);del buf[:remaining];remaining=None
    if active is None:raise RuntimeError('TLS output without active transport')
    try:active.sendall(wire);report['tx_ciphertext_bytes']+=len(wire)
    except (BrokenPipeError,ConnectionResetError):pass
    continue
   if remaining is None and b'\n' in buf:
    line,_,tail=buf.partition(b'\n');buf=bytearray(tail);text=line.decode(errors='replace').strip();lines.append(text)
    if text.startswith('TLS TX '):remaining=int(text[7:],16)
    elif text=='MQTT TLS OPEN':
     if active is not None:active.close()
     active=socket.create_connection(('127.0.0.1',port),timeout=3);active.setblocking(False);report['connections']+=1
    elif text=='MQTT TRANSPORT DROP':
     if active is not None:active.close();active=None
     report['drops']+=1;proc.stdin.write(b'DROPPED\n');proc.stdin.flush()
    elif text=='PASS: MQTT facade and TLS memory reclaimed':report['passed']=True;break
    elif text.startswith('MQTT TEST FAILED '):report['fixture_failure']=int(text[17:],16);break
    else:print(text,flush=True)
    continue
   readers=[proc.stdout]
   if active is not None:readers.append(active)
   ready,_,_=select.select(readers,[],[],.02)
   if proc.stdout in ready:buf.extend(os.read(proc.stdout.fileno(),65536))
   if active is not None and active in ready:
    try:wire=active.recv(8192)
    except ConnectionResetError:wire=b''
    if wire:report['rx_ciphertext_bytes']+=len(wire);proc.stdin.write(wire);proc.stdin.flush()
    else:active.close();active=None
  with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as channel:
   channel.settimeout(3);channel.connect(str(qmp));f=channel.makefile('rwb',buffering=0);json.loads(f.readline());f.write(b'{"execute":"qmp_capabilities"}\n')
   while 'return' not in json.loads(f.readline()):pass
   for _ in range(20):
    f.write(b'{"execute":"human-monitor-command","arguments":{"command-line":"xp /4wx 0x3ffb0000"}}\n')
    while True:
     msg=json.loads(f.readline())
     if 'return' in msg:report['control_block']=msg['return'];break
    if '0x444f4e45' in report['control_block'] or '0x54524150' in report['control_block']:break
    time.sleep(.02)
  assert report['passed'] and '0x444f4e45 0x00000000 0x00000000' in report['control_block'],report
  text=(out/'broker.log').read_text()
  if mode in (0,5,8,9,10):
   assert text.count(' as flexscript-xtensa (')==(3 if mode in (5,8) else 2),text
   for qos in range(3):assert f'q{qos},' in text
   assert 'Received PINGREQ' in text and text.count('Received SUBSCRIBE')==(3 if mode==8 else 2) and text.count('Received UNSUBSCRIBE')==(3 if mode==8 else 2)
   if mode in (5,8):assert 'Received PUBLISH from flexscript-xtensa (d1, q1,' in text
  report['authenticated_tls_broker']=mode not in (2,4,6,7)
 finally:
  if active is not None:active.close()
  for process in [proc,broker]:
   if process is not None:
    process.terminate()
    try:process.wait(timeout=3)
    except subprocess.TimeoutExpired:process.kill();process.wait()
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'uart.log').write_text('\n'.join(lines)+'\n')
print('PASS: MQTT/TLS/Mosquitto',a.case)
