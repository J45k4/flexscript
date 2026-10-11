#!/usr/bin/env python3
"""Build a diskless Mesa probe using graphics libraries from the official ISO."""
import argparse
from collections import defaultdict
from pathlib import Path
import shlex
import stat
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--compiler", required=True, type=Path)
parser.add_argument("--runtime-root", required=True, type=Path)
parser.add_argument("--module-root", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--temp-root", type=Path)
args = parser.parse_args()
archive = bytearray()
next_inode = 1

def entry(name, mode, data=b"", major=0, minor=0, inode=None, links=1):
    global next_inode
    if inode is None:
        inode = next_inode
        next_inode += 1
    encoded = name.encode() + b"\0"
    fields = [inode, mode, 0, 0, links, 0, len(data), 0, 0, major, minor, len(encoded), 0]
    archive.extend(b"070701" + b"".join(f"{value:08x}".encode() for value in fields))
    archive.extend(encoded)
    archive.extend(b"\0" * (-len(archive) % 4))
    archive.extend(data)
    archive.extend(b"\0" * (-len(archive) % 4))

runtime = args.runtime_root.resolve()
for required in ("usr/lib/ld-linux-x86-64.so.2", "usr/lib/libgbm.so.1", "usr/lib/libEGL.so.1", "usr/lib/libGLESv2.so.2", "usr/share/glvnd/egl_vendor.d/50_mesa.json"):
    if not (runtime / required).exists():
        parser.error(f"Missing official runtime file: {required}")

with tempfile.TemporaryDirectory(prefix="flexvirt-mesa-init-", dir=args.temp_root) as directory:
    directory = Path(directory)
    init = directory / "init"
    probe = directory / "mesa-probe"
    source = Path(__file__).with_name("linux-mesa-probe.c")
    subprocess.run([str(args.compiler.resolve()), str(Path(__file__).with_name("linux-mesa-init.flex")), "-o", str(init)], check=True)
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "gbm", "egl", "glesv2", "libdrm"], text=True))
    subprocess.run(["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(probe), *flags], check=True)
    for name in ("dev", "sys", "proc", "tmp", "run", "usr", "usr/lib", "usr/share", "usr/share/glvnd"):
        entry(name, stat.S_IFDIR | (0o1777 if name == "tmp" else 0o755))
    entry("lib", stat.S_IFLNK | 0o777, b"usr/lib")
    entry("lib64", stat.S_IFLNK | 0o777, b"usr/lib")
    entry("dev/console", stat.S_IFCHR | 0o600, major=5, minor=1)
    entry("init", stat.S_IFREG | 0o755, init.read_bytes())
    entry("mesa-probe", stat.S_IFREG | 0o755, probe.read_bytes())
    # Mesa DRI entry points may hardlink to one large Gallium library. Preserve
    # those links so the initramfs contains the payload once, not per driver.
    files = sorted({p for base in (runtime / "usr/lib", runtime / "usr/share/glvnd") for p in base.rglob("*")})
    groups = defaultdict(list)
    directories = {"usr/lib", "usr/share/glvnd"}
    for p in files:
        mode = p.lstat().st_mode
        name = str(p.relative_to(runtime))
        if stat.S_ISDIR(mode):
            if name not in directories:
                entry(name, stat.S_IFDIR | 0o755)
                directories.add(name)
        elif stat.S_ISLNK(mode):
            entry(name, stat.S_IFLNK | 0o777, p.readlink().as_posix().encode())
        elif stat.S_ISREG(mode):
            info = p.stat()
            groups[(info.st_dev, info.st_ino)].append(p)
        else:
            parser.error(f"Unexpected runtime file type: {p}")
    for group in groups.values():
        inode = next_inode
        next_inode += 1
        for index, p in enumerate(group):
            entry(str(p.relative_to(runtime)), stat.S_IFREG | (p.stat().st_mode & 0o777), p.read_bytes() if index == len(group) - 1 else b"", inode=inode, links=len(group))
    for name in ("virtio_dma_buf", "virtio-gpu"):
        paths = list(args.module_root.rglob(name + ".ko.zst"))
        if len(paths) != 1:
            parser.error(f"Expected exactly one {name}.ko.zst under {args.module_root}")
        data = subprocess.check_output(["zstd", "-d", "-c", str(paths[0])])
        entry(name + ".ko", stat.S_IFREG | 0o644, data)
entry("TRAILER!!!", 0)
args.output.write_bytes(archive)
print(f"Mesa diagnostic archive: {len(archive)} bytes")
