#!/usr/bin/env python3
"""S3 cached firmware contracts: primary headers, ROM calls and rejection controls.

The native fixtures spy on calls and scripted return values. They do not execute
Xtensa instructions or model peripherals. Firmware execution uses stock QEMU.
"""
import argparse, hashlib, json, os, re, shutil, struct, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['compiler','reference','work']: p.add_argument('--'+k,required=True)
    a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
    assert not (w/'report.json').exists(),'use a fresh work directory'
    env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
    def run(args,name,ok=0):
        r=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=60)
        (w/(name+'.log')).write_bytes(r.stdout+r.stderr)
        assert r.returncode==ok,(name,r.returncode,(r.stdout+r.stderr)[-2000:])
        return r.stdout.decode()
    ref=Path(a.reference).resolve();prov=json.loads((ref.parent/'reference-provenance.json').read_text())
    for name,row in prov.items(): assert sha(ref/name)==row['sha256']
    inc=w/'include';(inc/'soc').mkdir(parents=True,exist_ok=True)
    for name in ['soc.h','reg_base.h','extmem_reg.h','ext_mem_defs.h']: shutil.copyfile(ref/name,inc/'soc'/name)
    shutil.copyfile(ref/'cache.h',inc/'cache.h')
    (inc/'esp_bit_defs.h').write_text('#ifndef BIT\n#define BIT(n) (1U << (n))\n#endif\n')
    (inc/'esp_assert.h').write_text('')
    c=w/'oracle.c';c.write_text('''#include <stdio.h>
#define __ASSEMBLER__ 1
#include "cache.h"
#include "soc/soc.h"
#include "soc/extmem_reg.h"
#include "soc/ext_mem_defs.h"
int main(void) {
 printf("%u %u %u %u %u %u %u %u %u %u %u %u %u %u\\n",
 ICACHE_SIZE_32KB,CACHE_8WAYS_ASSOC,CACHE_LINE_SIZE_32B,DCACHE_SIZE_32KB,
 CACHE_4WAYS_ASSOC,SOC_MMU_ENTRY_NUM,SOC_MMU_ACCESS_FLASH,SOC_MMU_INVALID,
 SOC_MMU_IBUS_VADDR_BASE,SOC_MMU_DBUS_VADDR_BASE,
 EXTMEM_ICACHE_CTRL1_REG,EXTMEM_DCACHE_CTRL1_REG,
 EXTMEM_ICACHE_SHUT_CORE0_BUS,EXTMEM_DCACHE_SHUT_CORE0_BUS);
 return 0;
}
''')
    run(['cc','-std=c11','-Wall','-Wextra','-Werror','-I',inc,c,'-o',w/'oracle-bin'],'oracle-build')
    values=list(map(int,run([w/'oracle-bin'],'oracle').split()))
    isize,iways,line,dsize,dways,entries,flash,invalid,ibus,dbus,ireg,dreg,imask,dmask=values
    assert entries==512 and invalid==1<<14 and imask==dmask==1
    rom={n:int(v,16) for n,v in re.findall(r'(\w+)\s*=\s*(0x[0-9a-fA-F]+)',(ref/'esp32s3.rom.ld').read_text())}
    # The first 64 entries belong to the 4MiB instruction virtual range. Each
    # region needs 256 bytes in the shared table; ROM limits their sum to 1024.
    iend=64*4;dend=2*iend;dvirtual=dbus+64*65536
    (w/'oracle.json').write_text(json.dumps(dict(header_values=values,MMU_bytes=[iend,iend],IROM=ibus,DROM=dvirtual,ROM=rom),indent=2)+'\n')
    module=ROOT/'lib/platform/esp32s3-xip.flex';original=module.read_text()
    cases=[]
    def case(name,state=0x3fca8000,cp=3,dp=3,cf=0x30000,df=None,ig=256,dg=512,ir=0,dr=0):
        if df is None: df=cf+cp*65536
        calls=[];writes=0;saves=int(state==0x3fca8000)
        def add(n,args=(),ret=0): calls.append([rom[n],*args,*([0]*(8-len(args))),ret])
        bad=cf!=0x30000 or not 1<=cp<=48 or not 0<=dp<=48 or df!=cf+cp*65536 or df+dp*65536>0x400000
        if not saves: result=-95
        elif bad: result=-22
        else:
            add('Cache_Disable_ICache');add('Cache_Disable_DCache')
            add('Cache_Set_ICache_Mode',(isize,iways,line));add('Cache_Set_DCache_Mode',(dsize,dways,line))
            add('Cache_Set_IDROM_MMU_Size',(iend,iend));add('Cache_Get_IROM_MMU_End',ret=ig)
            if ig!=iend: result=-5
            else:
                add('Cache_Get_DROM_MMU_End',ret=dg)
                if dg!=dend: result=-5
                else:
                    add('Cache_MMU_Init');add('ets_efuse_get_spiconfig',ret=0x01234567)
                    add('spi_flash_attach',(0x01234567,0));add('Cache_Ibus_MMU_Set',(flash,ibus,cf,64,cp,0),ir)
                    result=ir
                    if not result and dp: add('Cache_Dbus_MMU_Set',(flash,dvirtual,df,64,dp,0),dr);result=dr
                    if not result:
                        writes=2;add('Cache_Enable_ICache');add('Cache_Enable_DCache')
        fields=[state,cp,dp,cf,df,result,len(calls),writes,saves]
        cases.append(dict(name=name,fields=fields,calls=calls))
    for cp,dp in [(1,0),(1,1),(3,3),(48,13),(13,48)]: case(f'valid-{cp}-{dp}',cp=cp,dp=dp)
    for name,kw in [('wrong-profile',dict(state=0x3fcb0000)),('no-pages',dict(cp=0)),('negative-code',dict(cp=-1)),('code-overflow',dict(cp=49)),('negative-data',dict(dp=-1)),('data-overflow',dict(dp=49)),('flash-overflow',dict(cp=48,dp=14)),('wrong-offset',dict(cf=0x20000)),('gap',dict(df=0x90000)),('bad-irom-split',dict(ig=0)),('bad-drom-split',dict(dg=0)),('ibus-error',dict(ir=2)),('dbus-error',dict(dr=3))]: case(name,**kw)
    blob=bytearray(struct.pack('<q',len(cases)))
    for row in cases:
        blob+=struct.pack('<9q',*row['fields'])
        for call in row['calls']: blob+=struct.pack('<10q',*call)
    vectors=w/'calls.bin';vectors.write_bytes(blob)
    (w/'calls.json').write_text(json.dumps(cases,indent=2)+'\n')
    template='''import "@HOST@";
import "@MODULE@";
global xc_row=0;global xc_plan=0;global xc_n=0;global xc_pos=0;
global xc_failed=0;global xc_checks=0;global xc_saved=0;global xc_restored=0;
global xc_writes=0;global xc_reads=0;
fn xc_expect(ok) {xc_checks=xc_checks+1;if !ok {xc_failed=1;}return 0;}
fn esp32_state() {return load64(xc_row);}
fn esp32_external(name) {
 if h_equal(name,"_flex_irom_pages") {return load64(xc_row+8);}
 if h_equal(name,"_flex_drom_pages") {return load64(xc_row+16);}
 if h_equal(name,"_flex_irom_flash") {return load64(xc_row+24);}
 if h_equal(name,"_flex_drom_flash") {return load64(xc_row+32);}
 xc_failed=1;return 0;
}
fn esp32_irq_save() {xc_saved=xc_saved+1;return 0x400ef;}
fn esp32_irq_restore(ps) {xc_expect(ps==0x400ef);xc_restored=xc_restored+1;return 0;}
fn esp32_load32(address) {xc_reads=xc_reads+1;xc_expect(address==@IREG@ || address==@DREG@);return 0xa5a5a5a7;}
fn esp32_store32(address,value) {let reg=@IREG@;if xc_writes {reg=@DREG@;}xc_expect(address==reg && value==0xa5a5a5a6);xc_writes=xc_writes+1;return 0;}
fn esp32_call32(address,a,b,c,d,e,f,g,h) {
 xc_expect(xc_pos<xc_n);if xc_pos>=xc_n {return -5;}let p=xc_plan+xc_pos*80;xc_pos=xc_pos+1;
 xc_expect(address==load64(p));xc_expect(a==load64(p+8));xc_expect(b==load64(p+16));xc_expect(c==load64(p+24));xc_expect(d==load64(p+32));xc_expect(e==load64(p+40));xc_expect(f==load64(p+48));xc_expect(g==load64(p+56));xc_expect(h==load64(p+64));return load64(p+72);
}
fn main(argc,argv) {
 h_environment(argc,argv);let bytes=h_read(load64(argv+8));let n=load64(bytes);let i=0;let at=bytes+8;
 while i<n {xc_row=at;xc_plan=at+72;xc_n=load64(at+48);xc_pos=0;xc_saved=0;xc_restored=0;xc_writes=0;xc_reads=0;
  let result=esp_xip_enable();xc_expect(result==load64(at+40));xc_expect(xc_pos==xc_n);xc_expect(xc_saved==load64(at+64));xc_expect(xc_restored==xc_saved);xc_expect(xc_writes==load64(at+56));xc_expect(xc_reads==xc_writes);
  if xc_failed {h_print(2,h_cat3("cache contract mismatch case ",h_int(i),"\\n"));return 1;}
  at=xc_plan+xc_n*80;i=i+1;
 }h_print(1,h_cat3("Cache contract: ",h_int(xc_checks)," checks\\n"));return 0;
}
'''.replace('@HOST@',str(ROOT/'scripts/lib/host.flex')).replace('@IREG@',str(ireg)).replace('@DREG@',str(dreg))
    def spy(label,text,ok):
        d=w/label;d.mkdir(exist_ok=True);m=d/'cache.flex';m.write_text(text);src=d/'test.flex';src.write_text(template.replace('@MODULE@',str(m)))
        exe=d/'test';run([a.compiler,src,'-o',exe],label+'-build');return run([exe,vectors],label,ok)
    output=spy('canonical',original,0);match=re.fullmatch(r'Cache contract: (\d+) checks\n',output);assert match
    mutations=[('overlapping-mmu','0x3c400000','0x3c000000'),('oversized-mmu','256,256,0','1024,1024,0'),('wrong-cache-size','0x40001620,1,1,1','0x40001620,0,1,1'),('wrong-cache-ways','0x4000162c,0,0,1','0x4000162c,0,1,1'),('wrong-line','0x40001620,1,1,1','0x40001620,1,1,0'),('old-rom-entry','0x400019a4','0x40009a14'),('wrong-flash-mode','0x400019a4,0,','0x400019a4,1,'),('lost-split-readback','!=256','!=0'),('wrong-pin-routing','0x40000aec,pins,0','0x40000aec,0,0'),('legacy-attach','0x40000aec,pins,0','0x40000aec,pins,1'),('enable-on-failure','if !result {','if 1 {'),('lost-ps-restore','}esp32_irq_restore(ps);return result;','}return result;'),('skip-layout-bound',' || data_flash+data_pages*65536>0x400000',''),('admit-empty-code','code_pages<1','code_pages<0'),('wrong-profile-admitted','esp32_state()!=0x3fca8000','0'),('clear-cpu1-bus','&~1','&~3')]
    detected=[]
    for name,before,after in mutations:
        assert before in original,name;spy(name,original.replace(before,after,1),1);detected.append(name)
    # Buffer checking uses the real SPI entry point, while stores are counted.
    # Values never reach a native MMIO access: every invalid descriptor must
    # return EINVAL before touching the FIFO or output buffer.
    common=ROOT/'lib/platform/esp32s3-common.flex';ct=common.read_text().replace('"esp32s3.flex"',json.dumps(str(ROOT/'lib/platform/esp32s3.flex')))
    spi=(ROOT/'lib/platform/esp32s3-spi.flex').read_text();body=(ROOT/'tests/esp32/s3-buffer-body.flex').read_text();fixture=(ROOT/'tests/esp32/s3-buffer-checks.flex').read_text()
    def buffers(label,text,ok):
        d=w/label;d.mkdir(exist_ok=True);m=d/'common.flex';m.write_text(text);s=d/'spi.flex';s.write_text(spi.replace('"esp32s3-common.flex"',json.dumps(str(m))))
        b=d/'body.flex';b.write_text(body.replace('"../../lib/platform/esp32s3-spi.flex"',json.dumps(str(s))));src=d/'test.flex';src.write_text(fixture.replace('"s3-buffer-body.flex"',json.dumps(str(b))))
        exe=d/'test';run([a.compiler,src,'-o',exe],label+'-build');out=subprocess.run([exe],capture_output=True,cwd=ROOT,env=env,timeout=10);(w/(label+'.log')).write_bytes(out.stdout+out.stderr);assert out.returncode==ok,(label,out.returncode,out.stderr)
        return out.stdout
    result=buffers('buffers-canonical',ct,0);assert struct.unpack('<q',result)[0]==73
    bm=[('reserved-header-admitted','pointer>=state+24','pointer>=state+16'),('new-native-rejected','pointer>=state+24','pointer>=0x3fcb0010'),('sdk-iram-alias-admitted','pointer>=state+24','pointer>=0x3fcb0010 || pointer==0x3fc90000'),('new-profile-rejected',' && state!=0x3fca8000',''),('unknown-profile-admitted',' {return 0;}return size',' {return 1;}return size'),('upper-byte-admitted','size<=0x3fcd0000-pointer','size<=0x3fcd0001-pointer'),('empty-end-rejected','pointer<=0x3fcd0000','pointer<0x3fcd0000'),('extent-overflow','size<=0x3fcd0000-pointer','pointer+size<=0x3fcd0000')]
    for name,before,after in bm:
        assert before in ct,name;buffers(name,ct.replace(before,after,1),1)
    report=dict(pass_all=True,cache_cases=len(cases),cache_checks=int(match[1]),cache_defects=detected,buffer_checks=73,buffer_defects=[x[0] for x in bm],compiler_sha256=sha(a.compiler),physical_hardware=False,emulator_implementation_changes=False,source_sha256={str(x.relative_to(ROOT)):sha(x) for x in [module,common,Path(__file__)]})
    (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: {len(cases)} cache cases, {match[1]} call checks, 73 buffer checks; {len(detected)+len(bm)} defects detected',flush=True)
if __name__=='__main__':main()
