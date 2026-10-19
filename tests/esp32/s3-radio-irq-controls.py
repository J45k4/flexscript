#!/usr/bin/env python3
"""Check S3 vendor IRQ registration using native Xtensa software interrupts.

One isolated source copy replaces the pending-register read with scripted
values and inserts software-IRQ probes at publication boundaries. No emulator
instructions, peripheral models or timing code are changed.
"""
import argparse,hashlib,json,os,re,runpy,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def edit(text,function,before,after):
    start=text.index('fn '+function+'(');brace=text.index('{',start);depth=1;end=brace+1
    while depth:
        if text[end]=='{':depth+=1
        elif text[end]=='}':depth-=1
        end+=1
    body=text[start:end];assert before in body,(function,before)
    return text[:start]+body.replace(before,after,1)+text[end:]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for k in ['compiler','driver','prefix','qemu','peer','work']:p.add_argument('--'+k,required=True)
    a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True);assert not (w/'report.json').exists()
    env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp')
    helper=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'));base=w/'source';manifest=helper['copy_closure'](ROOT/'tests/esp32/s3-radio-irq.flex',base)
    manifest.update(helper['copy_closure'](ROOT/'tests/esp32/s3-radio-irq-plain.flex',base))
    original=(base/'lib/platform/esp32s3-radio-irq.flex').read_text()
    instrumented=original.replace('esp32_load32(0x600c218c)','si_status()')
    for function,before,after in [('esp_radio_cb_set_isr','esp_radio_isr=b;','esp_radio_isr=b;si_probe();'),('esp_radio_cb_ints_on','esp32_store32(esp_radio_route(0),1);','esp32_store32(esp_radio_route(0),1);si_probe();'),('esp_radio_cb_ints_off','esp32_store32(esp_radio_route(0),6);','esp32_store32(esp_radio_route(0),6);si_probe();')]:instrumented=edit(instrumented,function,before,after)
    def boot(name,text,forced,ok,profile="esp32s3-xip-elf",fixture="s3-radio-irq.flex"):
        tree=w/name/'source';shutil.copytree(base,tree,dirs_exist_ok=True);(tree/'lib/platform/esp32s3-radio-irq.flex').write_text(text)
        src=tree/'tests/esp32'/fixture
        if forced:src.write_text(src.read_text().replace('global si_forced=0;','global si_forced=1;'))
        report=w/(name+'.json');args=[a.driver,'--compiler',a.compiler,'--work',w/name/'run','--qemu',a.qemu,'--prefix',a.prefix,'--source',src,'--chip','esp32s3','--profile',profile,'--extra',a.peer,'--report',report]
        q=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,timeout=30);text=(q.stdout+q.stderr).decode(errors='replace');(w/(name+'.log')).write_text(text)
        assert q.returncode==ok,(name,q.returncode,text[-1800:]);assert 'SHUTDOWN' in text or not ok,(name,text[-1000:])
        if ok:assert 'main returned zero' in text and '0x444f4e45' in text,(name,text[-1000:])
        else:assert 'PASS:' in text,(name,text[-1000:])
        print(name,'detected' if ok else 'passed',flush=True)
        return dict(name=name,source_sha256=sha(src),module_sha256=sha(tree/'lib/platform/esp32s3-radio-irq.flex'),checks=int(re.search(r'checks=([0-9a-f]+)',text)[1],16) if not ok and 'checks=' in text else None,report=str(report) if not ok else None)
    positives=[boot('plain-native',original,False,0,'esp32s3-elf','s3-radio-irq-plain.flex')]
    for profile in ['esp32s3-sdk-elf','esp32s3-xip-elf']:
        positives.append(boot(profile+'-native',original,False,0,profile))
        positives.append(boot(profile+'-publication',instrumented,True,0,profile))
    preserved=w/'plain-limit-preserved.elf';preserved.write_bytes(b'preserve existing output');digest=sha(preserved)
    limit=subprocess.run([a.compiler,'--target','esp32s3-elf',str(base/'tests/esp32/s3-radio-irq.flex'),'-o',str(preserved)],cwd=ROOT,env=env,capture_output=True,timeout=30)
    (w/'plain-limit.log').write_bytes(limit.stdout+limit.stderr);assert limit.returncode==1 and b'exceeds 128 KiB IRAM' in limit.stderr and sha(preserved)==digest
    mutations=[
      ('half-pair','esp_radio_cb_set_isr','esp_radio_isr=b;si_probe();','esp32_irq_restore(0);esp_radio_isr=b;si_probe();'),
      ('missing-power-preflight','esp_radio_cb_set_isr','result=esp_radio_irq_can_claim(2,handler);','result=0;'),
      ('missing-capacity-preflight','esp_radio_cb_set_isr','result=esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2));','result=0;'),
      ('capacity-for-one','esp_radio_cb_set_isr','esp_irq_reserve(!esp_irq_handler(0)+!esp_irq_handler(2))','esp_irq_reserve(!esp_irq_handler(0))'),
      ('missing-power-attach','esp_radio_cb_set_isr','result=esp_irq_attach(2,handler);','result=0;'),
      ('missing-argument','esp_radio_cb_set_isr','esp_radio_isr_arg=c;','esp_radio_isr_arg=0;'),
      ('wrong-domain','esp_radio_cb_set_isr','if esp_radio_owner!=1','if !esp_radio_owner'),
      ('half-enable','esp_radio_cb_ints_on','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(0);'),
      ('half-disable','esp_radio_cb_ints_off','let ps=esp32_irq_save();','let ps=esp32_irq_save();esp32_irq_restore(0);'),
      ('missing-power-disable','esp_radio_cb_ints_off','esp32_store32(esp_radio_route(2),6);',''),
      ('missing-power-enable','esp_radio_cb_ints_on','esp32_store32(esp_radio_route(2),1);',''),
      ('clobbered-intenable','esp_radio_cb_ints_on','esp32_irq_enabled()|2','2'),
      ('wrong-pending-bit','esp_radio_irq','(1<<source)','1'),
      ('no-pending-check','esp_radio_irq',' || !(si_status()&(1<<source))',''),
      ('no-route-check','esp_radio_irq',' || esp32_load32(esp_radio_route(source))!=1',''),
      ('mac-only','esp_radio_irq','if source!=0 && source!=2','if source!=0'),
      ('bad-source-admitted','esp_radio_cb_set_intr','if b!=0 && b!=2','if b<0'),
      ('stale-cleanup-pair','esp_radio_s3_irq_deinit','esp_radio_isr=0;esp_radio_isr_arg=0;',''),
    ]
    defects=[]
    for name,fn,before,after in mutations:defects.append(boot(name,edit(instrumented,fn,before,after),True,1))
    assert all(sha(ROOT/n)==digest for n,digest in manifest.items())
    (w/'source-sha256.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (w/'report.json').write_text(json.dumps(dict(pass_all=True,positive_cases=positives,defect_controls=defects,plain_IRAM_limit_preserves_output=True,compiler_sha256=sha(a.compiler),C_peer_sha256=sha(a.peer),qemu_sha256=sha(a.qemu),physical_RF=False,emulator_implementation_changes=False),indent=2)+'\n')
    print(f'PASS: {len(positives)} native/publication boots and {len(defects)} defects',flush=True)
if __name__=='__main__':main()
