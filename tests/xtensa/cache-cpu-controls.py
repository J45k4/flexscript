#!/usr/bin/env python3
"""Check paged-memory or ROM-integer tests reject deliberately broken CPUs.

Uses an explicitly supplied compiler and already assembled GNU fixture; no
network, physical device access, source encoder or compiler bootstrap.
"""
from emulator_sources import source_path, clone_source
import argparse, hashlib, json, re, subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
for flag in ('compiler', 'instructions', 'work', 'report'):
    p.add_argument('--' + flag, type=Path, required=True)
p.add_argument("--suite",choices=("pages","integers"),required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
compiler = a.compiler.resolve()
raw = a.instructions.resolve()
modules = ('xtensa.flex','xtensa-cycle.flex','xtensa-timer.flex', 'xtensa-window.flex', 'xtensa-user.flex', 'xtensa-memory-pages.flex', 'emulator-memory.flex')
sources = {name: clone_source(root,name) for name in modules}
fixture = (root / ('tests/xtensa/pages.flex' if a.suite=='pages' else 'tests/xtensa/rom-integers.flex')).read_text()
mutations = [('page-gate-ignored', 'xtensa-memory-pages.flex', 'if gate && !load64(gate)', 'if 0'), ('zero-page-uses-first-page', 'xtensa-memory-pages.flex', 'if !page{xt_fault(c,-14,address);return 0;}', 'if !page{page=load64(table);}'), ('page-offset-shifted', 'xtensa-memory-pages.flex', 'let first=page+(offset&mask);', 'let first=page+((offset+1)&mask);'), ('assumes-contiguous-backing', 'xtensa-memory-pages.flex', 'if (offset&mask)+n<=mask+1{return first;}', 'if 1{return first;}'), ('cross-page-no-tail-validation', 'xtensa-memory-pages.flex', 'if !tail{xt_fault(c,-14,address+mask+1-(offset&mask));return 0;}', 'if !tail{return first;}'), ('cross-page-reuses-first-page', 'xtensa-memory-pages.flex', 'load64(table+(at>>shift)*8)+(at&mask)', 'page+(at&mask)'), ('wrong-page-index', 'xtensa-memory-pages.flex', '(offset>>shift)*8', '((offset>>shift)&1)*8'), ('paged-map-can-be-writable', 'xtensa-memory-pages.flex', '(flags!=1 && flags!=5)', '(flags!=1 && flags!=3 && flags!=5)'), ('missing-page-alignment', 'xtensa-memory-pages.flex', 'if (address&mask) || (size&mask){return -22;}', ''), ('ELF-bypasses-page-device', 'xtensa.flex', ' || (load64(region+24)&8)', ''), ('paged-region-not-dispatched', 'xtensa.flex', 'return xt_paged_pointer(c,p,address,n,permission);', 'return load64(p+16)+address-base;'), ('gate-fault-wrong-code', 'xtensa-memory-pages.flex', 'xt_fault(c,-5,address)', 'xt_fault(c,-14,address)'), ('unmap-removes-normal-memory', 'xtensa-memory-pages.flex', 'if !(load64(p+24)&8){return -22;}', ''), ('unmap-compacts-wrong-region', 'xtensa-memory-pages.flex', 'em_copy(load64(c+136)+j*32,load64(c+136)+(j+1)*32,32);', 'em_copy(load64(c+136)+j*32,load64(c+136),32);')] if a.suite=="pages" else [('SEXT-off-by-one', 'xtensa.flex', 'let shift=56-a;', 'let shift=55-a;'), ('SEXT-zero-extended', 'xtensa.flex', '(left<<shift)>>shift', 'left&((1<<(a+8))-1)'), ('MOVEQZ-inverted', 'xtensa.flex', 'let take=right==0;', 'let take=right!=0;'), ('MOVNEZ-inverted', 'xtensa.flex', 'if high==0x93{take=right!=0;}', 'if high==0x93{take=right==0;}'), ('MOVLTZ-unsigned', 'xtensa.flex', 'if high==0xa3{take=xt_signed(right)<0;}', 'if high==0xa3{take=right<0;}'), ('MOVGEZ-unsigned', 'xtensa.flex', 'if high==0xb3{take=xt_signed(right)>=0;}', 'if high==0xb3{take=right>=0;}'), ('conditional-move-always-writes', 'xtensa.flex', 'if take{xt_setreg(c,d,left);}', 'xt_setreg(c,d,left);'), ('signed-division-is-unsigned', 'xtensa.flex', 'if high&16{lhs=xt_signed(left);rhs=xt_signed(right);}', ''), ('remainder-is-quotient', 'xtensa.flex', 'if high&32{value=lhs%rhs;}', ''), ('quotient-is-remainder', 'xtensa.flex', 'let value=lhs/rhs;', 'let value=lhs%rhs;'), ('divzero-wrong-cause', 'xtensa.flex', 'xt_exception(c,6,pc)', 'xt_exception(c,5,pc)'), ('SEXT-missing-window', 'xtensa-window.flex', 'if (op&0xff000f)==0x230000{return xt_window_max(b,d,0);}', ''), ('SEXT-destination-window-ignored', 'xtensa-window.flex', 'if (op&0xff000f)==0x230000{return xt_window_max(b,d,0);}', 'if (op&0xff000f)==0x230000{return b/4;}'), ('conditional-move-registers-not-windowed', 'xtensa-window.flex', 'high==0x83 || high==0x93 || high==0xa3 || high==0xb3 || ', '')]
controls = []
for label, module, old, new in mutations:
    assert sources[module].count(old)>=1,(label,'mutation anchor missing')
    directory = work / label
    directory.mkdir(exist_ok=True)
    for name, text in sources.items():
        if name == module:
            if a.suite == 'pages' and name == 'xtensa-memory-pages.flex':
                # Mutate the original strict route,not a similarly worded
                # optional device route with different local variables.
                head, marker, tail = text.partition('// Optional read observation.')
                assert old in head, (label, 'strict mutation anchor missing')
                text = head.replace(old, new) + marker + tail
            else:
                text = text.replace(old, new)
        (directory / name).write_text(text)
    source = directory / 'user.flex'
    source.write_text(fixture.replace('"../../emulator/xtensa/cpu.flex"', json.dumps(str(directory / 'xtensa.flex'))).replace('"../../scripts/lib/host.flex"', json.dumps(str(root / 'scripts/lib/host.flex'))))
    binary = directory / 'user'
    compiled = subprocess.run([str(compiler), str(source), '-o', str(binary)], cwd=root, capture_output=True, timeout=25)
    assert compiled.returncode == 0, (label, 'defect must compile', compiled.stderr)
    result = subprocess.run([str(binary), str(raw)], cwd=root, capture_output=True, timeout=25)
    assert result.returncode == 1 and re.search(rb'(?:Page|ROM integer) case \d+:', result.stderr), (label, 'defect not rejected by assertion', result.returncode, result.stderr)
    controls.append({'control': label, 'detected': True, 'diagnostic': result.stderr.decode().strip()})
    print('Page/integer defect controls:', len(controls), flush=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {'pass': True, 'physical_hardware': False, 'controls': controls, 'compiler_sha256': sha(compiler), 'gnu_instructions_sha256': sha(raw), 'sources': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()}}
a.report.write_text(json.dumps(report, indent=2) + '\n')
print('PASS:', len(controls), 'independent CPU defect controls detected')
