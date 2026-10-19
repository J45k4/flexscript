#!/usr/bin/env python3
"""Execute S3 cached-firmware defects and preserve rejected linker outputs.

All mutations affect isolated source copies. The stock QEMU executable and its
ROM images remain unchanged. This is firmware validation, not emulator work.
"""
import argparse, hashlib, json, os, runpy, shutil, struct, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def elf(path): return runpy.run_path(str(ROOT/'tests/esp32/s3-sdk-reference.py'))['elf'](path)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['compiler','driver','prefix','qemu','positive','compiler-source','work']: p.add_argument('--'+k,required=True)
    a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
    assert not (w/'report.json').exists(),'choose fresh work directory'
    env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp');helper=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
    def run(args,name,ok=0,contains=None,cwd=ROOT):
        r=subprocess.run(list(map(str,args)),cwd=cwd,env=env,capture_output=True,timeout=60)
        text=(r.stdout+r.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text)
        assert r.returncode==ok,(name,r.returncode,text[-1600:]);assert contains is None or contains in text,(name,contains,text[-1600:]);return text
    def copy(entry,d): return helper['copy_closure'](ROOT/entry,d)
    def change(path,before,after):
        text=path.read_text();assert before in text,(path,before);path.write_text(text.replace(before,after,1))
    controls=[];positive=Path(a.positive).resolve();inputelf=positive/'0/firmware-input.elf';linker=positive/'0/link';dest=w/'preserved.elf'
    def reject(args,name,message):
        dest.write_bytes(b'preserve existing output\n');digest=sha(dest);run(args,name,1,message);assert sha(dest)==digest;controls.append(name)
    base=[linker,'--firmware',inputelf,'--output',dest,'--ld',a.prefix+'ld']
    reject(base,'missing-xip','flash firmware requires --xip')
    data,sections,info=elf(inputelf)
    for word in [2,4,5,6,7]:
        b=bytearray(data);at=sections['.flex.info']['offset']+word*4;struct.pack_into('<I',b,at,struct.unpack_from('<I',b,at)[0]+16);path=w/f'bad-profile-{word}.elf';path.write_bytes(b)
        reject([linker,'--firmware',path,'--output',dest,'--ld',a.prefix+'ld','--xip'],f'metadata-{word}','invalid ESP32-S3 cached memory profile')
    b=bytearray(data);at=sections['.flex.info']['offset']+12;struct.pack_into('<I',b,at,info[3]+16);path=w/'bad-profile-3.elf';path.write_bytes(b)
    reject([linker,'--firmware',path,'--output',dest,'--ld',a.prefix+'ld','--xip'],'metadata-3','unexpected memory layout')
    reject([linker,'--firmware',positive/'10/firmware-input.elf','--output',dest,'--ld',a.prefix+'ld','--xip'],'sdk-cannot-cache','--xip requires')
    src=w/'missing-bootstrap.flex';src.write_text('fn main(){return 0;}')
    reject([a.compiler,'--target','esp32s3-xip-elf',src,'-o',dest],'missing-bootstrap','requires esp_xip_enable()')
    src=w/'static-overflow.flex';src.write_text('import '+json.dumps(str(ROOT/'lib/platform/esp32s3-xip.flex'))+';\n'+'fn main(){let text='+json.dumps('x'*32768)+';return load8(text);}')
    reject([a.compiler,'--target','esp32s3-xip-elf',src,'-o',dest],'static-overflow','static data overlaps')
    # Linker bounds must include external C/ASM inputs, including cache data.
    for name,section,size,message in [('iram-overflow','.phyiram.oversized',98304,'vendor code exceeds available IRAM'),('dram-overflow','.dram1.oversized',32768,'vendor data overlaps'),('flash-overflow','.rodata.oversized',4194304,'XIP image exceeds 4 MiB flash')]:
        asm=w/(name+'.S');asm.write_text(f'.section {section},"a"\n.space {size}\n.global excess_{name.replace("-","_")}\nexcess_{name.replace("-","_")}:\n.byte 1\n');obj=w/(name+'.o');run([a.prefix+'as',asm,'-o',obj],name+'-as')
        # Force retention; otherwise GNU --gc-sections rightly discards it.
        symbol='excess_'+name.replace('-','_');f=w/(name+'.flex');f.write_text('import '+json.dumps(str(ROOT/'lib/platform/esp32s3-xip.flex'))+f';fn main(){{return esp32_external("{symbol}");}}')
        binary=w/(name+'.elf');run([a.compiler,'--target','esp32s3-xip-elf',f,'-o',binary],name+'-compile')
        reject([linker,'--firmware',binary,'--output',dest,'--ld',a.prefix+'ld','--xip','--object',obj],name,message)
    # An allocated orphan inside a cached window must never disappear from the
    # final flash payload. Give GNU ld a deterministic explicit address.
    for label,address,ph in [('irom',0x42040000,'irom'),('drom',0x3c430000,'drom')]:
        tree=w/('orphan-'+label)/'source';copy('scripts/esp32-link.flex',tree);script=tree/'scripts/esp32-link.flex'
        change(script,'text=h_cat(text,".flex.info 0 :',f'text=h_cat(text,".orphan {address} : {{ LONG(123); }} :{ph}\\n.flex.info 0 :')
        exe=tree.parent/'link';run([a.compiler,script,'-o',exe],'orphan-'+label+'-build')
        image=w/('orphan-'+label)/'preserved.bin';image.write_bytes(b'preserve image');digest=sha(image)
        reject([exe,'--firmware',positive/'1/firmware-input.elf','--output',dest,'--image',image,'--ld',a.prefix+'ld','--xip','--object',positive/'cache.o','--object',positive/'cache-data.o'],'orphan-'+label,'cached allocated section is outside emitted')
        assert sha(image)==digest
    # Firmware defects are tested with the same normal completion assertion.
    # The harness prints the actual TRAP/DONE and QMP SHUTDOWN, then fails.
    bootcases=[]
    def driver(src,name,extra=(),compiler=None):
        args=[a.driver,'--compiler',compiler or a.compiler,'--work',w/name,'--qemu',a.qemu,'--prefix',a.prefix,'--source',src,'--chip','esp32s3','--xip','yes',*extra]
        text=run(args,name,1);assert ('0x54524150' in text or 'main returned zero' in text) and 'SHUTDOWN' in text,(name,text[-1700:]);bootcases.append(name)
    tree=w/'bootstrap-failure/source';copy('tests/esp32/s3-xip.flex',tree);change(tree/'lib/platform/esp32s3-xip.flex','if esp32_state()!=0x3fca8000','if 1');driver(tree/'tests/esp32/s3-xip.flex','bootstrap-rejected')
    for name,anchor,replacement in [('malloc-fixed96','size>esp_sdk_end-esp_sdk_begin-32','size>98304'),('calloc-fixed96','n>(esp_sdk_end-esp_sdk_begin-32)/size','n>98304/size'),('calloc-product-overflow','n>(esp_sdk_end-esp_sdk_begin-32)/size','n*size>esp_sdk_end-esp_sdk_begin-32')]:
        tree=w/name/'source';copy('tests/esp32/s3-xip-heap-bounds.flex',tree);change(tree/'lib/platform/esp32-sdk-heap.flex',anchor,replacement);driver(tree/'tests/esp32/s3-xip-heap-bounds.flex',name+'-boot')
    # Losing physical-PC translation must fail cached callback/return execution.
    tree=w/'flat-pc/compiler-source';shutil.copytree(a.compiler_source,tree,dirs_exist_ok=True);change(tree/'compiler/backends/esp32.flex','fn esp_code_address(offset) {if esp_flash && offset>=0x50000 {return esp_irom_base()+offset-0x50000;}return esp_code_base+offset;}','fn esp_code_address(offset) {return esp_code_base+offset;}')
    badcompiler=w/'flat-pc/compiler';run([a.compiler,tree/'compiler/main.flex','-o',badcompiler],'flat-pc-build');driver(ROOT/'tests/esp32/s3-xip.flex','flat-pc-boot',compiler=badcompiler)
    # Recreate the real unified-MMU overlap bug by changing both bootstrap and
    # link VMA together; this still produces a valid ROM-integrity image.
    tree=w/'overlap/source';copy('tests/esp32/s3-xip-data.flex',tree);copy('scripts/esp32-link.flex',tree)
    change(tree/'lib/platform/esp32s3-xip.flex','0x3c400000','0x3c000000');change(tree/'scripts/lib/esp32-elf.flex','0x3c400000','0x3c000000')
    badlinker=w/'overlap/link';run([a.compiler,tree/'scripts/esp32-link.flex','-o',badlinker],'overlap-link-build')
    badinput=w/'overlap/input.elf';run([a.compiler,'--target','esp32s3-xip-elf',tree/'tests/esp32/s3-xip-data.flex','-o',badinput],'overlap-compile')
    badimage=w/'overlap/firmware.bin';run([badlinker,'--firmware',badinput,'--output',w/'overlap/firmware.elf','--image',badimage,'--ld',a.prefix+'ld','--xip','--object',positive/'cache.o','--object',positive/'cache-data.o'],'overlap-link')
    boot=w/'overlap/check.flex';boot.write_text('import '+json.dumps(str(ROOT/'scripts/lib/esp32-test.flex'))+';fn main(argc,argv){h_environment(argc,argv);te_init(load64(argv+8));te_qemu=load64(argv+16);te_s3_xip=1;te_xip=1;te_work=load64(argv+24);te_run(load64(argv+32),0,"PASS:");return 0;}')
    exe=w/'overlap/check';run([a.compiler,boot,'-o',exe],'overlap-check-build');out=run([exe,a.compiler,a.qemu,w/'overlap',badimage],'overlap-boot',1,'0x54524150');assert 'SHUTDOWN' in out;bootcases.append('overlap-boot')
    report=dict(pass_all=True,rejections=controls,firmware_defect_boots=bootcases,compiler_sha256=sha(a.compiler),qemu_sha256=sha(a.qemu),physical_hardware=False,emulator_implementation_changes=False)
    (w/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(f'PASS: {len(controls)} rejected compiler/link inputs and {len(bootcases)} firmware defect boots',flush=True)
if __name__=='__main__':main()
