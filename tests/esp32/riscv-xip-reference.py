#!/usr/bin/env python3
"""Cached native/C/ROM execution through stock C3 ROM; C6 execution is opt-in."""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--radio',action='store_true');p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();compiler=a.compiler.resolve();cases=[];rejections=[];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 for manifest in ['xip-provenance.json','rom-libc-provenance.json','riscv-libc-provenance.json']:
  # Archive/header provenance has its own schema and is also checked by the
  # existing full stdlib/ROM suites. This family checks all pinned XIP sources.
  if manifest!='xip-provenance.json':assert (ref/manifest).is_file();continue
  for row in json.loads((ref/manifest).read_text())['sources']:assert sha(ref/row['path'])==row['sha256']
 def run(args,reject=False):
  r=subprocess.run(list(map(str,args)),cwd=root,capture_output=True,text=True,timeout=60);assert (r.returncode!=0 if reject else r.returncode==0),(args,r.stdout,r.stderr);return r
 linker=work/'linker';run(['nice','-n','19',compiler,'scripts/esp32-link.flex','-o',linker]);config={}
 for chip in [3,6]:
  name='esp32c'+str(chip);directory=work/name;directory.mkdir(exist_ok=True);(directory/'rom').mkdir(exist_ok=True);(directory/'rom/libc_stubs.h').write_bytes((ref/f'components/esp_rom/{name}/include/{name}/rom/libc_stubs.h').read_bytes());maps='\n'.join(p.read_text() for p in (ref/f'components/esp_rom/{name}/ld').glob('*.ld'))
  def symbol(n):return re.search(r'\b'+re.escape(n)+r'\s*=\s*(0x[0-9a-fA-F]+)',maps)[1]
  aliases=directory/'rom-alias.ld';aliases.write_text(''.join(alias+' = '+symbol(n)+';\n' for alias,n in [('rom_strdup','strdup'),('rom_strtol','strtol'),('rom_printf','printf'),('Cache_Disable_ICache','Cache_Disable_ICache'),('Cache_Enable_ICache','Cache_Enable_ICache')]));(directory/'rom-probe-config.h').write_text(f'#define ROM_GLOBAL_SLOT {symbol("_global_impure_ptr")}\n#define CODE_BEGIN 0x42000000\n#define ROM_STAT_32 {int(chip==3)}\n#define ROM_HAS_COMMON_FIXTURE 0\n#define ROM_COMMON_0 0\n#define ROM_COMMON_1 0\n');config[chip]=(directory,aliases)
 def source_text(text,chip):
  text=text.replace('esp32c3','esp32c'+str(chip))
  if chip==6:text=text.replace('0x3fcb8000','0x40848000').replace('0x3fcb0000','0x40840000')
  if a.radio:text=text.replace('0x3fcb8000','0x3fc9c000').replace('0x3fcb0000','0x3fc98000').replace('0x40848000','0x4081c000').replace('0x40840000','0x40818000').replace('0x3fca0000','0x3fc90000').replace('0x40830000','0x40810000').replace('0x403a0000','0x40390000').replace('0x40820000','0x40810000')
  return re.sub(r'^\s*import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
 def boot(name,text,chip,objects=(),libc=False,platform=None,trap=False,guard=False,words=False):
  directory,aliases=config[chip];prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+('.seta' if platform else '.flex'));elf=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin');report=Path(str(prefix)+'.json');source.write_text(source_text(text,chip));cmd=['nice','-n','19',compiler,'--target',f'esp32c{chip}-'+('radio-elf' if a.radio else 'xip-elf')]
  if platform:cmd+=['--platform',platform if isinstance(platform,Path) else root/f'lib/platform/esp32c{chip}-xip.flex']
  cmd += [source,'-o',elf];run(cmd);cmd=[linker,'--ld',a.ld,'--xip','--firmware',elf,'--rom',aliases,'--output',linked,'--image',image,'--map',Path(str(prefix)+'.map')]
  if libc:cmd+=['--newlib-stdio','--archive',ref/'riscv-libc.a','--archive',ref/'riscv-libgcc.a']
  if libc and libc!='stdio':cmd+=['--newlib-rom']
  for obj in objects:cmd+=['--object',obj]
  run(cmd);cmd=['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--xip','--image',image,'--elf',linked,'--report',report]
  if a.radio:cmd+=['--radio']
  if chip==6 and not a.execute_c6:cmd+=['--validate-only']
  else:
   if trap:cmd+=['--trap']
   if guard:cmd+=['--expect-memory',(('0x3fc98000' if a.radio else '0x3fcb0000') if chip==3 else ('0x40818000' if a.radio else '0x40840000'))+':256:0xa5']
   if words:cmd+=['--words']
  run(cmd);row=json.loads(report.read_text());raw=linked.read_bytes();off=struct.unpack_from('<I',raw,28)[0];n=struct.unpack_from('<H',raw,44)[0];loads=[struct.unpack_from('<8I',raw,off+i*32) for i in range(n)];row.update(case=name,trap_expected=trap,poison_unchanged_checked=guard and (chip==3 or a.execute_c6),cache_segments=[dict(address=x[2],bytes=x[5]) for x in loads if x[0]==1 and (0x42000000<=x[2]<0x43000000 or 0x3c400000<=x[2]<0x3c700000)])
  if (chip==3 or a.execute_c6) and name.startswith('ROM-preempt-'):
   lines=row['uart'].split(('entry 0x40380080\r\n' if chip==3 else 'entry 0x40800080\r\n'),1)[1].splitlines();assert len(lines)==24 and lines.count('ROMW1:A')==12 and lines.count('ROMW2:B')==12;row['exact_ROM_output_lines']=24
  if (chip==3 or a.execute_c6) and name.startswith('stdio-format-'):assert row['uart'].endswith('STDIO: value=-17/1122334455667788/1.25\n'),row['uart']
  cases.append(row);return source,elf
 flags=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections','-I',ref/'components/newlib/platform_include','-I',ref/'riscv-newlib','-I',ref]
 for march in ['rv32im_zicsr_zifencei','rv32imc_zicsr_zifencei']:
  for opt in ['-O0','-O2','-Os']:
   for chip in [3,6]:
    directory,aliases=config[chip];tag=f'{march}{opt}-c{chip}';obj=work/(tag+'.o');worker=work/(tag+'-worker.o');cmd=['nice','-n','19',*flags,'-I',directory,'-march='+march,opt]
    extra=['-DC6'] if chip==6 else []
    run([*cmd,*extra,'-c',root/'tests/esp32/riscv-xip.c','-o',obj]);run([*cmd,'-c',root/'tests/esp32/riscv-rom-libc.c','-o',worker]);boot('pages-'+march+opt,(root/'tests/esp32/riscv-xip-pages.flex').read_text(),chip,[obj]);text='import "../../lib/platform/esp32c3-xip.flex";\n'+(root/'tests/esp32/riscv-rom-libc-preempt.flex').read_text();boot('ROM-preempt-'+march+opt,text,chip,[worker],libc=True);fmt=work/(tag+'-format.o');run([*cmd,'-c',root/'tests/esp32/riscv-stdio-format.c','-o',fmt]);text='import "../../lib/platform/esp32c3-xip.flex";\n'+(root/'tests/esp32/riscv-stdio-format.flex').read_text();boot('stdio-format-'+march+opt,text,chip,[fmt],libc='stdio')
 for chip in [3,6]:
  boot('native-smoke',(root/'tests/esp32/riscv-xip.flex').read_text(),chip)
  text='import "../../lib/platform/esp32c3-xip.flex";\nfn large(x){'+('x=x+1;'*4000)+'return x;}fn main(){return large(3)-4003;}';boot('large-native',text,chip)
  boot('Seta-platform',(root/'tests/esp32/frontend-state.seta').read_text(),chip,platform='seta')
  directory,aliases=config[chip];tls=work/f'tls-c{chip}.o';run(['nice','-n','19',*flags,'-march=rv32imc_zicsr','-Os','-ftls-model=local-exec','-c',root/'tests/esp32/riscv-tls.c','-o',tls]);text='import "../../lib/platform/esp32c3-xip.flex";\n'+(root/'tests/esp32/riscv-tls.flex').read_text();boot('TLS-task-reaping',text,chip,[tls])
  early=work/f'early-platform-c{chip}.flex';early.write_text(f'import "{root}/lib/platform/esp32c{chip}-xip.flex";\nglobal early=0;fn esp_platform_init(){{if !esp_xip_ready{{return 1;}}let r=esp32_call32(esp32_external("tls_validate_initial"),0,0,0,0,0,0,0,0);if r{{return r;}}early=1;return 0;}}fn check_early(){{return early!=1;}}');boot('TLS-early-platform','plugin rv.xip v1 {} extern fn check_early()->i32 fn main()->i32{return check_early()}',chip,[tls],platform=early)
  prefix='import "../../lib/platform/esp32c3-xip.flex";\nfn main(){let guard=alloc(256);let i=0;while i<256{store8(guard+i,165);i=i+1;}'
  for name,body in [('null-pointer','store8(0,1);'),('null-C-target','esp32_call32(0,0,0,0,0,0,0,0,0);'),('bad-stack','return recurse();}fn recurse(){return 1+recurse();')]:boot('guard-'+name,prefix+body+'return 99;}',chip,trap=True,guard=True)
 # Failure preserves all destinations; the explicit target supplies its own
 # early mapper rather than treating --xip as a generic SRAM ELF postprocessor.
 source,elf=boot('rejection-base',(root/'tests/esp32/riscv-xip.flex').read_text(),3)
 outputs=[work/('preserved'+s) for s in ['.elf','.bin','.map']]
 for f in outputs:f.write_bytes(b'preserve output')
 result=run([linker,'--ld',a.ld,'--firmware',elf,'--rom',config[3][1],'--output',outputs[0],'--image',outputs[1],'--map',outputs[2]],reject=True);assert 'requires --xip' in result.stderr and all(f.read_bytes()==b'preserve output' for f in outputs);rejections.append(dict(case='missing-xip-link-flag',preserved_outputs=3))
 for chip in [3,6]:
  output=work/f'preserved-c{chip}.elf';output.write_bytes(b'preserve output');source=work/f'missing-mapper-c{chip}.flex';source.write_text('fn main(){return 0;}');r=run([compiler,'--target',f'esp32c{chip}-'+('radio-elf' if a.radio else 'xip-elf'),source,'-o',output],reject=True);assert 'requires esp_xip_enable()' in r.stderr and output.read_bytes()==b'preserve output';rejections.append(dict(case=f'missing-mapper-c{chip}',preserved_outputs=1))
 # The primary ROM digest deliberately excludes cached bytes; the peer must
 # still reject corruption using the independent ELF contract.
 positive=work/'pages-rv32imc_zicsr_zifencei-Os-c3';elf=Path(str(positive)+'-linked.elf');raw=elf.read_bytes();shoff=struct.unpack_from('<I',raw,32)[0];count=struct.unpack_from('<H',raw,48)[0];names_index=struct.unpack_from('<H',raw,50)[0];sections=[struct.unpack_from('<10I',raw,shoff+i*40) for i in range(count)];names=sections[names_index];pool=raw[names[4]:names[4]+names[5]];byname={pool[x[0]:pool.index(0,x[0])].decode():x for x in sections};layout=byname['.flex.xip'];cf,cp,df,dp=struct.unpack_from('<4I',raw,layout[4])
 payload=Path(str(positive)+'.bin').read_bytes()
 for name,offset in [('corrupt-cached-code',cf),('corrupt-cached-data',df),('corrupt-gap',0x2ffff)]:
  corrupt=bytearray(payload);corrupt[offset]^=1;image=work/(name+'.bin');image.write_bytes(corrupt);r=run(['python3',root/'tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--xip',*(['--radio'] if a.radio else []),'--validate-only','--image',image,'--elf',elf,'--report',work/(name+'.json')],reject=True);assert 'AssertionError' in r.stderr;rejections.append(dict(case=name,detection='independent ELF/cache payload contract',ROM_primary_digest_still_valid=True))
 for chip in [3,6]:
  source=work/f'large-IRAM-c{chip}.flex';output=work/f'large-IRAM-c{chip}.elf';output.write_bytes(b'preserve output');text='import "../../lib/platform/esp32c3-xip.flex";\nfn large(x){'+('x=x+1;'*4000)+'return x;}fn main(){return esp32_iram_callback(large)==0;}';source.write_text(source_text(text,chip));r=run([compiler,'--target',f'esp32c{chip}-'+('radio-elf' if a.radio else 'xip-elf'),source,'-o',output],reject=True);assert ('64 KiB SRAM region' if a.radio else '128 KiB SRAM region') in r.stderr and output.read_bytes()==b'preserve output';rejections.append(dict(case=f'IRAM-closure-overflow-c{chip}',preserved_outputs=1))
 for chip in [3,6]:
  output=work/f'large-code-c{chip}.elf';output.write_bytes(b'preserve output');source=work/f'large-code-c{chip}.flex';text='import "../../lib/platform/esp32c3-xip.flex";fn large(){let x=0;'+('x=1;'*140000)+'return x;}fn main(){return large();}';source.write_text(source_text(text,chip));r=run([compiler,'--target',f'esp32c{chip}-'+('radio-elf' if a.radio else 'xip-elf'),source,'-o',output],reject=True);assert 'flash code exceeds 3 MiB' in r.stderr and output.read_bytes()==b'preserve output';rejections.append(dict(case=f'native-flash-overflow-c{chip}',preserved_outputs=1))
 for name,size,code_words,message in [('DROM-overflow',3145732,0,'linked segment outside permitted memory'),('physical-flash-overflow',3145728,262144,'XIP image exceeds 4 MiB flash')]:
  c=work/(name+'.c');c.write_text('const unsigned char big_drom['+str(size)+']={17};unsigned big_code(void){__asm__ volatile(".rept '+str(code_words)+'\\n.4byte 0x00000013\\n.endr");return 11;}');obj=work/(name+'.o');run(['nice','-n','19',*flags,'-march=rv32imc_zicsr','-Os','-c',c,'-o',obj])
  for chip in [3,6]:
   source=work/(name+f'-c{chip}.flex');source.write_text(source_text('import "../../lib/platform/esp32c3-xip.flex";fn main(){return load8(esp32_external("big_drom"))+esp32_call32(esp32_external("big_code"),0,0,0,0,0,0,0,0);}',chip));fw=work/(name+f'-c{chip}-input.elf');run([compiler,'--target',f'esp32c{chip}-'+('radio-elf' if a.radio else 'xip-elf'),source,'-o',fw]);outputs=[work/(name+f'-c{chip}'+suffix) for suffix in ['.elf','.bin','.map']]
   for f in outputs:f.write_bytes(b'preserve output')
   r=run([linker,'--ld',a.ld,'--xip','--firmware',fw,'--object',obj,'--output',outputs[0],'--image',outputs[1],'--map',outputs[2]],reject=True);assert message in r.stdout+r.stderr and all(f.read_bytes()==b'preserve output' for f in outputs);rejections.append(dict(case=name+f'-c{chip}',preserved_outputs=3))
 if a.radio:
  for chip in [3,6]:
   boot('radio-arena',(root/'tests/esp32/riscv-radio-profile.flex').read_text(),chip)
   boot('radio-PC-guard',(root/'tests/esp32/riscv-radio-pc-guard.flex').read_text(),chip,trap=True,guard=True)
   # Both native and linked C static data must respect the smaller32KiB arena.
   output=work/f'radio-static-c{chip}.elf';output.write_bytes(b'preserve output');source=work/f'radio-static-c{chip}.flex';source.write_text(source_text('import "../../lib/platform/esp32c3-xip.flex";fn main(){let p="'+('x'*32768)+'";return load8(p);}',chip));r=run([compiler,'--target',f'esp32c{chip}-radio-elf',source,'-o',output],reject=True);assert 'static data exceeds 32 KiB' in r.stderr and output.read_bytes()==b'preserve output';rejections.append(dict(case=f'radio-native-static-c{chip}',preserved_outputs=1))
   c=work/f'radio-C-static-c{chip}.c';c.write_text('unsigned char radio_large_data[40000];');obj=work/f'radio-C-static-c{chip}.o';run([*flags,'-march=rv32imc_zicsr','-Os','-c',c,'-o',obj]);source=work/f'radio-C-static-c{chip}.flex';source.write_text(source_text('import "../../lib/platform/esp32c3-xip.flex";fn main(){return load8(esp32_external("radio_large_data"));}',chip));fw=work/f'radio-C-static-input-c{chip}.elf';run([compiler,'--target',f'esp32c{chip}-radio-elf',source,'-o',fw]);outputs=[work/f'radio-C-static-c{chip}{suffix}' for suffix in ['.elf','.bin','.map']]
   for out in outputs:out.write_bytes(b'preserve output')
   r=run([linker,'--ld',a.ld,'--xip','--firmware',fw,'--object',obj,'--output',outputs[0],'--image',outputs[1],'--map',outputs[2]],reject=True);assert ('vendor data overlaps reserved SRAM' in r.stdout+r.stderr or 'linked segment outside permitted memory' in r.stdout+r.stderr) and all(out.read_bytes()==b'preserve output' for out in outputs);rejections.append(dict(case=f'radio-C-static-c{chip}',preserved_outputs=3))
 report=dict(pass_all=True,radio_profile=a.radio,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_package_checks=sum(not x['ROM_boot'] for x in cases),C3_poison_unchanged_checks=sum(x.get('machine')=='esp32c3' and x['poison_unchanged_checked'] for x in cases),C6_poison_unchanged_checks=sum(x.get('machine')=='esp32c6' and x['poison_unchanged_checked'] for x in cases),physical_hardware=False,complete_vendor_radio_startup_verified=False,radio_reservations_verified=False,cases=cases,rejections=rejections,compiler_sha256=sha(compiler),emulator_implementation_changes=False);(work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: XIP',report['C3_ROM_boots'],'C3 boots,',report['C6_ROM_boots'],'C6 boots,',report['C6_package_checks'],'C6 packages')
if __name__=='__main__':main()
