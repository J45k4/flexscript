#!/usr/bin/env python3
"""Native clipboard interoperability against independent wl-clipboard peers.

Requires an explicitly private compositor with --fake-seat and the Weston input
test module. C/Python are test-only; application transfer code is Flexscript.
"""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary',type=Path,required=True)
p.add_argument('--runtime',type=Path,required=True)
p.add_argument('--display',required=True)
p.add_argument('--out',type=Path,default=ROOT/'build/migration/clipboard-peer-tests')
a=p.parse_args();root=a.runtime.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
assert root.stat().st_uid==os.getuid() and stat.S_IMODE(root.stat().st_mode)==0o700
assert '/' not in a.display and stat.S_ISSOCK((root/a.display).stat().st_mode)
env=dict(os.environ,XDG_RUNTIME_DIR=str(root),WAYLAND_DISPLAY=a.display);env.pop('DISPLAY',None)
for payload in [('Häät 中文 👋 — native clipboard\n'*2500).encode(),b'Boundary '+b'x'*(1048576-9)]:
    file=out/'payload.txt';file.write_bytes(payload)
    for mode in ['copy','paste']:
        name=f'{mode}-{len(payload)}';ready=out/f'{name}.ready';result=out/f'{name}.json';ack=Path(str(ready)+'.done')
        for path in [ready,result,ack]:path.unlink(missing_ok=True)
        if mode=='paste':
            cleared=subprocess.run(['wl-copy','--clear'],env=env,capture_output=True,timeout=8)
            assert cleared.returncode==0,cleared.stderr
        app=subprocess.Popen([str(a.binary.resolve()),mode,str(file),str(ready),str(result)],env=env,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            until=time.monotonic()+8
            while time.monotonic()<until and app.poll() is None:
                if ready.exists() and ready.read_text()==('copied' if mode=='copy' else 'ready'):break
                time.sleep(.02)
            assert ready.exists() and ready.read_text()==('copied' if mode=='copy' else 'ready'),(name,'readiness failed')
            if mode=='copy':
                peer=subprocess.run(['wl-paste','--no-newline','--type','text/plain;charset=utf-8'],env=env,capture_output=True,timeout=8)
                assert peer.returncode==0 and peer.stdout==payload,(name,peer.returncode,len(peer.stdout),peer.stderr)
                # The owner must outlive the consumer, including any compositor
                # clipboard-manager reads. Pipe write completion is not a peer ack.
                ack.write_text('consumed')
            else:
                peer=subprocess.run(['wl-copy','--foreground','--paste-once','--type','text/plain;charset=utf-8'],input=payload,env=env,capture_output=True,timeout=8)
                assert peer.returncode==0,(name,peer.returncode,peer.stderr)
            stdout,stderr=app.communicate(timeout=5);(out/f'{name}.stderr.log').write_bytes(stderr)
            assert app.returncode==0,(name,app.returncode,stdout,stderr)
            row=json.loads(result.read_text());assert row['success'] and row['bytes']==len(payload),row
            print('PASS',row,flush=True)
        finally:
            if app.poll() is None:
                app.kill();stdout,stderr=app.communicate();(out/f'{name}.stderr.log').write_bytes(stderr)
print('PASS native copy/paste interoperates at 100,000 and 1,048,576 bytes; no SDL loaded')
