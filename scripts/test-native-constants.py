#!/usr/bin/env python3
"""Independent word oracle for native constants, local registers and expressions."""
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
MASK = (1<<64)-1
MIN = -(1<<63)
CONSTANTS = [MIN,-4294967296,-2147483649,-2147483648,-129,-128,-127,-3,-2,-1,
             0,1,2,3,4,7,8,15,16,31,32,63,64,127,128,129,255,256,65535,65536,
             2147483647,2147483648,4294967295,4294967296,1<<40,1<<62,(1<<63)-1]
OPS = ['+','-','*','&','|','^','<<','>>','==','!=','<','>','<=','>=','/','%']


def signed(v):
    v &= MASK
    return v-(1<<64) if v>>63 else v


def result(a,b,op):
    if op in ['/', '%']:
        if b == 0 or (a == MIN and b == -1):
            return 77
        q = abs(a)//abs(b)*(1 if (a<0)==(b<0) else -1)
        return q if op=='/' else a-q*b
    if op == '<<': return (a << (b&63)) & MASK
    if op == '>>': return a >> (b&63)
    return int(eval(f'a {op} b',{},dict(a=a,b=b)))


def main():
    compiler = os.environ.get('FLEX_COMPILER',str(ROOT/'build/flex'))
    rng = random.Random(734)
    values = CONSTANTS+[signed(rng.getrandbits(64)) for _ in range(1000)]
    with tempfile.TemporaryDirectory(prefix='flex-constants-') as temp:
        temp = Path(temp)
        source = ['global seen=0;fn side(v){seen=seen+1;return v;}']
        for i,b in enumerate(CONSTANTS):
            lines = [f'fn calc{i}(a,p){{']
            for j,op in enumerate(OPS):
                expr = f'a {op} ({b})'
                if op in ['/', '%']:
                    expr = f'77; if ({b})!=0 && !(a==({MIN}) && ({b})==(-1)) {{v=a {op} ({b});}}'
                    lines.append(f'let v{j}={expr.replace("v=",f"v{j}=")};store64(p+{j*8},v{j});')
                else:
                    lines.append(f'store64(p+{j*8},{expr});')
            lines.append('return 0;}')
            source.extend(lines)
        source.append('fn dynamic(a,b,p){')
        for j,op in enumerate(OPS):
            if op in ['/', '%']:
                source.append(f'let v{j}=77;if b!=0 && !(a==0x8000000000000000 && b==(-1)){{v{j}=a {op} b;}}store64(p+{j*8},v{j});')
            else:
                source.append(f'store64(p+{j*8},a {op} b);')
        source.append('return 0;}')
        # Nested RHS expressions exercise temporary-register lifetimes. Calls
        # and inline syscalls must preserve locals and invalidate scratch R11.
        expression_ops = OPS[:-2]
        def expression(depth):
            if not depth:
                name = rng.choice(list('abcdefghj'))
                return name, lambda env: env[name], 0
            left, left_eval, lc = expression(depth-1)
            right, right_eval, rc = expression(depth-1)
            op = rng.choice(expression_ops)
            text = f'({left} {op} {right})'
            evaluate = lambda env: signed(result(left_eval(env),right_eval(env),op))
            if rng.randrange(4)==0:
                return f'side({text})', evaluate, lc+rc+1
            if rng.randrange(4)==0:
                text = f'({text}+(syscall(39,0,0,0,0,0,0)&0))'
            return text, evaluate, lc+rc
        complex_cases = [expression(4) for _ in range(48)]
        for j,(text,_,_) in enumerate(complex_cases):
            source.append(f'fn nested{j}(a,b,c,d,e,f){{let g=a+b;let h=c^d;let j=e-f;return {text};}}')
        # Constant-folded left operands and side effects with zero/one RHS.
        source.append('fn folded(p){')
        folded=[]
        for a in [-1,0,MIN,7,(1<<63)-1]:
            for b in CONSTANTS:
                for op in OPS:
                    if op in ['/', '%'] and (b==0 or(a==MIN and b==-1)):continue
                    source.append(f'store64(p+{len(folded)*8},({a}) {op} ({b}));')
                    folded.append(result(a,b,op)&MASK)
        source.append('return 0;}')
        nbytes=len(OPS)*len(CONSTANTS)*8
        source.append(f'fn main(argc,argv){{let fd=syscall(2,load64(argv+8),0,0,0,0,0);let word=alloc(8);let out=alloc({max(nbytes,len(folded)*8)});let n=syscall(0,fd,word,8,0,0,0);while n==8{{let a=load64(word);')
        for i in range(len(CONSTANTS)):
            source.append(f'calc{i}(a,out+{i*len(OPS)*8});')
        source.append(f'syscall(1,1,out,{nbytes},0,0,0);dynamic(a,a^0xdeadbeef12345678,out);syscall(1,1,out,{len(OPS)*8},0,0,0);seen=0;')
        for j in range(len(complex_cases)):
            source.append(f'store64(out+{j*8},nested{j}(a,a^0xdeadbeef12345678,a+37,a*19,a>>7,a&0xffff));')
        source.append(f'if seen!={sum(c for _,_,c in complex_cases)}{{return 9;}}syscall(1,1,out,{len(complex_cases)*8},0,0,0);seen=0;n=syscall(0,fd,word,8,0,0,0);}}folded(out);syscall(1,1,out,{len(folded)*8},0,0,0);if side(13)*0!=0 || side(-8)/1!=(-8) || side(9)%1!=0 || seen!=3{{return 7;}}return 0;}}')
        path=temp/'test.flex';path.write_text('\n'.join(source).replace(str(MIN),'0x8000000000000000').replace('};store64','}store64'))
        inp=temp/'input';inp.write_bytes(b''.join(struct.pack('<Q',v&MASK) for v in values))
        binary=temp/'native'
        subprocess.run([compiler,str(path),'-o',str(binary)],check=True)
        out=subprocess.check_output([str(binary),str(inp)])
        expected=[]
        for a in values:
            b=signed(a^0xdeadbeef12345678)
            expected.extend(result(a,k,op)&MASK for k in CONSTANTS for op in OPS)
            expected.extend(result(a,b,op)&MASK for op in OPS)
            c,d,e,f=signed(a+37),signed(a*19),a>>7,a&0xffff
            env=dict(a=a,b=b,c=c,d=d,e=e,f=f,g=signed(a+b),h=signed(c^d),j=signed(e-f))
            expected.extend(evaluate(env)&MASK for _,evaluate,_ in complex_cases)
        expected.extend(folded)
        words=[v[0] for v in struct.iter_unpack('<Q',out)]
        assert len(words)==len(expected),(len(words),len(expected))
        for i,(a,b) in enumerate(zip(words,expected)):
            assert a==b,(i,a,b)
        print(f'Native expressions: {len(expected):,} independent arithmetic/bit/compare results, nested calls, syscalls and side effects pass')


if __name__=='__main__':main()
