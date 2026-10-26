#!/usr/bin/env python3
"""Check the System V six-word callback used by the desktop native broker."""
import argparse
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='callback-',dir=ROOT/'build') as directory:
 d=Path(directory);source=ROOT/'tests/tooling/native-callback.flex'
 subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/tooling/native-callback.c'),'-o',str(d/'fixture.so')],check=True)
 subprocess.run([str(a.compiler.resolve()),'--native-pipeline','direct',str(source),'-o',str(d/'callback')],check=True)
 subprocess.run([str(d/'callback'),str(d/'fixture.so')],check=True)
 r=subprocess.run([str(a.compiler.resolve()),'--target','linux-arm64',str(source),'-o',str(d/'rejected.fir')],capture_output=True)
 assert r.returncode and b'native_callback requires native x86-64 code' in r.stderr,(r.returncode,r.stderr)
 assert not (d/'rejected.fir').exists()
print('PASS repeated callbacks preserve six argument values, signed results and caller locals; portable IR rejects callbacks')
