#!/usr/bin/env python3
"""Build a diskless network diagnostic with matching official ISO modules."""
import argparse
from pathlib import Path
import stat
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--compiler", required=True, type=Path)
parser.add_argument("--module-root", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
archive = bytearray()
inode = 1

def entry(name, mode, data=b"", major=0, minor=0):
    global inode
    encoded = name.encode() + b"\0"
    fields = [inode, mode, 0, 0, 1, 0, len(data), 0, 0, major, minor, len(encoded), 0]
    inode += 1
    archive.extend(b"070701" + b"".join(f"{value:08x}".encode() for value in fields))
    archive.extend(encoded)
    archive.extend(b"\0" * (-len(archive) % 4))
    archive.extend(data)
    archive.extend(b"\0" * (-len(archive) % 4))

with tempfile.TemporaryDirectory(prefix="flexvirt-net-init-") as directory:
    binary = Path(directory) / "init"
    subprocess.run([str(args.compiler.resolve()), str(Path(__file__).with_name("linux-net-init.flex")), "-o", str(binary)], check=True)
    for name in ("dev", "sys"):
        entry(name, stat.S_IFDIR | 0o755)
    entry("dev/console", stat.S_IFCHR | 0o600, major=5, minor=1)
    entry("init", stat.S_IFREG | 0o755, binary.read_bytes())
    for name in ("failover", "net_failover", "virtio_net"):
        paths = list(args.module_root.rglob(name + ".ko.zst"))
        if len(paths) != 1:
            parser.error(f"Expected exactly one {name}.ko.zst under {args.module_root}")
        data = subprocess.run(["zstd", "-d", "-c", str(paths[0])], check=True, stdout=subprocess.PIPE).stdout
        entry(name + ".ko", stat.S_IFREG | 0o644, data)
entry("TRAILER!!!", 0)
args.output.write_bytes(archive)
