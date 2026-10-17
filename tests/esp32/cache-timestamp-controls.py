#!/usr/bin/env python3
"""Reject invalid native cycle-stamp proofs before any device child starts."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
for name in ('matrix','backup','work','report'):
    p.add_argument('--'+name,type=Path,required=True)
p.add_argument('--backup-sha256',required=True)
a=p.parse_args()
root=Path(__file__).resolve().parents[2]
work=a.work.resolve()
work.mkdir(parents=True,exist_ok=True)
sha=lambda data:hashlib.sha256(data).hexdigest()
controls=[]
for label in ('missing-start-stamp','stamp-overflows-32-bits','zero-elapsed-cycles','UART-hash-mismatch'):
    matrix=work/label
    matrix.mkdir()
    for clock in (40,160):
        for kind in (5,6):
            group=f'clock{clock}-kind{kind}'
            source=a.matrix.resolve()/group
            target=matrix/group
            target.mkdir()
            for file in source.iterdir():
                if file.suffix=='.elf' or file.name=='manifest.json':
                    (target/file.name).symlink_to(file)
            shutil.copytree(source/'native',target/'native')
            shutil.copy2(source/'native.json',target/'native.json')
    target=matrix/'clock40-kind5'
    uart=target/'native/bus0-mode0.uart'
    data=uart.read_bytes()
    if label=='missing-start-stamp':
        data=data.replace(b' STARTCC ',b' STARTXX ',1)
    elif label=='stamp-overflows-32-bits':
        data,count=re.subn(rb' STARTCC [0-9a-f]{16}',b' STARTCC 0000000100000000',data,count=1)
        assert count==1
    elif label=='zero-elapsed-cycles':
        stamp=re.search(rb' STARTCC ([0-9a-f]{16})',data)[1]
        data,count=re.subn(rb' IRQCC [0-9a-f]{16}',b' IRQCC '+stamp,data,count=1)
        assert count==1
    else:
        data=data.replace(b' STARTCC ',b' INVALID ',1)
    uart.write_bytes(data)
    if label!='UART-hash-mismatch':
        proof=json.loads((target/'native.json').read_text())
        proof['cases'][0]['UART_sha256']=sha(data)
        (target/'native.json').write_text(json.dumps(proof,indent=2)+'\n')
    report=matrix/'outer-report.json'
    command=['python3',root/'tests/esp32/cache-latency-physical.py','--matrix',matrix,
             '--post-kinds','5','6','--backup',a.backup.resolve(),
             '--backup-sha256',a.backup_sha256,'--port','/tmp/no-timestamp-control-port',
             '--espflash','/tmp/no-timestamp-control-espflash','--report',report]
    q=subprocess.run([str(x) for x in command],capture_output=True,timeout=10)
    assert q.returncode==1 and 'AssertionError' in q.stderr.decode() and not report.exists(),(label,q.returncode,q.stdout,q.stderr)
    controls.append({'control':label,'rejected_before_any_device_child':True})
    print('Timestamp preflight controls:',len(controls),flush=True)
a.report.write_text(json.dumps({'pass':True,'physical_hardware_touched':False,
    'controls':controls},indent=2)+'\n')
print('PASS:4 bad native cycle-stamp proofs rejected before device access')
