#!/usr/bin/env python3
"""Check GNU window tests reject deliberately broken CPU implementations.

Uses an explicitly supplied compiler and already assembled GNU fixture; no
network, physical device access, source encoder or compiler bootstrap.
"""
from emulator_sources import source_path, clone_source
import argparse, hashlib, json, re, subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for flag in ('compiler', 'instructions', 'metadata', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()
raw, meta = a.instructions.resolve(), a.metadata.resolve()
modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-window.flex', 'xtensa-user.flex', 'xtensa-memory-pages.flex', 'emulator-memory.flex')
sources = {name: clone_source(root,name) for name in modules}
fixture = (root / 'tests/xtensa/windows.flex').read_text()
mutations = [
    ('window-view-does-not-rotate', 'xtensa.flex', '(load64(c+1088)&15)*4', '0'),
    ('window-start-not-masked', 'xtensa.flex', 'if index==73{value=value&65535;}', ''),
    ('entry-stack-immediate-is-words', 'xtensa.flex', '((op>>12)*8)', '((op>>12)*4)'),
    ('entry-does-not-activate-window', 'xtensa.flex', 'xt_wsr(c,73,xt_sr(c,73)|xt_window_bit(wb));', ''),
    ('callx-overwrites-overlapping-target', 'xtensa.flex', 'next=target;', 'next=xt_reg(c,b);'),
    ('retw-uses-callinc', 'xtensa-window.flex', 'let n=(address>>30)&3;', 'let n=(ps>>16)&3;'),
    ('retw-keeps-departed-window', 'xtensa-window.flex', 'xt_wsr(c,73,ws&~xt_window_bit(wb));', ''),
    ('retw-ignores-mismatched-frame', 'xtensa-window.flex', '(nearest && nearest!=n)', '0'),
    ('overflow-skips-highest-operand-group', 'xtensa-window.flex', 'while step<=group', 'while step<group'),
    ('wrong-overflow-vector-kind', 'xtensa-window.flex', 'let offset=(kind-1)*128+underflow*64;', 'let offset=underflow*64;'),
    ('refill-does-not-activate-caller', 'xtensa-window.flex', 'if underflow{ws=ws|xt_window_bit(wb);}', 'if underflow{}'),
    ('rfwo-leaves-excm-set', 'xtensa-window.flex', 'xt_wsr(c,230,ps&~16);', 'xt_wsr(c,230,ps);'),
    ('xsr-writes-new-window', 'xtensa.flex', 'store64(physical,value&0xffffffff);', 'xt_setreg(c,a,value);'),
    ('compact-fetch-reads-three-bytes', 'xtensa.flex', 'p=xt_pointer(c,pc,length,5);', 'p=xt_pointer(c,pc,3,5);'),
    ('compact-addi-zero-is-zero', 'xtensa.flex', 'if !a{value= -1;}', ''),
    ('compact-movi-symmetric-sign', 'xtensa.flex', 'if value>=96{value=value-128;}', 'if value>=64{value=value-128;}'),
    ('addx-does-not-scale', 'xtensa.flex', '(left<<((high>>4)-8))+right', 'left+right'),
    ('subx-scales-wrong-operand', 'xtensa.flex', '(left<<((high>>4)-12))-right', 'left-(right<<((high>>4)-12))'),
    ('loop-count-is-off-by-one', 'xtensa.flex', 'xt_wsr(c,2,count-1);', 'xt_wsr(c,2,count);'),
    ('loopgtz-uses-unsigned-predicate', 'xtensa.flex', 'xt_signed(count)<=0', 'count==0'),
    ('loop-boundary-ignores-excm', 'xtensa.flex', 'let loop_ok= !(xt_sr(c,230)&16);', 'let loop_ok=1;'),
    ('irq-loop-uses-interrupted-ps', 'xtensa.flex', 'let loop_ok= !(xt_sr(c,230)&16);', 'let loop_ok= !(ps&16);'),
    ('loop-count-never-decrements', 'xtensa.flex', 'xt_wsr(c,2,xt_sr(c,2)-1);', ''),
    ('signed-immediate-minus1-is-zero', 'xtensa.flex', 'if unsigned{return 32768;}return -1;', 'if unsigned{return 32768;}return 0;'),
    ('unsigned-immediate-uses-sign-range', 'xtensa.flex', 'if unsigned{return 32768;}', 'if unsigned{return 0x80000000;}'),
    ('signed-branch-compares-unsigned', 'xtensa.flex', 'if a==10{take=xt_signed(left)<right;}', 'if a==10{take=left<(right&0xffffffff);}'),
    ('mask-all-uses-any', 'xtensa.flex', 'if d==4{take=(left&right)==right;}', 'if d==4{take=(left&right)!=0;}'),
    ('register-bit-index-unmasked', 'xtensa.flex', '1<<(right&31)', '1<<right'),
    ('high-immediate-bit-loses-bit4', 'xtensa.flex', 'let bit=a+((d&1)*16);', 'let bit=a;'),
    ('immediate-bit-index-causes-window-fault', 'xtensa-window.flex', 'if d==6 || d==7 || d==14 || d==15{return b/4;}', ''),
    ('immediate-branch-skips-window-source', 'xtensa-window.flex', 'if low==6 && (a==1 || a==5 || a==9 || a==13 || a==2 || a==6 || a==10 || a==14 || a==11 || a==15){return b/4;}', ''),
    ('zero-branch-missing-negative-offset', 'xtensa.flex', 'if delta&2048{delta=delta-4096;}', ''),
    ('mmio-read-skips-loop-retirement', 'xtensa.flex', 'xt_loop_next(c,load64(c+208),!(xt_sr(c,230)&16))', 'load64(c+208)'),
]
controls = []
for label, module, old, new in mutations:
    expected = 2 if label == 'window-view-does-not-rotate' else 1
    assert sources[module].count(old) == expected, (label, 'mutation anchor count')
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        (directory / name).write_text(text.replace(old, new) if name == module else text)
    source = directory / 'windows.flex'
    source.write_text(fixture.replace('"../../emulator/xtensa/cpu.flex"', json.dumps(str(directory / 'xtensa.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'windows'
    compiled = subprocess.run([str(compiler), str(source), '-o', str(binary)], cwd=root, capture_output=True, timeout=25)
    assert compiled.returncode == 0, (label, 'defect must compile', compiled.stderr)
    result = subprocess.run([str(binary), str(raw), str(meta)], cwd=root, capture_output=True, timeout=25)
    assert result.returncode == 1 and re.search(rb'Window case \d+ check \d+:', result.stderr), (label, 'defect not rejected by assertion', result.returncode, result.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': result.stderr.decode().strip()})
    print('Window defect controls:', len(controls), flush=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {'pass': True, 'physical_hardware': False, 'controls': controls, 'compiler_sha256': sha(compiler), 'gnu_instructions_sha256': sha(raw), 'metadata_sha256': sha(meta), 'sources': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()}}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:', len(controls), 'independent CPU defect controls detected')
