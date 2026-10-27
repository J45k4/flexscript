#!/usr/bin/env python3
"""Cursor frame/deadline oracle. CPU evidence, not compositor delivery proof."""
import argparse,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
out=ROOT/'build/migration/cursor-state-tests';out.mkdir(parents=True,exist_ok=True)
subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(ROOT/'tests/tooling/cursor-abi.c'),'-o',str(out/'cursor-abi')],check=True)
subprocess.run([str(out/'cursor-abi')],check=True)
for pipeline in ['ir','direct']:
    binary=out/f'cursor-{pipeline}'
    subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'tests/ui/cursor-state.flex','-o',str(binary)],cwd=ROOT,check=True)
    result=subprocess.run([str(binary)],cwd=ROOT,capture_output=True,timeout=15)
    (out/f'{pipeline}.stderr.log').write_bytes(result.stderr)
    assert result.returncode==0,(pipeline,result.returncode,result.stderr)
    rows=json.loads(result.stdout);assert len(rows)==2000
    for elapsed,frame,deadline in rows:
        phase=elapsed%230
        expected=0 if phase<45 else 1 if phase<115 else 2
        end=[45,115,230][expected]
        assert (frame,deadline)==(expected,1_000_000_000+(elapsed+end-phase)*1_000_000),(pipeline,elapsed,frame,deadline)
    (out/f'{pipeline}.json').write_bytes(result.stdout)
print('PASS IR/direct 2000 cursor frame/deadline cases each, 49-day wrap, zero-delay/static frames, bounds, timer/callback/leave and focus cleanup')
