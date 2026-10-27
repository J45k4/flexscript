#!/usr/bin/env python3
"""Retained native layout against official paragraph levels, with rich runs/wrap.

The reference only applies the independently specified L1/L2 line operations to
official expected paragraph levels; it does not reuse the implementation's
paragraph resolution or its piece ordering to calculate expected results.
"""
import argparse
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', required=True, type=Path)
    a = p.parse_args()
    out = ROOT / 'build/migration/ui-bidi-tests'
    out.mkdir(parents=True, exist_ok=True)
    base = ROOT / 'tests/tooling/unicode/17.0.0'
    classes = ['L'] * 0x110000
    for missing in (True, False):
        for raw in (base / 'extracted/DerivedBidiClass.txt').read_text().splitlines():
            if missing:
                if '@missing:' not in raw:
                    continue
                raw = raw.split('@missing:', 1)[1]
            else:
                raw = raw.split('#', 1)[0]
            if not raw.strip():
                continue
            span, cls = [f.strip() for f in raw.split(';')]
            cls = {'Left_To_Right': 'L', 'Right_To_Left': 'R', 'Arabic_Letter': 'AL',
                   'European_Terminator': 'ET'}.get(cls, cls)
            limits = [int(t, 16) for t in span.split('..')]
            classes[limits[0]:limits[-1]+1] = [cls] * (limits[-1]+1-limits[0])
    pool = []
    for line_number, raw in enumerate((base / 'BidiCharacterTest.txt').read_text().splitlines(), 1):
        raw = raw.split('#', 1)[0].strip()
        if not raw:
            continue
        text, mode, paragraph, levels, order = raw.split(';')
        cps = [int(t, 16) for t in text.split()]
        depth = 0
        auto_base = 0
        for cp in cps:
            cls = classes[cp]
            if cls in ('LRI', 'RLI', 'FSI'):
                depth += 1
            elif cls == 'PDI':
                depth = max(0, depth-1)
            elif not depth and cls in ('L', 'R', 'AL'):
                auto_base = int(cls != 'L')
                break
        if (mode == '2' or int(mode) == auto_base) and len(cps) <= 100:
            pool.append(dict(text=''.join(map(chr, cps)), base=int(paragraph),
                             levels=[255 if t == 'x' else int(t) for t in levels.split()],
                             source=line_number))
    rng = random.Random(170009)
    selected = pool[:80] + rng.sample(pool[80:], min(256, max(0, len(pool)-80)))
    requests = []
    expected = []
    for item in selected:
        for width, styled in [(8192, 0), (8192, 1), (140, 1)]:
            requests.append(dict(text=item['text'], width=width, styled=styled))
            expected.append(item)
    # Multi-paragraph separator/CRLF cases also exercise different bases across
    # rich-run boundaries. Their exact line count is independent of bidi levels.
    for text, lines in [('שלום\r\nabc', 2), ('abc\r\nשלום', 2), ('שלום\u2029abc', 2),
                        ('שלום\u2028abc', 2), ('שלום\u0085abc', 2), ('שלום\n\nabc', 3)]:
        for styled in (0, 1):
            requests.append(dict(text=text, width=8192, styled=styled))
            expected.append(dict(lines=lines))
    path = out / 'requests.json'
    path.write_text(json.dumps(requests, ensure_ascii=False))
    for pipeline in ('ir', 'direct'):
        binary = out / ('bidi-layout-' + pipeline)
        subprocess.run([str(a.compiler.resolve()), '--native-pipeline', pipeline,
                        str(ROOT / 'tests/ui/bidi-layout.flex'), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary), str(path)], capture_output=True, text=True, timeout=120)
        (out / (pipeline + '.stderr.log')).write_text(result.stderr)
        assert result.returncode == 0, (pipeline, result.stderr)
        reports = [json.loads(line) for line in result.stdout.splitlines()]
        (out / (pipeline + '.json')).write_text(json.dumps(reports))
        for case, (request, want, report) in enumerate(zip(requests, expected, reports, strict=True)):
            if 'lines' in want:
                assert report['height'] == report['line']*want['lines'], (pipeline, case, request, report)
                continue
            text = request['text']
            offsets = [0]
            for char in text:
                offsets.append(offsets[-1] + len(char.encode()))
            scalar_at = {byte: i for i, byte in enumerate(offsets)}
            lines = {}
            previous_end = 0
            for piece in report['pieces']:
                start, end, level, visual, x, width, y, direction = piece
                assert start >= previous_end and end >= start, (case, 'Logical piece order changed', report)
                previous_end = end
                assert start in scalar_at and end in scalar_at, (case, 'UTF-8 piece boundary', piece)
                if direction:
                    assert direction == 4+(level & 1), (case, 'Direction differs from resolved level', piece)
                lines.setdefault(y, []).append(piece)
            for pieces in lines.values():
                first = scalar_at[pieces[0][0]]
                end = scalar_at[pieces[-1][1]]
                levels = want['levels'].copy()
                trailing = True
                for i in range(end-1, first-1, -1):
                    cls = classes[ord(text[i])]
                    if levels[i] == 255:
                        continue
                    if cls in ('B', 'S'):
                        levels[i] = want['base']
                        trailing = True
                    elif trailing and cls in ('WS', 'FSI', 'LRI', 'RLI', 'PDI'):
                        levels[i] = want['base']
                    else:
                        trailing = False
                order = [i for i in range(first, end) if levels[i] != 255]
                for threshold in range(max((levels[i] for i in order), default=0), 0, -1):
                    at = 0
                    while at < len(order):
                        if levels[order[at]] >= threshold:
                            stop = at+1
                            while stop < len(order) and levels[order[stop]] >= threshold:
                                stop += 1
                            order[at:stop] = reversed(order[at:stop])
                            at = stop
                        else:
                            at += 1
                got_order = []
                sorted_pieces = sorted(pieces, key=lambda row: row[3])
                last_right = None
                for start, stop, level, visual, x, width, y, direction in sorted_pieces:
                    logical = [i for i in range(scalar_at[start], scalar_at[stop]) if levels[i] != 255]
                    assert all(levels[i] == level for i in logical), (pipeline, case, want['source'], 'Level', logical, levels, pieces)
                    got_order.extend(reversed(logical) if level & 1 else logical)
                    assert last_right is None or x == last_right, (pipeline, case, 'Visual pieces overlap/gap', pieces)
                    last_right = x+width
                assert got_order == order, (pipeline, case, want['source'], 'Visual order', order, got_order, pieces)
        print(f'PASS {pipeline}: {len(reports)} retained native bidi layouts, rich runs, wrapped lines and separators', flush=True)
    (out / 'report.json').write_text(json.dumps(dict(status='pass', layouts=len(requests),
                 paragraphs=len(selected), pipelines=['ir', 'direct']), indent=2)+'\n')


if __name__ == '__main__':
    main()
