#!/usr/bin/env python3
"""Explicit pinned C3/C6 builder and preserved-output rejection checks."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();c=a.compiler.resolve();cases=[];rejections=[];sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
 def run(cmd,reject=False,match=None):
  r=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,text=True,timeout=60);assert (r.returncode!=0 if reject else r.returncode==0),(cmd,r.stdout,r.stderr)
  if match:assert match in r.stdout+r.stderr,(match,r.stdout,r.stderr)
  return r
 builder=w/'builder';run([c,root/'scripts/build-esp32-radio.flex','-o',builder]);base=['nice','-n','19',builder,'--kind','wifi','--compiler',c,'--libc',ref/'riscv-libc.a','--libgcc',ref/'riscv-libgcc.a','--libm',ref/'riscv-libm.a','--ld','ld.lld','--nm','llvm-nm']
 for chip in [3,6]:
  source=w/f'probe-c{chip}.flex';source.write_text((root/f'examples/esp32c{chip}-vendor-probe.flex').read_text().replace('../lib/',str(root/'lib')+'/'));cmd=base+['--chip',f'esp32c{chip}','--vendor',ref/f'vendor/esp32c{chip}','--rom',ref/f'components/esp_rom/esp32c{chip}/ld','--source',source];output=w/f'c{chip}.bin';run(cmd+['--output',output]);peer=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--xip','--radio','--image',output,'--elf',str(output)+'.elf','--report',w/f'c{chip}.json']
  if chip==6 and not a.execute_c6:peer+=['--validate-only']
  run(peer);row=json.loads((w/f'c{chip}.json').read_text());row['actual_vendor_MAC_preinit_and_WPA_hexstr2bin']=row['ROM_boot'];cases.append(row);protected=w/f'protected-c{chip}.bin';outputs=[protected,Path(str(protected)+'.elf'),Path(str(protected)+'.map')]
  for f in outputs:f.write_bytes(b'preserve existing output')
  invalid=w/f'invalid-c{chip}.flex';invalid.write_text('fn main(){return 0;}')
  guards=[('unsupported-Bluetooth',['--kind','bluetooth'],'Bluetooth vendor startup'),('unsupported-TLS',['--tls','unused'],'TLS vendor archives'),('wrong-vendor',['--vendor',ref/f'vendor/esp32c{9-chip}'],'vendor archive checksum mismatch' if chip==3 else 'cannot read'),('wrong-ROM',['--rom',ref/f'components/esp_rom/esp32c{9-chip}/ld'],'cannot read'),('wrong-libc',['--libc',ref/'riscv-libgcc.a'],'vendor archive checksum mismatch'),('wrong-libgcc',['--libgcc',ref/'riscv-libc.a'],'vendor archive checksum mismatch'),('wrong-libm',['--libm',ref/'riscv-libc.a'],'vendor archive checksum mismatch'),('missing-cache-mapper',['--source',invalid],'requires esp_xip_enable()')]
  for name,opts,message in guards:
   chosen=cmd.copy()
   for i in range(0,len(opts),2):
    flag,val=opts[i:i+2]
    if flag in chosen:at=chosen.index(flag);chosen[at+1]=val
    else:chosen += [flag,val]
   run(chosen+['--output',protected],reject=True,match=message);assert all(x.read_bytes()==b'preserve existing output' for x in outputs);rejections.append(dict(chip=chip,case=name,preserved_outputs=3))
  chosen=cmd.copy();at=chosen.index('--source');del chosen[at:at+2];run(chosen+['--output',protected],reject=True,match='require --source');assert all(x.read_bytes()==b'preserve existing output' for x in outputs);rejections.append(dict(chip=chip,case='source-required',preserved_outputs=3))
  run(cmd+['--output',source],reject=True,match='radio output aliases input');alias=w/f'alias-c{chip}.bin'
  if alias.exists():alias.unlink()
  os.link(source,alias);before=sha(source);run(cmd+['--output',alias],reject=True,match='radio output aliases input');assert sha(source)==sha(alias)==before;rejections.append(dict(chip=chip,case='source-path-and-hardlink-aliases',preserved_inputs=2));print('builder',chip,'passed',flush=True)
 report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),cases=cases,rejections=rejections,complete_vendor_radio_startup=False,physical_hardware=False,compiler_sha256=sha(c));(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: pinned radio builder;',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages,',len(rejections),'preserved-output/input rejection cases')
if __name__=='__main__':main()
