#!/usr/bin/env python3
"""Both complete Unicode 17 bidi corpora, independent properties and generator.

Python only serializes official expected output and parses pinned source data;
the algorithm, generated tables and shipped application remain Flexscript.
"""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLASSES = 'L R AL EN ES ET AN CS NSM BN B S WS ON LRE LRO RLE RLO PDF LRI RLI FSI PDI'.split()
ALIASES = dict(Left_To_Right='L', Right_To_Left='R', Arabic_Letter='AL', European_Terminator='ET')
# One representative per class, deliberately no paired bracket. Class lookup
# itself is verified independently at every Unicode codepoint below.
REPRESENTATIVES = [0x61, 0x5d0, 0x627, 0x30, 0x2b, 0x24, 0x660, 0x2c, 0x300,
                   0xad, 0xa, 0x9, 0x20, 0x21, 0x202a, 0x202d, 0x202b, 0x202e,
                   0x202c, 0x2066, 0x2067, 0x2068, 0x2069]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    args = parser.parse_args()
    base = ROOT / 'tests/tooling/unicode/17.0.0'
    out = ROOT / 'build/migration/unicode-bidi-tests'
    out.mkdir(parents=True, exist_ok=True)
    compiler = str(args.compiler.resolve())
    manifest = json.loads((base / 'manifest.json').read_text())
    for source in manifest['sources']:
        assert hashlib.sha256((base / source['file']).read_bytes()).hexdigest() == source['sha256'], source
    generator = out / 'generator'
    subprocess.run([compiler, str(ROOT / 'scripts/unicode-bidi-properties.flex'), '-o', str(generator)], check=True)
    generated = out / 'bidi-properties.flex'
    subprocess.run([str(generator), str(base), str(generated)], check=True)
    assert generated.read_bytes() == (ROOT / 'libs/unicode/bidi-properties.flex').read_bytes(), 'Regenerate bidi properties'

    values = bytearray(0x110000)
    lines = (base / 'extracted/DerivedBidiClass.txt').read_text().splitlines()
    # @missing defaults must precede explicit entries; checking only assigned
    # characters would miss RTL and Arabic defaults in reserved script blocks.
    for missing in (True, False):
        for raw in lines:
            if missing:
                if '@missing:' not in raw:
                    continue
                raw = raw.split('@missing:', 1)[1]
            else:
                raw = raw.split('#', 1)[0]
            if not raw.strip():
                continue
            span, cls = [f.strip() for f in raw.split(';')]
            bounds = [int(s, 16) for s in span.split('..')]
            lo, hi = bounds[0], bounds[-1]
            value = CLASSES.index(ALIASES.get(cls, cls))
            values[lo:hi+1] = bytes([value]) * (hi+1-lo)
    brackets = {}
    mirrors = {}
    for filename, target in [('BidiBrackets.txt', brackets), ('BidiMirroring.txt', mirrors)]:
        for raw in (base / filename).read_text().splitlines():
            raw = raw.split('#', 1)[0].strip()
            if not raw:
                continue
            fields = [f.strip() for f in raw.split(';')]
            cp, paired = [int(f, 16) for f in fields[:2]]
            target[cp] = (paired << 2) | {'o': 1, 'c': 2}[fields[2]] if target is brackets else paired
    properties = bytearray(0x110000*9)
    for cp, value in enumerate(values):
        struct.pack_into('<BII', properties, cp*9, value, brackets.get(cp, 0), mirrors.get(cp, cp))
    for cls, cp in zip(CLASSES, REPRESENTATIVES, strict=True):
        assert values[cp] == CLASSES.index(cls), (cls, cp)

    sources = []
    path = out / 'cases.bin'
    with path.open('wb') as stream:
        def case(cps, mode, expected_base, levels, order, source):
            stream.write(struct.pack('<IBBBB', len(cps), mode, expected_base, 0, 0))
            stream.write(struct.pack('<' + 'I'*len(cps), *cps))
            stream.write(bytes(255 if t == 'x' else int(t) for t in levels))
            stream.write(struct.pack('<I', len(order)))
            stream.write(struct.pack('<' + 'I'*len(order), *order))
            sources.append(source)

        for line_number, raw in enumerate((base / 'BidiTest.txt').read_text().splitlines(), 1):
            raw = raw.split('#', 1)[0].strip()
            if not raw:
                continue
            if raw.startswith('@Levels:'):
                levels = raw.split(':', 1)[1].split()
            elif raw.startswith('@Reorder:'):
                order = [int(t) for t in raw.split(':', 1)[1].split()]
            elif not raw.startswith('@'):
                text, mask = raw.split(';')
                cps = [REPRESENTATIVES[CLASSES.index(t)] for t in text.split()]
                for bit, mode in [(1, 2), (2, 0), (4, 1)]:
                    if int(mask, 16) & bit:
                        case(cps, mode, 255, levels, order, ('BidiTest.txt', line_number, mode))
        type_count = len(sources)
        for line_number, raw in enumerate((base / 'BidiCharacterTest.txt').read_text().splitlines(), 1):
            raw = raw.split('#', 1)[0].strip()
            if raw:
                text, mode, expected_base, levels, order = raw.split(';')
                case([int(t, 16) for t in text.split()], int(mode), int(expected_base),
                     levels.split(), [int(t) for t in order.split()], ('BidiCharacterTest.txt', line_number, int(mode)))
    # Useful when a native assertion reports a serialized case index.
    (out / 'sources.json').write_text(json.dumps(sources))
    for pipeline in ('ir', 'direct'):
        binary = out / f'bidi-{pipeline}'
        subprocess.run([compiler, '--native-pipeline', pipeline, str(ROOT / 'tests/unicode/bidi.flex'), '-o', str(binary)], check=True)
        output = out / f'properties-{pipeline}.bin'
        result = subprocess.run([str(binary), str(path), str(output)], capture_output=True, text=True, timeout=300)
        (out / f'{pipeline}.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            import re
            match = re.search(r'Bidi case (\d+)', result.stderr)
            detail = sources[int(match.group(1))] if match else ''
            raise AssertionError((pipeline, detail, result.stdout, result.stderr))
        assert output.read_bytes() == properties, (pipeline, 'Full bidi class/bracket/mirror property oracle differs')
        print(pipeline, result.stdout.strip(), flush=True)
    report = dict(unicode='17.0.0', type_cases=type_count, character_cases=len(sources)-type_count,
                  total=len(sources), codepoints=0x110000, pipelines=['ir', 'direct'], status='pass')
    (out / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
