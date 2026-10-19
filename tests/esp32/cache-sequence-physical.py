#!/usr/bin/env python3
"""Authorized read-only RAM experiment matrix with full-flash guards/reset.

Each manifest ELF is hash checked andloaded with --ram only. Reset separates
cases. Completion versus timeout after the armed-read marker are observations;
neither claims emulator fidelity. Finally verifies the original full4MiB.
"""
import argparse,hashlib,json,os,re,signal,subprocess,time
from pathlib import Path
import serial
p=argparse.ArgumentParser(description=__doc__)
for n in ('manifest','backup','work','espflash'):p.add_argument('--'+n,type=Path,required=True)
for n in ('backup-sha256','port'):p.add_argument('--'+n,required=True)
p.add_argument('--first',type=int,default=0);p.add_argument('--count',type=int,default=4)
a=p.parse_args();assert 0<=a.first<16 and 1<=a.count<=4 and a.first+a.count<=16,'bounded batch selection';flash=str(a.espflash.resolve());assert Path(flash).is_file() and os.access(flash,os.X_OK),'explicit espflash executable';os.umask(0o077);w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);backup=a.backup.read_bytes();sha=lambda b:hashlib.sha256(b).hexdigest();assert len(backup)==4194304 and sha(backup)==a.backup_sha256;md5=hashlib.md5(backup).hexdigest();cases=json.loads(a.manifest.read_text());assert len(cases)==16 and {(c['bus'],c['mode']) for c in cases}=={(b,m) for b in (0,1) for m in range(8)}
selected=cases[a.first:a.first+a.count]
for c in selected:
 c['elf']=str((a.manifest.parent/c['elf']).resolve());assert sha(Path(c['elf']).read_bytes())==c['sha256']
common=['--port',a.port,'--chip','esp32','--baud','115200','--non-interactive','--skip-update-check','--no-stub'];report={'pass':False,'ram_only':True,'espflash_sha256':sha(Path(flash).read_bytes()),'flash_write_requested':False,'backup_sha256':a.backup_sha256,'expected_full_flash_MD5':md5,'before_matches':False,'after_matches':False,'final_reset':False,'selection':{'first':a.first,'count':a.count},'cases':[],'started_at':time.time()};rp=w/'physical.json'
def save():rp.write_text(json.dumps(report,indent=2)+'\n')
def run(args,name):
 q=subprocess.run(args,capture_output=True,timeout=90);(w/(name+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(name,q.stdout[-500:],q.stderr[-500:]);return (q.stdout+q.stderr).decode(errors='replace')
def checksum(name):return any(int(s,16)==int(md5,16) for s in re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',run([flash,'checksum-md5',*common,'--after','no-reset','0x0','0x400000'],name)))
def interrupted(signum,frame):raise InterruptedError('RAM batch interrupted bysignal'+str(signum))
signal.signal(signal.SIGTERM,interrupted);signal.signal(signal.SIGINT,interrupted)
uart=None
try:
 print('before',flush=True);report['before_matches']=checksum('before');save();assert report['before_matches'],'original differs;abort before RAM load'
 for case in selected:
  label=f"bus{case['bus']}-mode{case['mode']}";print(label,flush=True);uart=serial.Serial(port=None,baudrate=115200,timeout=.1);uart.dtr=False;uart.rts=False;uart.port=a.port;uart.open();uart.reset_input_buffer();run([flash,'flash','--ram',*common,'--after','no-reset','--ignore-app-descriptor',case['elf']],label+'-RAM-load');data=bytearray(uart.read(uart.in_waiting));marker=f"CACHE SEQ COMPLETE {case['bus']:016x} MODE {case['mode']:016x}".encode();deadline=time.monotonic()+5
  while time.monotonic()<deadline and marker not in data and b' FAIL' not in data:data.extend(uart.read(4096))
  data.extend(uart.read(4096));uart.close();uart=None;(w/(label+'.uart')).write_bytes(data);entry={**case,'UART_sha256':sha(data),'completed':marker in data,'armed_second_read':b'SECOND READ ARMED' in data,'UART':data.decode(errors='replace'),'final_reset':False};report['cases'].append(entry);save();assert b' FAIL' not in data,(label,'fixture assertion');assert entry['completed'] or entry['armed_second_read'],(label,'stopped before test access');run([flash,'reset',*common],label+'-reset');entry['final_reset']=True;save();print('completed' if entry['completed'] else 'second read stalled untilreset',flush=True)
finally:
 if uart is not None:uart.close()
 try:
  if report['before_matches']:print('after',flush=True);report['after_matches']=checksum('after')
 finally:
  run([flash,'reset',*common],'final-reset');report['final_reset']=True;report['finished_at']=time.time();report['pass']=report['before_matches'] and report['after_matches'] and report['final_reset'] and len(report['cases'])==a.count and all(c['final_reset'] for c in report['cases']);save()
assert report['pass'];print('PASS: bounded RAM sequence observations;original full4MiB unchanged/reset',flush=True)
