#!/usr/bin/env python3
"""Detect isolated RV32 relaxation defects using already generated peer cases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'cases', 'qemu-c6', 'work'):
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    compiler, cases, qemu, work = [x.resolve() for x in (a.compiler, a.cases, a.qemu_c6, a.work)]
    assert json.loads((cases / 'report.json').read_text())['pass_all']
    work.mkdir(parents=True, exist_ok=True)
    assert not (work / 'report.json').exists()
    (work / 'tmp').mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(work / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
    source = (ROOT / 'compiler/main.flex').read_text()
    backend = (ROOT / 'compiler/backends/riscv32.flex').read_text()
    source = re.sub(r'^import "([^"]+)";', lambda m: 'import ' + json.dumps(str((ROOT / 'compiler' / m[1]).resolve())) + ';', source, flags=re.M)
    backend_import = 'import ' + json.dumps(str(ROOT / 'compiler/backends/riscv32.flex')) + ';'
    defects = [
        ('compressed-sign', 'rv_c_jump', '((delta&2048)<<1)', '0', 'compressed-backward', None),
        ('direct-sign', 'rv_medium_jump', '(((delta>>20)&1)<<31)', '0', 'medium-backward', None),
        ('single-layout-pass', 'rv_function', 'store64(rv_jumps+pc/2,at|(form<<32));stable=0;', 'store64(rv_jumps+pc/2,at|(form<<32));stable=1;', 'cascading-growth', None),
        ('stale-call-relocations', 'rv_function', 'output_size=start;rv_fixup_count=fixups;', 'output_size=start;', 'call-relocations-after-growth', None),
        ('no-full-range', 'rv_jump_form', 'return 2;', 'return 1;', 'full-range-forward', 'direct jump out of range'),
        ('wrong-conditional-skip', 'rv_function_body', 'rv_patch_branch(skip,output_size);', 'rv_patch_branch(skip,output_size+6);', 'untaken-11', None),
    ]

    def run(args, label):
        r = subprocess.run(list(map(str, ['nice', '-n', '19', *args])), cwd=ROOT, env=env, capture_output=True, timeout=120)
        (work / (label + '.log')).write_bytes(r.stdout + r.stderr)
        return r

    linker, alias = work / 'linker', work / 'empty.ld'
    assert run([compiler, ROOT / 'scripts/esp32-link.flex', '-o', linker], 'linker').returncode == 0
    alias.write_text('/* no external symbols */\n')
    results = []
    for name, function, before, after, case, diagnostic in defects:
        tree = work / name
        tree.mkdir()
        start = backend.index('fn ' + function + '(')
        end = backend.find('\nfn ', start + 1)
        if end < 0:
            end = len(backend)
        body = backend[start:end]
        assert body.count(before) == 1, (name, body.count(before))
        mutated = backend[:start] + body.replace(before, after) + backend[end:]
        (tree / 'backend.flex').write_text(mutated)
        entry = source.replace(backend_import, 'import ' + json.dumps(str(tree / 'backend.flex')) + ';')
        assert entry != source
        (tree / 'main.flex').write_text(entry)
        exe = tree / 'compiler'
        r = run([compiler, tree / 'main.flex', '-o', exe], name + '-compiler')
        assert r.returncode == 0, r.stderr[-2000:]
        suffix = '-xip-elf' if case == 'full-range-forward' else '-elf'
        target = 'esp32c6' + suffix
        elf, linked, image, report = [tree / n for n in ('input.elf', 'linked.elf', 'image.bin', 'ROM.json')]
        args = [exe, '--ir-opt', 'none', '--language', 'ir', '--target', target]
        if suffix == '-xip-elf':
            args += ['--platform', ROOT / 'lib/platform/esp32c6-xip.flex']
        r = run([*args, cases / (case + '.fir'), '-o', elf], name + '-build')
        if diagnostic:
            assert r.returncode == 1 and diagnostic.encode() in r.stderr, (name, r.returncode, r.stderr[-1800:])
            detection = 'specific compiler rejection'
        else:
            assert r.returncode == 0, (name, r.stderr[-1800:])
            r = run([linker, '--ld', 'ld.lld', '--rom', alias, '--firmware', elf, '--output', linked, '--image', image], name + '-link')
            assert r.returncode == 0, (name, r.stderr[-1800:])
            r = run(['python3', ROOT / 'tests/esp32/riscv-rom-peer.py', '--qemu', qemu, '--image', image, '--elf', linked, '--report', report], name + '-ROM')
            assert r.returncode == 1 and b'AssertionError' in r.stderr, (name, r.returncode, r.stdout[-1000:], r.stderr[-1800:])
            assert b'FileNotFoundError' not in r.stderr
            detection = 'C6 ROM execution fails independent result/trap checks'
        results.append(dict(defect=name, case=case, detected=True, detection=detection,
                            compiler_sha256=hashlib.sha256(exe.read_bytes()).hexdigest()))
        print('DETECTED', name, flush=True)
    result = dict(pass_all=True, defects=results, physical_hardware=False, emulator_implementation_changes=False,
                  source_sha256=hashlib.sha256(backend.encode()).hexdigest(), cases_report_sha256=hashlib.sha256((cases / 'report.json').read_bytes()).hexdigest())
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS:', len(results), 'isolated compiler defects detected')


if __name__ == '__main__':
    main()
