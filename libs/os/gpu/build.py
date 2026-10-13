#!/usr/bin/env python3
"""Compose Flexscript device functions into one cooperative resident program."""
import argparse
import fcntl
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def build_locked(compiler, directory):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / "tmp"
    temporary.mkdir(exist_ok=True)
    environment = dict(os.environ, TMPDIR=str(temporary))
    sections = []
    calls = []
    header = None
    for name, source in [("gemv", "gemv-wide-rdna"), ("element", "element"),
                         ("rope", "rope"), ("attention", "attention")]:
        text = (ROOT / f"libs/ml/llm/kernels/{source}.flex").read_text()
        common = ROOT / "libs/ml/llm/kernels/common-f16.flex"
        text = text.replace('import "common.flex";', f'import "{common}";')
        flex = directory / f"{name}.flex"
        hip = directory / f"{name}.hip"
        flex.write_text(text)
        subprocess.run([str(Path(compiler).resolve()), "--target", "hip", str(flex),
                        "-o", str(hip)], cwd=ROOT, env=environment, check=True)
        code = hip.read_text()
        start = code.index("__device__ __forceinline__ W flex_fn")
        end = code.index('extern "C" __global__ void flex_kernel')
        if header is None:
            header = code[:start]
        entry = re.search(r"(flex_fn\d+)\(index,input,output,count,u\)", code[end:]).group(1)
        functions = re.sub(r"\bflex_fn(\d+)\b", rf"os_{name}_fn\1", code[start:end])
        sections.append(functions)
        calls.append(f"FD void os_{name}(W index,W count,FWords u){{"
                     f"os_{name}_{entry[5:]}(index,0,0,count,u);}}\n")
    generated = directory / "resident.hip"
    generated.write_text(header + "\n".join(sections + calls) +
                         (ROOT / "libs/os/gpu/resident.hip").read_text())
    bundle = directory / "resident.bundle"
    subprocess.run(["/opt/rocm/bin/hipcc", "--genco", "--offload-arch=gfx1201",
                    "-O3", "-ffp-contract=off", str(generated), "-o", str(bundle)],
                   cwd=ROOT, env=environment, check=True)
    output = directory / "resident.hsaco"
    candidate = directory / "resident.hsaco.tmp"
    subprocess.run(["/opt/rocm/llvm/bin/clang-offload-bundler", "--unbundle", "--type=o",
                    "--targets=hipv4-amdgcn-amd-amdhsa--gfx1201", f"--input={bundle}",
                    f"--output={candidate}"], cwd=ROOT, env=environment, check=True)
    if candidate.read_bytes()[:4] != b"\x7fELF":
        raise RuntimeError("resident worker is not an ELF code object")
    candidate.replace(output)
    print(output)


def build(compiler, directory):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    # Multiple chat processes can start at once; keep temporary compiler output
    # private to one builder and publish the finished ELF with atomic rename.
    with (directory / "build.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        build_locked(compiler, directory)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", default="build/flex")
    parser.add_argument("--output", default="build/gpu-os")
    args = parser.parse_args()
    build(args.compiler, args.output)
