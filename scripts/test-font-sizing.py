#!/usr/bin/env python3
"""Independent bitmap/scalable font metrics and rendered-size verification."""
import argparse, hashlib, json, os, shlex, stat, struct, subprocess, zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=Path, action='append', required=True)
p.add_argument('--session', type=Path)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
oracle = out / 'oracle.so'
flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', 'SDL2_ttf', 'freetype2', 'harfbuzz'], text=True))
flags += shlex.split(subprocess.check_output(['pkg-config', '--libs', 'freetype2', 'harfbuzz'], text=True))
subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', 'tests/tooling/bitmap-font.c', '-o', str(oracle), *flags, '-ldl'], cwd=ROOT, check=True)
fonts = [subprocess.check_output(['fc-match', '-f', '%{file}', pattern], text=True) for pattern in ['sans-serif', 'sans-serif:charset=1f44b']]
env = dict(os.environ)
env.pop('DISPLAY', None); env.pop('SDL_VIDEO_DRIVER', None)
backends = ['sdl2']
if a.session:
    session = json.loads(a.session.read_text()); runtime = Path(session['XDG_RUNTIME_DIR'])
    assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
    assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime / session['WAYLAND_DISPLAY']).stat().st_mode)
    env.update(session, SDL_VIDEODRIVER='wayland', SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0')
    backends.append('wayland')
else:
    env.pop('WAYLAND_DISPLAY', None)
    env['SDL_VIDEODRIVER'] = 'dummy'
reports = []
for index, binary in enumerate(a.binary):
    for backend in backends:
        directory = out / f'{index}-{backend}'; directory.mkdir(exist_ok=True)
        prefix = str(directory / 'size-')
        r = subprocess.run([str(binary.resolve()), str(oracle), *fonts, prefix], cwd=ROOT,
                           env=dict(env, FLEX_GUI_BACKEND=backend), capture_output=True, timeout=30)
        (directory / 'stdout.log').write_bytes(r.stdout); (directory / 'stderr.log').write_bytes(r.stderr)
        assert r.returncode == 0, (backend, index, r.returncode, r.stdout, r.stderr)
        row = json.loads(Path(prefix + 'report.json').read_text())
        assert row['backend'] == backend and len(row['cases']) == 10, row
        for path in directory.glob('*.rgba'):
            raw = path.read_bytes(); w, h = row['pixel_width'], row['pixel_height']; assert len(raw) == w * h * 4
            def chunk(tag, payload):
                return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff)
            scan = b''.join(b'\0' + raw[y*w*4:(y+1)*w*4] for y in range(h))
            path.with_suffix('.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(scan)) + chunk(b'IEND', b''))
        reports.append(row)
        print('PASS independent font sizes:', index, backend, '10 metrics cases, 5 bitmap captures and repeated fallback/release', flush=True)
(out / 'report.json').write_text(json.dumps(dict(fonts=fonts, software_correctness_only=not bool(a.session), rows=reports,
    oracle_sha256=hashlib.sha256(oracle.read_bytes()).hexdigest(),
    source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ['scripts/test-font-sizing.py', 'tests/tooling/bitmap-font.c', 'tests/ui/font-sizing.flex', 'libs/gui/draw.flex', 'libs/gui/text/bitmap-size.flex']},
    binaries={str(binary): hashlib.sha256(binary.read_bytes()).hexdigest() for binary in a.binary}), indent=2) + '\n')
