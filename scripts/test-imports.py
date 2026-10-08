#!/usr/bin/env python3
"""Verify native compiler imports, graph handling, diagnostics and source safety."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*command, cwd=None):
    return subprocess.run([str(part) for part in command], cwd=cwd, capture_output=True, timeout=30)


def suite(compiler):
    count = 0
    with tempfile.TemporaryDirectory(prefix='flexscript-imports-') as folder:
        work = Path(folder)
        def case(name, files):
            directory = work / name
            for name, text in files.items():
                path = directory / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            return directory

        def compile(directory, source='main.flex', destination='program'):
            return run(compiler, directory / source, '-o', directory / destination, cwd=work)

        def accepted(directory, status=0, stdout=b'', source='main.flex'):
            nonlocal count
            result = compile(directory, source)
            assert result.returncode == 0 and result.stderr == b'', result.stderr
            binary = directory / 'program'
            assert os.access(binary, os.X_OK) and binary.read_bytes()[:4] == b'\x7fELF'
            result = run(binary)
            assert (result.returncode, result.stdout) == (status, stdout), result
            count += 1
            return binary.read_bytes()

        def rejected(directory, message, location=None, destination='program'):
            nonlocal count
            output = directory / destination
            if not output.exists():
                output.write_bytes(b'preserve existing output')
            snapshots = {p: p.read_bytes() for p in directory.rglob('*') if p.is_file()}
            result = compile(directory, destination=destination)
            assert result.returncode == 1 and message.encode() in result.stderr, result.stderr
            assert re.search(rb':\d+:\d+: error: ', result.stderr), result.stderr
            if location:
                assert location.encode() in result.stderr, result.stderr
            for path, content in snapshots.items():
                assert path.read_bytes() == content, f'Compiler changed {path}'
            count += 1

        result = run(compiler, ROOT / 'examples/imports/main.flex', '-o', work / 'example')
        assert result.returncode == 0, result.stderr
        assert run(work / 'example').stdout == b'Hello from imported Flexscript!\n'
        count += 1
        accepted(case('global-only', {'main.flex': 'import "value.flex"; fn main(){return answer;}',
                                      'value.flex': 'global answer=42;'}), status=42)
        accepted(case('imported-main', {'main.flex': 'import "entry.flex";',
                                        'entry.flex': 'fn main(){return 7;}'}), status=7)
        accepted(case('empty', {'main.flex': 'import "empty.flex"; fn main(){return 0;}', 'empty.flex': ''}))
        accepted(case('cross-file-globals', {
            'main.flex': 'import "lib/a.flex"; import "lib/b.flex"; global root=2; fn main(){return get();}',
            'lib/a.flex': 'global a=3; fn get(){return root+a+b;}', 'lib/b.flex': 'global b=5;'}), status=10)
        accepted(case('forward-calls', {
            'main.flex': 'import "even.flex"; import "odd.flex"; fn main(){return even(8);}',
            'even.flex': 'fn even(n){if n==0{return 1;} return odd(n-1);}',
            'odd.flex': 'fn odd(n){if n==0{return 0;} return even(n-1);}'}), status=1)
        graph = case('diamond', {
            'main.flex': 'import "lib/a.flex"; import "lib/b.flex"; fn main(){a();b();return total;}',
            'lib/a.flex': 'import "shared.flex"; fn a(){increment();}',
            'lib/b.flex': 'import "shared.flex"; fn b(){increment();}',
            'lib/shared.flex': 'global total=0; fn increment(){total=total+1;}'} )
        before = accepted(graph, status=2)
        os.link(graph / 'lib/shared.flex', graph / 'hardlink.flex')
        (graph / 'symlink.flex').symlink_to('lib/shared.flex')
        main = graph / 'main.flex'
        main.write_text('import "./lib/../lib/shared.flex"; import "hardlink.flex"; import "symlink.flex";\n' + main.read_text())
        # Loading shared first can change function layout, but deduplication
        # must keep exactly one shared global and function across every alias.
        accepted(graph, status=2)
        main.write_text('import "lib/a.flex"; import "lib/b.flex"; import "lib/a.flex"; fn main(){a();b();return total;}')
        assert accepted(graph, status=2) == before, 'Repeated import changed generated binary'
        accepted(case('relative-nesting', {
            'entry/main.flex': 'import "../library/one.flex"; fn main(){return one();}',
            'library/one.flex': 'import "nested/two.flex"; fn one(){return two();}',
            'library/nested/two.flex': 'fn two(){return 12;}'}), status=12, source='entry/main.flex')
        directory = case('absolute', {'main.flex': '', 'library.flex': 'fn number(){return 13;}'})
        (directory / 'main.flex').write_text(f'import "{directory}/library.flex"; fn main(){{return number();}}')
        accepted(directory, status=13)
        accepted(case('escaped-path', {'main.flex': 'import "a\\\"b.flex"; fn main(){return value();}',
                                       'a"b.flex': 'fn value(){return 14;}'}), status=14)
        accepted(case('unicode-path', {'main.flex': 'import "你好.flex"; fn main(){return value();}',
                                       '你好.flex': 'fn value(){return 15;}'}), status=15)
        accepted(case('not-directives', {'main.flex': r'fn main(){let s="import \"missing.flex\";";return load8(s);}' + '\n// import "missing.flex";'}), status=105)

        bad = [
            ('unquoted', 'import library; fn main(){}', 'expected quoted import path'),
            ('empty-path', 'import ""; fn main(){}', 'import path cannot be empty'),
            ('null-path', 'import "a\\0.flex"; fn main(){}', 'import path cannot contain a zero byte'),
            ('long-path', 'import "' + 'a' * 4096 + '"; fn main(){}', 'import path exceeds'),
            ('semicolon', 'import "library.flex" fn main(){}', "expected ';' after import"),
            ('after-global', 'global x=0; import "library.flex"; fn main(){}', 'imports must precede'),
            ('after-function', 'fn main(){} import "library.flex";', 'imports must precede'),
            ('reserved-global', 'global import=0; fn main(){}', 'reserved declaration name'),
            ('reserved-function', 'fn import(){} fn main(){}', 'reserved declaration name'),
            ('reserved-local', 'fn main(){let import=0;}', 'reserved declaration name'),
        ]
        for name, source, message in bad:
            rejected(case(name, {'main.flex': source, 'library.flex': ''}), message)
        directory = case('missing', {'main.flex': '// header\nimport "absent.flex";\nfn main(){}'})
        rejected(directory, 'cannot open source', f'{directory}/main.flex:2:1: error:')
        directory = case('syntax-location', {'main.flex': 'import "bad.flex"; fn main(){bad();}',
                                            'bad.flex': 'fn bad() {\n  return @;\n}\n'})
        rejected(directory, 'unexpected source byte', f'{directory}/bad.flex:2:10: error:')
        directory = case('deferred-location', {'main.flex': 'import "bad.flex"; fn main(){bad();}',
                                              'bad.flex': 'fn bad() {\n    missing();\n}\n'})
        rejected(directory, 'undefined function', f'{directory}/bad.flex:2:5: error:')
        directory = case('arity-location', {'main.flex': 'import "bad.flex"; fn main(){bad();}',
                                           'bad.flex': 'fn bad() {\n    zero(1);\n}\nfn zero(){}'})
        rejected(directory, 'wrong function argument count', f'{directory}/bad.flex:2:5: error:')
        directory = case('root-location', {'main.flex': 'import "empty.flex";\nfn main(){\n  missing();\n}', 'empty.flex': ''})
        rejected(directory, 'undefined function', f'{directory}/main.flex:3:3: error:')
        rejected(case('global-order', {'main.flex': 'import "bad.flex"; fn main(){}',
                                       'bad.flex': 'fn f(){} global x=0;'}), 'globals must precede functions')
        rejected(case('duplicate-function', {'main.flex': 'import "a.flex"; import "b.flex"; fn main(){}',
                                             'a.flex': 'fn duplicate(){}', 'b.flex': 'fn duplicate(){}'}), 'duplicate function')
        rejected(case('duplicate-global', {'main.flex': 'import "a.flex"; import "b.flex"; fn main(){}',
                                           'a.flex': 'global duplicate=0;', 'b.flex': 'global duplicate=0;'}), 'duplicate global')
        rejected(case('namespace-conflict', {'main.flex': 'import "a.flex"; global x=0; fn main(){}',
                                             'a.flex': 'fn x(){}'}), 'duplicate function')
        rejected(case('self-cycle', {'main.flex': 'import "main.flex"; fn main(){}'}), 'circular import')
        rejected(case('cycle', {'main.flex': 'import "a.flex"; fn main(){}',
                                'a.flex': 'import "b.flex";', 'b.flex': 'import "a.flex";'}), 'circular import')
        directory = case('alias-cycle', {'main.flex': 'import "alias.flex"; fn main(){}'})
        (directory / 'alias.flex').symlink_to('main.flex')
        rejected(directory, 'circular import')
        directory = case('directory', {'main.flex': 'import "library"; fn main(){}'})
        (directory / 'library').mkdir()
        rejected(directory, 'source must be a regular file')
        directory = case('fifo', {'main.flex': 'import "pipe.flex"; fn main(){}'})
        os.mkfifo(directory / 'pipe.flex')
        # No snapshot of the FIFO: it must fail without a blocking read.
        result = compile(directory)
        assert result.returncode == 1 and b'source must be a regular file' in result.stderr
        count += 1
        directory = case('protect-import', {'main.flex': 'import "library.flex"; fn main(){return value;}',
                                            'library.flex': 'global value=1;'})
        rejected(directory, 'source and output refer to the same file', destination='library.flex')
        os.link(directory / 'library.flex', directory / 'alias.flex')
        rejected(directory, 'source and output refer to the same file', destination='alias.flex')
        (directory / 'symlink').symlink_to('library.flex')
        rejected(directory, 'cannot open output', destination='symlink')
        directory = case('depth', {'main.flex': 'import "f1.flex"; fn main(){}'})
        for i in range(1, 64):
            (directory / f'f{i}.flex').write_text(f'import "f{i+1}.flex";' if i < 63 else '')
        accepted(directory)
        (directory / 'f63.flex').write_text('import "f64.flex";')
        (directory / 'f64.flex').write_text('')
        rejected(directory, 'import nesting exceeds 64')
        directory = case('file-count', {'main.flex': '', **{f'f{i}.flex': '' for i in range(256)}})
        imports = ''.join(f'import "f{i}.flex";' for i in range(255))
        (directory / 'main.flex').write_text(imports + 'fn main(){}')
        accepted(directory)
        (directory / 'main.flex').write_text(imports + 'import "f255.flex"; fn main(){}')
        rejected(directory, 'too many imported files')
        directory = case('source-limit', {'main.flex': 'import "large.flex"; fn main(){}',
                                         'large.flex': ' ' * 16777216})
        rejected(directory, 'combined source must be smaller than 16 MiB')
    print(f'{compiler.name}: {count} import checks passed', flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compilers', nargs='+', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    results = [{'compiler': str(p), 'checks': suite(p.resolve())} for p in args.compilers]
    total = sum(item['checks'] for item in results)
    print(f'Total: {total} import checks passed')
    if args.report:
        args.report.write_text(json.dumps({'results': results, 'total': total}, indent=2) + '\n')


if __name__ == '__main__':
    main()
