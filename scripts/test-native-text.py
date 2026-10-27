#!/usr/bin/env python3
"""Compare direct Flexscript font results with an independent C library oracle.

C and Python are test-only; neither is used to build or run the GUI backend.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler', type=Path, required=True)
a = p.parse_args()
d = ROOT / 'build/migration/text-tests'
d.mkdir(parents=True, exist_ok=True)
flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'freetype2', 'harfbuzz'], text=True))
for fixture in ['font-abi', 'font-oracle']:
    subprocess.run(['cc', '-O2', str(ROOT / f'tests/tooling/{fixture}.c'), *flags, '-o', str(d / fixture)], check=True)
actual = dict(line.split('=') for line in subprocess.check_output([str(d / 'font-abi')], text=True).splitlines())
expected = {'FT_FaceRec.face_flags':16, 'FT_FaceRec.num_fixed_sizes':56, 'FT_FaceRec.available_sizes':64,
            'FT_FaceRec.glyph':152, 'FT_FaceRec.size':160, 'FT_SizeRec.metrics':24,
            'FT_Size_Metrics.y_ppem':2, 'FT_Size_Metrics.ascender':24, 'FT_Size_Metrics.descender':32, 'FT_Size_Metrics.height':40,
            'FT_Bitmap_Size.y_ppem':24, 'FT_Bitmap_Size.sizeof':32, 'FT_GlyphSlotRec.bitmap':152,
            'FT_GlyphSlotRec.bitmap_left':192, 'FT_GlyphSlotRec.bitmap_top':196, 'FT_Bitmap.rows':0,
            'FT_Bitmap.width':4, 'FT_Bitmap.pitch':8, 'FT_Bitmap.buffer':16, 'FT_Bitmap.pixel_mode':26,
            'hb_glyph_info_t.cluster':8, 'hb_glyph_position_t.x_advance':0, 'hb_glyph_position_t.y_advance':4,
            'hb_glyph_position_t.x_offset':8, 'hb_glyph_position_t.y_offset':12,
            'hb_glyph_info_t.sizeof':20, 'hb_glyph_position_t.sizeof':20}
assert {k:int(v) for k,v in actual.items()} == expected, actual
fixtures = [('sans-serif', 16, 'office AV ffi', 0), ('sans-serif', 13, 'Häät — pieni teksti', 0),
            ('sans-serif', 24, 'a\u0301 e\u0308', 0), ('sans-serif', 18, 'السَّلَامُ', 5),
            ('sans-serif', 18, 'שלום', 5), ('monospace', 15, 'code { x += 42; }', 4),
            ('sans-serif:charset=4e2d', 16, '中文测试', 0),
            ('sans-serif:charset=1f44b', 16, '👋🏽 🐈', 0),
            ('sans-serif:charset=1f44b', 36, '👨‍👩‍👧‍👦 ❤️', 0),
            ('sans-serif', 16, '', 0)]
checks = 0
for pipeline in ['ir', 'direct']:
    binary = d / f'native-font-{pipeline}'
    subprocess.run([str(a.compiler.resolve()), '--native-pipeline', pipeline,
                    str(ROOT / 'tests/ui/native-font.flex'), '-o', str(binary)], check=True)
    for pattern, px, text, direction in fixtures:
        font = subprocess.check_output(['fc-match', '-f', '%{file}', pattern], text=True)
        args = [font, str(px), text, str(direction)]
        oracle = json.loads(subprocess.check_output([str(d / 'font-oracle'), *args], text=True))
        candidate = json.loads(subprocess.check_output([str(binary), *args], text=True))
        assert candidate == oracle, (pipeline, pattern, px, text, oracle, candidate)
        checks += 1
print(f'PASS {checks} native font comparisons: ABI, shaping/clusters, hinted raster checksums, CJK, RTL runs, combining marks, fixed-strike color emoji and cleanup')
