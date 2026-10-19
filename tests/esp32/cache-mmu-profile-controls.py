#!/usr/bin/env python3
"""Reject forged MMU fault/synchronization metadata before any device child."""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','backup','work','report'):p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[2];work=a.work.resolve();work.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();results=[]
for label in ('wrong-fault-family','forged-prefix-sync','forged-unmask-near'):
    matrix=work/label;matrix.mkdir()
    for clock in (40,160):
        group=f'clock{clock}-kind0';source=a.matrix.resolve()/group;target=matrix/group;target.mkdir()
        for path in source.glob('*.elf'):
            if 'unlinked' not in path.name:(target/path.name).symlink_to(path)
        manifest=json.loads((source/'manifest.json').read_text())
        for case in manifest:
            if label=='wrong-fault-family':case['fault']='disabled-data'
            if label=='forged-prefix-sync':case['prefix_sync']=1
            if label=='forged-unmask-near':case['prefix_sync']=0;case['unmask_near']=1
        path=target/'manifest.json';path.write_text(json.dumps(manifest,indent=2)+'\n')
        native=json.loads((source/'native.json').read_text());native['manifest_sha256']=sha(path)
        (target/'native.json').write_text(json.dumps(native,indent=2)+'\n')
    report=matrix/'outer.json';cmd=['python3',root/'tests/esp32/cache-latency-physical.py','--family','mmu','--post-kinds','0','--matrix',matrix,'--backup',a.backup.resolve(),'--backup-sha256',a.backup_sha256,'--port','/tmp/no-mmu-profile-control-port','--espflash','/tmp/no-mmu-profile-control-espflash','--report',report]
    if label=='forged-prefix-sync':cmd+=['--prefix-sync','1']
    if label=='forged-unmask-near':cmd+=['--unmask-near','1']
    q=subprocess.run([str(x) for x in cmd],capture_output=True,timeout=10)
    assert q.returncode==1 and b'AssertionError' in q.stderr and not report.exists(),(label,q.returncode,q.stdout,q.stderr)
    results.append({'control':label,'rejected_before_any_device_child':True});print('MMU profile controls:',len(results),flush=True)
a.report.write_text(json.dumps({'pass':True,'physical_hardware_touched':False,'controls':results},indent=2)+'\n')
print('PASS:3 consistently hashed forged MMU profiles rejected beforedevice access')
