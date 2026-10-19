#!/usr/bin/env python3
"""Independent ELF objects and ROM alias/filter contracts for radio tooling."""
import argparse,hashlib,json,re,struct,subprocess
from pathlib import Path

def main():
 p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--legacy-data-source',type=Path);p.add_argument('--reference',required=True,type=Path);p.add_argument('--work',required=True,type=Path);a=p.parse_args();root=Path(__file__).resolve().parents[2];w=a.work.resolve();w.mkdir(parents=True,exist_ok=True);ref=a.reference.resolve();c=a.compiler.resolve();checks=0;rejects=[]
 def run(cmd,reject=False,match=None):
  q=subprocess.run(list(map(str,cmd)),cwd=root,capture_output=True,text=True,timeout=60);assert (q.returncode!=0 if reject else q.returncode==0),(cmd,q.stdout,q.stderr)
  if match:assert match in q.stdout+q.stderr,(match,q.stdout,q.stderr)
  return q
 tool=w/'data-object';run([c,root/'scripts/esp32-data-object.flex','-o',tool]);objects=[]
 for arch,machine in [('xtensa',94),('riscv32',243)]:
  for size,value in [(1,None),(2,None),(3,None),(4,None),(480,None),(508,None),(32768,None),(1,255),(2,65535),(3,16777215),(4,4294967295)]:
   file=w/f'{arch}-{size}-{value}.o';cmd=[tool,'--arch',arch,'--symbol','object_under_test','--size',size,'--output',file]
   if value is not None:cmd+=['--value',value]
   run(cmd);raw=file.read_bytes();assert raw[:7]==b'\x7fELF\x01\x01\x01' and struct.unpack_from('<HHI',raw,16)==(1,machine,1);off=struct.unpack_from('<I',raw,32)[0];ss=[struct.unpack_from('<10I',raw,off+i*40) for i in range(5)];assert ss[0]==(0,)*10;data,sym,strings,names=ss[1:];assert data[1:4]==(1,3,0) and data[5]==size and data[8]==4;expected=bytes(size) if value is None else value.to_bytes(size,'little');assert raw[data[4]:data[4]+size]==expected;assert sym[1]==2 and sym[5]==32 and sym[6:]==(3,1,4,16);assert raw[sym[4]:sym[4]+16]==bytes(16);entry=struct.unpack_from('<IIIBBH',raw,sym[4]+16);assert entry==(1,0,size,17,0,1);assert raw[strings[4]:strings[4]+strings[5]]==b'\0object_under_test\0';assert raw[names[4]:names[4]+names[5]]==b'\0.data\0.symtab\0.strtab\0.shstrtab\0';assert len(raw)==off+200;objects.append(dict(arch=arch,size=size,value=value,sha256=hashlib.sha256(raw).hexdigest()));checks+=10
 protected=w/'protected.o';protected.write_bytes(b'preserve object')
 for name,options,message in [('bad-arch',['--arch','arm64'],'--arch must be'),('zero-size',['--size','0'],'requires --symbol'),('large-size',['--size','32769'],'requires --symbol'),('bad-name',['--symbol','bad-name'],'requires --symbol'),('wide-byte',['--size','1','--value','256'],'--value must fit'),('wide-word',['--value','4294967296'],'--value must fit'),('large-initializer',['--size','480','--value','0'],'--value must fit')]:
  cmd=[tool,'--symbol','valid','--output',protected];protected.write_bytes(b'preserve object')
  for i in range(0,len(options),2):
   flag,value=options[i:i+2]
   if flag in cmd:cmd[cmd.index(flag)+1]=value
   else:cmd += [flag,value]
  run(cmd,reject=True,match=message);assert protected.read_bytes()==b'preserve object';rejects.append(name)
 # Compile the prior exact source to prove the default Xtensa object ABI stays
 # byte-identical; the new architecture flag changes only e_machine.
 previous=a.legacy_data_source or ref/'compat/esp32-data-object.flex'
 if previous.exists():
  old_source=w/'old-data-object.flex';old_source.write_text(re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'scripts'/m[1]).resolve())+'";',previous.read_text(),flags=re.M));old=w/'old-data-object';run([c,old_source,'-o',old]);before=w/'old.o';after=w/'default.o';args=['--symbol','unchanged','--size','4','--value','305419896'];run([old,*args,'--output',before]);run([tool,*args,'--output',after]);assert before.read_bytes()==after.read_bytes();checks+=1
 # Use the actual production parser/filter functions from the builder module.
 source=(root/'scripts/build-esp32-radio.flex').read_text().replace('fn main(argc,argv)','fn radio_reference_main(argc,argv)');source=re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'scripts'/m[1]).resolve())+'";',source,flags=re.M);module=w/'builder-module.flex';module.write_text(source);probe=w/'ROM-probe.flex';probe.write_text(f'import "{module}";\nfn main(argc,argv){{h_environment(argc,argv);let cfg=j_parse(h_read(load64(argv+8)));let symbols=j_object();let maps=j_get(cfg,"maps");let i=0;while i<j_count(maps){{er_rv_rom_symbols(symbols,j_value(j_at(maps,i)));i=i+1;}}let inputs=j_get(cfg,"inputs");i=0;while i<j_count(inputs){{er_rv_defined(symbols,h_executable("llvm-nm"),j_value(j_at(inputs,i)));i=i+1;}}return j_save(load64(argv+16),symbols);}}');runner=w/'ROM-probe';run([c,probe,'-o',runner]);aliases=[]
 for chip in [3,6]:
  maps=sorted((ref/f'components/esp_rom/esp32c{chip}/ld').glob('*.ld'));expected={}
  for file in maps:
   for line in file.read_text().splitlines():
    m=re.match(r'^\s*(?:PROVIDE\s*\(\s*)?([A-Za-z_]\w*)\s*=\s*(0x[0-9a-fA-F]+|[A-Za-z_]\w*)\s*[;)]',line)
    if m and m[1]!=m[2]:expected[m[1]]=m[2]
  inputs=[*sorted((ref/f'vendor/esp32c{chip}').glob('*.a')),ref/'riscv-libc.a',ref/'riscv-libgcc.a'];cfg=w/f'ROM-c{chip}.json';out=w/f'ROM-filtered-c{chip}.json';cfg.write_text(json.dumps(dict(maps=list(map(str,maps)),inputs=list(map(str,inputs)))));run([runner,cfg,out]);defined=set()
  for file in inputs:
   for line in run(['llvm-nm','--defined-only','--extern-only','-P',file]).stdout.splitlines():
    parts=line.split()
    if len(parts)>1 and len(parts[1])==1:defined.add(parts[0])
  expected={name:0 if name in defined else value for name,value in expected.items()};actual=json.loads(out.read_text());assert actual==expected,({k:(v,actual.get(k)) for k,v in expected.items() if actual.get(k)!=v},set(actual)-set(expected));checks+=len(expected);aliases.append(dict(chip=chip,primary_symbols=len(expected),compiled_symbols_excluded=sum(value==0 for value in expected.values())))
 for expression in ['0x40000000+4','other_symbol+4']:
  file=w/'invalid-ROM.ld';file.write_text('PROVIDE (bad = '+expression+');\n');cfg=w/'invalid-ROM.json';cfg.write_text(json.dumps(dict(maps=[str(file)],inputs=[])));out=w/'invalid-ROM-output.json';out.write_bytes(b'preserve ROM output');run([runner,cfg,out],reject=True,match='unsupported pinned ROM expression');assert out.read_bytes()==b'preserve ROM output';rejects.append(expression)
 report=dict(pass_all=True,checks=checks,legacy_Xtensa_byte_identical=previous.exists(),data_objects=objects,ROM_aliases=aliases,rejections=rejects,CPU_execution=False,physical_hardware=False);(w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS:',len(objects),'ELF objects,',checks,'tool checks,',len(rejects),'preserved-output rejections')
if __name__=='__main__':main()
