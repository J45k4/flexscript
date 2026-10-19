#!/usr/bin/env python3
"""Authorized single-image GPIO21--GPIO25 RAM test; no flash writes.

Verify the exact native image/transcript before serial access. Complete 4MiB
checksum guards and a final reset surround the test, including signal cleanup.
"""
import argparse,hashlib,json,os,re,signal,subprocess,time
from pathlib import Path
import serial
p=argparse.ArgumentParser(description=__doc__)
for name in ('elf','native-proof','native-uart','backup','espflash','work'):p.add_argument('--'+name,type=Path,required=True)
for name in ('backup-sha256','port'):p.add_argument('--'+name,required=True)
a=p.parse_args();sha=lambda data:hashlib.sha256(data).hexdigest()
backup=a.backup.read_bytes();assert len(backup)==4194304 and sha(backup)==a.backup_sha256
native=json.loads(a.native_proof.read_text());expected=a.native_uart.read_bytes()
assert native['pass'] and native['absent_wire_control_detected'] and native['frozen_ELF_rebuild_byte_identical']
assert sha(a.elf.read_bytes())==native['ELF_sha256'] and sha(expected)==native['native_UART_sha256']
start=b'GPIO WIRE START 21 25\r\n';marker=b'PASS: GPIO21--GPIO25 bidirectional drive,pulls,open-drain and5IRQ modes\r\n'
assert expected.startswith(start) and expected.endswith(marker) and b' FAIL' not in expected
rows=re.findall(rb'GPIO WIRE ([0-9a-f]{16}) TX ([0-9a-f]{16}) RX ([0-9a-f]{16}) MODE ([0-9a-f]{16}) COUNT ([0-9a-f]{16})\r\n',expected)
wanted=[]
for tx,rx in ((21,25),(25,21)):
 wanted += [(1,tx,rx,pull,64) for pull in range(3)]
 wanted += [(2,tx,rx,pull,16) for pull in (1,2)]
 wanted += [(3,tx,rx,1,64)]
 wanted += [(4,tx,rx,event,16) for event in range(1,6)]
assert [tuple(int(v,16) for v in row) for row in rows]==wanted
assert b'GPIO WIRE CHECKS 00000000000002e0\r\n' in expected
assert Path(a.port).is_symlink() and Path(a.port).name=='usb-1a86_USB_Serial-if00-port0'
flash=a.espflash.resolve();assert flash.is_file() and os.access(flash,os.X_OK)
os.umask(0o077);work=a.work.resolve();assert not work.exists();work.mkdir(parents=True)
md5=hashlib.md5(backup).hexdigest();common=['--port',a.port,'--chip','esp32','--baud','115200','--non-interactive','--skip-update-check','--no-stub']
report={'pass':False,'ram_only':True,'flash_write_requested':False,'ELF_sha256':native['ELF_sha256'],'native_UART_sha256':sha(expected),'backup_sha256':a.backup_sha256,'espflash_sha256':sha(flash.read_bytes()),'expected_full_flash_MD5':md5,'before_matches':False,'after_matches':False,'final_reset':False,'started_at':time.time()}
path=work/'physical.json';uart=None

def save():path.write_text(json.dumps(report,indent=2)+'\n')
def run(args,label):
 print(label,flush=True);q=subprocess.run([str(x) for x in [flash,*args]],capture_output=True,timeout=90);(work/(label+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(label,q.stdout[-500:],q.stderr[-500:]);return (q.stdout+q.stderr).decode(errors='replace')
def checksum(label):return any(int(v,16)==int(md5,16) for v in re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',run(['checksum-md5',*common,'--after','no-reset','0','0x400000'],label)))
def interrupted(signum,frame):raise InterruptedError('RAM GPIO probe interrupted; checking flash and resetting')
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
try:
 report['before_matches']=checksum('before');save();assert report['before_matches'],'original fullflash mismatch; abort before RAM load'
 uart=serial.Serial(port=None,baudrate=115200,timeout=.1);uart.dtr=False;uart.rts=False;uart.port=a.port;uart.open();uart.reset_input_buffer()
 run(['flash','--ram',*common,'--after','no-reset','--ignore-app-descriptor',a.elf.resolve()],'RAM-load')
 data=bytearray(uart.read(uart.in_waiting));deadline=time.monotonic()+15
 while time.monotonic()<deadline and marker not in data and b' FAIL' not in data:
  data.extend(uart.read(4096));(work/'uart.bin').write_bytes(data)
 data.extend(uart.read(4096));(work/'uart.bin').write_bytes(data)
 report['UART_sha256']=sha(data);report['UART']=data.decode(errors='replace')
 app=bytes(data)[bytes(data).find(start):] if start in data else b''
 report['native_application_UART_matches']=app==expected
 report['raw_UART_identical']=bytes(data)==expected
 report['completed']=marker in data and b' FAIL' not in data and data.count(start)==1 and app==expected
 save();assert report['completed'],('GPIO probe failed or differed from native transcript',report['UART'])
 print('GPIO physical:736 samples,160 callbacks;complete native application UART matches',flush=True)
finally:
 signal.signal(signal.SIGTERM,signal.SIG_IGN);signal.signal(signal.SIGINT,signal.SIG_IGN)
 if uart is not None:uart.close()
 try:
  if report['before_matches']:report['after_matches']=checksum('after')
 finally:
  try:run(['reset',*common],'final-reset');report['final_reset']=True
  finally:
   report['finished_at']=time.time();report['pass']=report.get('completed',False) and report['before_matches'] and report['after_matches'] and report['final_reset'];save()
assert report['pass'];print('PASS: GPIO RAM hardware verification;original4MiB unchanged/reset',flush=True)
