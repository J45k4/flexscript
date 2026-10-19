#!/usr/bin/env python3
"""Both native ROMs return full words through the actual Flexscript JSON reader."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser()
    for name in ('compiler', 'qemu', 'qemu-c6', 'work'):
        p.add_argument('--' + name, required=True, type=Path)
    a = p.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = a.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    compiler = a.compiler.resolve()
    cases = []
    vectors = [('refusal', '-95', -95), ('minus-one', '-1', -1),
               ('minimum', '(-9223372036854775807-1)', -(1 << 63)),
               ('maximum', '9223372036854775807', (1 << 63) - 1)]

    def run(cmd):
        r = subprocess.run(list(map(str, cmd)), cwd=root, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, (cmd, r.stdout, r.stderr)
        return r

    for chip in (3, 6):
        for label, expression, expected in vectors:
            prefix = work / (label + f'-c{chip}')
            source, image, elf, report = [Path(str(prefix) + suffix) for suffix in ('.flex', '.bin', '.elf', '.json')]
            source.write_text('fn main(){return ' + expression + ';}\n')
            run([compiler, '--target', f'esp32c{chip}', source, '-o', image])
            run([compiler, '--target', f'esp32c{chip}-elf', source, '-o', elf])
            run(['python3', root / 'tests/esp32/riscv-rom-peer.py', '--qemu', a.qemu if chip == 3 else a.qemu_c6,
                 '--image', image, '--elf', elf, '--report', report, '--expected', expected])
            row = json.loads(report.read_text())
            bits = f'{expected & ((1 << 64) - 1):016x}'
            assert row['ROM_boot'] and row['result'] == expected and row['result_word_hex'] == bits
            cases.append(dict(chip=chip, case=label, expected_result=expected, expected_hex=bits, report=row))
    payload = work / 'words.json'
    payload.write_text(json.dumps(cases, indent=2) + '\n')
    reader = work / 'reader.flex'
    reader.write_text(f'''import "{root}/scripts/lib/build.flex";
fn main(argc,argv){{h_environment(argc,argv);let values=j_parse(h_read({json.dumps(str(payload))}));if j_count(values)!=8{{return 1;}}let i=0;while i<8{{let row=j_at(values,i);let report=j_get(row,"report");let result=j_get(report,"result");if j_kind(result)!=1 || j_value(result)!=j_value(j_get(row,"expected_result")){{return 2;}}if !h_equal(j_value(j_get(report,"result_word_hex")),j_value(j_get(row,"expected_hex"))){{return 3;}}i=i+1;}}let again=j_parse(j_dump(values));if j_count(again)!=8{{return 4;}}return 0;}}
''')
    binary = work / 'reader'
    run([compiler, reader, '-o', binary])
    run([binary])
    result = dict(pass_all=True, C3_ROM_boots=4, C6_ROM_boots=4, Flexscript_JSON_parse_and_roundtrip=True,
                  signed_word_limits=True, exact_unsigned_hex_preserved=True, physical_hardware=False,
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=cases)
    (work / 'report.json').write_text(json.dumps(result, indent=2) + '\n')
    print('PASS: native return words through signed Flexscript JSON; 4 C3 and 4 C6 ROM boots')


if __name__ == '__main__':
    main()
