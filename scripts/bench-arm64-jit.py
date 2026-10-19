#!/usr/bin/env python3
"""Measure warmed ARM64 JIT calls against C and an independent IR interpreter.

QEMU numbers compare generated code under emulation, not physical ARM throughput.
Compilation, publication, cache lookup and input resets are outside call timing.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import struct
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--generator', type=Path, default=Path('vm/jit-arm64.flex'))
    parser.add_argument('--out', type=Path, default=Path('build/arm64-jit-bench'))
    parser.add_argument('--baseline-report', type=Path, help='Compare with a saved run of the original generator')
    parser.add_argument('--cpu', type=int, help='Pin compiler and QEMU to an allowed CPU for paired comparisons')
    parser.add_argument('--deadline', action='store_true', help='Enable the VM deadline and include its clock syscalls')
    parser.add_argument('--qemu', default=shutil.which('qemu-aarch64') or shutil.which('qemu-aarch64-static'))
    args = parser.parse_args()
    if args.cpu is not None:
        assert args.cpu in os.sched_getaffinity(0), 'CPU is outside the current process affinity'
        os.sched_setaffinity(0, {args.cpu})
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)

    def run(cmd):
        result = subprocess.run(list(map(str, cmd)), capture_output=True, timeout=120)
        assert result.returncode == 0, (cmd, result.returncode, result.stderr.decode(errors='replace'))
        return result.stdout

    source = out / 'jit.flex'
    source.write_text(f'import "{args.generator.resolve()}";fn main(){{return 0;}}')
    program = out / 'jit.o'
    run([args.compiler.resolve(), '--target', 'android-arm64', source, '-o', program])
    objects = []
    for source in ('platform/android/jit-host.c', 'tests/arm64/jit-benchmark.c'):
        obj = out / (Path(source).stem + '.o')
        run(['clang', '--target=aarch64-linux-gnu', '-ffreestanding', '-fno-stack-protector',
             '-fno-builtin', '-Wall', '-Wextra', '-Werror', '-O2',
             f'-DBENCH_DEADLINE={int(args.deadline)}', '-c', source, '-o', obj])
        objects.append(obj)
    start = out / 'start.s'
    start.write_text('.global _start\n.text\n_start:\nbl runner_main\nmov x8,#93\nsvc #0\n.section .note.GNU-stack,"",@progbits\n')
    startup = out / 'start.o'
    run(['clang', '--target=aarch64-linux-gnu', '-c', start, '-o', startup])
    binary = out / 'jit-benchmark'
    run(['ld.lld', '-static', '-e', '_start', startup, *objects, program, '-o', binary])
    data = run([args.qemu, binary])
    (out / 'samples.bin').write_bytes(data)
    assert len(data) >= 480, len(data)
    rows = []
    offset = 480
    for index, name in enumerate(('integer hash', 'checked array update')):
        record = struct.unpack_from('<30q', data, index * 240)
        code = data[offset:offset + record[1]]
        assert len(code) == record[1]
        offset += record[1]
        raw = out / f'kernel-{index}.bin'
        raw.write_bytes(code)
        assembly = out / f'kernel-{index}.s'
        assembly.write_text(f'.text\n.global jit_kernel_{index}\njit_kernel_{index}:\n' + ''.join(f'.inst 0x{word:08x}\n' for (word,) in struct.iter_unpack('<I', code)))
        obj = out / f'kernel-{index}.o'
        run(['clang', '--target=aarch64-linux-gnu', '-c', assembly, '-o', obj])
        if shutil.which('llvm-objdump'):
            (out / f'kernel-{index}.asm').write_bytes(run(['llvm-objdump', '-D', '--section=.text', obj]))
        medians = [statistics.median(record[3 + engine::3]) / 32 for engine in range(3)]
        rows.append({'kernel': name, 'iterations': 20000, 'code_bytes': record[1], 'compile_ns': record[2],
                     'native_c_ns': medians[0], 'interpreter_ns': medians[1], 'jit_ns': medians[2],
                     'speedup_vs_interpreter': medians[1] / medians[2],
                     'jit_over_native_c': medians[2] / medians[0],
                     'samples_ns_per_32_calls': [record[3 + engine::3] for engine in range(3)]})
    report = {'engine': 'QEMU AArch64 Linux user emulation; not physical-device performance',
              'generator': str(args.generator.resolve()), 'kernels': rows,
              'generator_sha256': hashlib.sha256(args.generator.read_bytes()).hexdigest(),
              'deadline_enabled': args.deadline,
              'cpu_affinity': sorted(os.sched_getaffinity(0)),
              'benchmark_sha256': hashlib.sha256(Path('tests/arm64/jit-benchmark.c').read_bytes()).hexdigest()}
    assert offset == len(data), (offset, len(data))
    if args.baseline_report:
        baseline = json.loads(args.baseline_report.read_text())
        assert baseline['engine'] == report['engine']
        assert baseline.get('deadline_enabled', False) == args.deadline, 'Deadline modes differ'
        if 'benchmark_sha256' in baseline:
            assert baseline['benchmark_sha256'] == report['benchmark_sha256'], 'Benchmark harness changed; refresh baseline'
        assert [r['kernel'] for r in baseline['kernels']] == [r['kernel'] for r in rows]
        for old, new in zip(baseline['kernels'], rows):
            assert old['iterations'] == new['iterations']
            new['speedup_vs_original_jit'] = old['jit_ns'] / new['jit_ns']
            new['original_jit_ns'] = old['jit_ns']
            new['original_code_bytes'] = old['code_bytes']
            new['speedup_normalized_to_c'] = old['jit_over_native_c'] / new['jit_over_native_c']
        report['baseline_report'] = str(args.baseline_report.resolve())
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
