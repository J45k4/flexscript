#!/usr/bin/env python3
"""Native Linux threads, atomics, futex mutexes and fail-closed target boundaries."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
args = parser.parse_args()
compiler = args.compiler.resolve()
IMPORT = 'import ' + json.dumps(str(ROOT / 'libs/thread.flex')) + ';\n'

ATOMIC = '''
fn main(){
 if !thread_supported(){return 1;}
 let p=alloc(16);store64(p,0x1122334400000000);
 if atomic_load32(p)!=0 || atomic_load64(p)!=0x1122334400000000{return 2;}
 if atomic_exchange32(p,-1)!=0 || load64(p)!=0x11223344ffffffff{return 3;}
 if atomic_fetch_add32(p,1)!=0xffffffff || load64(p)!=0x1122334400000000{return 4;}
 if atomic_compare_exchange32(p,0x7777777700000000,0x100000005)!=0{return 5;}
 if load64(p)!=0x1122334400000005{return 6;}
 if atomic_compare_exchange32(p,6,9)!=5 || atomic_load32(p)!=5{return 7;}
 if atomic_compare_exchange32(p,5,0xffffffff)!=5 || atomic_load32(p)!=0xffffffff{return 8;}
 if atomic_exchange64(p,0x7fffffffffffffff)!=0x11223344ffffffff{return 9;}
 if atomic_fetch_add64(p,1)!=0x7fffffffffffffff || atomic_load64(p)!=0x8000000000000000{return 10;}
 if atomic_compare_exchange64(p,0,55)!=0x8000000000000000 || atomic_load64(p)!=0x8000000000000000{return 11;}
 if atomic_compare_exchange64(p,0x8000000000000000,-1)!=0x8000000000000000{return 12;}
 if atomic_fetch_add64(p,1)!= -1 || atomic_load64(p)!=0{return 13;}
 // Both arguments and live register locals survive the syscall lowering.
 let a=10;let b=20;let c=30;let d=40;let e=50;let f=60;let g=70;let h=80;
 if atomic_exchange64(p,123)!=0{return 14;}
 if a+b+c+d+e+f+g+h!=360{return 15;}
 syscall(11,p,16,0,0,0,0);return 0;
}
'''

CONCURRENT = '''
global counter=0;
fn worker(arg,b,c,d,e,f){
 if b || c || d || e || f{return -1;}
 let shared=load64(arg);let slot=load64(arg+8);let lock=load64(shared);
 let tid=syscall(186,0,0,0,0,0,0);store64(slot,tid);
 if syscall(39,0,0,0,0,0,0)!=load64(shared+8){return -2;}
 atomic_fetch_add64(shared+16,1);
 while !atomic_load32(shared+24){let r=syscall(202,shared+24,128,0,0,0,0);if r<0 && r!= -11 && r!= -4{return -3;}}
 let i=0;while i<10000{
  if mutex_lock(lock)<0{return -4;}counter=counter+1;if mutex_unlock(lock)<0{return -5;}
  atomic_fetch_add64(shared+32,1);atomic_fetch_add32(shared+40,1);
  let observed=atomic_load64(shared+48);
  while atomic_compare_exchange64(shared+48,observed,observed+1)!=observed{observed=atomic_load64(shared+48);}
  i=i+1;
 }
 // Exercise allocation, nested calls and private stack locals in workers.
 let p=alloc(8);if p<0{return -6;}store64(p,tid);let result=load64(p);syscall(11,p,8,0,0,0,0);
 return result+0x1234567800000000;
}
fn main(){
 let shared=alloc(64);let records=alloc(128);let tids=alloc(32);let handles=alloc(32);let out=alloc(8);
 let lock=mutex_create();if lock<0{return 1;}store64(shared,lock);store64(shared+8,syscall(39,0,0,0,0,0,0));
 let callback=native_callback(worker);let i=0;
 while i<4{store64(records+i*16,shared);store64(records+i*16+8,tids+i*8);let t=thread_start(callback,records+i*16);if t<0{syscall(231,2,0,0,0,0,0);}store64(handles+i*8,t);i=i+1;}
 while atomic_load64(shared+16)!=4{syscall(24,0,0,0,0,0,0);}
 // All four real kernel tasks are alive together, with distinct TIDs.
 i=0;while i<4{let j=i+1;let tid=load64(tids+i*8);if tid<=0 || tid==syscall(186,0,0,0,0,0,0){syscall(231,3,0,0,0,0,0);}while j<4{if tid==load64(tids+j*8){syscall(231,4,0,0,0,0,0);}j=j+1;}i=i+1;}
 if thread_destroy(load64(handles))!= -16{syscall(231,5,0,0,0,0,0);}
 atomic_exchange32(shared+24,1);syscall(202,shared+24,129,4,0,0,0);
 i=0;while i<4{let t=load64(handles+i*8);if thread_join(t,out)!=0{return 6;}if load64(out)!=load64(tids+i*8)+0x1234567800000000{return 7;}if thread_join(t,out)!= -22{return 8;}if thread_destroy(t)!=0{return 9;}i=i+1;}
 if counter!=40000 || atomic_load64(shared+32)!=40000 || atomic_load32(shared+40)!=40000 || atomic_load64(shared+48)!=40000{return 10;}
 if mutex_try_lock(lock)!=0 || mutex_try_lock(lock)!= -16 || mutex_destroy(lock)!= -16{return 11;}
 if mutex_unlock(lock)!=0 || mutex_unlock(lock)!= -22 || mutex_destroy(lock)!=0{return 12;}
 syscall(11,shared,64,0,0,0,0);syscall(11,records,128,0,0,0,0);syscall(11,tids,32,0,0,0,0);syscall(11,handles,32,0,0,0,0);syscall(11,out,8,0,0,0,0);return 0;
}
'''

LIFECYCLE = '''
fn leaf(a,b,c,d,e,f){return a^0xfeedface12345678;}
fn nested(a,b,c,d,e,f){
 let out=alloc(8);let child=thread_start_with_stack(native_callback(leaf),a,65537);if child<0{return 1;}
 if thread_join(child,out)<0{return 2;}let result=load64(out);if thread_destroy(child)<0{return 3;}
 syscall(11,out,8,0,0,0,0);return result;
}
fn self_join(a,b,c,d,e,f){
 let t=atomic_load64(a);while !t{syscall(24,0,0,0,0,0,0);t=atomic_load64(a);}return thread_join(t,0);
}
fn main(){
 let out=alloc(8);let callback=native_callback(leaf);
 if thread_start(0,0)!= -22 || thread_start_with_stack(callback,0,1)!= -22 || thread_start_with_stack(callback,0,0x7fffffffffffffff)!= -22{return 1;}
 if thread_join(0,0)!= -22 || thread_destroy(-1)!= -22 || mutex_lock(0)!= -22 || mutex_try_lock(1)!= -22{return 2;}
 let i=0;while i<128{
  let t=thread_start_with_stack(callback,i,65536);if t<0{return 3;}
  let x=i+100;let y=i+200;let z=i+300;
  if thread_join(t,out)!=0 || load64(out)!=(i^0xfeedface12345678){return 4;}
  if x+y+z!=i*3+600 || thread_destroy(t)!=0{return 5;}i=i+1;
 }
 let t=thread_start(native_callback(nested),0x1234);if t<0{return 6;}
 if thread_join(t,out)!=0 || load64(out)!=(0x1234^0xfeedface12345678) || thread_destroy(t)!=0{return 7;}
 let box=alloc(8);t=thread_start(native_callback(self_join),box);if t<0{return 8;}
 atomic_exchange64(box,t);if thread_join(t,out)!=0 || load64(out)!= -35 || thread_destroy(t)!=0{return 9;}
 t=thread_start(callback,0);if t<0 || thread_join(t,0)!=0 || thread_destroy(t)!=0{return 10;}
 syscall(11,box,8,0,0,0,0);syscall(11,out,8,0,0,0,0);return 0;
}
'''

ORDERING = '''
fn receiver(p,b,c,d,e,f){
 let i=0;while i<10000{
  while atomic_load32(p)!=1{syscall(24,0,0,0,0,0,0);}
  if load64(p+8)!=i || load64(p+16)!= ~i{return -1;}
  atomic_exchange32(p,0);i=i+1;
 }return i;
}
fn main(){
 let p=alloc(24);let out=alloc(8);let task=thread_start(native_callback(receiver),p);if task<0{return 1;}
 let i=0;while i<10000{
  while atomic_load32(p)!=0{syscall(24,0,0,0,0,0,0);}
  store64(p+8,i);store64(p+16,~i);atomic_exchange32(p,1);i=i+1;
 }
 if thread_join(task,out)!=0 || load64(out)!=10000 || thread_destroy(task)!=0{return 2;}
 syscall(11,p,24,0,0,0,0);syscall(11,out,8,0,0,0,0);return 0;
}
'''

RESOURCES = '''
fn waiting(gate,b,c,d,e,f){
 while !atomic_load32(gate){let r=syscall(202,gate,128,0,0,0,0);if r<0 && r!= -11 && r!= -4{return -1;}}
 return 0xabcdef0123456789;
}
fn joining(p,b,c,d,e,f){return thread_join(load64(p),load64(p+8));}
fn main(){
 let gate=alloc(8);let out=alloc(8);let vector=alloc(4096);let args=alloc(16);
 let t=thread_start(native_callback(waiting),gate);if t<0{return 1;}
 // Internal layout assertions check guard mappings and reclamation.
 let base=load64(t+32);let size=load64(t+40);
 if syscall(27,base,size,vector,0,0,0)!=0{return 2;}
 let pipe=alloc(8);if syscall(293,pipe,0,0,0,0,0)!=0{return 3;}
 let readfd=load64(pipe)&0xffffffff;let writefd=load64(pipe)>>32;
 store8(vector,42);if syscall(1,writefd,vector,1,0,0,0)!=1{return 4;}
 if syscall(0,readfd,base,1,0,0,0)!= -14{return 5;}
 if syscall(0,readfd,base+size-4096,1,0,0,0)!= -14{return 6;}
 if syscall(0,readfd,base+4096,1,0,0,0)!=1{return 7;}
 store64(args,t);store64(args+8,out);
 let joiner=thread_start(native_callback(joining),args);if joiner<0{return 8;}
 while atomic_load32(t+48)!=1{syscall(24,0,0,0,0,0,0);}
 if thread_join(t,0)!= -16 || thread_destroy(t)!= -16{return 9;}
 atomic_exchange32(gate,1);syscall(202,gate,129,1,0,0,0);
 if thread_join(joiner,vector)!=0 || load64(vector)!=0 || load64(out)!=0xabcdef0123456789{return 10;}
 if syscall(27,base,size,vector,0,0,0)!= -12{return 11;}
 if thread_destroy(t)!=0 || syscall(27,t,4096,vector,0,0,0)!= -12{return 12;}
 if thread_destroy(joiner)!=0{return 13;}
 syscall(3,readfd,0,0,0,0,0);syscall(3,writefd,0,0,0,0,0);
 syscall(11,gate,8,0,0,0,0);syscall(11,out,8,0,0,0,0);syscall(11,vector,4096,0,0,0,0);syscall(11,args,16,0,0,0,0);syscall(11,pipe,8,0,0,0,0);return 0;
}
'''

# A syscall boundary can fail after both stack and handle were allocated. A
# process-local seccomp filter deterministically rejects clone with EAGAIN.
# Repeating that path under a tight address-space limit detects leaked stacks.
FAILURE = '''
fn leaf(a,b,c,d,e,f){return 0;}
fn main(){
 let filter=alloc(32);let program=alloc(16);let limit=alloc(16);
 store64(filter,0x20);store64(filter+8,(56<<32)|0x01000015);
 store64(filter+16,(0x0005000b<<32)|6);store64(filter+24,(0x7fff0000<<32)|6);
 store64(program,4);store64(program+8,filter);
 if syscall(157,38,1,0,0,0,0)!=0 || syscall(317,1,0,program,0,0,0)!=0{return 1;}
 store64(limit,67108864);store64(limit+8,67108864);if syscall(160,9,limit,0,0,0,0)!=0{return 2;}
 let callback=native_callback(leaf);let i=0;
 while i<128{if thread_start(callback,0)!= -11{return 3;}i=i+1;}return 0;
}
'''

UNSUPPORTED = '''
fn main(){if thread_supported(){return 1;}if thread_start(1,0)!= -38 || thread_join(1,0)!= -38 || thread_destroy(1)!= -38 || mutex_create()!= -38 || mutex_lock(1)!= -38{return 2;}return 0;}
'''

checks = 0


def run(command, expected=0):
    global checks
    result = subprocess.run([str(x) for x in command], capture_output=True, timeout=40)
    if result.returncode != expected:
        raise AssertionError((command, result.returncode, result.stdout.decode(), result.stderr.decode()))
    checks += 1
    return result


with tempfile.TemporaryDirectory(prefix='thread-', dir=ROOT / 'build') as directory:
    work = Path(directory)
    for name, body in [('atomic', ATOMIC), ('concurrent', CONCURRENT), ('lifecycle', LIFECYCLE), ('ordering', ORDERING), ('resources', RESOURCES), ('failure', FAILURE)]:
        source = work / (name + '.flex')
        source.write_text(IMPORT + body)
        for pipeline in ['ir', 'direct']:
            for optimization in ['basic', 'none']:
                binary = work / f'{name}-{pipeline}-{optimization}'
                run([compiler, '--native-pipeline', pipeline, '--ir-opt', optimization, source, '-o', binary])
                run([binary])
        print('PASS', name, flush=True)
    source = work / 'unsupported.flex'
    source.write_text(IMPORT + UNSUPPORTED)
    for mode in ['--interpret', '--jit']:
        run([compiler, 'run', mode, source])
    binary = work / 'reference'
    run([compiler, '--lowering-mode', 'reference', source, '-o', binary])
    run([binary])
    # Actual atomic operations must trap rather than execute a non-atomic body.
    source.write_text(IMPORT + 'fn main(){return atomic_load64(alloc(8));}')
    result = subprocess.run([str(compiler), 'run', '--interpret', str(source)], capture_output=True, timeout=20)
    assert result.returncode != 0, result
    checks += 1
    # The sequential checker must not certify concurrency through fallback bodies.
    result = subprocess.run([str(compiler), 'verify', str(source)], capture_output=True, timeout=20)
    assert result.returncode != 0 and b'lowering declarations' in result.stdout, result
    checks += 1
    # Existing callbacks reject VM and non-native targets clearly.
    source.write_text(IMPORT + LIFECYCLE)
    for flags in [['run', '--interpret'], ['--target', 'linux-arm64'], ['--target', 'wasm32']]:
        command = [str(compiler), *flags, str(source)]
        if flags[0] != 'run':
            command += ['-o', str(work / 'rejected')]
        result = subprocess.run(command, capture_output=True, timeout=20)
        assert result.returncode != 0 and b'native_callback requires native x86-64 code' in result.stderr, result
        checks += 1
    for example in sorted((ROOT / 'examples/thread').glob('*.flex')):
        run([compiler, example, '-o', work / 'example'])
        run([work / 'example'])
print(f'PASS: {checks} thread build/execution/boundary checks; four native pipeline/optimization combinations')
