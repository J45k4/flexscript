#!/usr/bin/env python3
"""Break isolated compiler/runtime copies; execute the emitted Xtensa firmware.

Uses existing Espressif QEMU unchanged. Production sources are never patched.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def replace_once(path, before, after):
    text = path.read_text()
    if text.count(before) != 1:
        raise RuntimeError(f'{path}: mutation anchor count {text.count(before)}')
    path.write_text(text.replace(before, after))


def closure(entry, destination):
    seen = set()
    def visit(path):
        path = path.resolve()
        relative = path.relative_to(ROOT)
        if relative in seen:
            return
        seen.add(relative)
        data = path.read_bytes()
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        for name in re.findall(rb'^import\s+"([^"]+)"', data, re.M):
            visit(path.parent / name.decode())
    visit(entry)
    return {str(p): digest(destination / p) for p in sorted(seen)}


def run(args, log, env):
    with log.open('w') as out:
        result = subprocess.run([str(a) for a in args], cwd=ROOT, env=env,
                                stdout=out, stderr=subprocess.STDOUT, timeout=45)
    return result.returncode, log.read_text()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['compiler', 'native-compiler', 'driver', 'qemu', 'prefix',
                 'c-object', 'asm-object', 'work']:
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    work = Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    if (work / 'report.json').exists():
        raise RuntimeError('choose a fresh work directory to retain earlier evidence')
    env = os.environ.copy()
    (work / 'tmp').mkdir(exist_ok=True)
    env['TMPDIR'] = str(work / 'tmp')
    compiler_source = work / 'compiler-source'
    compiler_hashes = closure(ROOT / 'compiler/main.flex', compiler_source)
    firmware_source = work / 'firmware-source'
    firmware_hashes = closure(ROOT / 'tests/esp32/sdk-preempt.flex', firmware_source)
    firmware_hashes.update(closure(ROOT / 'tests/esp32/sdk-preempt-ram.flex', firmware_source))
    definitions = [
        ('missing-irq-tail', 'compiler',
         'if esp_irq_tail_index>=0 {\n        esp_ins(0x006f20);',
         'if 0 {\n        esp_ins(0x006f20);', 'sdk-preempt-ram.flex',
         'guest completion/trap status', None),
        ('missing-thread-restore', 'compiler',
         'esp_load(2,1,100);esp_user_write(2,231);', '', 'sdk-preempt.flex',
         'main returned zero', 'PREEMPT FAIL 000000000000008c'),
        ('missing-fpu-restore', 'compiler',
         'i=0;while i<16 {esp_load(2,1,104+i*4);esp_wfr(i,2);i=i+1;}',
         '', 'sdk-preempt.flex', 'main returned zero', 'PREEMPT FAIL 0000000000000078'),
        ('missing-semaphore-wake', 'sync',
         'store64(s+8,n+1);esp_sdk_reschedule_request();',
         'store64(s+8,n+1);', 'sdk-preempt.flex',
         'main returned zero', 'PREEMPT FAIL 0000000000000011'),
        ('past-autoreload-alarm', 'preempt',
         'esp_timer_ack(3,0);esp_timer_alarm(3,esp_timer_read(3)+esp_sdk_preempt_quantum,0);',
         'esp_timer_ack(3,1);', 'sdk-preempt.flex',
         'main returned zero', 'PREEMPT FAIL 0000000000000019'),
    ]
    records = []
    for name, kind, before, after, source, diagnostic, uart in definitions:
        case = work / name
        case.mkdir()
        compiler = Path(a.compiler).resolve()
        if kind == 'compiler':
            tree = case / 'source'
            shutil.copytree(compiler_source, tree)
            replace_once(tree / 'compiler/backends/esp32.flex', before, after)
            compiler = case / 'compiler'
            code, output = run([a.native_compiler, tree / 'compiler/main.flex', '-o', compiler],
                               case / 'build.log', env)
            if code:
                raise RuntimeError(f'{name}: compiler build failed: {output[-2000:]}')
            fixture = firmware_source / 'tests/esp32' / source
        else:
            tree = case / 'source'
            shutil.copytree(firmware_source, tree)
            target = tree / 'lib/platform' / ('esp32-sdk-sync-core.flex' if kind == 'sync' else 'esp32-sdk-preempt-core.flex')
            replace_once(target, before, after)
            if kind == 'preempt':
                replace_once(target, 'esp_timer_alarm(3,quantum_us,0);',
                             'esp_timer_alarm(3,quantum_us,1);')
            fixture = tree / 'tests/esp32' / source
        args = [a.driver, '--compiler', compiler, '--source', fixture,
                '--work', case / 'firmware', '--qemu', a.qemu, '--prefix', a.prefix]
        if source != 'sdk-preempt-ram.flex':
            args += ['--xip', 'yes', '--extra', a.c_object, '--assembly', a.asm_object]
        code, output = run(args, case / 'execution.log', env)
        # The UART printer uses a fixed width lower-case hexadecimal word.
        rejected = code == 1 and diagnostic in output and (uart is None or uart in output)
        qmp = case / 'firmware/qmp-failure.log'
        shutdown = qmp.exists() and 'SHUTDOWN' in qmp.read_text()
        record = dict(name=name, rejected=rejected, exit_code=code, shutdown=shutdown,
                      compiler_sha256=digest(compiler), log=str(case / 'execution.log'),
                      log_sha256=digest(case / 'execution.log'), expected_uart=uart)
        records.append(record)
        print(json.dumps(record), flush=True)
        report = dict(pass_all=all(r['rejected'] and r['shutdown'] for r in records),
                      controls=records, physical_hardware=False,
                      compiler_source_sha256=compiler_hashes,
                      firmware_source_sha256=firmware_hashes,
                      inputs={str(Path(v).resolve()): digest(Path(v)) for v in
                              [a.compiler, a.native_compiler, a.driver, a.qemu,
                               a.c_object, a.asm_object]})
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if not rejected or not shutdown:
            raise RuntimeError(f'{name}: missing intended rejection or QMP shutdown; see {case}')
    print('Preemption: all five independent defect controls rejected and QEMU stopped')


if __name__ == '__main__':
    main()
