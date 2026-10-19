#!/usr/bin/env python3
"""Authorized RAM-only GNU cycle measurements with full-flash guards/reset."""
import argparse,hashlib,json,os,re,signal,subprocess,time
from pathlib import Path
import serial
from irq_cycle_protocol import parse,parse_ram,header as irq_header,record_words
p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','native-proof','backup','espflash','work'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--clock',type=int,choices=(40,160),required=True)
for name in ('backup-sha256','port'):p.add_argument('--'+name,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];sha=lambda b:hashlib.sha256(b).hexdigest()
backup=a.backup.read_bytes();assert len(backup)==4194304 and sha(backup)==a.backup_sha256
proof=json.loads(a.native_proof.read_text());manifest=json.loads((a.matrix/'manifest.json').read_text());assert proof['pass'] and proof['native_records']==768 and proof['family'] in ('IRQ7-entry-return-v1','IRQ7-entry-return-v2-marker') and proof['images']==manifest
for f,h in proof['source_sha256'].items():assert sha((root/f).read_bytes())==h,('build source changed',f)
item=next(c for c in manifest if c['clock_mhz']==a.clock);elf=a.matrix/item['elf'];image=elf.read_bytes();raw=a.matrix/item['native_records'];header=a.matrix/item['native_header']
assert sha(image)==item['sha256'] and sha(raw.read_bytes())==item['native_records_sha256'] and sha(header.read_bytes())==item['native_header_sha256']
words=len(record_words(image));assert proof.get('record_words',16)==item.get('record_words',16)==words
assert proof['family']==('IRQ7-entry-return-v2-marker' if words==17 else 'IRQ7-entry-return-v1')
native=parse_ram(raw.read_bytes(),image);assert len(native)==item['records']==384
irq_header(header.read_bytes(),a.clock)
flash=a.espflash.resolve();assert flash.is_file() and os.access(flash,os.X_OK)
assert Path(a.port).is_symlink() and Path(a.port).name=='usb-1a86_USB_Serial-if00-port0'
os.umask(0o077);work=a.work.resolve();assert not work.exists();work.mkdir(parents=True)
md5=hashlib.md5(backup).hexdigest();common=['--port',a.port,'--chip','esp32','--baud','115200','--non-interactive','--skip-update-check','--no-stub']
report={'pass':False,'ram_only':True,'flash_write_requested':False,'clock_mhz':a.clock,'ELF_sha256':sha(image),'native_records_sha256':sha(raw.read_bytes()),'backup_sha256':a.backup_sha256,'espflash_sha256':sha(flash.read_bytes()),'expected_full_flash_MD5':md5,'before_matches':False,'after_matches':False,'final_reset':False,'started_at':time.time()};path=work/'physical.json';uart=None

def save():path.write_text(json.dumps(report,indent=2)+'\n')
def run(args,label):
 print(label,flush=True);q=subprocess.run([str(x) for x in [flash,*args]],capture_output=True,timeout=90);(work/(label+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(label,q.stdout[-600:],q.stderr[-600:]);return (q.stdout+q.stderr).decode(errors='replace')
def checksum(label):return any(int(v,16)==int(md5,16) for v in re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',run(['checksum-md5',*common,'--after','no-reset','0x0','0x400000'],label)))
def interrupted(signum,frame):raise InterruptedError('RAM cycle probe interrupted;checking flash andresetting')
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
try:
 report['before_matches']=checksum('before');save();assert report['before_matches'],'original fullflash mismatch;abort before RAM load'
 uart=serial.Serial(port=None,baudrate=115200,timeout=.1);uart.dtr=False;uart.rts=False;uart.port=a.port;uart.open();uart.reset_input_buffer()
 run(['flash','--ram',*common,'--after','no-reset','--ignore-app-descriptor',elf.resolve()],'RAM-load')
 data=bytearray(uart.read(uart.in_waiting));marker=f'IRQC COMPLETE CLOCK {a.clock:016x}\r\n'.encode();deadline=time.monotonic()+45
 while time.monotonic()<deadline and marker not in data and b' FAIL' not in data:
  data.extend(uart.read(4096));(work/'uart.bin').write_bytes(data)
 data.extend(uart.read(4096));(work/'uart.bin').write_bytes(data);report['UART_sha256']=sha(data)
 physical=parse(bytes(data),image,a.clock);report['observations']=physical
 report['native_comparison']=[{'identity':[c[k] for k in ('PROFILE','GATE','TALIGN','RALIGN','REPEAT')],'physical_entry':(c['IRQCC']-c['START'])&0xffffffff,'native_entry':(n['IRQCC']-n['START'])&0xffffffff,'physical_return':(c['END']-c['RETCC'])&0xffffffff,'native_return':(n['END']-n['RETCC'])&0xffffffff,'architectural_differences':{k:[c[k],n[k]] for k in c if k not in ('START','IRQCC','RETCC','END') and c[k]!=n[k]}} for c,n in zip(physical,native)]
 report['completed_observations']=len(physical);report['native_transport']='actual guest-RAM checkpoint';report['physical_transport']='actual full UART dump aftercollecting allrecords';report['completed']=len(physical)==384;save()
 print('VERIFIED:384 physical IRQ7 observations;raw entry/return stamps and EPCs retained',flush=True)
finally:
 signal.signal(signal.SIGTERM,signal.SIG_IGN);signal.signal(signal.SIGINT,signal.SIG_IGN)
 if uart is not None:uart.close()
 try:
  if report['before_matches']:report['after_matches']=checksum('after')
 finally:
  try:run(['reset',*common],'final-reset');report['final_reset']=True
  finally:
   report['finished_at']=time.time();report['pass']=report.get('completed',False) and report['before_matches'] and report['after_matches'] and report['final_reset'];save()
assert report['pass'];print('PASS:IRQ7 entry/return RAM observations;original4MiB unchanged/reset',flush=True)
