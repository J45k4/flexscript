#!/usr/bin/env python3
"""Compile the reusable Flexscript leaf JIT and execute its tests with QEMU."""
import argparse
import importlib.util
import json
from pathlib import Path
import resource
import shutil
import struct
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--qemu", default=shutil.which("qemu-aarch64") or shutil.which("qemu-aarch64-static"))
    parser.add_argument("--out", type=Path, default=Path("build/arm64-jit"))
    args = parser.parse_args()
    assert args.qemu, "QEMU user emulation is required"
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    def run(command, **kwargs):
        result = subprocess.run([str(value) for value in command], capture_output=True, timeout=60, **kwargs)
        assert result.returncode == 0, (command, result.returncode, result.stderr[:2000])
        return result

    specification = importlib.util.spec_from_file_location("jit_cases", "tests/arm64/jit_cases.py")
    fixtures = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(fixtures)
    cases, data = fixtures.write_cases(out)
    source = out / "jit.flex"
    source.write_text('import "' + str(Path("vm/jit-arm64.flex").resolve()) + '";fn main(){return 0;}')
    program = out / "jit.o"
    run([args.compiler.resolve(), "--target", "android-arm64", source, "-o", program])
    objects = []
    for source in ("platform/android/jit-host.c", "platform/android/jit-runtime.c", "tests/arm64/jit-runner.c"):
        obj = out / (Path(source).stem + ".o")
        run(["clang", "--target=aarch64-linux-gnu", "-ffreestanding", "-fno-stack-protector", "-fno-builtin",
             "-Wall", "-Wextra", "-Werror", "-O2", "-c", source, "-o", obj])
        objects.append(obj)
    start = out / "start.s"
    start.write_text('.global _start\n.text\n_start:\nbl runner_main\nmov x8,#93\nsvc #0\n.section .note.GNU-stack,"",@progbits\n')
    startup = out / "start.o"
    run(["clang", "--target=aarch64-linux-gnu", "-c", start, "-o", startup])
    binary = out / "jit-runner"
    run(["ld.lld", "-static", "-e", "_start", startup, *objects, program, "-o", binary])
    result = subprocess.run([args.qemu, str(binary)], input=data, capture_output=True, timeout=60)
    assert len(result.stdout) == 40 + len(cases) * 80, (result.returncode, result.stderr[:1000])
    (out / "results.bin").write_bytes(result.stdout)
    summary = struct.unpack_from("<5q", result.stdout)
    failures = []
    for index, case in enumerate(cases):
        record = struct.unpack_from("<10q", result.stdout, 40 + index * 80)
        compiled = record[0] > 0 if case["compile"] == 1 else record[0] == case["compile"]
        if not compiled or (record[1], record[2], record[3], record[9]) != case["expected"] or record[5] != case["backedges"]:
            failures.append({"name": case["name"], "actual": record, "expected": case["expected"], "expected_backedges": case["backedges"]})
    report = {"total": len(cases), "passed": summary[1], "compilations": summary[2],
              "native_calls": summary[3], "cache_hits": summary[4], "failures": failures,
              "engine": "runtime-generated AArch64 instructions executed in QEMU Linux user emulation",
              "generator": "vm/jit-arm64.flex", "oracle": "independent Python word-IR interpreter"}
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    assert not failures and result.returncode == 0 and summary[0] == summary[1] and summary[4] > 0, report
    buffer_obj = out / "jit-buffer-runner.o"
    run(["clang", "--target=aarch64-linux-gnu", "-ffreestanding", "-fno-stack-protector", "-fno-builtin",
         "-Wall", "-Wextra", "-Werror", "-O2", "-c", "tests/arm64/jit-buffer-runner.c", "-o", buffer_obj])
    buffer_binary = out / "jit-buffer-runner"
    abi_obj = out / "jit-abi.o"
    run(["clang", "--target=aarch64-linux-gnu", "-c", "tests/arm64/jit-abi.s", "-o", abi_obj])
    run(["ld.lld", "-static", "-e", "_start", startup, buffer_obj, abi_obj, objects[0], program, "-o", buffer_binary])
    run([args.qemu, buffer_binary])
    report["buffer_capacity_checks"] = "every byte capacity; scratch canaries; guard-page reads/writes; retry"
    report["backedge_counts"] = "every result compared with the independent interpreter"
    report["abi_checks"] = "x19-x29 preserved on fast/checked success, division and fuel exits"
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
