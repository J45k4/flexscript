#!/usr/bin/env python3
"""Check writable literal identity and explicit shared native literal pools."""
import os,random,string,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];compiler=Path(os.environ.get('FLEX_COMPILER','build/flex')).resolve();checks=0
with tempfile.TemporaryDirectory(prefix='native-literals-',dir=ROOT/'build') as directory:
 work=Path(directory);source=work/'test.flex';binary=work/'app'
 def build(text,mode=None):
  source.write_text(text);args=[str(compiler)]
  if mode:args+=['--native-literals',mode]
  subprocess.run(args+[str(source),'-o',str(binary)],check=True,capture_output=True)
  return binary.read_bytes()
 def run(status=42,stdout=b''):
  result=subprocess.run([str(binary)],capture_output=True,timeout=5);assert (result.returncode,result.stdout)==(status,stdout),(result.returncode,result.stdout,result.stderr)
 # Source sites stay distinct and the same site's mutated storage persists.
 text='fn first(){return "ab\\0cd";}fn second(){return "ab\\0cd";}fn main(){let a=first();let b=second();if a==b{return 1;}store8(a+3,90);if load8(first()+3)!=90 || load8(b+3)!=99{return 2;}syscall(1,1,a,6,0,0,0);return 42;}'
 for mode in (None,'writable'):build(text,mode);run(stdout=b'ab\0Zd\0');checks+=1
 # Full binary bytes participate in deduplication, including bytes after NUL.
 text='fn first(){return "ab\\0cd";}fn main(){let a=first();let b="ab\\0cd";let c="ab\\0ef";if a!=b || a==c{return 1;}if load8(c+3)!=101{return 2;}syscall(1,1,a,6,0,0,0);return 42;}'
 build(text,'shared');run(stdout=b'ab\0cd\0');checks+=1
 # Exercise collisions in both the hash-table slot and the complete FNV hash.
 def fnv(value):
  h=2166136261
  for c in value+b'\0':h=((h^c)*16777619)&0xffffffff
  return h
 rng=random.Random(1234);seen={};pair=None
 for _ in range(250000):
  value=''.join(rng.choices(string.ascii_letters,k=10)).encode();h=fnv(value)
  if h in seen and value!=seen[h]:pair=(seen[h].decode(),value.decode());break
  seen[h]=value
 assert pair,'deterministic FNV collision fixture was not found'
 a,b=pair;build(f'fn main(){{let a="{a}";let b="{b}";let c="{a}";if a==b || a!=c{{return 1;}}if load8(a)!={ord(a[0])} || load8(b)!={ord(b[0])}{{return 2;}}return 42;}}','shared');run();checks+=1
 # Large repeated literals and branches test relocation replay and the size win.
 body='let total=0;let i=0;while i<3{'
 for i in range(80):body+=f'if i!={i}{{let p="repeated literal payload for native pooling";total=total+load8(p);}}'
 body+='i=i+1;}return total%200;'
 text='fn unused(){return "unreachable_literal_marker";}fn main(){'+body+'}'
 reference=build(text,'writable');ref_run=subprocess.run([str(binary)],capture_output=True)
 pooled=build(text,'shared');pool_run=subprocess.run([str(binary)],capture_output=True)
 assert ref_run.returncode==pool_run.returncode and len(pooled)<len(reference)-2000,(len(reference),len(pooled))
 assert b'unreachable_literal_marker' not in pooled
 assert build(text,'shared')==pooled,'literal pool layout is nondeterministic';checks+=3
 original=binary.read_bytes()
 for flags in (['--native-literals','bad'],['--native-literals','shared','--native-literals','writable'],['--native-literals','shared','--native-pipeline','direct'],['--native-literals','shared','--target','wasm32']):
  result=subprocess.run([str(compiler),*flags,str(source),'-o',str(binary)],capture_output=True)
  assert result.returncode!=0 and binary.read_bytes()==original,(flags,result.stderr);checks+=1
print(f'PASS {checks} native literal checks: writable identity/mutation, binary strings, full hash collision, branch replay, reachability, deterministic output and option validation')
