#!/usr/bin/env python3
"""Package Collie's shared Flexscript engine in an Android application.

Python runs only on the build machine. The APK contains Java, a small C host,
and the existing Flexscript compiler/interpreter/provider/FlexDB compiled to ARM64.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|[A-Za-z_]\w*|\s+|.', re.S)


def flatten(entries):
    """Preserve source bodies; only reorder module globals and remove imports."""
    seen, declarations, functions = set(), [], []
    for entry in entries:
        def visit(path):
            path = path.resolve()
            if path in seen:
                return
            assert path.is_relative_to(ROOT), path
            seen.add(path)
            text = path.read_text()
            imports = list(re.finditer(r'(?m)^\s*import\s+"([^"]+)"\s*;', text))
            for match in imports:
                visit(path.parent / match[1])
            text = re.sub(r'(?m)^\s*import\s+"([^"]+)"\s*;', '', text)
            tokens = list(TOKEN.finditer(text))
            begin, level, function = 0, 0, False
            for token in tokens:
                word = token[0]
                if word.startswith('"') or word.startswith('//'):
                    continue
                if level == 0 and word == 'fn':
                    function = True
                if word == '{':
                    level += 1
                elif word == '}':
                    level -= 1
                    if level == 0 and function:
                        functions.append(text[begin:token.end()])
                        begin, function = token.end(), False
                elif word == ';' and level == 0:
                    declarations.append(text[begin:token.end()])
                    begin = token.end()
            assert level == 0 and not function, path
        visit(entry)
    return '\n'.join(declarations), '\n'.join(functions)


def generate(out):
    declarations, functions = flatten([
        ROOT / 'compiler/main.flex',
        ROOT / 'apps/collie/adapters/linux.flex',
        ROOT / 'apps/collie/providers/codex.flex',
    ])
    # Keep the original compiler and VM source shared. Only trusted HOST calls
    # change ABI; strings containing model instructions/guest source stay intact.
    names = {'alloc': 'ca_alloc', 'syscall': 'ca_host_syscall', 'main': 'ca_cli_main'}
    arities = {'ffi_open': 1, 'ffi_symbol': 2, 'ffi_call': 7,
               'ffi_call_i32': 7, 'ffi_call_u32': 7}
    names.update({name: 'ca_disabled_' + name for name in arities})
    def rewrite(text):
        return ''.join(names.get(t[0], t[0]) if re.fullmatch(r'[A-Za-z_]\w*', t[0])
                       else t[0] for t in TOKEN.finditer(text))
    declarations, functions = rewrite(declarations), rewrite(functions)
    functions = re.sub(r'(\bfn next\(\)\s*\{)', r'\1ca_compile_tick();', functions)
    functions = functions.replace('vm_execute(main_index);', 'ca_host(1003,0,0,0,0,0,0);vm_execute(main_index);')
    globals_ = re.findall(r'\bglobal\s+([A-Za-z_]\w*)\s*=\s*([^;]+);', declarations)
    assert globals_ and len(globals_) == sum(t[0] == 'global' for t in TOKEN.finditer(declarations)), 'unsupported global declaration'
    stubs = '\n'.join('fn ca_disabled_' + name + '(' +
                      ','.join('a'+str(i) for i in range(count)) + '){return 0;}'
                      for name, count in arities.items())
    # Engine globals also reset between native calls, including after a failed
    # compilation. All per-call mappings belong to the bounded native arena.
    extra_globals, extra_functions = flatten([HERE / 'engine.flex'])
    assert not (HERE / 'engine.flex').read_text().lstrip().startswith('import'), 'engine must use the shared flattened modules'
    globals_ += re.findall(r'\bglobal\s+([A-Za-z_]\w*)\s*=\s*([^;]+);', extra_globals)
    reset = 'fn ca_reset_globals(){\n' + '\n'.join(f'{n}={v};' for n,v in globals_) + '\n}\n'
    guest = (HERE / 'guest-files.flex').read_text()
    embedded = 'fn ca_guest_extra(){return '+json.dumps(guest, ensure_ascii=False)+';}\n'
    source = out / 'engine-generated.flex'
    source.write_text(declarations+'\n'+extra_globals+'\n'+functions+'\n'+stubs+'\n'+
                      reset+embedded+extra_functions+'\nfn main(){return 0;}\n')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=ROOT/'build/collie-android')
    parser.add_argument('--sdk', type=Path, default=Path(os.environ.get('ANDROID_HOME','/opt/android-sdk')))
    parser.add_argument('--java-home', type=Path)
    parser.add_argument('--native-only', action='store_true')
    parser.add_argument('--debug', action='store_true', help='Enable private ADB testing; development only')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    if args.java_home:
        env['JAVA_HOME'] = str(args.java_home.resolve())
        env['PATH'] = str(args.java_home.resolve()/'bin')+os.pathsep+env['PATH']
    def run(command):
        subprocess.run(list(map(str, command)), cwd=ROOT, env=env, check=True)
    source = generate(out)
    run([args.compiler.resolve(), '--target','android-arm64',source,'-o',out/'engine.o'])
    flags = ['clang','--target=aarch64-linux-android26','-ffreestanding','-fPIC',
             '-fno-stack-protector','-fno-builtin','-fvisibility=hidden',
             '-mgeneral-regs-only','-Wall','-Wextra','-Werror','-O2']
    run([*flags,'-c',HERE/'host.c','-o',out/'host.o'])
    run([*flags,'-c',HERE/'native-test.c','-o',out/'native-test.o'])
    run(['ld.lld','-static','-e','_start',out/'native-test.o',out/'host.o',
         out/'engine.o','-o',out/'native-test'])
    run(['ld.lld','-shared','-z','defs','-z','relro','-z','now','-z','noexecstack',
         '-z','max-page-size=16384','--hash-style=both','-soname','libcollie.so',
         out/'host.o',out/'engine.o','-o',out/'libcollie.so'])
    if args.native_only:
        print(out/'native-test')
        return
    sdk = args.sdk.resolve()
    tools = sdk/'build-tools/36.1.0'
    android = sdk/'platforms/android-36/android.jar'
    assert android.is_file(), android
    classes, dex = out/'classes', out/'dex'
    classes.mkdir(exist_ok=True)
    dex.mkdir(exist_ok=True)
    java = lambda name: shutil.which(name,path=env['PATH'])
    run([java('javac'),'-source','8','-target','8','-classpath',android,
         '-d',classes,*sorted(HERE.glob('*.java'))])
    run([tools/'d8','--min-api','26','--lib',android,'--output',dex,*sorted(classes.rglob('*.class'))])
    manifest=out/'AndroidManifest.xml'
    manifest.write_text((HERE/'AndroidManifest.xml').read_text().replace('android:debuggable="false"', 'android:debuggable="'+str(args.debug).lower()+'"'))
    run([tools/'aapt2','compile','--dir',HERE/'res','-o',out/'resources.zip'])
    run([tools/'aapt2','link','-I',android,'--manifest',manifest,out/'resources.zip',
         '--version-code','1','--version-name','0.1.0','-o',out/'unsigned.apk'])
    with zipfile.ZipFile(out/'unsigned.apk','a',compression=zipfile.ZIP_STORED) as apk:
        apk.write(dex/'classes.dex','classes.dex')
        apk.write(out/'libcollie.so','lib/arm64-v8a/libcollie.so')
    run([tools/'zipalign','-f','-P','16','4',out/'unsigned.apk',out/'aligned.apk'])
    key = out/'development.keystore'
    if not key.exists():
        run([java('keytool'),'-genkeypair','-noprompt','-keystore',key,
             '-storepass','android','-keypass','android','-alias','development',
             '-dname','CN=Collie Development','-keyalg','RSA','-keysize','2048','-validity','3650'])
    apk = out/'collie.apk'
    run([tools/'apksigner','sign','--ks',key,'--ks-key-alias','development',
         '--ks-pass','pass:android','--key-pass','pass:android','--out',apk,out/'aligned.apk'])
    run([tools/'apksigner','verify',apk])
    run([tools/'zipalign','-c','-P','16','4',apk])
    report = dict(apk=str(apk),sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                  package='org.flexscript.collie',abi='arm64-v8a',debug=args.debug,
                  compiler=str(args.compiler.resolve()),engine='shared Flexscript frontend, checked interpreter, provider protocol and FlexDB')
    (out/'build.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
