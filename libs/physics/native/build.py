"""Build the optional qualified six-participant Linux CPU physics backend."""
import argparse
import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
IMPORT = re.compile(r'(^\s*import\s+")([^"\n]+)("\s*;)', re.M)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_directory(workers):
    if workers not in (3, 6):
        raise ValueError('native physics supports three or six participants')
    return HERE if workers == 6 else HERE / 'reference'


def qualification(workers=6):
    return json.loads((source_directory(workers) / 'qualified.json').read_text())


def validate_sources(workers=6):
    q = qualification(workers)
    for name, digest in q['source_sha256'].items():
        if sha(source_directory(workers) / name) != digest:
            raise ValueError('unqualified native physics source: ' + name)
    common = qualification(6)
    for name, digest in common.get('support_sha256', {}).items():
        if sha(ROOT / name) != digest:
            raise ValueError('unqualified native physics support source: ' + name)
    if workers == 3 and sha(HERE / 'collision.flex') != common['source_sha256']['collision.flex']:
        raise ValueError('unqualified native physics collision source')
    return q


def solver_source(library_dir, collision='collision.flex', color='../color.flex',
                  poll='ph_native_poll', clock='ph_native_now', workers=3):
    """Bind host hooks by symbol, without importing any application code.

    Consumers supply polling/clock functions in their compilation unit. The
    standalone bundle provides no-op polling and CLOCK_MONOTONIC milliseconds.
    """
    for symbol in [poll, clock]:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', symbol):
            raise ValueError('native physics hooks must be function names')
    for path in [str(library_dir), collision, color]:
        if any(c in path for c in ['"', '\n', '\r']):
            raise ValueError('invalid native physics import/library path')
    validate_sources(workers)
    text = (source_directory(workers) / 'solver.flex').read_text()
    text = IMPORT.sub(lambda m: m[1] + (collision if Path(m[2]).name == 'collision.flex' else color) + m[3], text)
    text = re.sub(r'\bph_native_poll\b', poll, text)
    text = re.sub(r'\bph_native_now\b', clock, text)
    return text.replace('@BUILD@', str(library_dir))


def assembly(source):
    q = validate_sources()
    digest = lambda text: hashlib.sha256(text.encode()).hexdigest()
    if digest(source) != q['reference_assembly_sha256']:
        raise ValueError('unqualified native physics compiler assembly')
    spec = importlib.util.spec_from_file_location('_physics_contact_copy', HERE / 'contact_assembly.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = module.align_transform(module.exit_transform(module.entry_transform(source)))
    if digest(result) != q['copy_assembly_sha256']:
        raise ValueError('unqualified native physics contact-copy assembly')
    return result


def sources(workers=6):
    """Collect the standalone import closure, replacing only its solver entry."""
    selected = source_directory(workers) / 'solver.flex'
    pending = [ROOT / 'libs/physics/physics.flex', selected]
    found = set()
    while pending:
        path = pending.pop().resolve()
        if path == ROOT / 'libs/physics/solver.flex':
            path = selected
        if path in found:
            continue
        if not path.is_relative_to(ROOT):
            raise ValueError('native physics dependency escaped Flexscript')
        found.add(path)
        pending.extend((path.parent / m[2]).resolve() for m in IMPORT.finditer(path.read_text()))
    return found


def stage_sources(stage, final, workers=6):
    selected = source_directory(workers) / 'solver.flex'
    paths = sources(workers)
    special = {ROOT / 'libs/physics/physics.flex': Path('physics.flex'),
               selected: Path('solver.flex'), HERE / 'collision.flex': Path('collision.flex')}
    mapping = {p: special.get(p, Path('library') / p.relative_to(ROOT)) for p in paths}
    for source, relative in mapping.items():
        text = source.read_text()
        if source == selected:
            text = text.replace('@BUILD@', str(final))
        def relocate(match):
            dependency = (source.parent / match[2]).resolve()
            if dependency == ROOT / 'libs/physics/solver.flex':
                dependency = selected
            return match[1] + str(stage / mapping[dependency]) + match[3]
        text = IMPORT.sub(relocate, text)
        if relative == Path('physics.flex'):
            text += '''
// One active shared world per process. Stop helpers before releasing the arena.
fn ph_native_poll(){return 1;}
fn ph_native_now(){return net_now();}
fn ph_native_world(bodies,shapes,contacts,joints){
    let size=ph_world_bytes(bodies,shapes,contacts,joints);
    let w=syscall(9,0,size,3,33,-1,0);if w<0{return 0;}
    return ph_world_init(w,bodies,shapes,contacts,joints);
}
fn ph_native_start(w){if !phase_init() || !nk_init(){return 0;}return par_start(w);}
fn ph_native_stop(){return par_stop();}
fn ph_native_close(w){par_stop();return ph_world_close(w);}
'''
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)


def verify(folder):
    folder = Path(folder).resolve()
    manifest = json.loads((folder / 'manifest.json').read_text())
    if manifest.get('schema') != 'flexscript.native-physics.v1' or manifest.get('workers') not in (3, 6):
        raise ValueError('not a native physics bundle')
    artifacts = manifest.get('artifacts_sha256', {})
    if not {'contact.so', 'phases.so', 'physics.flex', 'solver.flex'}.issubset(artifacts):
        raise ValueError('native physics bundle lacks required artifacts')
    for name, digest in artifacts.items():
        path = (folder / name).resolve()
        if not path.is_relative_to(folder) or sha(path) != digest:
            raise ValueError('native physics artifact changed: ' + name)
    for name, digest in qualification(manifest['workers'])['libraries_sha256'].items():
        if sha(folder / name) != digest:
            raise ValueError('unqualified native physics numerical library: ' + name)
    return folder


def build(output_root=None, clang=None, workers=3):
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise RuntimeError('native physics requires Linux x86-64')
    q = validate_sources(workers)
    directory = source_directory(workers)
    clang = Path(clang or shutil.which('clang') or '/usr/bin/clang').resolve()
    files = sources(workers) | {p for p in HERE.rglob('*') if p.is_file() and p.suffix in ['.py', '.c', '.cpp', '.hpp', '.json', '.flex']} | {clang}
    inputs = {str(p): sha(p) for p in sorted(files)}
    key = hashlib.sha256(json.dumps(dict(inputs=inputs, workers=workers), sort_keys=True).encode()).hexdigest()
    output_root = Path(output_root or ROOT / 'target/physics-native').resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    final = output_root / key
    if final.exists():
        return verify(final)
    with tempfile.TemporaryDirectory(prefix='.building-', dir=output_root) as tmp:
        stage = Path(tmp)
        for name in q['source_sha256']:
            if Path(name).suffix not in ['.flex']:
                shutil.copy2(directory / name, stage / name)
        stage_sources(stage, final, workers)
        commands = []
        def run(command, name):
            commands.append(command)
            with (stage / name).open('w') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
            if result.returncode:
                raise RuntimeError('native physics build failed:\n' + (stage / name).read_text())
        if workers == 3:
            run([str(clang), '--driver-mode=g++', '-std=c++17', '-O3', '-march=znver3', '-shared', '-fPIC',
                 '-fvisibility=hidden', '-fno-fast-math', '-ffp-contract=off', str(stage / 'contact.cpp'),
                 '-o', str(stage / 'contact.so')], 'compile-contact.log')
        else:
            run([str(clang), '--driver-mode=g++', '-std=c++17', '-O3', '-march=znver3', '-fPIC',
                 '-fvisibility=hidden', '-fno-fast-math', '-ffp-contract=off', '-S', str(stage / 'contact.cpp'),
                 '-o', str(stage / 'contact-reference.s')], 'compile-assembly.log')
            (stage / 'contact-copy.s').write_text(assembly((stage / 'contact-reference.s').read_text()))
            run([str(clang), '--driver-mode=g++', '-march=znver3', '-shared', '-fPIC',
                 str(stage / 'contact-copy.s'), '-o', str(stage / 'contact.so')], 'compile-contact.log')
        run([str(clang), '-O3', '-march=znver3', '-shared', '-fPIC', '-fvisibility=hidden',
             '-fno-fast-math', '-ffp-contract=off', str(stage / 'phases.c'), '-o', str(stage / 'phases.so')], 'compile-phases.log')
        for name, digest in q['libraries_sha256'].items():
            if sha(stage / name) != digest:
                raise ValueError('unqualified native physics library output: ' + name)
        for file in stage.rglob('*.flex'):
            file.write_text(IMPORT.sub(lambda m: m[1] + m[2].replace(str(stage), str(final)) + m[3], file.read_text()))
        if any(sha(p) != h for p, h in inputs.items()):
            raise RuntimeError('native physics source changed during build')
        manifest = dict(schema='flexscript.native-physics.v1', workers=workers, inputs_sha256=inputs,
                        artifacts_sha256={str(p.relative_to(stage)): sha(p) for p in sorted(stage.rglob('*')) if p.is_file()},
                        commands=commands, limits=q['scope'])
        (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        try:
            stage.rename(final)
        except OSError as error:
            if error.errno not in (errno.EEXIST, errno.ENOTEMPTY):
                raise
    return verify(final)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path)
    parser.add_argument('--clang', type=Path)
    parser.add_argument('--workers', type=int, choices=(3, 6), default=3)
    args = parser.parse_args()
    print(json.dumps(dict(bundle=str(build(args.output_root, args.clang, args.workers)), workers=args.workers)))
