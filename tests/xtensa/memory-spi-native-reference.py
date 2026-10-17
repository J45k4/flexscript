#!/usr/bin/env python3
"""Replay read-only ROM/NOR commands against an explicitly supplied flash image.

Builds expected FNV values from the given private NOR without printing its bytes.
No downloads,physical hardware access,compiler bootstrap or flash writes.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for n in ('compiler','rom','nor','work','report'):p.add_argument('--'+n,type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(exist_ok=True,parents=True);compiler=a.compiler.resolve();nor=a.nor.resolve();rom=a.rom.resolve();blob=nor.read_bytes();assert len(blob)==4194304,'explicit original4MiB NOR profile'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
cases=[]
for at,n in [(0,1),(0,64),(4093,7),(65533,17),(262137,31),(4194240,64),(1048559,63),(2097151,3)]:
 h=2166136261
 for b in blob[at:at+n]:h=((h^b)*16777619)&0xffffffff
 cases.append((at,n,h))
text='import '+json.dumps(str(root/'tests/esp32/emulator-memory-spi.flex'))+';\n'
for name,column in [('ms_at',0),('ms_size',1),('ms_expected',2)]:text+='fn '+name+'(i){'+''.join('if i=='+str(i)+'{return '+str(row[column])+';}' for i,row in enumerate(cases))+'return 0;}\n'
source=w/'read-probe.flex';source.write_text(text);elf=w/'read-probe.elf';runner=w/'board-run';uart=w/'native.uart'
def checked(args,label):
 q=subprocess.run([str(x) for x in args],cwd=root,capture_output=True,timeout=120);(w/(label+'.stdout')).write_bytes(q.stdout);(w/(label+'.stderr')).write_bytes(q.stderr);assert q.returncode==0,(label,q.stdout,q.stderr);return q
checked([compiler,'--target','esp32-elf',source,'-o',elf],'compile-firmware');checked([compiler,root/'tests/xtensa/board-run.flex','-o',runner],'compile-runner');q=checked([runner,elf,uart,'--rom',rom,'--flash-nor',nor,'--download-clock','--fuel','10000000'],'native')
expected=b'START: real ROM and NOR commands\r\nPASS: real ROM,NOR ID/status/WEL and16 exact reads\r\n';assert uart.read_bytes()==expected,'complete application UART'
r={'pass':True,'physical_hardware':False,'NOR_sha256':sha(nor),'ROM_sha256':sha(rom),'ELF_sha256':sha(elf),'UART_sha256':sha(uart),'compiler_sha256':sha(compiler),'cases':cases,'native':q.stdout.decode(),'scope':'Read-only real-ROM SPI0/1 startup,Puya ID,volatile WEL/status and16 hardware/USR reads. No NOR program/erase or timing/waveform parity claim.'};a.report.write_text(json.dumps(r,indent=2)+'\n');print('PASS: unchanged ROM and16 exact NOR reads')
