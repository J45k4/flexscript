#!/usr/bin/env python3
"""Whole-target public clear, clipping restoration and pixel parity, privately."""
import argparse, hashlib, json, os, stat, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=Path, action='append', required=True)
p.add_argument('--session', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args(); session = json.loads(a.session.read_text()); runtime = Path(session['XDG_RUNTIME_DIR'])
assert runtime.name.startswith('fs-ime-') and runtime.stat().st_uid == os.getuid() and stat.S_IMODE(runtime.stat().st_mode) == 0o700
assert '/' not in session['WAYLAND_DISPLAY'] and stat.S_ISSOCK((runtime/session['WAYLAND_DISPLAY']).stat().st_mode)
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True); rows = []; captures = {}
for index, binary in enumerate(a.binary):
    for backend in ['sdl2', 'wayland']:
        prefix = out/f'{index}-{backend}-'; report = out/f'{index}-{backend}.json'
        env = dict(os.environ, **session, FLEX_GUI_BACKEND=backend, SDL_VIDEODRIVER='wayland', SDL_RENDER_DRIVER='opengl', SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0'); env.pop('DISPLAY', None)
        result = subprocess.run([str(binary.resolve()), str(prefix), str(report)], cwd=ROOT, env=env, capture_output=True, timeout=60)
        (out/f'{index}-{backend}.stdout.log').write_bytes(result.stdout); (out/f'{index}-{backend}.stderr.log').write_bytes(result.stderr)
        assert result.returncode == 0, (index, backend, result.returncode, result.stdout, result.stderr[-3000:])
        row = json.loads(report.read_text()); assert row['backend'] == backend and row['checks'] == 6 and row['gl_error'] == 0, row
        rows.append(row)
        for path in out.glob(f'{index}-{backend}-*.rgba'):
            scene = path.name.removeprefix(f'{index}-{backend}-')
            width, height = (32, 24) if scene.startswith('layer-') else (row['width'], row['height'])
            data = path.read_bytes(); assert len(data) == width*height*4
            value = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
            if scene in captures: assert captures[scene] == value, (scene, captures[scene], value)
            else: captures[scene] = value
        assert len(captures) == 6
        print('PASS public clear pixels:', index, backend, row, flush=True)
(out/'report.json').write_text(json.dumps(dict(correctness_only=True, byte_identical=True, rows=rows, captures=captures,
    binary_sha256={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in a.binary},
    source_sha256={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ['libs/gui/renderer/gl.flex','libs/gui/canvas.flex','libs/gui/draw.flex','tests/ui/canvas-clear.flex','scripts/test-canvas-clear.py']}), indent=2)+'\n')
