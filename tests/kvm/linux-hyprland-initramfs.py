#!/usr/bin/env python3
"""Build a diskless official Hyprland compositor compatibility diagnostic."""
import argparse
from collections import defaultdict
from pathlib import Path
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
for required in ("usr/bin/Hyprland", "usr/bin/hyprctl", "usr/bin/seatd", "usr/bin/seatd-launch", "usr/bin/bash", "usr/lib/libEGL.so.1", "etc/fonts/fonts.conf", "usr/share/icons/Adwaita/cursors/left_ptr", "usr/share/icons/default/index.theme"):
    if not (runtime / required).exists():
        parser.error(f"Missing official runtime file: {required}")

with tempfile.TemporaryDirectory(prefix="flexvirt-hyprland-init-", dir=args.temp_root) as directory:
    directory = Path(directory)
    init = directory / "init"
    subprocess.run([str(args.compiler.resolve()), str(Path(__file__).with_name("linux-hyprland-init.flex")), "-o", str(init)], check=True)
    for name in ("dev", "sys", "proc", "tmp", "run", "run/user", "run/user/0", "root", "root/.config", "etc", "usr", "usr/bin", "usr/lib", "usr/share"):
        entry(name, stat.S_IFDIR | (0o1777 if name == "tmp" else 0o700 if name in ("run/user/0", "root", "root/.config") else 0o755))
    entry("lib", stat.S_IFLNK | 0o777, b"usr/lib")
    entry("lib64", stat.S_IFLNK | 0o777, b"usr/lib")
    entry("dev/console", stat.S_IFCHR | 0o600, major=5, minor=1)
    entry("init", stat.S_IFREG | 0o755, init.read_bytes())
    entry("bin", stat.S_IFLNK | 0o777, b"usr/bin")
    entry("sbin", stat.S_IFLNK | 0o777, b"usr/bin")
    entry("etc/passwd", stat.S_IFREG | 0o644, b"root:x:0:0:root:/root:/bin/bash\n")
    entry("etc/group", stat.S_IFREG | 0o644, b"root:x:0:\nvideo:x:44:root\ninput:x:45:root\n")
    config = b"""-- Diagnostic guest configuration; no host configuration is changed.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.config({ animations = { enabled = false },
            debug = { disable_logs = false, enable_stdout_logs = true },
            misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 } })
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/bin/hyprctl -j monitors > /dev/ttyS0 2>&1")
end)
"""
    entry("hyprland.lua", stat.S_IFREG | 0o644, config)
    # Mesa DRI entry points may hardlink to one large Gallium library. Preserve
    # those links so the initramfs contains the payload once, not per driver.
    files = sorted({p for base in (runtime / "usr/lib", runtime / "usr/share", runtime / "etc/fonts") for p in base.rglob("*")} |
                   {runtime / "usr/bin" / name for name in ("Hyprland", "hyprctl", "seatd", "seatd-launch", "bash", "sh", "Xwayland")})
    groups = defaultdict(list)
    directories = {"usr/lib", "usr/share"}
    entry("etc/fonts", stat.S_IFDIR | 0o755)
    directories.add("etc/fonts")
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
with args.output.open("xb") as output:
    output.write(archive)
print(f"Hyprland diagnostic archive: {len(archive)} bytes")
