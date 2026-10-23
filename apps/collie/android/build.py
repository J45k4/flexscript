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


def flatten(entries, transformed=None):
    """Preserve source bodies; only reorder module globals and remove imports."""
    seen, declarations, functions = set(), [], []
    for entry in entries:
        def visit(path):
            path = path.resolve()
            if path in seen:
                return
            assert path.is_relative_to(ROOT), path
            seen.add(path)
            text = (transformed or {}).get(path, path.read_text())
            imports = list(re.finditer(r'(?m)^\s*import\s+"([^"]+)"\s*;', text))
            for match in imports:
                visit(path.parent / match[1])
            text = re.sub(r'(?m)^\s*(?:import|extend)\s+"([^"]+)"\s*;', '', text)
            tokens = list(TOKEN.finditer(text))
            begin, level, function = 0, 0, False
            for token in tokens:
                word = token[0]
                if word.startswith('"') or word.startswith('//'):
                    continue
                if level == 0 and word in ('fn', 'view'):
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


def generate(out, compiler):
    # Run the shared view compiler on a small, normally imported UI program.
    # Exported modules are already validated by the same ordinary compiler;
    # flattening only adapts their host ABI, as for all other engine modules.
    ui_entry = out / 'ui-entry.flex'
    ui_entry.write_text('import '+json.dumps(str(ROOT/'apps/collie/ui/app.flex'))+';\n'
                        'extend '+json.dumps(str(ROOT/'libs/ui/syntax.flex'))+' with "source";\n'
                        'fn main(){return 0;}\n')
    generated = subprocess.run([str(compiler.resolve()), str(ui_entry), '-o', str(out/'ui-check')],
                               cwd=ROOT, capture_output=True)
    transformed = {}
    at = 0
    diagnostics = []
    # Length-prefixed UTF-8 modules avoid re-escaping/scanning generated source
    # in the bounded compile-time VM. No screen/compiler output is re-parsed by
    # an unrelated DSL implementation on the build host.
    while at < len(generated.stderr):
        end = generated.stderr.find(b'\n', at)
        if end < 0: end = len(generated.stderr)
        line = generated.stderr[at:end]
        at = end + 1
        if line.startswith(b'FLEXSCRIPT_UI_MODULE '):
            path_size, source_size = map(int, line.split()[1:])
            assert 0 < path_size < 16384 and 0 <= source_size < 1048576
            path = Path(generated.stderr[at:at+path_size].decode()).resolve()
            at += path_size
            assert path.is_relative_to(ROOT) and at+source_size <= len(generated.stderr)
            transformed[path] = generated.stderr[at:at+source_size].decode()
            at += source_size
            assert generated.stderr[at:at+1] == b'\n'
            at += 1
        else:
            diagnostics.append(line.decode(errors='replace'))
    if generated.returncode:
        raise RuntimeError('\n'.join(diagnostics))
    for line in diagnostics:
        if line: print(line)
    assert ROOT/'apps/collie/ui/app.flex' in transformed, 'UI compiler did not export the screen'
    declarations, functions = flatten([
        ROOT / 'compiler/main.flex',
        ROOT / 'apps/collie/adapters/linux.flex',
        ROOT / 'apps/collie/providers/codex.flex',
        ROOT / 'apps/collie/core/scheduler.flex',
        ROOT / 'apps/collie/core/checkpoint.flex',
        ROOT / 'apps/collie/core/recall.flex',
        ROOT / 'apps/collie/providers/stream.flex',
        ROOT / 'apps/collie/providers/images.flex',
    ], transformed)
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
    functions = functions.replace('vm_execute(main_index);', 'cv_execute(main_index);')
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
    guest = (HERE / 'guest-files.flex').read_text() + '\n' + (ROOT/'apps/collie/guest/workers.flex').read_text() + '\n' + (ROOT/'apps/collie/guest/memory.flex').read_text()
    embedded = 'fn ca_guest_extra(){return '+json.dumps(guest, ensure_ascii=False)+';}\n'
    source = out / 'engine-generated.flex'
    source.write_text(declarations+'\n'+extra_globals+'\n'+functions+'\n'+stubs+'\n'+
                      reset+embedded+extra_functions+'\nfn main(){return 0;}\n')
    # A small UI image has its own globals and allocator. Native UI evaluation
    # must never wait for the compiler/guest VM's process-wide engine lock.
    ui_globals, ui_functions = flatten([ROOT/'apps/collie/ui/app.flex'], transformed)
    ui_names = {'alloc':'uh_alloc', 'syscall':'uh_syscall'}
    ui_names.update({name:'uh_disabled_'+name for name in arities})
    def ui_rewrite(text):
        return ''.join(ui_names.get(t[0],t[0]) if re.fullmatch(r'[A-Za-z_]\w*',t[0]) else t[0]
                       for t in TOKEN.finditer(text))
    ui_globals, ui_functions = ui_rewrite(ui_globals), ui_rewrite(ui_functions)
    ui_variables = re.findall(r'\bglobal\s+([A-Za-z_]\w*)\s*=\s*([^;]+);',ui_globals)
    ui_reset = 'fn uh_reset(){'+''.join(f'{name}={value};' for name,value in ui_variables)+'return 0;}\n'
    ui_stubs = stubs.replace('ca_disabled_', 'uh_disabled_')
    ui_source = out/'ui-generated.flex'
    ui_source.write_text(ui_globals+'\nglobal uh_bridge=0;global uh_packet=0;\n'+ui_functions+'\n'+ui_stubs+'\n'+ui_reset+
        'fn uh_syscall(n,a,b,c,d,e,f){store64(uh_packet,a);store64(uh_packet+8,b);store64(uh_packet+16,c);store64(uh_packet+24,d);store64(uh_packet+32,e);store64(uh_packet+40,f);return ffi_call(uh_bridge,n,uh_packet,0,0,0,0); }\n'
        'fn uh_alloc(n){return uh_syscall(1000,n,0,0,0,0,0); }\n'
        'fn uh_entry(op,text,bridge,packet){uh_reset();uh_bridge=bridge;uh_packet=packet;let request=c_json(text);let result=0;if op==10{result=cu_permissions(request);}else{result=cu_ui_host(request);}return j_dump(result); }\n'
        'fn main(){return 0;}\n')
    return source,ui_source


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
    source,ui_source = generate(out, args.compiler)
    run([args.compiler.resolve(), '--target','android-arm64',source,'-o',out/'engine.o'])
    flags = ['clang','--target=aarch64-linux-android26','-ffreestanding','-fPIC',
             '-fno-stack-protector','-fno-builtin','-fvisibility=hidden',
             '-mgeneral-regs-only','-Wall','-Wextra','-Werror','-O2']
    run([args.compiler.resolve(), '--target','android-arm64',ui_source,'-o',out/'ui.o'])
    run([*flags,'-c',HERE/'ui-host.c','-o',out/'ui-host.o'])
    run([*flags,'-Dcollie_call=collie_ui_call','-c',HERE/'native-test.c','-o',out/'ui-test.o'])
    run(['ld.lld','-static','-e','_start',out/'ui-test.o',out/'ui-host.o',out/'ui.o','-o',out/'ui-native-test'])
    run(['ld.lld','-shared','-Bsymbolic','-z','defs','-z','relro','-z','now','-z','noexecstack',
         '-z','max-page-size=16384','--hash-style=both','-soname','libcollie_ui.so',
         out/'ui-host.o',out/'ui.o','-o',out/'libcollie_ui.so'])
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
    # Deleted platform classes must not survive incremental APK builds.
    for directory in (classes, dex):
        if directory.exists(): shutil.rmtree(directory)
        directory.mkdir()
    java = lambda name: shutil.which(name,path=env['PATH'])
    java_sources = sorted(HERE.glob('*.java'))
    if args.debug: java_sources += sorted((ROOT/'apps/collie/tests/android').glob('*.java'))
    run([java('javac'),'-source','8','-target','8','-classpath',android,
         '-d',classes,*java_sources])
    run([tools/'d8','--min-api','26','--lib',android,'--output',dex,*sorted(classes.rglob('*.class'))])
    manifest=out/'AndroidManifest.xml'
    manifest.write_text((HERE/'AndroidManifest.xml').read_text().replace('android:debuggable="false"', 'android:debuggable="'+str(args.debug).lower()+'"'))
    run([tools/'aapt2','compile','--dir',HERE/'res','-o',out/'resources.zip'])
    run([tools/'aapt2','link','-I',android,'--manifest',manifest,out/'resources.zip',
         '--version-code','1','--version-name','0.1.0','-o',out/'unsigned.apk'])
    with zipfile.ZipFile(out/'unsigned.apk','a',compression=zipfile.ZIP_STORED) as apk:
        apk.write(dex/'classes.dex','classes.dex')
        apk.write(out/'libcollie.so','lib/arm64-v8a/libcollie.so')
        apk.write(out/'libcollie_ui.so','lib/arm64-v8a/libcollie_ui.so')
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
