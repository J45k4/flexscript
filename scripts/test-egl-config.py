#!/usr/bin/env python3
"""Independent current EGL configuration/ownership and pixel checks, privately."""
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
out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True); oracle = out/'oracle.so'
subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', 'tests/tooling/egl-config.c', '-lEGL', '-o', str(oracle)], cwd=ROOT, check=True)
rows = []
for index,binary in enumerate(a.binary):
    for backend in ['sdl2', 'wayland']:
        prefix = out/f'{index}-{backend}'; report = prefix.with_suffix('.json')
        env = dict(os.environ, **session, FLEX_GUI_BACKEND=backend, SDL_VIDEODRIVER='wayland', SDL_RENDER_DRIVER='opengl', SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY='0'); env.pop('DISPLAY', None)
        result = subprocess.run([str(binary.resolve()), str(oracle), str(report)], cwd=ROOT, env=env, capture_output=True, timeout=20)
        prefix.with_suffix('.stdout.log').write_bytes(result.stdout); prefix.with_suffix('.stderr.log').write_bytes(result.stderr)
        assert result.returncode == 0, (index, backend, result.returncode, result.stdout, result.stderr[-3000:])
        row = json.loads(report.read_text())
        assert row['backend'] == backend and row['independent_oracle'] and row['identical_pixels'] and row['egl_error_after'] == 0x3000, row
        assert row['config_id'] == row['surface_config_id'] and row['surface_width'] == row['gui_pixel_width'] and row['surface_height'] == row['gui_pixel_height'], row
        assert row['gl_renderer'] and not any(v in row['gl_renderer'].lower() for v in ['llvmpipe', 'softpipe', 'software']), row
        rows.append(row)
        print('PASS independent EGL metadata:', index, backend, {key: row[key] for key in ['red_bits','green_bits','blue_bits','alpha_bits','depth_bits','stencil_bits','samples','gl_version']}, flush=True)
fields = ['red_bits', 'green_bits', 'blue_bits', 'alpha_bits', 'depth_bits', 'stencil_bits', 'buffer_bits', 'sample_buffers', 'samples', 'surface_type', 'renderable_type', 'minimum_swap_interval', 'maximum_swap_interval', 'swap_behavior', 'render_buffer', 'client_api', 'gl_renderer', 'gl_version']
for backend in ['sdl2', 'wayland']:
    selected = [row for row in rows if row['backend'] == backend]
    assert all(all(row[key] == selected[0][key] for key in fields) for row in selected), 'Pipeline configuration mismatch'
(out/'report.json').write_text(json.dumps(dict(correctness_only=True, physical_scanout_verified=False, rows=rows,
    binary_sha256={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in a.binary},
    source_sha256={path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ['tests/ui/egl-config.flex','tests/ui/egl-config-driver.flex','tests/tooling/egl-config.c','scripts/test-egl-config.py']}), indent=2)+'\n')
