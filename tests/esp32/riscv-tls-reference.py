#!/usr/bin/env python3
"""Static TLS through LLVM ELF relocations and unmodified stock C3 ROM boot."""
import argparse,hashlib,importlib.util,json,re,struct,subprocess
from pathlib import Path


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def seal_image(raw):
    raw=bytearray(raw);at=24;checksum=0xef
    for _ in range(raw[1]):
        size=struct.unpack_from('<I',raw,at+4)[0];at+=8
        for b in raw[at:at+size]:checksum^=b
        at+=size
    while at%16!=15:at+=1
    raw[at]=checksum;raw[at+1:]=hashlib.sha256(raw[:at+1]).digest();return raw


def main():
    p=argparse.ArgumentParser();p.add_argument('--compiler',required=True,type=Path);p.add_argument('--qemu',required=True,type=Path);p.add_argument('--work',required=True,type=Path);p.add_argument('--clang',default='clang');p.add_argument('--ld',default='ld.lld');p.add_argument('--legacy-compiler',type=Path);p.add_argument('--execute-c6',action='store_true');p.add_argument('--qemu-c6',type=Path);a=p.parse_args()
    root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);compiler=a.compiler.resolve();cases=[];rejections=[]
    spec=importlib.util.spec_from_file_location('elf_reference',root/'tests/esp32/riscv-c-abi-reference.py');elf_reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(elf_reference)
    def run(args,reject=None):
        r=subprocess.run(list(map(str,args)),cwd=root,text=True,capture_output=True,timeout=60)
        if reject is None:assert r.returncode==0,(args,r.stdout,r.stderr)
        else:assert r.returncode!=0 and reject.lower() in (r.stdout+r.stderr).lower(),(args,r.returncode,r.stdout,r.stderr)
        return r
    linker=work/'linker';run([compiler,'scripts/esp32-link.flex','-o',linker])
    base=[a.clang,'--target=riscv32','-mabi=ilp32','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0','-ffunction-sections','-fdata-sections']
    def input_text(text,chip):
        text=text.replace('esp32c3','esp32c'+str(chip))
        if chip==6:text=text.replace('0x3fcb8000','0x40848000')
        return re.sub(r'^import "([^"]+)";',lambda m:'import "'+str((root/'tests/esp32'/m[1]).resolve())+'";',text,flags=re.M)
    def link(name,text,chip,obj,extra=(),language=None,parser=None):
        prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.flex');source.write_text(input_text(text,chip));firmware=Path(str(prefix)+'.elf');linked=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin')
        cmd=[parser or compiler,'--target',f'esp32c{chip}-elf',*extra]
        if language:cmd+=['--language',language]
        run([*cmd,source,'-o',firmware]);run([linker,'--ld',a.ld,'--firmware',firmware,'--object',obj,'--output',linked,'--image',image]);return firmware,linked,image
    def metadata(elf,chip):
        raw,sections=elf_reference.elf_sections(elf);ph=[struct.unpack_from('<8I',raw,52+i*32) for i in range(struct.unpack_from('<H',raw,44)[0])];tls=[x for x in ph if x[0]==7 and x[5]];assert len(tls)==1
        t=tls[0];d=struct.unpack_from('<8I',sections['.data'][1],24);base_address=0x3fca0000 if chip==3 else 0x40830000
        assert d==(0x31534c54,t[2],t[4],t[5],max(16,t[7]),sections['.flex.tls.main'][0][3],0,0)
        assert d[1]>=base_address+56 and d[5]>=d[1]+d[3] and d[5]+d[3]<=base_address+65536
        assert not d[1]%d[4] and not d[5]%d[4]
        assert all(x[0]!=1 or (x[2] in (base_address,0x40380000 if chip==3 else 0x40800000)) for x in ph)
        return d,raw,sections,ph
    def boot(name,image,chip,elf=None,trap=False,expect=None):
        report=work/(name+f'-c{chip}.json');cmd=['python3','tests/esp32/riscv-rom-peer.py','--qemu',(a.qemu_c6 or a.qemu) if chip==6 and a.execute_c6 else a.qemu,'--image',image,'--report',report]
        if elf:cmd+=['--elf',elf]
        if chip==6 and not a.execute_c6:cmd+=['--validate-only']
        else:
            if trap:cmd+=['--trap']
            if expect:cmd+=['--expect-memory',expect]
        run(cmd);row=json.loads(report.read_text());row['case']=name;row['C6_execution']=chip==6 and row['ROM_boot'];cases.append(row)
    def image_data(raw):return 32+struct.unpack_from('<I',raw,28)[0]+8
    fixture=(root/'tests/esp32/riscv-tls.flex').read_text();retained=None
    for model in ('local-exec','initial-exec'):
        for march in ('rv32im_zicsr','rv32imc_zicsr'):
            for opt in ('-O0','-O2','-Os'):
                name=model+'-'+march+opt;obj=work/(name+'.o');run([*base,'-march='+march,opt,'-fPIC','-ftls-model='+model,'-c','tests/esp32/riscv-tls.c','-o',obj])
                for chip in (3,6):
                    firmware,elf,image=link(name,fixture,chip,obj);d,raw,sections,ph=metadata(elf,chip);boot(name,image,chip,elf)
                    if chip==3:
                        poisoned=bytearray(image.read_bytes());at=image_data(poisoned)+d[5]-0x3fca0000;poisoned[at:at+d[3]]=b'\xa5'*d[3];derived=work/(name+'-poisoned.bin');derived.write_bytes(seal_image(poisoned));boot(name+'-poisoned-main',derived,chip)
                        retained=(firmware,elf,image,obj,d)
    for model in ('local-exec','initial-exec'):
        name='aligned4096-'+model;obj=work/(name+'.o');run([*base,'-march=rv32imc_zicsr','-O2','-fPIC','-ftls-model='+model,'-DTLS_ALIGNMENT=4096','-c','tests/esp32/riscv-tls.c','-o',obj])
        for chip in (3,6):
            _,elf,image=link(name,fixture,chip,obj);d,*_=metadata(elf,chip);assert d[4]==4096;boot(name,image,chip,elf)
    for name,source in [('bss-only','__attribute__((aligned(64))) __thread volatile unsigned char value[33];unsigned int run(void){for(unsigned i=0;i<33;i++)if(value[i])return 1;return 0;}'),('data-only','__thread volatile unsigned long long value=0x8877665544332211ULL;unsigned int run(void){return value!=0x8877665544332211ULL;}')]:
        c=work/(name+'.c');c.write_text(source);obj=work/(name+'.o');run([*base,'-march=rv32imc_zicsr','-O2','-ftls-model=local-exec','-c',c,'-o',obj])
        for chip in (3,6):
            _,elf,image=link(name,'fn main(){return esp32_call32(esp32_external("run"),0,0,0,0,0,0,0,0);}',chip,obj);metadata(elf,chip);boot(name,image,chip,elf)
    # TLS must exist before the trusted platform's initializer is called.
    platform=work/'platform.flex';platform.write_text('global early=0;fn esp_platform_init(){let r=esp32_call32(esp32_external("tls_validate_initial"),0,0,0,0,0,0,0,0);if r{return r;}esp32_call32(esp32_external("tls_set"),13,0,0,0,0,0,0,0);early=1;return 0;}fn check(){if early!=1{return 1;}return esp32_call32(esp32_external("tls_validate_set"),13,0,0,0,0,0,0,0);}')
    for chip in (3,6):
        name='early-platform';prefix=work/(name+f'-c{chip}');source=Path(str(prefix)+'.seta');source.write_text('plugin rv.tls v1 {} extern fn check()->i32 fn main()->i32{return check()}');firmware=Path(str(prefix)+'.elf');elf=Path(str(prefix)+'-linked.elf');image=Path(str(prefix)+'.bin')
        run([compiler,'--target',f'esp32c{chip}-elf','--platform',platform,source,'-o',firmware]);run([linker,'--ld',a.ld,'--firmware',firmware,'--object',retained[3],'--output',elf,'--image',image]);metadata(elf,chip);boot(name,image,chip,elf)
    firmware,elf,image,obj,d=retained;original=image.read_bytes();base_address=0x3fca0000
    corrupt=[('magic',0,17),('disabled-nonzero',0,0),('initial-overflow',2,d[3]+1),('total-zero',3,0),('total-overflow',3,65537),('small-align',4,8),('nonpower-align',4,48),('large-align',4,131072),('template-unaligned',1,d[1]+1),('template-kernel',1,base_address),('template-overflow',1,base_address+65536),('main-unaligned',5,d[5]+1),('main-overlap',5,d[1]),('main-overflow',5,base_address+65536),('reserved',6,1)]
    for name,index,value in corrupt:
        raw=bytearray(original);data_at=image_data(raw);at=data_at+d[5]-base_address;raw[at:at+d[3]]=b'\xa5'*d[3];struct.pack_into('<I',raw,data_at+24+index*4,value);bad=work/('bad-'+name+'.bin');bad.write_bytes(seal_image(raw));boot('bad-'+name,bad,3,trap=True,expect=f'{d[5]:#x}:{d[3]}:0xa5')
    output,mapfile,rom=[work/x for x in ['protected.elf','protected.map','protected.bin']]
    def reject(name,fw=firmware,objects=(),ld=None,error='TLS'):
        for f in (output,mapfile,rom):f.write_text('preserve '+f.name)
        before=[sha(f) for f in (output,mapfile,rom)];cmd=[linker,'--firmware',fw,'--ld',ld or a.ld,'--output',output,'--map',mapfile,'--image',rom]
        for x in objects or [obj]:cmd+=['--object',x]
        result=run(cmd,reject=error);assert before==[sha(f) for f in (output,mapfile,rom)];rejections.append(dict(case=name,error=result.stderr[-250:]))
    for name,text in [('oversize','__thread volatile unsigned char huge[40000]={1};unsigned int run(void){return huge[0];}'),('oversize-alignment','__attribute__((aligned(65536))) __thread volatile unsigned char huge[1]={1};unsigned int run(void){return huge[0];}'),('dynamic-model','__thread volatile unsigned int huge=1;unsigned int run(void){return huge;}')]:
        c=work/(name+'.c');c.write_text(text);badobj=work/(name+'.o');flags=['-fPIC','-ftls-model=global-dynamic'] if name=='dynamic-model' else ['-ftls-model=local-exec'];run([*base,'-march=rv32im_zicsr','-O2',*flags,'-c',c,'-o',badobj]);src=work/(name+'.flex');src.write_text('fn main(){return esp32_call32(esp32_external("run"),0,0,0,0,0,0,0,0);}')
        fw=work/(name+'.elf');run([compiler,'--target','esp32c3-elf',src,'-o',fw]);reject(name,fw,[badobj],error='undefined symbol' if name=='dynamic-model' else 'TLS')
    # Validate hostile external-linker output before replacing destinations.
    good_raw,sections=elf_reference.elf_sections(elf);tls_ph=next(52+i*32 for i in range(struct.unpack_from('<H',good_raw,44)[0]) if struct.unpack_from('<I',good_raw,52+i*32)[0]==7);main_sh=struct.unpack_from('<I',good_raw,32)[0]+next(i*40 for i in range(struct.unpack_from('<H',good_raw,48)[0]) if struct.unpack_from('<I',good_raw,struct.unpack_from('<I',good_raw,32)[0]+i*40+12)[0]==d[5]);data_at=sections['.data'][0][4]
    mutations=[('TLS-file-overflow',tls_ph+16,65537),('TLS-size-overflow',tls_ph+20,65537),('TLS-bad-alignment',tls_ph+28,48),('TLS-file-unmapped',tls_ph+4,0),('TLS-missing-segment',tls_ph,0),('TLS-main-overlap',main_sh+12,d[1]),('TLS-main-small',main_sh+20,1),('TLS-descriptor-dirty',data_at+24,17)]
    for name,offset,value in mutations:
        raw=bytearray(good_raw);raw[data_at+24:data_at+56]=bytes(32);struct.pack_into('<I',raw,offset,value);malformed=work/(name+'.elf');malformed.write_bytes(raw);fake=work/(name+'-linker.py');fake.write_text('#!/usr/bin/env python3\nimport sys,shutil\nshutil.copyfile('+repr(str(malformed))+',sys.argv[sys.argv.index("-o")+1])\n');fake.chmod(0o755);reject(name,ld=fake)
    if a.legacy_compiler:
        plain=work/'plain.c';plain.write_text('unsigned int run(void){return 0;}');plainobj=work/'plain.o';run([*base,'-march=rv32im_zicsr','-c',plain,'-o',plainobj])
        legacy=a.legacy_compiler.resolve()
        for chip in (3,6):
            _,oldelf,oldimage=link('legacy-no-TLS','fn main(){return esp32_call32(esp32_external("run"),0,0,0,0,0,0,0,0);}',chip,plainobj,parser=legacy);boot('legacy-no-TLS',oldimage,chip,oldelf)
        source=work/'legacy.flex';source.write_text('fn main(){return esp32_call32(esp32_external("tls_validate_initial"),0,0,0,0,0,0,0,0);}')
        fw=work/'legacy.elf';run([legacy,'--target','esp32c3-elf',source,'-o',fw]);reject('legacy-no-descriptor',fw,error='TLS descriptor')
    # Direct TLS variable pointers must use a C accessor, never an absolute import.
    source=work/'TLS-direct.flex';source.write_text('fn main(){return esp32_external("tls_first");}');fw=work/'TLS-direct.elf';run([compiler,'--target','esp32c3-elf',source,'-o',fw]);reject('direct-TLS-import',fw,error='tls')
    for chip in (3,6):
        for text in ['global flex_tls_descriptor=0;fn main(){return 0;}','fn flex_tls_descriptor(){return 0;}fn main(){return 0;}']:
            source=work/'reserved.flex';source.write_text(text);before=sha(output);run([compiler,'--target',f'esp32c{chip}-elf',source,'-o',output],reject='reserved RISC-V TLS symbol');assert sha(output)==before;rejections.append(dict(case='reserved-symbol-c'+str(chip)))
    report=dict(pass_all=True,C3_ROM_boots=sum(x.get('machine')=='esp32c3' and x['ROM_boot'] for x in cases),C6_ROM_boots=sum(x.get('machine')=='esp32c6' and x['ROM_boot'] for x in cases),C6_packages=sum(not x['ROM_boot'] for x in cases),poisoned_main_checks=12,boot_descriptor_guards=len(corrupt),cases=cases,rejections=rejections,compiler_sha256=sha(compiler),physical_hardware=False,dynamic_TLS=False,vendor_library_startup=False)
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS: static TLS',report['C3_ROM_boots'],'C3 boots;',report['C6_ROM_boots'],'C6 boots;',report['C6_packages'],'C6 packages;',len(rejections),'preserved-output rejections')


if __name__=='__main__':main()
