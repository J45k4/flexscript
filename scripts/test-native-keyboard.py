#!/usr/bin/env python3
"""Independent XKB keymap/mask/compose checks, not OS input delivery proof."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler',type=Path,required=True)
a=p.parse_args();out=ROOT/'build/migration/keyboard-tests';out.mkdir(parents=True,exist_ok=True)
flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','xkbcommon'],text=True))
oracle=out/'oracle';subprocess.run(['cc','-O2',str(ROOT/'tests/tooling/keyboard-oracle.c'),*flags,'-o',str(oracle)],check=True)
keymap=out/'fi.xkb';expected=json.loads(subprocess.check_output([str(oracle),str(keymap)],text=True))
assert expected['text']==['a','ö','ä','å','A','@','','á'],expected
for pipeline in ['ir','direct']:
    binary=out/f'keyboard-{pipeline}'
    subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(ROOT/'tests/ui/native-keyboard.flex'),'-o',str(binary)],check=True)
    actual=json.loads(subprocess.check_output([str(binary),str(keymap),str(expected['shift_mask']),str(expected['altgr_mask'])],text=True))
    assert actual==expected['text'],(pipeline,actual,expected)
print('PASS IR/direct Finnish XKB keymaps, serialized modifiers, AltGr, dead-key compose, physical GUI keys and repeat eligibility')
