#!/usr/bin/env python3
"""Rebuild/replay the exact RAM-only SPI capture and compare it with silicon.
No device is opened by this verifier; it consumes an existing physical report.
"""
from emulator_sources import source_path, clone_source
import argparse,hashlib,json,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True);p.add_argument('--physical-report',type=Path,required=True);p.add_argument('--work',type=Path,required=True);p.add_argument('--report',type=Path);p.add_argument('--negative-control',action='store_true')
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();physical_path=a.physical_report.resolve();physical=json.loads(physical_path.read_text());capture=(physical_path.parent/'physical-uart.bin').read_bytes();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert physical['pass'] and physical['ram_only'] and physical['flash_unchanged'] and not physical['flash_write_requested'];assert physical['stages'][-1]=='physical-final-reset';assert physical['uart'].encode()==capture;assert physical['compiler_sha256']==sha(compiler)
records=[]
for line in capture.splitlines():
 if line.startswith(b'FIFO '):
  fields=line.split();assert len(fields)==11 and all(re.fullmatch(rb'[0-9a-f]{16}',x) for x in fields[1:]),line
  records.append(tuple(int(x,16) for x in fields[1:]))
assert len(records)==272 and b'PASS: SPI FIFO padding capture272 cases\r\n' in capture
keys=set();lengths={1,7,8,9,15,16,17,24,31,32,33,63,64,65,255,256,257,512};words=0
for bus,order,high,constant,bits,last,*values in records:
 assert bus in (2,3) and order in (0,1) and high in (0,1) and constant in (0,1) and bits in lengths and bits<=(256 if high else 512)
 key=(bus,order,high,constant,bits);assert key not in keys;keys.add(key);assert last==high*8+(bits-1)//32
 indexes=[0,last,last+1 if last<15 else 0,15]
 for index,actual in zip(indexes,values):
  expected=(0xa5963cc3^(index*0x01030507))&0xffffffff
  for byte in range(4):
   at=index*4+byte-high*32
   if 0<=at<(bits+7)//8:
    n=min(8,bits-at*8);value=((1<<n)-1) if constant else 0
    if not order:value<<=8-n
    expected=(expected&~(255<<(byte*8)))|(value<<(byte*8))
  assert actual==expected,(key,index,hex(actual),hex(expected));words+=1
expected_keys={(b,o,h,c,n) for b in (2,3) for o in (0,1) for h in (0,1) for c in (0,1) for n in lengths if n<=(256 if h else 512)};assert keys==expected_keys

def run(args,label):
 q=subprocess.run([str(x) for x in args],cwd=root,capture_output=True);(work/(label+'.log')).write_bytes(q.stdout+q.stderr);assert q.returncode==0,(label,q.stdout[-500:],q.stderr[-1000:]);return q
image=work/'peer.elf';run([compiler,'--target','esp32-elf','tests/esp32/spi-fifo-padding.flex','-o',image],'image-build');assert sha(image)==physical['image_sha256']==sha(physical_path.parent/'peer.elf')
runner=work/'board-run';run([compiler,'tests/xtensa/board-run.flex','-o',runner],'runner-build');trace=work/'emulated.uart';result=run([runner,image,trace,'--fuel','500000000'],'emulator');assert trace.read_bytes()==capture,'current emulator differs from exact silicon transcript'
control=None
if a.negative_control:
 directory=work/'missing-byte-clear';directory.mkdir(exist_ok=True)
 for name in ['esp32-emulator.flex','esp32-gpio-emulator.flex','esp32-gpio-pads.flex','esp32-spi-emulator.flex']:
  source=clone_source(root,name)
  if name=='esp32-spi-emulator.flex':
   token='if !se_chip(s){em_zero(p+1600,(rxlen+7)/8);}'
   assert source.count(token)==1;source=source.replace(token,'')
  source=source.replace('"xtensa.flex"',json.dumps(str(source_path(root,'xtensa.flex'))));(directory/name).write_text(source)
 source=(root/'tests/xtensa/board-run.flex').read_text().replace('"../../emulator/esp32/board.flex"',json.dumps(str(directory/'esp32-emulator.flex'))).replace('"../../scripts/lib/esp32-elf.flex"',json.dumps(str(root/'scripts/lib/esp32-elf.flex')))
 fixture=directory/'board-run.flex';fixture.write_text(source);bad_runner=directory/'board-run';run([compiler,fixture,'-o',bad_runner],'negative-control-build');bad_trace=directory/'emulated.uart';before=run([bad_runner,image,bad_trace,'--fuel','500000000'],'negative-control');data=bad_trace.read_bytes();assert data!=capture,'missing-byte-clear defect escaped silicon comparison';index=next((i for i,(x,y) in enumerate(zip(data,capture)) if x!=y),min(len(data),len(capture)));control={'runner_sha256':sha(bad_runner),'interpreter':before.stdout.decode(),'first_differing_byte':index,'uart_sha256':sha(bad_trace),'detected':True,'model_change':'Omit original-chip RX byte initialization; all other engine/CPU behavior is identical'}

report={'pass':True,'chip':'esp32-rev3','physical_cases':len(records),'independent_word_comparisons':words,'elf_sha256':sha(image),'runner_sha256':sha(runner),'uart_sha256':sha(trace),'uart_bytes':len(capture),'interpreter':result.stdout.decode(),'physical_report_sha256':sha(physical_path),'physical_report':str(physical_path),'ram_only':True,'flash_unchanged':True,'byte_identical_physical_and_emulated_uart':True,'padding_defect_control':control,'limitations':['Input is an internal GPIO matrix constant; external SPI device and waveforms are not verified','S3 physical padding remains unverified']}
if a.report:a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'pass':True,'physical_cases':len(records),'words':words,'uart_bytes':len(capture),'padding_defect_detected':control is not None}))
