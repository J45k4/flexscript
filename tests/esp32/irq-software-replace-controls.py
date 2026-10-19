#!/usr/bin/env python3
"""Execute pending software-IRQ replacement on both real target ROM paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
ROOT=Path(__file__).resolve().parents[2]
h=runpy.run_path(str(ROOT/'tests/esp32/lifecycle-preempt-reference.py'))
p=argparse.ArgumentParser(description=__doc__)
for name in ['compiler','driver','qemu','prefix','s3-prefix','work']:p.add_argument('--'+name,required=True)
a=p.parse_args();w=Path(a.work).resolve();w.mkdir(parents=True,exist_ok=True)
if (w/'report.json').exists():raise RuntimeError('choose a fresh work directory')
source=w/'production-source';manifest={}
for name in ['irq-software-replace.flex','irq-software-replace-s3.flex']:manifest.update(h['copy_closure'](ROOT/'tests/esp32'/name,source))
env=os.environ.copy();(w/'tmp').mkdir(exist_ok=True);env['TMPDIR']=str(w/'tmp');records=[]
def sha(path):
 with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
for chip,prefix,fixture,module in [('esp32',a.prefix,'irq-software-replace.flex','esp32-irq.flex'),('esp32s3',a.s3_prefix,'irq-software-replace-s3.flex','esp32s3-irq.flex')]:
    for defect in [False,True]:
        name=chip+('-drop-pending' if defect else '-protected');tree=w/name/'source';shutil.copytree(source,tree)
        if defect:h['change'](tree/'lib/platform'/module,'esp_irq_software',lambda text:h['once'](text,'if first {esp32_irq_clear(128);}','esp32_irq_clear(128);'))
        out=w/name/'firmware';log=w/name/'execution.log';cmd=[a.driver,'--compiler',a.compiler,'--qemu',a.qemu,'--prefix',prefix,'--chip',chip,'--source',str(tree/'tests/esp32'/fixture),'--work',str(out)]
        with log.open('w') as stream:r=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=45)
        text=log.read_text();qmp=out/'qmp-failure.log';ok=r.returncode==(1 if defect else 0)
        if defect:ok=ok and 'main returned zero' in text and qmp.exists() and '0x00000005 0x00000000' in qmp.read_text() and 'SHUTDOWN' in qmp.read_text()
        else:ok=ok and 'PASS:64 software IRQ replacements/rejections' in text
        row=dict(chip=chip,defect=defect,expected_behavior=ok,exit_code=r.returncode,log=str(log),log_sha256=sha(log),elf=str(out/'firmware.elf'),elf_sha256=sha(out/'firmware.elf'),image_sha256=sha(out/'firmware.bin'));records.append(row);print(json.dumps(row),flush=True)
        (w/'report.json').write_text(json.dumps(dict(pass_all=all(x['expected_behavior'] for x in records),cases=records,source_sha256=manifest,tools_sha256={str(Path(x).resolve()):sha(x) for x in [a.compiler,a.driver,a.qemu,__file__]},physical_hardware=False,emulator_changes=False),indent=2)+'\n')
        if not ok:raise RuntimeError(f'{name}: intended behavior missing; see {log}')
print('Both chips deliver64 pending/rejected events exactly once; both drop-pending defects rejected')
