#!/usr/bin/env python3
"""Explicitly authorized temporary cached firmware test with full restoration.

Requires exact image/ELF/backup hashes and an expected native UART transcript.
Only the sector-aligned image interval at0x1000 is written. The finally path
restores that interval,checks all4MiB,and resets; a full restore is the fallback.
"""
import argparse,hashlib,json,os,re,subprocess,time
from pathlib import Path
import serial
p=argparse.ArgumentParser(description=__doc__)
for n in ('image','elf','backup','native-uart','work'):p.add_argument('--'+n,type=Path,required=True)
for n in ('image-sha256','elf-sha256','backup-sha256','port','marker'):p.add_argument('--'+n,required=True)
a=p.parse_args();os.umask(0o077);w=a.work.resolve();w.mkdir(exist_ok=True,parents=True)
sha=lambda data:hashlib.sha256(data).hexdigest()
original=a.backup.read_bytes();image=a.image.read_bytes();elf=a.elf.read_bytes();expected=a.native_uart.read_bytes();marker=a.marker.encode()
assert len(original)==4194304 and sha(original)==a.backup_sha256,'full backup hash'
assert 0<len(image)<=0x3ff000 and len(image)%4096==0 and sha(image)==a.image_sha256,'image hash/alignment'
assert elf[:4]==b'\x7fELF' and sha(elf)==a.elf_sha256,'ELF hash'
assert marker in expected and expected.endswith(b'\r\n'),'expected native UART'
patched=original[:4096]+image+original[4096+len(image):]
original_md5=hashlib.md5(original).hexdigest();patched_md5=hashlib.md5(patched).hexdigest()
common=['--no-stub','--port',a.port,'--chip','esp32','--baud','115200','--non-interactive','--skip-update-check'];fast=common.copy();fast[fast.index('--baud')+1]='460800'
r={'pass':False,'restored':False,'final_reset':False,'flash_write_requested':True,'started_at':time.time(),'ELF_sha256':sha(elf),'image_sha256':sha(image),'native_UART_sha256':sha(expected),'backup_sha256':sha(original),'expected_original_MD5':original_md5,'expected_probe_MD5':patched_md5,'image_offset':4096,'image_bytes':len(image),'stages':[]};report=w/'physical.json'
def save():report.write_text(json.dumps(r,indent=2)+'\n')
def run(args,label,timeout=240):
 print(label,flush=True);r['stages'].append(label);save();q=subprocess.run(args,capture_output=True,timeout=timeout);(w/(label+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(label,q.stdout[-1000:],q.stderr[-1000:]);return (q.stdout+q.stderr).decode(errors='replace')
def same(text,digest):return any(int(s,16)==int(digest,16) for s in re.findall(r'0x([0-9a-fA-F]{1,32})(?![0-9a-fA-F])',text))
def checksum(label,digest):return same(run(['espflash','checksum-md5',*common,'--after','no-reset','0x0','0x400000'],label),digest)
mutating=False;uart=None
try:
 r['before_matches']=checksum('before',original_md5);save();assert r['before_matches'],'device differs from verified backup; abort before flash write'
 mutating=True;run(['espflash','write-bin',*fast,'--after','no-reset','0x1000',str(a.image.resolve())],'write-probe')
 uart=serial.Serial(port=None,baudrate=115200,timeout=.1);uart.dtr=False;uart.rts=False;uart.port=a.port;uart.open();uart.reset_input_buffer();uart.rts=True;time.sleep(.1);uart.rts=False
 data=bytearray();end=time.monotonic()+65
 while time.monotonic()<end and marker not in data and b' FAIL' not in data:
  data.extend(uart.read(4096));(w/'uart.bin').write_bytes(data)
 end=time.monotonic()+1
 while time.monotonic()<end:data.extend(uart.read(4096))
 (w/'uart.bin').write_bytes(data);r['UART_sha256']=sha(data);r['UART']=data.decode(errors='replace');r['native_UART_matches']=expected in data;r['probe_pass']=marker in data and b' FAIL' not in data and r['native_UART_matches'];save();print(r['UART'],flush=True)
 uart.close();uart=None;r['probe_flash_matches']=checksum('probe-checksum',patched_md5);save();assert r['probe_pass'] and r['probe_flash_matches'],'cached firmware or full-image verification failed'
except BaseException as error:r['error']=repr(error);save();raise
finally:
 if uart is not None:uart.close()
 try:
  if mutating:
   for attempt,baud in enumerate(('460800','115200')):
    try:
     restore=common.copy();restore[restore.index('--baud')+1]=baud
     if attempt==0:
      prefix=w/'restore-prefix.bin';prefix.write_bytes(original[4096:4096+len(image)]);run(['espflash','write-bin',*restore,'--after','no-reset','0x1000',str(prefix)],'restore-prefix')
     else:run(['espflash','write-bin',*restore,'--after','no-reset','0x0',str(a.backup.resolve())],'full-restore',900)
     assert checksum('restored-check-'+str(attempt),original_md5),'full4MiB differs after restore'
     r['restored']=True;save();break
    except BaseException as error:r['restore_error']=repr(error);save();print('Restore retry:',error,flush=True)
   assert r['restored'],'RESTORE FAILED; verified full backup retained'
 finally:
  if not mutating or r['restored']:
   run(['espflash','reset',*common],'final-reset');r['final_reset']=True
  r['finished_at']=time.time();r['pass']=r.get('probe_pass',False) and r.get('probe_flash_matches',False) and r['restored'] and r['final_reset'];save()
assert r['pass'];print('PASS: same cached firmware/native UART; full4MiB restored/checksummed/reset',flush=True)
