#!/usr/bin/env python3
"""Check the System V six-word callback used by the desktop native broker."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler',type=Path,required=True);a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='callback-',dir=ROOT/'build') as directory:
 d=Path(directory);source=ROOT/'tests/tooling/native-callback.flex'
 subprocess.run(['cc','-shared','-fPIC','-O2',str(ROOT/'tests/tooling/native-callback.c'),'-o',str(d/'fixture.so')],check=True)
 for pipeline in ['direct','ir']:
  for optimization in ['basic','none']:
   subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'--ir-opt',optimization,str(source),'-o',str(d/'callback')],check=True)
   subprocess.run([str(d/'callback'),str(d/'fixture.so')],check=True)
 # The target is reachable only through its address, escapes a returned factory,
 # calls another function, owns locals and mutates globals through reentrant FFI.
 extended=d/'extended.flex';extended.write_text('''
 global visits=0;
 fn mix(a,b,c,d,e,f){return a+b*2+c*3+d*4+e*5+f*6;}
 fn callback(a,b,c,d,e,f){let kept=alloc(8);store64(kept,a);visits=visits+1;let value=mix(load64(kept),b,c,d,e,f);syscall(11,kept,8,0,0,0,0);return value;}
 fn factory(){let before=visits;let ptr=native_callback(callback);if visits!=before{return 0;}return ptr;}
 fn unused(a,b,c,d,e,f){return 1234;}
 fn main(argc,argv){let library=ffi_open(load64(argv+8));let run=ffi_symbol(library,"invoke");let x=124;let y=456;let ptr=factory();let i=0;while i<1000{if ffi_call(run,ptr,0,0,0,0,0)!=1{return 1;}i=i+1;}if x!=124 || y!=456 || visits!=3000{return 2;}return 0;}
 ''')
 for pipeline in ['direct','ir']:
  for optimization in ['basic','none']:
   subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,'--ir-opt',optimization,str(extended),'-o',str(d/'extended')],check=True)
   subprocess.run([str(d/'extended'),str(d/'fixture.so')],check=True)
 # View/program transforms inspect the containing source graph in a restricted
 # VM. Native callback addresses are inspectable metadata there, never callable
 # VM pointers. This covers ordinary `extend` users importing GUI libraries.
 extension=d/'inspect.flex';extension.write_text('import '+json.dumps(str(ROOT/'compiler/transform-sdk.flex'))+''';
 fn transform_program(context,version){ext_init(context,version);let f=ext_find_function("factory");if f<0 || !(ext_function_effects(f)&32){ext_error("native callback capability missing from snapshot");}let i=0;let found=0;while i<ext_function_instruction_count(f){if ext_op(f,i)==29{let call=ext_arg(f,i);if ext_call_arity(call)!=6{ext_error("callback arity metadata differs");}found=1;}i=i+1;}if !found{ext_error("callback address missing from snapshot");}return ext_finish();}
 ''')
 transformed=d/'transformed.flex';transformed.write_text('extend '+json.dumps(str(extension))+';\n'+extended.read_text())
 for pipeline in ['direct','ir']:
  subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(transformed),'-o',str(d/'transformed')],check=True)
  subprocess.run([str(d/'transformed'),str(d/'fixture.so')],check=True)
 forbidden=d/'forbidden.flex';forbidden.write_text('fn callback(a,b,c,d,e,f){return a;}fn transform_program(context,version){return native_callback(callback);}')
 rejected=d/'rejected-transform.flex';rejected.write_text('extend '+json.dumps(str(forbidden))+';fn main(){return 0;}')
 r=subprocess.run([str(a.compiler.resolve()),str(rejected),'-o',str(d/'forbidden')],capture_output=True)
 assert r.returncode and b'native_callback requires native x86-64 code' in r.stderr and not (d/'forbidden').exists(),r.stderr
 r=subprocess.run([str(a.compiler.resolve()),'--target','linux-arm64',str(source),'-o',str(d/'rejected.fir')],capture_output=True)
 assert r.returncode and b'native_callback requires native x86-64 code' in r.stderr,(r.returncode,r.stderr)
 assert not (d/'rejected.fir').exists()
 for declaration in ['fn wrong(a){return a;}fn main(){return native_callback(wrong);}', 'fn main(){return native_callback(missing);}']:
  invalid=d/'invalid.flex';invalid.write_text(declaration)
  for pipeline in ['ir','direct']:
   target=d/'invalid';r=subprocess.run([str(a.compiler.resolve()),'--native-pipeline',pipeline,str(invalid),'-o',str(target)],capture_output=True)
   assert r.returncode and not target.exists(),(pipeline,r.stderr)
print('PASS IR/direct callbacks, optimization modes, escaped pointer reachability, 18012 native callbacks, semantic-transform metadata, nested calls/locals/globals and portable/invalid/transform-execution rejection')
