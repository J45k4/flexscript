#!/usr/bin/env python3
"""Independent QEMU UART1 echo peer; same firmware still selects internal loopback.
QEMU lacks internal UART loopback and derives TX_DONE from FIFO empty. This
adapter supplies bytes through its actual UART1 character backend instead.
"""
import argparse,hashlib,json,re,selectors,socket,subprocess,time,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--qemu',type=Path,required=True);p.add_argument('--image',type=Path,required=True);p.add_argument('--chip',choices=['esp32','esp32s3'],required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
image=a.image.read_bytes();flash=bytearray(b'\xff'*4194304);offset=4096 if a.chip=='esp32' else 0;assert len(image)<len(flash)-offset;flash[offset:offset+len(image)]=image;(work/'flash.bin').write_bytes(flash)
sockets=tempfile.TemporaryDirectory(prefix='flex-uart-');qpath=Path(sockets.name)/'qmp.sock';upath=Path(sockets.name)/'uart1.sock';assert len(str(qpath).encode())<104 and len(str(upath).encode())<104
for path in [qpath,upath]:
 if path.exists():path.unlink()
sha=lambda b:hashlib.sha256(b).hexdigest();trace=bytearray();pending=bytearray();qbuffer=bytearray();messages=[];events=selectors.DefaultSelector();qmp=None;uart=None;process=None;ident=0;report={'pass':False,'physical_hardware':False,'transport':'QEMU UART1 character backend and independent host echo; internal loopback bit is not emulated by QEMU','chip':a.chip,'image_sha256':sha(image)}
def pump(timeout):
 for key,mask in events.select(timeout):
  try:data=key.fileobj.recv(8192)
  except BlockingIOError:continue
  if not data:events.unregister(key.fileobj);continue
  if key.data=='uart':
   trace.extend(data);assert len(trace)<=16,'unexpected UART1 bytes';pending.extend(data)
  else:
   qbuffer.extend(data)
   while b'\n' in qbuffer:
    line,_,rest=qbuffer.partition(b'\n');qbuffer[:]=rest
    if line.strip():messages.append(json.loads(line))
 if pending:
  try:n=uart.send(pending);del pending[:n]
  except BlockingIOError:pass
 assert len(messages)<10000,'unbounded QMP messages'
def connect(path):
 end=time.monotonic()+5
 while time.monotonic()<end:
  assert process.poll() is None,'QEMU exited before socket connection'
  s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
  try:s.connect(str(path));s.setblocking(False);return s
  except (FileNotFoundError,ConnectionRefusedError):s.close();time.sleep(.01)
 raise AssertionError('QEMU socket unavailable: '+str(path))
def command(name,arguments=None):
 global ident
 ident+=1;packet={'execute':name,'id':ident}
 if arguments:packet['arguments']=arguments
 qmp.sendall((json.dumps(packet)+'\n').encode());end=time.monotonic()+3
 while time.monotonic()<end:
  pump(.01)
  for value in messages:
   if value.get('id')==ident:
    assert 'error' not in value,value;return value.get('return')
 raise AssertionError('QMP command timeout: '+name)
def xp(address,words):return command('human-monitor-command',{'command-line':f'xp /{words}wx 0x{address:x}'})
try:
 with (work/'qemu.out').open('wb') as out,(work/'qemu.err').open('wb') as err:
  process=subprocess.Popen([str(a.qemu.resolve()),'-M',a.chip,'-display','none','-monitor','none','-qmp',f'unix:{qpath},server=on,wait=off','-serial','file:'+str(work/'uart0.log'),'-serial',f'unix:{upath},server=on,wait=off','-drive',f'file={work}/flash.bin,if=mtd,format=raw','-nic','none','-no-reboot','-S'],stdout=out,stderr=err)
  qmp=connect(qpath);events.register(qmp,selectors.EVENT_READ,'qmp');uart=connect(upath);events.register(uart,selectors.EVENT_READ,'uart');command('qmp_capabilities');command('cont');address=0x3ffb0000 if a.chip=='esp32' else 0x3fcb0000;end=time.monotonic()+10;done=False
  while time.monotonic()<end and not done:
   status=xp(address+4,1);assert '0x54524150' not in status,'guest trap';done='0x444f4e45' in status
   if not done:pump(.01)
  assert done,'guest did not complete';report['main_result']=xp(address+8,2);assert '0x00000000 0x00000000' in report['main_result'],report['main_result'];command('quit');process.wait(timeout=3);assert process.returncode==0,process.returncode
  expected=bytes((i*37+11)&255 for i in range(16));assert bytes(trace)==expected,(bytes(trace),expected);serial=(work/'uart0.log').read_bytes();assert b'PASS: UART1 loopback, RX and TX_DONE interrupts\r\n' in serial,serial;assert (work/'flash.bin').read_bytes()==flash,'flash changed';report.update(pass_=True,echo_bytes=len(trace),uart1_hex=trace.hex(),uart0_sha256=sha(serial),full4MiB_flash_unchanged=True);report['pass']=report.pop('pass_')
finally:
 if process is not None and process.poll() is None:
  try:command('quit')
  except Exception:process.terminate()
  try:process.wait(timeout=3)
  except subprocess.TimeoutExpired:process.kill();process.wait(timeout=3)
 if process is not None:report['qemu_exit']=process.returncode
 for s in [qmp,uart]:
  if s is not None:s.close()
 events.close();sockets.cleanup();(work/'uart1.bin').write_bytes(trace);(work/'qmp.json').write_text(json.dumps(messages,indent=2)+'\n');a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'chip':a.chip,'echo_bytes':len(trace),'transport':report['transport']}))
