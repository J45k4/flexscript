#!/usr/bin/env python3
"""Prepare official Hyprland libraries for a diskless emulator diagnostic."""
import argparse
from collections import deque
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--unsquashfs', type=Path, required=True)
parser.add_argument('--squashfs', type=Path, required=True)
parser.add_argument('--mesa-runtime', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--temp-root', type=Path)
args = parser.parse_args()
for name in ('usr/lib/libgbm.so.1', 'usr/lib/libEGL.so.1', 'usr/lib/libc.so.6'):
    if not (args.mesa_runtime / name).exists():
        parser.error('Incomplete Mesa runtime: ' + name)
args.output.mkdir(mode=0o700)
root = args.output.resolve()
subprocess.run(['cp', '-a', '--reflink=auto', str(args.mesa_runtime.resolve()) + '/.', str(root)], check=True)
tool, squashfs = str(args.unsquashfs.resolve()), str(args.squashfs.resolve())
manifest = subprocess.check_output([tool, '-ll', squashfs], text=True)
loaded = set()
# Library names whose Arch package name cannot be inferred directly.
providers = {'libglslang-default-resource-limits.so': 'glslang', 'libglslang.so': 'glslang',
             'liblua5.4.so': 'lua54', 'liblua.so': 'lua', 'libjxl_threads.so': 'libjxl',
             'libxcb-errors.so': 'xcb-util-errors', 'libxcb-icccm.so': 'xcb-util-wm',
             'libxcb-image.so': 'xcb-util-image', 'libxcb-keysyms.so': 'xcb-util-keysyms',
             'libxcb-render-util.so': 'xcb-util-renderutil', 'liboeffis.so': 'libei',
             'librrd.so': 'rrdtool', 'libgdk_pixbuf-2.0.so': 'gdk-pixbuf2',
             'libglib-2.0.so': 'glib2', 'libgobject-2.0.so': 'glib2', 'libgio-2.0.so': 'glib2',
             'libbrotlidec.so': 'brotli', 'libbrotlicommon.so': 'brotli',
             'libhwy.so': 'highway', 'libpng16.so': 'libpng',
             'libgdk-3.so': 'gtk3', 'libgtk-3.so': 'gtk3',
             'libatk-1.0.so': 'at-spi2-core', 'libatk-bridge-2.0.so': 'at-spi2-core',
             'libgraphene-1.0.so': 'graphene'}
with tempfile.TemporaryDirectory(prefix='flexvirt-hyprland-packages-', dir=args.temp_root) as temp:
    def package(name):
        if name in loaded:
            return False
        matches = re.findall(r'squashfs-root/(var/cache/omarchy/mirror/offline/' + re.escape(name)
                             + r'-[0-9][^/\s]*-(?:x86_64|any)\.pkg\.tar\.zst)$', manifest, re.MULTILINE)
        if len(matches) != 1:
            return False
        directory = Path(temp) / name
        subprocess.run([tool, '-no-progress', '-d', str(directory), squashfs, matches[0]], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['bsdtar', '--no-same-owner', '--no-same-permissions', '-xf', str(directory / matches[0]), '-C', str(root)], check=True)
        loaded.add(name)
        return True

    for name in ('hyprland', 'aquamarine', 'seatd', 'hyprutils', 'hyprlang', 'hyprcursor', 'hyprgraphics',
                 'libinput', 'libdisplay-info', 'libxkbcommon', 'libxcursor', 'xorg-xwayland', 'xkeyboard-config',
                 'bash', 'fontconfig', 'ttf-liberation', 'adwaita-cursors', 'default-cursors'):
        if not package(name):
            parser.error('Expected one official offline package: ' + name)
    def image_file(path):
        for _ in range(40):
            path = Path(os.path.normpath(path))
            if not path.is_relative_to(root):
                return None
            if not path.is_symlink():
                return path if path.is_file() and path.resolve().is_relative_to(root) else None
            target = path.readlink()
            path = root / target.relative_to('/') if target.is_absolute() else path.parent / target
        return None

    entries = [root / 'usr/bin' / name for name in ('Hyprland', 'hyprctl', 'seatd', 'seatd-launch', 'bash', 'Xwayland')]
    # Mesa loads drivers via GLVND/dlopen; keep the already verified Mesa
    # library roots in addition to the actual compositor executable roots.
    entries += [root / path.relative_to(args.mesa_runtime.resolve())
                for path in (args.mesa_runtime.resolve() / 'usr/lib').rglob('*')
                if path.is_file() and not path.is_symlink()]
    for iteration in range(16):
        needed, seen, checked = set(), set(), set()
        pending = deque(entries)
        while pending:
            p = image_file(pending.popleft())
            if p is None:
                continue
            info = p.stat()
            key = info.st_dev, info.st_ino
            if key in seen:
                continue
            seen.add(key)
            dynamic = subprocess.run(['readelf', '-d', str(p)], capture_output=True, text=True)
            if dynamic.returncode == 0:
                checked.add(p)
            for name in re.findall(r'\(NEEDED\).*\[(.*?)\]', dynamic.stdout):
                needed.add(name)
                library = image_file(root / 'usr/lib' / name)
                if library is not None:
                    pending.append(library)
        missing = sorted(name for name in needed if image_file(root / 'usr/lib' / name) is None)
        if not missing:
            break
        patterns, absent = [], []
        for name in missing:
            prefix = name.split('.so')[0] + '.so' if '.so' in name else name
            if re.search(r'squashfs-root/usr/lib/' + re.escape(name) + r'(?:\s|$)', manifest):
                patterns.append('usr/lib/' + prefix + '*')
            else:
                absent.append(name)
        if patterns:
            subprocess.run([tool, '-f', '-no-progress', '-d', str(root), squashfs, *patterns], check=True, stdout=subprocess.DEVNULL)
            root.chmod(0o700)
        for name in absent:
            if image_file(root / 'usr/lib' / name) is not None:
                continue
            prefix = name.split('.so')[0] + '.so' if '.so' in name else name
            raw = prefix.split('.so')[0]
            stem = re.sub(r'-[0-9].*$', '', raw.lower())
            family = 'abseil-cpp' if raw.startswith('libabsl_') else ('icu' if raw.startswith('libicu') else '')
            candidates = [providers.get(prefix, ''), family, raw, raw.lower(), stem,
                          raw[3:] if raw.startswith('lib') else '', stem[3:] if stem.startswith('lib') else '']
            if not any(candidate and package(candidate) for candidate in candidates):
                parser.error('Cannot resolve official package for ' + name)
    else:
        parser.error('Hyprland dependency closure did not converge')
def versions(path):
    text = subprocess.check_output(['readelf', '--version-info', str(path)], text=True)
    section, provider = '', ''
    definitions, requirements = set(), {}
    for line in text.splitlines():
        if line.startswith('Version definition section'):
            section = 'definitions'
        elif line.startswith('Version needs section'):
            section = 'requirements'
        match = re.search(r'\bFile: (\S+)', line)
        if match and section == 'requirements':
            provider = match[1]
        match = re.search(r'\bName: (\S+)', line)
        if match and section == 'definitions':
            definitions.add(match[1])
        elif match and section == 'requirements':
            requirements.setdefault(provider, set()).add(match[1])
    return definitions, requirements

cache = {}
for path in sorted(checked):
    _, requirements = versions(path)
    for name, wanted in requirements.items():
        provider = image_file(root / 'usr/lib' / name)
        if provider is None:
            parser.error('Missing version provider: ' + name)
        if provider not in cache:
            cache[provider] = versions(provider)[0]
        if not wanted <= cache[provider]:
            parser.error(f'{path.relative_to(root)} needs absent {name} versions: {sorted(wanted - cache[provider])}')
print('PASS: official Hyprland, seatd, shell and Xwayland ELF dependencies and symbol versions')
