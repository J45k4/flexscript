"""Qualified integer-bit contact copies and callback stack alignment.

Generated from the canonical contact.cpp with the qualified compiler flags.
Refuse any changed assembly/layout: numerical instructions are never rewritten.
"""
import hashlib

EXIT_START = '\n.LBB8_87:\n'


EXIT_END = '\n.LBB8_218:\n'


COLUMNS = [288,480,736,832,256,704,1408,1600,1536,1568,1184,960,
           128,416,576,448,64,192,96,1344,1312,1120,992,1024]


def transpose():
    out=[]
    for i in range(0,8,2):
        out += [f'\tvunpcklps %ymm{i+1},%ymm{i},%ymm{8+i}',
                f'\tvunpckhps %ymm{i+1},%ymm{i},%ymm{9+i}']
    for i in range(0,8,4):
        out += [f'\tvshufps $0x44,%ymm{10+i},%ymm{8+i},%ymm{i}',
                f'\tvshufps $0xee,%ymm{10+i},%ymm{8+i},%ymm{i+1}',
                f'\tvshufps $0x44,%ymm{11+i},%ymm{9+i},%ymm{i+2}',
                f'\tvshufps $0xee,%ymm{11+i},%ymm{9+i},%ymm{i+3}']
    for i in range(4):
        out += [f'\tvperm2f128 $0x20,%ymm{i+4},%ymm{i},%ymm{8+i}',
                f'\tvperm2f128 $0x31,%ymm{i+4},%ymm{i},%ymm{12+i}']
    return out


def exit_replacement():
    # These two A columns are live in registers at the terminal join. All
    # remaining columns have current copies in their original spill slots.
    out=['\tvmovups %ymm14,288(%rsp)', '\tvmovups %ymm3,480(%rsp)',
         '\tmovq _ZL6shared(%rip),%r12']
    for side in range(2):
        out += ['\tvpxor %xmm0,%xmm0,%xmm0',
                f'\tvpcmpeqd {640+32*side}(%rbx),%ymm0,%ymm1',
                '\tvpandn 704(%rbx),%ymm1,%ymm1',
                '\tvpcmpeqd %ymm0,%ymm1,%ymm1',
                '\tvmovmskps %ymm1,%r10d', '\txorl $255,%r10d',
                '\ttestl %r10d,%r10d',f'\tjz .Lcopy_side{side}_end']
        for half in range(2):
            cols=COLUMNS[side*12+half*6:side*12+half*6+6]
            out += [f'\tvmovups {off}(%rsp),%ymm{i}' for i,off in enumerate(cols)]
            out += ['\tvpxor %xmm6,%xmm6,%xmm6','\tvpxor %xmm7,%xmm7,%xmm7']
            out += transpose()
            for lane in range(8):
                label=f'.Lcopy_{side}_{half}_{lane}_skip'
                out += [f'\ttestl ${1<<lane},%r10d',f'\tjz {label}',
                        f'\tmovl {side*32+lane*4}(%rbx),%eax','\tshlq $6,%rax',
                        f'\tvmovups %ymm{8+lane},{256+32*half}(%r12,%rax)',label+':']
        out += [f'.Lcopy_side{side}_end:']
    return '\n'.join(out)+'\n'


def exit_transform(source):
    a=source.index(EXIT_START)+len(EXIT_START);b=source.index(EXIT_END,a)
    assert source[a:b].startswith('\tvxorps\t%xmm15, %xmm15, %xmm15')
    result=source[:a]+exit_replacement()+source[b:]
    assert result[:a]==source[:a] and result[result.index(EXIT_END):]==source[b:]
    return result


PREFIX='''\ttestb\t$16, %spl
\tjz\t.Lcallback_original_body
\tsubq\t$8, %rsp
\t.cfi_def_cfa_offset 16
\tcallq\t.Lcallback_original_body
\taddq\t$8, %rsp
\t.cfi_def_cfa_offset 8
\tretq
.Lcallback_original_body:
'''


def align_transform(source):
    start=source.index('\nnative_iterations_step:');end=source.index('\n.Lfunc_end12:',start)
    body=source[start:end];anchor='\t.cfi_startproc\n# %bb.0:\n'
    assert body.count(anchor)==1 and '\tsubq\t$24, %rsp' in body
    result=source[:start]+body.replace(anchor,anchor+PREFIX)+source[end:]
    assert result.replace(PREFIX,'',1)==source
    return result


ENTRY_START='\tmovl\t8552832(%rdx,%r8), %eax\n'


ENTRY_END='\tcmpl\t%eax, 544(%rsp)'


def entry_replacement():
 out=['\tleaq 8552832(%rdx,%r8),%rbx']
 for side in range(2):
  for lane in range(8):out += [f'\tmovl {side*32+lane*4}(%rbx),%r{8+lane}d',f'\tshlq $6,%r{8+lane}']
  for half in range(2):
   out += [f'\tvmovups {256+half*32}(%rdx,%r{8+lane}),%ymm{lane}' for lane in range(8)]
   # Same exact 8x8 bit permutation as independently qualified exit-copy
   # primitive. Columns6/7 are discarded; omit only their final permutations.
   out += [line for line in transpose() if not(line.startswith('\tvperm2f128 $0x31') and line.endswith(('%ymm14','%ymm15')))]
   for field,offset in enumerate(COLUMNS[side*12+half*6:side*12+half*6+6]):out.append(f'\tvmovups %ymm{8+field},{offset}(%rsp)')
 out += ['\tmovl 384(%rsp),%eax']
 return '\n'.join(out)+'\n'


def entry_transform(source):
 at=source.index('\n_ZL12vector_batchjj:');a=source.index(ENTRY_START,at);b=source.index(ENTRY_END,a)
 original=source[a:b];assert original.rstrip().endswith('32-byte Spill')
 result=source[:a]+entry_replacement()+source[b:]
 assert result.replace(entry_replacement(),original,1)==source
 return result


REFERENCE_SHA256='429c4e0575fc99180f77d22214d2f51e67c0e1eef34b2d3baf84f3e553813edb'

OPTIMIZED_SHA256='acd6241320e4e75914a256cbc7d77bbfacc91a1b65052a6f81a275b9482bba82'


def transform(source):
    if hashlib.sha256(source.encode()).hexdigest()!=REFERENCE_SHA256:
        raise ValueError('contact assembly differs from qualified compiler/layout; review required')
    result=align_transform(exit_transform(entry_transform(source)))
    if hashlib.sha256(result.encode()).hexdigest()!=OPTIMIZED_SHA256:
        raise ValueError('contact copy transform differs from qualified output')
    return result
