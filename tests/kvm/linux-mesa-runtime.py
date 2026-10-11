#!/usr/bin/env python3
"""Extract a standalone Mesa runtime from a previously verified Omarchy ISO root."""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--unsquashfs", required=True, type=Path)
parser.add_argument("--squashfs", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path, help="New workspace directory; existing paths are refused")
parser.add_argument("--temp-root", type=Path)
args = parser.parse_args()
tool, squashfs = str(args.unsquashfs.resolve()), str(args.squashfs.resolve())
args.output.mkdir(mode=0o700)
root = args.output.resolve()
manifest = subprocess.check_output([tool, "-ll", squashfs], text=True)
packages = []
for name in ("mesa", "libglvnd", "llvm-libs", "spirv-tools", "libxxf86vm", "libelf", "lm_sensors", "wayland", "libxshmfence"):
    matches = re.findall(r"squashfs-root/(var/cache/omarchy/mirror/offline/" + re.escape(name) + r"-[0-9][^/\s]*-x86_64\.pkg\.tar\.zst)$", manifest, re.MULTILINE)
    if len(matches) != 1:
        parser.error(f"Expected exactly one official offline {name} package, found {len(matches)}")
    packages.extend(matches)

with tempfile.TemporaryDirectory(prefix="flexvirt-mesa-packages-", dir=args.temp_root) as directory:
    subprocess.run([tool, "-no-progress", "-d", str(Path(directory) / "packages"), squashfs, *packages], check=True, stdout=subprocess.DEVNULL)
    for relative in packages:
        subprocess.run(["bsdtar", "--no-same-owner", "--no-same-permissions", "-xf", str(Path(directory) / "packages" / relative), "-C", str(root)], check=True)

for iteration in range(12):
    needed = {"ld-linux-x86-64.so.2", "libc.so.6"}
    seen = set()
    for path in (root / "usr/lib").rglob("*"):
        if not path.is_file() or ".so" not in path.name:
            continue
        info = path.stat()
        key = (info.st_dev, info.st_ino)
        if key in seen:
            continue
        seen.add(key)
        dynamic = subprocess.run(["readelf", "-d", str(path)], capture_output=True, text=True)
        needed.update(re.findall(r"\(NEEDED\).*\[(.*?)\]", dynamic.stdout))
    missing = sorted(name for name in needed if not (root / "usr/lib" / name).exists())
    if not missing:
        break
    patterns = ["usr/lib/" + name.split(".so")[0] + ".so*" if ".so" in name else "usr/lib/" + name for name in missing]
    subprocess.run([tool, "-f", "-no-progress", "-d", str(root), squashfs, *patterns], check=True, stdout=subprocess.DEVNULL)
    root.chmod(0o700)
    unresolved = [name for name in missing if not (root / "usr/lib" / name).exists()]
    if unresolved:
        parser.error("Required libraries absent from prepared packages and ISO live root: " + ", ".join(unresolved))
else:
    parser.error("Shared-library dependency closure did not converge")
print("PASS: official offline Mesa runtime and complete ELF dependency closure")
