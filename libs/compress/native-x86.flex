// Native x86-64 codec kernels emitted by Flexscript. No assembler, C compiler
// or shared codec library is used to build or execute these kernels.
// BMI2 gates the baseline SSE2 path. AVX2 additionally requires CPUID AVX,
// XSAVE/OSXSAVE and XCR0 XMM/YMM state enabled; every AVX routine clears YMM uppers.
// Code is written RW, patched completely, then made RX. Failure keeps the
// portable codec. Decoding checks untrusted input/output bounds; private
// encoder kernels run only after the caller validates their workspace bounds.
// Private context layout: sequence state +1664..1752; executable base +1760,
// decoder sequence/Huffman/FSE pointers +1768/+1776/+1792; code size +1784.
// Encoder pointers: bit packing +1800, matching +1864, Huffman stream +1872,
// histogram +2016; decoder Huffman table +2024, symbol count +2032, weights +2040.
// Baseline table/sequence entries +328/+336; optional AVX2 wide sequence +344.
// The 16 KiB mapping contains all variants; only supported entries are called.
// Descriptors +1800..2008 are reused serially and deliberately
// overlap between distinct encoder and decoder context types. Masks start +2048.
// The histogram has four independent lanes to avoid repeated-byte dependencies.
// Emitted routines follow System V x86-64 (SSE2 baseline, BMI2 gated by CPUID).
// Short branch fixups retain their encoded width and reject displacement
// overflow, undefined or duplicate labels. Function entries/loops align to 32.
// Sequence tables pack baseline:32, extra bits:5, state bits:8, next base:9.
// After shifting by 37, the low byte is the state width and next base is above
// it. SUB CL and BZHI consume that low byte; BZHI defines its index as SRC2[7:0].
// The ready cursor is 56+(bitpos&7). Extra bits <=29 plus three state widths
// <=9 each consume <=56 bits. A larger extra-bit sum returns to checked code.
// The word address is input+floor(bitpos/8)-7; a negative address exits before
// loading. Four operations advance the cursor and word address together.
// Before changing states/repeats/output, a sequence also requires 64 spare
// output bytes beyond its decoded end. This bounds every speculative copy;
// the final edge falls back without consuming that sequence. Literal and
// distance validation remain inside the kernel. Streaming's physical ring
// reserves a whole block beyond the logical history, so these stores cannot
// corrupt still-live history. Source-wrap reads keep their own exact bounds.
// The encoder bit packer requires capacity >= 10*sequence_count+16, established
// in fz_seq_bits; its worst case is 75 bits/sequence plus final states/stop bit.
import "../../lib/native.flex";
fn fz_jit_byte(j,value) {let n=load64(j+8);if n>=16384 {store64(j+56,1);return 0;}store8(load64(j)+n,value);store64(j+8,n+1);return 1;}
fn fz_jit_align(j,n) {while load64(j+8)&(n-1) {fz_jit_byte(j,144);}return 1;}
fn fz_jit_bytes(j,hex) {let i=0;while load8(hex+i) {let a=load8(hex+i);let b=load8(hex+i+1);if a>57 {a=a-87;}else {a=a-48;}if b>57 {b=b-87;}else {b=b-48;}fz_jit_byte(j,(a<<4)|b);i=i+2;}return 1;}
fn fz_jit_label(j,id) {if id<0 || id>=512 {store64(j+56,1);return 0;}if load64(load64(j+16)+id*8)>=0 {store64(j+56,1);return 0;}store64(load64(j+16)+id*8,load64(j+8));return 1;}
fn fz_jit_branch(j,kind,id) {if kind==233 {fz_jit_byte(j,233);}else {fz_jit_byte(j,15);fz_jit_byte(j,kind);}let count=load64(j+32);if count>=512 {store64(j+56,1);return 0;}let fix=load64(j+24)+count*16;store64(fix,load64(j+8));store64(fix+8,id);store64(j+32,count+1);fz_jit_bytes(j,"00000000");return 1;}
fn fz_jit_branch8(j,kind,id) {fz_jit_byte(j,kind);let count=load64(j+32);if count>=512 {store64(j+56,1);return 0;}let fix=load64(j+24)+count*16;store64(fix,load64(j+8));store64(fix+8,id|0x100000000);store64(j+32,count+1);fz_jit_byte(j,0);return 1;}
fn fz_jit_finish(j) {if load64(j+56) {return 0;}let i=0;while i<load64(j+32) {let f=load64(j+24)+i*16;let tag=load64(f+8);let id=tag&0xffffffff;if id>=512 {return 0;}let target=load64(load64(j+16)+id*8);if target<0 || target>load64(j+8) {return 0;}if tag>>32 {let delta=target-load64(f)-1;if delta< -128 || delta>127 {return 0;}store8(load64(j)+load64(f),delta);}else {bytes_store32(load64(j)+load64(f),target-load64(f)-4);}i=i+1;}return 1;}
fn fz_native_close(c) {if load64(c+1760) {syscall(11,load64(c+1760),16384,0,0,0,0);}store64(c+1760,0);store64(c+1768,0);store64(c+1776,0);store64(c+1784,0);store64(c+1792,0);store64(c+1800,0);store64(c+1864,0);store64(c+1872,0);store64(c+2016,0);store64(c+2024,0);store64(c+2040,0);store64(c+328,0);store64(c+336,0);store64(c+344,0);return 1;}
fn fz_native_open(c) {
 if load64(c+1760) {return 1;}let j=alloc(64);let code=alloc(16384);let labels=alloc(4096);let fixes=alloc(8192);let ready=0;
 if j>0 && code>0 && labels>0 && fixes>0 {store64(j,code);store64(j+16,labels);store64(j+24,fixes);fz_fill(labels,255,4096);fz_emit_cpuid(j);fz_jit_align(j,32);let seq=load64(j+8);fz_emit_sequences(j);fz_jit_align(j,32);let huf=load64(j+8);fz_emit_huffman(j);fz_jit_align(j,32);let fse=load64(j+8);fz_emit_fse(j);fz_jit_align(j,32);let bits=load64(j+8);fz_emit_encode_bits(j);fz_jit_align(j,32);let match=load64(j+8);fz_emit_match(j);fz_jit_align(j,32);let henc=load64(j+8);fz_emit_huffman_encode(j);fz_jit_align(j,32);let hist=load64(j+8);fz_emit_histogram(j);fz_jit_align(j,32);let htab=load64(j+8);fz_emit_huffman_table(j);fz_jit_align(j,32);let hweights=load64(j+8);fz_emit_huffman_weights(j);fz_jit_align(j,32);let htabavx=load64(j+8);fz_emit_huffman_table_avx2(j);fz_jit_align(j,32);let seqavx=load64(j+8);fz_emit_sequences_avx2(j);fz_jit_align(j,32);let seqwide=load64(j+8);fz_emit_sequences_avx2_large(j);
  if fz_jit_finish(j) && syscall(10,code,16384,5,0,0,0)==0  {let features=native_call1(code,0);if features {store64(c+328,code+htab);store64(c+336,code+seq);if features&2 {htab=htabavx;seq=seqavx;store64(c+344,code+seqwide);}store64(c+1760,code);store64(c+1768,code+seq);store64(c+1776,code+huf);store64(c+1784,load64(j+8));store64(c+1792,code+fse);store64(c+1800,code+bits);store64(c+1864,code+match);store64(c+1872,code+henc);store64(c+2016,code+hist);store64(c+2024,code+htab);store64(c+2040,code+hweights);ready=1;}}
 }
 if !ready && code>0 {syscall(11,code,16384,0,0,0,0);}if labels>0 {syscall(11,labels,4096,0,0,0,0);}if fixes>0 {syscall(11,fixes,8192,0,0,0,0);}if j>0 {syscall(11,j,64,0,0,0,0);}return ready;
}
// Query with a negative mode; zero disables acceleration, positive enables it
// when available. Change mode only at a frame boundary on an idle context.
fn zstd_decoder_acceleration(c,mode) {if !c {return 0;}if mode<0 {return load64(c+1760)!=0;}if load64(c+16) {return -1;}if !mode {fz_native_close(c);return 0;}return fz_native_open(c);}
// Encoder operations are synchronous. Change mode between calls.
fn zstd_encoder_acceleration(c,mode) {if !c {return 0;}if mode<0 {return load64(c+1760)!=0;}if !mode {fz_native_close(c);return 0;}return fz_native_open(c);}
fn fz_emit_cpuid(j) {
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_bytes(j,"0fa2"); // cpuid
 fz_jit_bytes(j,"83f807"); // cmp    eax,0x7
 fz_jit_branch8(j,114,1); // jb .Lunsupported
 fz_jit_bytes(j,"b807000000"); // mov    eax,0x7
 fz_jit_bytes(j,"31c9"); // xor    ecx,ecx
 fz_jit_bytes(j,"0fa2"); // cpuid
 fz_jit_bytes(j,"f7c300010000"); // test   ebx,0x100
 fz_jit_branch8(j,116,1); // je .Lunsupported
 fz_jit_bytes(j,"f7c320000000"); // test   ebx,0x20
 fz_jit_branch8(j,116,0); // je .Lbaseline
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"0fa2"); // cpuid
 fz_jit_bytes(j,"81e10000001c"); // and    ecx,0x1c000000
 fz_jit_bytes(j,"81f90000001c"); // cmp    ecx,0x1c000000
 fz_jit_branch8(j,117,0); // jne .Lbaseline
 fz_jit_bytes(j,"31c9"); // xor    ecx,ecx
 fz_jit_bytes(j,"0f01d0"); // xgetbv
 fz_jit_bytes(j,"83e006"); // and    eax,0x6
 fz_jit_bytes(j,"83f806"); // cmp    eax,0x6
 fz_jit_branch8(j,117,0); // jne .Lbaseline
 fz_jit_bytes(j,"b803000000"); // mov    eax,0x3
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 fz_jit_label(j,0); // .Lbaseline
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 fz_jit_label(j,1); // .Lunsupported
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_sequences(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"41ffb7a0060000"); // push   QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"4d8bb7b8060000"); // mov    r14,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"4d8baf98060000"); // mov    r13,QWORD PTR [r15+0x698]
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"4d8d7406f9"); // lea    r14,[r14+rax*1-0x7]
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"4d8ba7a0060000"); // mov    r12,QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"498b9fa8060000"); // mov    rbx,QWORD PTR [r15+0x6a8]
 fz_jit_bytes(j,"49039fc0060000"); // add    rbx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498bafc8060000"); // mov    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4903afb0060000"); // add    rbp,QWORD PTR [r15+0x6b0]
 fz_jit_bytes(j,"f3410f7eb780060000"); // movq   xmm6,QWORD PTR [r15+0x680]
 fz_jit_bytes(j,"66480f7ef0"); // movq   rax,xmm6
 fz_jit_bytes(j,"f3410f7e9cc700100000"); // movq   xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"f3410f7ebf88060000"); // movq   xmm7,QWORD PTR [r15+0x688]
 fz_jit_bytes(j,"66480f7ef8"); // movq   rax,xmm7
 fz_jit_bytes(j,"f3410f7ea4c700200000"); // movq   xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"f3450f7e8790060000"); // movq   xmm8,QWORD PTR [r15+0x690]
 fz_jit_bytes(j,"664c0f7ec0"); // movq   rax,xmm8
 fz_jit_bytes(j,"f3410f7eacc700280000"); // movq   xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"0f1f00"); // nop    DWORD PTR [rax]
 fz_jit_label(j,2); // .Lloop
 fz_jit_bytes(j,"4983fc02"); // cmp    r12,0x2
 fz_jit_branch(j,130,29); // jb .Ldone
 fz_jit_bytes(j,"4d3bb7b8060000"); // cmp    r14,QWORD PTR [r15+0x6b8]
 fz_jit_branch(j,130,29); // jb .Ldone
 fz_jit_bytes(j,"66490f7ed8"); // movq   r8,xmm3
 fz_jit_bytes(j,"66490f7ee1"); // movq   r9,xmm4
 fz_jit_bytes(j,"66490f7eea"); // movq   r10,xmm5
 fz_jit_bytes(j,"4c89c6"); // mov    rsi,r8
 fz_jit_bytes(j,"48c1ee20"); // shr    rsi,0x20
 fz_jit_bytes(j,"83e61f"); // and    esi,0x1f
 fz_jit_bytes(j,"4c89d7"); // mov    rdi,r10
 fz_jit_bytes(j,"48c1ef20"); // shr    rdi,0x20
 fz_jit_bytes(j,"83e71f"); // and    edi,0x1f
 fz_jit_bytes(j,"4c89ca"); // mov    rdx,r9
 fz_jit_bytes(j,"48c1ea20"); // shr    rdx,0x20
 fz_jit_bytes(j,"83e21f"); // and    edx,0x1f
 fz_jit_bytes(j,"8d0c3e"); // lea    ecx,[rsi+rdi*1]
 fz_jit_bytes(j,"01d1"); // add    ecx,edx
 fz_jit_bytes(j,"83f91d"); // cmp    ecx,0x1d
 fz_jit_branch(j,135,29); // ja .Ldone
 fz_jit_bytes(j,"66480f6ec2"); // movq   xmm0,rdx
 fz_jit_bytes(j,"418d4d38"); // lea    ecx,[r13+0x38]
 fz_jit_bytes(j,"4d8b1e"); // mov    r11,QWORD PTR [r14]
 fz_jit_bytes(j,"85d2"); // test   edx,edx
 fz_jit_branch8(j,116,3); // je .LofZero
 fz_jit_bytes(j,"29d1"); // sub    ecx,edx
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2e8f5c0"); // bzhi   rax,rax,rdx
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_branch8(j,235,4); // jmp .LofDone
 fz_jit_label(j,3); // .LofZero
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_label(j,4); // .LofDone
 fz_jit_bytes(j,"85ff"); // test   edi,edi
 fz_jit_branch8(j,116,5); // je .LmlZero
 fz_jit_bytes(j,"29f9"); // sub    ecx,edi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c0f5c0"); // bzhi   rax,rax,rdi
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_bytes(j,"4801c7"); // add    rdi,rax
 fz_jit_branch8(j,235,6); // jmp .LmlDone
 fz_jit_label(j,5); // .LmlZero
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_label(j,6); // .LmlDone
 fz_jit_bytes(j,"85f6"); // test   esi,esi
 fz_jit_branch(j,133,32); // jne .LllNonzero
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_label(j,7); // .LllDone
 fz_jit_bytes(j,"488d0433"); // lea    rax,[rbx+rsi*1]
 fz_jit_bytes(j,"4801f8"); // add    rax,rdi
 fz_jit_bytes(j,"4883c040"); // add    rax,0x40
 fz_jit_bytes(j,"493b87d8060000"); // cmp    rax,QWORD PTR [r15+0x6d8]
 fz_jit_branch(j,135,29); // ja .Ldone
 fz_jit_bytes(j,"49c1e825"); // shr    r8,0x25
 fz_jit_bytes(j,"4428c1"); // sub    cl,r8b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b8f5c0"); // bzhi   rax,rax,r8
 fz_jit_bytes(j,"49c1e808"); // shr    r8,0x8
 fz_jit_bytes(j,"4c01c0"); // add    rax,r8
 fz_jit_bytes(j,"66480f6ef0"); // movq   xmm6,rax
 fz_jit_bytes(j,"f3410f7e9cc700100000"); // movq   xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"49c1ea25"); // shr    r10,0x25
 fz_jit_bytes(j,"4428d1"); // sub    cl,r10b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2a8f5c0"); // bzhi   rax,rax,r10
 fz_jit_bytes(j,"49c1ea08"); // shr    r10,0x8
 fz_jit_bytes(j,"4c01d0"); // add    rax,r10
 fz_jit_bytes(j,"664c0f6ec0"); // movq   xmm8,rax
 fz_jit_bytes(j,"f3410f7eacc700280000"); // movq   xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"49c1e925"); // shr    r9,0x25
 fz_jit_bytes(j,"4428c9"); // sub    cl,r9b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b0f5c0"); // bzhi   rax,rax,r9
 fz_jit_bytes(j,"49c1e908"); // shr    r9,0x8
 fz_jit_bytes(j,"4c01c8"); // add    rax,r9
 fz_jit_bytes(j,"66480f6ef8"); // movq   xmm7,rax
 fz_jit_bytes(j,"f3410f7ea4c700200000"); // movq   xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"4189cd"); // mov    r13d,ecx
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"c1e903"); // shr    ecx,0x3
 fz_jit_bytes(j,"4d8d740ef9"); // lea    r14,[r14+rcx*1-0x7]
 fz_jit_bytes(j,"66480f7ec0"); // movq   rax,xmm0
 fz_jit_bytes(j,"83f801"); // cmp    eax,0x1
 fz_jit_branch8(j,118,8); // jbe .Lrepeat
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"498987a0000000"); // mov    QWORD PTR [r15+0xa0],rax
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"49898798000000"); // mov    QWORD PTR [r15+0x98],rax
 fz_jit_bytes(j,"49899790000000"); // mov    QWORD PTR [r15+0x90],rdx
 fz_jit_branch(j,233,10); // jmp .Loffset
 fz_jit_label(j,8); // .Lrepeat
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,117,9); // jne .LrepeatWide
 fz_jit_bytes(j,"498b9790000000"); // mov    rdx,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4885f6"); // test   rsi,rsi
 fz_jit_branch8(j,117,10); // jne .Loffset
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"49899798000000"); // mov    QWORD PTR [r15+0x98],rdx
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_branch8(j,235,10); // jmp .Loffset
 fz_jit_label(j,9); // .LrepeatWide
 fz_jit_bytes(j,"4883fe01"); // cmp    rsi,0x1
 fz_jit_bytes(j,"4883d200"); // adc    rdx,0x0
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"48ffc8"); // dec    rax
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_bytes(j,"490f4584d788000000"); // cmovne rax,QWORD PTR [r15+rdx*8+0x88]
 fz_jit_bytes(j,"4d8b87a0000000"); // mov    r8,QWORD PTR [r15+0xa0]
 fz_jit_bytes(j,"4d8b8f98000000"); // mov    r9,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_bytes(j,"4d0f45c1"); // cmovne r8,r9
 fz_jit_bytes(j,"4d8987a0000000"); // mov    QWORD PTR [r15+0xa0],r8
 fz_jit_bytes(j,"4d8b8790000000"); // mov    r8,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4d898798000000"); // mov    QWORD PTR [r15+0x98],r8
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_bytes(j,"4885d2"); // test   rdx,rdx
 fz_jit_branch(j,142,30); // jle .Lerror
 fz_jit_label(j,10); // .Loffset
 fz_jit_bytes(j,"4989fa"); // mov    r10,rdi
 fz_jit_bytes(j,"488d443500"); // lea    rax,[rbp+rsi*1+0x0]
 fz_jit_bytes(j,"493b8778060000"); // cmp    rax,QWORD PTR [r15+0x678]
 fz_jit_branch(j,135,30); // ja .Lerror
 fz_jit_bytes(j,"4983bf5806000000"); // cmp    QWORD PTR [r15+0x658],0x0
 fz_jit_branch8(j,117,11); // jne .LwindowOnly
 fz_jit_bytes(j,"498b8760060000"); // mov    rax,QWORD PTR [r15+0x660]
 fz_jit_bytes(j,"4801d8"); // add    rax,rbx
 fz_jit_bytes(j,"4801f0"); // add    rax,rsi
 fz_jit_bytes(j,"493b4738"); // cmp    rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"490f474738"); // cmova  rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,135,30); // ja .Lerror
 fz_jit_branch8(j,235,12); // jmp .Lvalidated
 fz_jit_label(j,11); // .LwindowOnly
 fz_jit_bytes(j,"493b5738"); // cmp    rdx,QWORD PTR [r15+0x38]
 fz_jit_branch(j,135,30); // ja .Lerror
 fz_jit_label(j,12); // .Lvalidated
 fz_jit_bytes(j,"4889f1"); // mov    rcx,rsi
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4801f3"); // add    rbx,rsi
 fz_jit_bytes(j,"4989f0"); // mov    r8,rsi
 fz_jit_bytes(j,"4889ee"); // mov    rsi,rbp
 fz_jit_bytes(j,"4c01c5"); // add    rbp,r8
 fz_jit_label(j,13); // .LliteralWide
 fz_jit_bytes(j,"f30f6f06"); // movdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"f30f7f07"); // movdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4883e910"); // sub    rcx,0x10
 fz_jit_branch8(j,127,13); // jg .LliteralWide
 fz_jit_branch8(j,235,14); // jmp .Lmatch
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,14); // .Lmatch
 fz_jit_bytes(j,"4983bf6806000000"); // cmp    QWORD PTR [r15+0x668],0x0
 fz_jit_branch(j,133,19); // jne .Lcopy
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b8730060000"); // sub    rax,QWORD PTR [r15+0x630]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,134,19); // jbe .Lcopy
 fz_jit_bytes(j,"4889d1"); // mov    rcx,rdx
 fz_jit_bytes(j,"4829d9"); // sub    rcx,rbx
 fz_jit_bytes(j,"49038fc0060000"); // add    rcx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"4c39d1"); // cmp    rcx,r10
 fz_jit_bytes(j,"490f47ca"); // cmova  rcx,r10
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_bytes(j,"4889d0"); // mov    rax,rdx
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"490387c0060000"); // add    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498b7740"); // mov    rsi,QWORD PTR [r15+0x40]
 fz_jit_bytes(j,"4829c6"); // sub    rsi,rax
 fz_jit_branch8(j,121,15); // jns .Lringindex
 fz_jit_bytes(j,"4903b770060000"); // add    rsi,QWORD PTR [r15+0x670]
 fz_jit_label(j,15); // .Lringindex
 fz_jit_bytes(j,"498b8f70060000"); // mov    rcx,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4829f1"); // sub    rcx,rsi
 fz_jit_bytes(j,"4c39c1"); // cmp    rcx,r8
 fz_jit_bytes(j,"490f47c8"); // cmova  rcx,r8
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4929c9"); // sub    r9,rcx
 fz_jit_bytes(j,"4c01c3"); // add    rbx,r8
 fz_jit_bytes(j,"4d29c2"); // sub    r10,r8
 fz_jit_bytes(j,"49037730"); // add    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4c29c7"); // sub    rdi,r8
 fz_jit_bytes(j,"488d440e07"); // lea    rax,[rsi+rcx*1+0x7]
 fz_jit_bytes(j,"4d8b5f30"); // mov    r11,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4d039f70060000"); // add    r11,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4c39d8"); // cmp    rax,r11
 fz_jit_branch8(j,119,17); // ja .LringExact
 fz_jit_label(j,16); // .LringWide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4883e908"); // sub    rcx,0x8
 fz_jit_branch8(j,127,16); // jg .LringWide
 fz_jit_bytes(j,"4801cf"); // add    rdi,rcx
 fz_jit_branch8(j,235,18); // jmp .LringFirstDone
 fz_jit_label(j,17); // .LringExact
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,18); // .LringFirstDone
 fz_jit_bytes(j,"4d85c9"); // test   r9,r9
 fz_jit_branch8(j,116,19); // je .Lcopy
 fz_jit_bytes(j,"498b7730"); // mov    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4c89c9"); // mov    rcx,r9
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,19); // .Lcopy
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4889fe"); // mov    rsi,rdi
 fz_jit_bytes(j,"4829d6"); // sub    rsi,rdx
 fz_jit_bytes(j,"4c01d3"); // add    rbx,r10
 fz_jit_bytes(j,"4d85d2"); // test   r10,r10
 fz_jit_branch(j,132,28); // je .Lnext
 fz_jit_bytes(j,"4883fa08"); // cmp    rdx,0x8
 fz_jit_branch8(j,114,23); // jb .LsmallOffset
 fz_jit_bytes(j,"4883fa10"); // cmp    rdx,0x10
 fz_jit_branch8(j,114,22); // jb .Lwide
 fz_jit_bytes(j,"f30f6f06"); // movdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"f30f7f07"); // movdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch(j,142,28); // jle .Lnext
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_label(j,20); // .Lwide32
 fz_jit_bytes(j,"f30f6f06"); // movdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"f30f7f07"); // movdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"f30f6f4610"); // movdqu xmm0,XMMWORD PTR [rsi+0x10]
 fz_jit_bytes(j,"f30f7f4710"); // movdqu XMMWORD PTR [rdi+0x10],xmm0
 fz_jit_bytes(j,"4883c620"); // add    rsi,0x20
 fz_jit_bytes(j,"4883c720"); // add    rdi,0x20
 fz_jit_bytes(j,"4983ea20"); // sub    r10,0x20
 fz_jit_branch8(j,127,20); // jg .Lwide32
 fz_jit_branch(j,233,28); // jmp .Lnext
 fz_jit_label(j,21); // .Lwide16Tail
 fz_jit_bytes(j,"f30f6f06"); // movdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"f30f7f07"); // movdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch8(j,127,21); // jg .Lwide16Tail
 fz_jit_branch8(j,235,28); // jmp .Lnext
 fz_jit_label(j,22); // .Lwide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,22); // jg .Lwide
 fz_jit_branch8(j,235,28); // jmp .Lnext
 fz_jit_label(j,23); // .LsmallOffset
 fz_jit_bytes(j,"4883fa01"); // cmp    rdx,0x1
 fz_jit_branch8(j,116,24); // je .Lfill1
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_branch8(j,116,25); // je .Lfill2
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_branch8(j,117,27); // jne .Lbytes
 fz_jit_bytes(j,"8b06"); // mov    eax,DWORD PTR [rsi]
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"48c1e120"); // shl    rcx,0x20
 fz_jit_bytes(j,"4809c8"); // or     rax,rcx
 fz_jit_branch8(j,235,26); // jmp .Lfill
 fz_jit_label(j,24); // .Lfill1
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"48b90101010101010101"); // movabs rcx,0x101010101010101
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_branch8(j,235,26); // jmp .Lfill
 fz_jit_label(j,25); // .Lfill2
 fz_jit_bytes(j,"0fb706"); // movzx  eax,WORD PTR [rsi]
 fz_jit_bytes(j,"48b90100010001000100"); // movabs rcx,0x1000100010001
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_label(j,26); // .Lfill
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,26); // jg .Lfill
 fz_jit_branch8(j,235,28); // jmp .Lnext
 fz_jit_label(j,27); // .Lbytes
 fz_jit_bytes(j,"4c89d1"); // mov    rcx,r10
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,28); // .Lnext
 fz_jit_bytes(j,"49ffcc"); // dec    r12
 fz_jit_branch(j,233,2); // jmp .Lloop
 fz_jit_label(j,29); // .Ldone
 fz_jit_bytes(j,"66410fd6b780060000"); // movq   QWORD PTR [r15+0x680],xmm6
 fz_jit_bytes(j,"66410fd6bf88060000"); // movq   QWORD PTR [r15+0x688],xmm7
 fz_jit_bytes(j,"66450fd68790060000"); // movq   QWORD PTR [r15+0x690],xmm8
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"492b87b8060000"); // sub    rax,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"48c1e003"); // shl    rax,0x3
 fz_jit_bytes(j,"4883c038"); // add    rax,0x38
 fz_jit_bytes(j,"4c01e8"); // add    rax,r13
 fz_jit_bytes(j,"49898798060000"); // mov    QWORD PTR [r15+0x698],rax
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b87c0060000"); // sub    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498987a8060000"); // mov    QWORD PTR [r15+0x6a8],rax
 fz_jit_bytes(j,"492bafc8060000"); // sub    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4989afb0060000"); // mov    QWORD PTR [r15+0x6b0],rbp
 fz_jit_bytes(j,"488b0424"); // mov    rax,QWORD PTR [rsp]
 fz_jit_bytes(j,"4c29e0"); // sub    rax,r12
 fz_jit_bytes(j,"4d89a7a0060000"); // mov    QWORD PTR [r15+0x6a0],r12
 fz_jit_branch8(j,235,31); // jmp .Lreturn
 fz_jit_label(j,30); // .Lerror
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,31); // .Lreturn
 fz_jit_bytes(j,"4883c408"); // add    rsp,0x8
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 fz_jit_label(j,32); // .LllNonzero
 fz_jit_bytes(j,"29f1"); // sub    ecx,esi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c8f5c0"); // bzhi   rax,rax,rsi
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_bytes(j,"4801c6"); // add    rsi,rax
 fz_jit_branch(j,233,7); // jmp .LllDone
 return 1;
}

fn fz_emit_huffman(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4889f8"); // mov    rax,rdi
 fz_jit_bytes(j,"50"); // push   rax
 fz_jit_bytes(j,"ff7068"); // push   QWORD PTR [rax+0x68]
 fz_jit_bytes(j,"ff7070"); // push   QWORD PTR [rax+0x70]
 fz_jit_bytes(j,"ff7078"); // push   QWORD PTR [rax+0x78]
 fz_jit_bytes(j,"4c8b6020"); // mov    r12,QWORD PTR [rax+0x20]
 fz_jit_bytes(j,"4c8b6828"); // mov    r13,QWORD PTR [rax+0x28]
 fz_jit_bytes(j,"4c8b7030"); // mov    r14,QWORD PTR [rax+0x30]
 fz_jit_bytes(j,"4c8b7838"); // mov    r15,QWORD PTR [rax+0x38]
 fz_jit_bytes(j,"488b5840"); // mov    rbx,QWORD PTR [rax+0x40]
 fz_jit_bytes(j,"488b6848"); // mov    rbp,QWORD PTR [rax+0x48]
 fz_jit_bytes(j,"488b7050"); // mov    rsi,QWORD PTR [rax+0x50]
 fz_jit_bytes(j,"488b7858"); // mov    rdi,QWORD PTR [rax+0x58]
 fz_jit_label(j,33); // .LhcBatch
 fz_jit_bytes(j,"488b542418"); // mov    rdx,QWORD PTR [rsp+0x18]
 fz_jit_bytes(j,"488b8280000000"); // mov    rax,QWORD PTR [rdx+0x80]
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"488b8a88000000"); // mov    rcx,QWORD PTR [rdx+0x88]
 fz_jit_bytes(j,"4829e9"); // sub    rcx,rbp
 fz_jit_bytes(j,"48c1e903"); // shr    rcx,0x3
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"488b8a90000000"); // mov    rcx,QWORD PTR [rdx+0x90]
 fz_jit_bytes(j,"4829f1"); // sub    rcx,rsi
 fz_jit_bytes(j,"48c1e903"); // shr    rcx,0x3
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"488b8a98000000"); // mov    rcx,QWORD PTR [rdx+0x98]
 fz_jit_bytes(j,"4829f9"); // sub    rcx,rdi
 fz_jit_bytes(j,"48c1e903"); // shr    rcx,0x3
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"4c89e1"); // mov    rcx,r12
 fz_jit_bytes(j,"48c1e906"); // shr    rcx,0x6
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"4c89e9"); // mov    rcx,r13
 fz_jit_bytes(j,"48c1e906"); // shr    rcx,0x6
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"4c89f1"); // mov    rcx,r14
 fz_jit_bytes(j,"48c1e906"); // shr    rcx,0x6
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"4c89f9"); // mov    rcx,r15
 fz_jit_bytes(j,"48c1e906"); // shr    rcx,0x6
 fz_jit_bytes(j,"4839c8"); // cmp    rax,rcx
 fz_jit_bytes(j,"480f47c1"); // cmova  rax,rcx
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch(j,132,35); // je .LhcTail
 fz_jit_bytes(j,"48890424"); // mov    QWORD PTR [rsp],rax
 fz_jit_bytes(j,"0f1f8000000000"); // nop    DWORD PTR [rax+0x0]
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_label(j,34); // .LhcGroup
 fz_jit_bytes(j,"488b542418"); // mov    rdx,QWORD PTR [rsp+0x18]
 fz_jit_bytes(j,"4c89e0"); // mov    rax,r12
 fz_jit_bytes(j,"4883c007"); // add    rax,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"488b0a"); // mov    rcx,QWORD PTR [rdx]
 fz_jit_bytes(j,"4c8b4401f8"); // mov    r8,QWORD PTR [rcx+rax*1-0x8]
 fz_jit_bytes(j,"4c89e0"); // mov    rax,r12
 fz_jit_bytes(j,"48f7d8"); // neg    rax
 fz_jit_bytes(j,"83e007"); // and    eax,0x7
 fz_jit_bytes(j,"c442f9f7c0"); // shlx   r8,r8,rax
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"4883c007"); // add    rax,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"488b4a08"); // mov    rcx,QWORD PTR [rdx+0x8]
 fz_jit_bytes(j,"4c8b4c01f8"); // mov    r9,QWORD PTR [rcx+rax*1-0x8]
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"48f7d8"); // neg    rax
 fz_jit_bytes(j,"83e007"); // and    eax,0x7
 fz_jit_bytes(j,"c442f9f7c9"); // shlx   r9,r9,rax
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"4883c007"); // add    rax,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"488b4a10"); // mov    rcx,QWORD PTR [rdx+0x10]
 fz_jit_bytes(j,"4c8b5401f8"); // mov    r10,QWORD PTR [rcx+rax*1-0x8]
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"48f7d8"); // neg    rax
 fz_jit_bytes(j,"83e007"); // and    eax,0x7
 fz_jit_bytes(j,"c442f9f7d2"); // shlx   r10,r10,rax
 fz_jit_bytes(j,"4c89f8"); // mov    rax,r15
 fz_jit_bytes(j,"4883c007"); // add    rax,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"488b4a18"); // mov    rcx,QWORD PTR [rdx+0x18]
 fz_jit_bytes(j,"4c8b5c01f8"); // mov    r11,QWORD PTR [rcx+rax*1-0x8]
 fz_jit_bytes(j,"4c89f8"); // mov    rax,r15
 fz_jit_bytes(j,"48f7d8"); // neg    rax
 fz_jit_bytes(j,"83e007"); // and    eax,0x7
 fz_jit_bytes(j,"c442f9f7db"); // shlx   r11,r11,rax
 fz_jit_bytes(j,"488b5260"); // mov    rdx,QWORD PTR [rdx+0x60]
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890b"); // mov    WORD PTR [rbx],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c0"); // shlx   r8,r8,rcx
 fz_jit_bytes(j,"4929cc"); // sub    r12,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d5c0301"); // lea    rbx,[rbx+rax*1+0x1]
 fz_jit_bytes(j,"4c89c8"); // mov    rax,r9
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66894d00"); // mov    WORD PTR [rbp+0x0],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c9"); // shlx   r9,r9,rcx
 fz_jit_bytes(j,"4929cd"); // sub    r13,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d6c0501"); // lea    rbp,[rbp+rax*1+0x1]
 fz_jit_bytes(j,"4c89d0"); // mov    rax,r10
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890e"); // mov    WORD PTR [rsi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7d2"); // shlx   r10,r10,rcx
 fz_jit_bytes(j,"4929ce"); // sub    r14,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d740601"); // lea    rsi,[rsi+rax*1+0x1]
 fz_jit_bytes(j,"4c89d8"); // mov    rax,r11
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890f"); // mov    WORD PTR [rdi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7db"); // shlx   r11,r11,rcx
 fz_jit_bytes(j,"4929cf"); // sub    r15,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d7c0701"); // lea    rdi,[rdi+rax*1+0x1]
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890b"); // mov    WORD PTR [rbx],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c0"); // shlx   r8,r8,rcx
 fz_jit_bytes(j,"4929cc"); // sub    r12,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d5c0301"); // lea    rbx,[rbx+rax*1+0x1]
 fz_jit_bytes(j,"4c89c8"); // mov    rax,r9
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66894d00"); // mov    WORD PTR [rbp+0x0],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c9"); // shlx   r9,r9,rcx
 fz_jit_bytes(j,"4929cd"); // sub    r13,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d6c0501"); // lea    rbp,[rbp+rax*1+0x1]
 fz_jit_bytes(j,"4c89d0"); // mov    rax,r10
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890e"); // mov    WORD PTR [rsi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7d2"); // shlx   r10,r10,rcx
 fz_jit_bytes(j,"4929ce"); // sub    r14,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d740601"); // lea    rsi,[rsi+rax*1+0x1]
 fz_jit_bytes(j,"4c89d8"); // mov    rax,r11
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890f"); // mov    WORD PTR [rdi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7db"); // shlx   r11,r11,rcx
 fz_jit_bytes(j,"4929cf"); // sub    r15,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d7c0701"); // lea    rdi,[rdi+rax*1+0x1]
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890b"); // mov    WORD PTR [rbx],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c0"); // shlx   r8,r8,rcx
 fz_jit_bytes(j,"4929cc"); // sub    r12,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d5c0301"); // lea    rbx,[rbx+rax*1+0x1]
 fz_jit_bytes(j,"4c89c8"); // mov    rax,r9
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66894d00"); // mov    WORD PTR [rbp+0x0],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c9"); // shlx   r9,r9,rcx
 fz_jit_bytes(j,"4929cd"); // sub    r13,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d6c0501"); // lea    rbp,[rbp+rax*1+0x1]
 fz_jit_bytes(j,"4c89d0"); // mov    rax,r10
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890e"); // mov    WORD PTR [rsi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7d2"); // shlx   r10,r10,rcx
 fz_jit_bytes(j,"4929ce"); // sub    r14,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d740601"); // lea    rsi,[rsi+rax*1+0x1]
 fz_jit_bytes(j,"4c89d8"); // mov    rax,r11
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890f"); // mov    WORD PTR [rdi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7db"); // shlx   r11,r11,rcx
 fz_jit_bytes(j,"4929cf"); // sub    r15,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d7c0701"); // lea    rdi,[rdi+rax*1+0x1]
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890b"); // mov    WORD PTR [rbx],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c0"); // shlx   r8,r8,rcx
 fz_jit_bytes(j,"4929cc"); // sub    r12,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d5c0301"); // lea    rbx,[rbx+rax*1+0x1]
 fz_jit_bytes(j,"4c89c8"); // mov    rax,r9
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66894d00"); // mov    WORD PTR [rbp+0x0],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7c9"); // shlx   r9,r9,rcx
 fz_jit_bytes(j,"4929cd"); // sub    r13,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d6c0501"); // lea    rbp,[rbp+rax*1+0x1]
 fz_jit_bytes(j,"4c89d0"); // mov    rax,r10
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890e"); // mov    WORD PTR [rsi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7d2"); // shlx   r10,r10,rcx
 fz_jit_bytes(j,"4929ce"); // sub    r14,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d740601"); // lea    rsi,[rsi+rax*1+0x1]
 fz_jit_bytes(j,"4c89d8"); // mov    rax,r11
 fz_jit_bytes(j,"48c1e835"); // shr    rax,0x35
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"66890f"); // mov    WORD PTR [rdi],cx
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c442f1f7db"); // shlx   r11,r11,rcx
 fz_jit_bytes(j,"4929cf"); // sub    r15,rcx
 fz_jit_bytes(j,"c1e818"); // shr    eax,0x18
 fz_jit_bytes(j,"488d7c0701"); // lea    rdi,[rdi+rax*1+0x1]
 fz_jit_bytes(j,"48ff0c24"); // dec    QWORD PTR [rsp]
 fz_jit_branch(j,133,34); // jne .LhcGroup
 fz_jit_branch(j,233,33); // jmp .LhcBatch
 fz_jit_label(j,35); // .LhcTail
 fz_jit_bytes(j,"4c8b5c2418"); // mov    r11,QWORD PTR [rsp+0x18]
 fz_jit_bytes(j,"498b5360"); // mov    rdx,QWORD PTR [r11+0x60]
 fz_jit_bytes(j,"4881ea00200000"); // sub    rdx,0x2000
 fz_jit_bytes(j,"4d8b03"); // mov    r8,QWORD PTR [r11]
 fz_jit_bytes(j,"4d8b8b80000000"); // mov    r9,QWORD PTR [r11+0x80]
 fz_jit_label(j,36); // .LhcTail0
 fz_jit_bytes(j,"4c39cb"); // cmp    rbx,r9
 fz_jit_branch8(j,115,39); // jae .LhcTailEnd0
 fz_jit_bytes(j,"4c89e0"); // mov    rax,r12
 fz_jit_bytes(j,"4883e80b"); // sub    rax,0xb
 fz_jit_branch8(j,120,37); // js .LhcTailLow0
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0400"); // mov    rax,QWORD PTR [r8+rax*1]
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_branch8(j,235,38); // jmp .LhcTailLookup0
 fz_jit_label(j,37); // .LhcTailLow0
 fz_jit_bytes(j,"498b00"); // mov    rax,QWORD PTR [r8]
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429e1"); // sub    ecx,r12d
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_label(j,38); // .LhcTailLookup0
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"4939cc"); // cmp    r12,rcx
 fz_jit_branch(j,130,52); // jb .LhcFailure
 fz_jit_bytes(j,"4929cc"); // sub    r12,rcx
 fz_jit_bytes(j,"c1e808"); // shr    eax,0x8
 fz_jit_bytes(j,"8803"); // mov    BYTE PTR [rbx],al
 fz_jit_bytes(j,"48ffc3"); // inc    rbx
 fz_jit_branch8(j,235,36); // jmp .LhcTail0
 fz_jit_label(j,39); // .LhcTailEnd0
 fz_jit_bytes(j,"4d85e4"); // test   r12,r12
 fz_jit_branch(j,133,52); // jne .LhcFailure
 fz_jit_bytes(j,"4d8b4308"); // mov    r8,QWORD PTR [r11+0x8]
 fz_jit_bytes(j,"4d8b8b88000000"); // mov    r9,QWORD PTR [r11+0x88]
 fz_jit_label(j,40); // .LhcTail1
 fz_jit_bytes(j,"4c39cd"); // cmp    rbp,r9
 fz_jit_branch8(j,115,43); // jae .LhcTailEnd1
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"4883e80b"); // sub    rax,0xb
 fz_jit_branch8(j,120,41); // js .LhcTailLow1
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0400"); // mov    rax,QWORD PTR [r8+rax*1]
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_branch8(j,235,42); // jmp .LhcTailLookup1
 fz_jit_label(j,41); // .LhcTailLow1
 fz_jit_bytes(j,"498b00"); // mov    rax,QWORD PTR [r8]
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429e9"); // sub    ecx,r13d
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_label(j,42); // .LhcTailLookup1
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"4939cd"); // cmp    r13,rcx
 fz_jit_branch(j,130,52); // jb .LhcFailure
 fz_jit_bytes(j,"4929cd"); // sub    r13,rcx
 fz_jit_bytes(j,"c1e808"); // shr    eax,0x8
 fz_jit_bytes(j,"884500"); // mov    BYTE PTR [rbp+0x0],al
 fz_jit_bytes(j,"48ffc5"); // inc    rbp
 fz_jit_branch8(j,235,40); // jmp .LhcTail1
 fz_jit_label(j,43); // .LhcTailEnd1
 fz_jit_bytes(j,"4d85ed"); // test   r13,r13
 fz_jit_branch(j,133,52); // jne .LhcFailure
 fz_jit_bytes(j,"4d8b4310"); // mov    r8,QWORD PTR [r11+0x10]
 fz_jit_bytes(j,"4d8b8b90000000"); // mov    r9,QWORD PTR [r11+0x90]
 fz_jit_label(j,44); // .LhcTail2
 fz_jit_bytes(j,"4c39ce"); // cmp    rsi,r9
 fz_jit_branch8(j,115,47); // jae .LhcTailEnd2
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"4883e80b"); // sub    rax,0xb
 fz_jit_branch8(j,120,45); // js .LhcTailLow2
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0400"); // mov    rax,QWORD PTR [r8+rax*1]
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_branch8(j,235,46); // jmp .LhcTailLookup2
 fz_jit_label(j,45); // .LhcTailLow2
 fz_jit_bytes(j,"498b00"); // mov    rax,QWORD PTR [r8]
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429f1"); // sub    ecx,r14d
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_label(j,46); // .LhcTailLookup2
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"4939ce"); // cmp    r14,rcx
 fz_jit_branch(j,130,52); // jb .LhcFailure
 fz_jit_bytes(j,"4929ce"); // sub    r14,rcx
 fz_jit_bytes(j,"c1e808"); // shr    eax,0x8
 fz_jit_bytes(j,"8806"); // mov    BYTE PTR [rsi],al
 fz_jit_bytes(j,"48ffc6"); // inc    rsi
 fz_jit_branch8(j,235,44); // jmp .LhcTail2
 fz_jit_label(j,47); // .LhcTailEnd2
 fz_jit_bytes(j,"4d85f6"); // test   r14,r14
 fz_jit_branch(j,133,52); // jne .LhcFailure
 fz_jit_bytes(j,"4d8b4318"); // mov    r8,QWORD PTR [r11+0x18]
 fz_jit_bytes(j,"4d8b8b98000000"); // mov    r9,QWORD PTR [r11+0x98]
 fz_jit_label(j,48); // .LhcTail3
 fz_jit_bytes(j,"4c39cf"); // cmp    rdi,r9
 fz_jit_branch8(j,115,51); // jae .LhcTailEnd3
 fz_jit_bytes(j,"4c89f8"); // mov    rax,r15
 fz_jit_bytes(j,"4883e80b"); // sub    rax,0xb
 fz_jit_branch8(j,120,49); // js .LhcTailLow3
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0400"); // mov    rax,QWORD PTR [r8+rax*1]
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_branch8(j,235,50); // jmp .LhcTailLookup3
 fz_jit_label(j,49); // .LhcTailLow3
 fz_jit_bytes(j,"498b00"); // mov    rax,QWORD PTR [r8]
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429f9"); // sub    ecx,r15d
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"25ff070000"); // and    eax,0x7ff
 fz_jit_label(j,50); // .LhcTailLookup3
 fz_jit_bytes(j,"8b0482"); // mov    eax,DWORD PTR [rdx+rax*4]
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"4939cf"); // cmp    r15,rcx
 fz_jit_branch8(j,114,52); // jb .LhcFailure
 fz_jit_bytes(j,"4929cf"); // sub    r15,rcx
 fz_jit_bytes(j,"c1e808"); // shr    eax,0x8
 fz_jit_bytes(j,"8807"); // mov    BYTE PTR [rdi],al
 fz_jit_bytes(j,"48ffc7"); // inc    rdi
 fz_jit_branch8(j,235,48); // jmp .LhcTail3
 fz_jit_label(j,51); // .LhcTailEnd3
 fz_jit_bytes(j,"4d85ff"); // test   r15,r15
 fz_jit_branch8(j,117,52); // jne .LhcFailure
 fz_jit_bytes(j,"488b442418"); // mov    rax,QWORD PTR [rsp+0x18]
 fz_jit_bytes(j,"4c896020"); // mov    QWORD PTR [rax+0x20],r12
 fz_jit_bytes(j,"4c896828"); // mov    QWORD PTR [rax+0x28],r13
 fz_jit_bytes(j,"4c897030"); // mov    QWORD PTR [rax+0x30],r14
 fz_jit_bytes(j,"4c897838"); // mov    QWORD PTR [rax+0x38],r15
 fz_jit_bytes(j,"48895840"); // mov    QWORD PTR [rax+0x40],rbx
 fz_jit_bytes(j,"48896848"); // mov    QWORD PTR [rax+0x48],rbp
 fz_jit_bytes(j,"48897050"); // mov    QWORD PTR [rax+0x50],rsi
 fz_jit_bytes(j,"48897858"); // mov    QWORD PTR [rax+0x58],rdi
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_branch8(j,235,53); // jmp .LhcCleanup
 fz_jit_label(j,52); // .LhcFailure
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,53); // .LhcCleanup
 fz_jit_bytes(j,"4883c420"); // add    rsp,0x20
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_fse(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"4d8bb7a0070000"); // mov    r14,QWORD PTR [r15+0x7a0]
 fz_jit_bytes(j,"4d8bafa8070000"); // mov    r13,QWORD PTR [r15+0x7a8]
 fz_jit_bytes(j,"4d01f5"); // add    r13,r14
 fz_jit_bytes(j,"4d8ba7b0070000"); // mov    r12,QWORD PTR [r15+0x7b0]
 fz_jit_bytes(j,"4d01f4"); // add    r12,r14
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_bytes(j,"31ed"); // xor    ebp,ebp
 fz_jit_bytes(j,"498db700480000"); // lea    rsi,[r15+0x4800]
 fz_jit_bytes(j,"4889f7"); // mov    rdi,rsi
 fz_jit_bytes(j,"498b8fb8070000"); // mov    rcx,QWORD PTR [r15+0x7b8]
 fz_jit_bytes(j,"48ffc1"); // inc    rcx
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_bytes(j,"f348ab"); // rep stos QWORD PTR [rdi],rax
 fz_jit_label(j,54); // .LfseFillInitial
 fz_jit_bytes(j,"4883fd10"); // cmp    rbp,0x10
 fz_jit_branch8(j,115,56); // jae .LfseLog
 fz_jit_bytes(j,"498d442404"); // lea    rax,[r12+0x4]
 fz_jit_bytes(j,"4c39e8"); // cmp    rax,r13
 fz_jit_branch8(j,119,55); // ja .LfseByteInitial
 fz_jit_bytes(j,"418b0424"); // mov    eax,DWORD PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"4983c404"); // add    r12,0x4
 fz_jit_bytes(j,"83c520"); // add    ebp,0x20
 fz_jit_branch8(j,235,56); // jmp .LfseLog
 fz_jit_label(j,55); // .LfseByteInitial
 fz_jit_bytes(j,"4d39ec"); // cmp    r12,r13
 fz_jit_branch(j,131,85); // jae .LfseError
 fz_jit_bytes(j,"410fb60424"); // movzx  eax,BYTE PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"49ffc4"); // inc    r12
 fz_jit_bytes(j,"83c508"); // add    ebp,0x8
 fz_jit_branch8(j,235,54); // jmp .LfseFillInitial
 fz_jit_label(j,56); // .LfseLog
 fz_jit_bytes(j,"89d8"); // mov    eax,ebx
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"83c005"); // add    eax,0x5
 fz_jit_bytes(j,"493b87c0070000"); // cmp    rax,QWORD PTR [r15+0x7c0]
 fz_jit_branch(j,135,85); // ja .LfseError
 fz_jit_bytes(j,"498987d8070000"); // mov    QWORD PTR [r15+0x7d8],rax
 fz_jit_bytes(j,"48c1eb04"); // shr    rbx,0x4
 fz_jit_bytes(j,"83ed04"); // sub    ebp,0x4
 fz_jit_bytes(j,"89c1"); // mov    ecx,eax
 fz_jit_bytes(j,"49c7c101000000"); // mov    r9,0x1
 fz_jit_bytes(j,"49d3e1"); // shl    r9,cl
 fz_jit_bytes(j,"4d8d4101"); // lea    r8,[r9+0x1]
 fz_jit_bytes(j,"4c8d5001"); // lea    r10,[rax+0x1]
 fz_jit_bytes(j,"4531db"); // xor    r11d,r11d
 fz_jit_label(j,57); // .LfseNormal
 fz_jit_bytes(j,"4983f801"); // cmp    r8,0x1
 fz_jit_branch(j,134,70); // jbe .LfseParsed
 fz_jit_bytes(j,"4d3b9fb8070000"); // cmp    r11,QWORD PTR [r15+0x7b8]
 fz_jit_branch(j,135,85); // ja .LfseError
 fz_jit_label(j,58); // .LfseFillNormal
 fz_jit_bytes(j,"4883fd10"); // cmp    rbp,0x10
 fz_jit_branch8(j,115,60); // jae .LfseCount
 fz_jit_bytes(j,"498d442404"); // lea    rax,[r12+0x4]
 fz_jit_bytes(j,"4c39e8"); // cmp    rax,r13
 fz_jit_branch8(j,119,59); // ja .LfseByteNormal
 fz_jit_bytes(j,"418b0424"); // mov    eax,DWORD PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"4983c404"); // add    r12,0x4
 fz_jit_bytes(j,"83c520"); // add    ebp,0x20
 fz_jit_branch8(j,235,60); // jmp .LfseCount
 fz_jit_label(j,59); // .LfseByteNormal
 fz_jit_bytes(j,"4d39ec"); // cmp    r12,r13
 fz_jit_branch(j,131,85); // jae .LfseError
 fz_jit_bytes(j,"410fb60424"); // movzx  eax,BYTE PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"49ffc4"); // inc    r12
 fz_jit_bytes(j,"83c508"); // add    ebp,0x8
 fz_jit_branch8(j,235,58); // jmp .LfseFillNormal
 fz_jit_label(j,60); // .LfseCount
 fz_jit_bytes(j,"4b8d5409ff"); // lea    rdx,[r9+r9*1-0x1]
 fz_jit_bytes(j,"4c29c2"); // sub    rdx,r8
 fz_jit_bytes(j,"498d41ff"); // lea    rax,[r9-0x1]
 fz_jit_bytes(j,"4821d8"); // and    rax,rbx
 fz_jit_bytes(j,"4839d0"); // cmp    rax,rdx
 fz_jit_branch8(j,115,61); // jae .LfseFullCount
 fz_jit_bytes(j,"498d4aff"); // lea    rcx,[r10-0x1]
 fz_jit_branch8(j,235,62); // jmp .LfseConsumeCount
 fz_jit_label(j,61); // .LfseFullCount
 fz_jit_bytes(j,"4c89d1"); // mov    rcx,r10
 fz_jit_bytes(j,"c4e2f0f5c3"); // bzhi   rax,rbx,rcx
 fz_jit_bytes(j,"4c39c8"); // cmp    rax,r9
 fz_jit_branch8(j,114,62); // jb .LfseConsumeCount
 fz_jit_bytes(j,"4829d0"); // sub    rax,rdx
 fz_jit_label(j,62); // .LfseConsumeCount
 fz_jit_bytes(j,"c4e2f3f7db"); // shrx   rbx,rbx,rcx
 fz_jit_bytes(j,"4829cd"); // sub    rbp,rcx
 fz_jit_bytes(j,"48ffc8"); // dec    rax
 fz_jit_bytes(j,"4a8904de"); // mov    QWORD PTR [rsi+r11*8],rax
 fz_jit_bytes(j,"49ffc3"); // inc    r11
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch8(j,120,63); // js .LfseRare
 fz_jit_bytes(j,"4929c0"); // sub    r8,rax
 fz_jit_branch8(j,235,64); // jmp .LfseThreshold
 fz_jit_label(j,63); // .LfseRare
 fz_jit_bytes(j,"49ffc8"); // dec    r8
 fz_jit_label(j,64); // .LfseThreshold
 fz_jit_bytes(j,"4d39c8"); // cmp    r8,r9
 fz_jit_branch8(j,115,65); // jae .LfseNext
 fz_jit_bytes(j,"4d85c9"); // test   r9,r9
 fz_jit_branch8(j,116,65); // je .LfseNext
 fz_jit_bytes(j,"49ffca"); // dec    r10
 fz_jit_bytes(j,"49d1e9"); // shr    r9,1
 fz_jit_branch8(j,235,64); // jmp .LfseThreshold
 fz_jit_label(j,65); // .LfseNext
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch(j,133,57); // jne .LfseNormal
 fz_jit_label(j,66); // .LfseZeros
 fz_jit_bytes(j,"4883fd10"); // cmp    rbp,0x10
 fz_jit_branch8(j,115,68); // jae .LfseZeroValue
 fz_jit_bytes(j,"498d442404"); // lea    rax,[r12+0x4]
 fz_jit_bytes(j,"4c39e8"); // cmp    rax,r13
 fz_jit_branch8(j,119,67); // ja .LfseByteZero
 fz_jit_bytes(j,"418b0424"); // mov    eax,DWORD PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"4983c404"); // add    r12,0x4
 fz_jit_bytes(j,"83c520"); // add    ebp,0x20
 fz_jit_branch8(j,235,68); // jmp .LfseZeroValue
 fz_jit_label(j,67); // .LfseByteZero
 fz_jit_bytes(j,"4d39ec"); // cmp    r12,r13
 fz_jit_branch(j,131,85); // jae .LfseError
 fz_jit_bytes(j,"410fb60424"); // movzx  eax,BYTE PTR [r12]
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"49ffc4"); // inc    r12
 fz_jit_bytes(j,"83c508"); // add    ebp,0x8
 fz_jit_branch8(j,235,66); // jmp .LfseZeros
 fz_jit_label(j,68); // .LfseZeroValue
 fz_jit_bytes(j,"89d8"); // mov    eax,ebx
 fz_jit_bytes(j,"25ff0f0000"); // and    eax,0xfff
 fz_jit_bytes(j,"3dff0f0000"); // cmp    eax,0xfff
 fz_jit_branch8(j,117,69); // jne .LfseFewZeros
 fz_jit_bytes(j,"4983c312"); // add    r11,0x12
 fz_jit_bytes(j,"48c1eb0c"); // shr    rbx,0xc
 fz_jit_bytes(j,"83ed0c"); // sub    ebp,0xc
 fz_jit_bytes(j,"4d3b9fb8070000"); // cmp    r11,QWORD PTR [r15+0x7b8]
 fz_jit_branch(j,135,85); // ja .LfseError
 fz_jit_branch8(j,235,66); // jmp .LfseZeros
 fz_jit_label(j,69); // .LfseFewZeros
 fz_jit_bytes(j,"89d8"); // mov    eax,ebx
 fz_jit_bytes(j,"83e003"); // and    eax,0x3
 fz_jit_bytes(j,"48c1eb02"); // shr    rbx,0x2
 fz_jit_bytes(j,"83ed02"); // sub    ebp,0x2
 fz_jit_bytes(j,"4901c3"); // add    r11,rax
 fz_jit_bytes(j,"4d3b9fb8070000"); // cmp    r11,QWORD PTR [r15+0x7b8]
 fz_jit_branch(j,135,85); // ja .LfseError
 fz_jit_bytes(j,"83f803"); // cmp    eax,0x3
 fz_jit_branch(j,132,66); // je .LfseZeros
 fz_jit_branch(j,233,57); // jmp .LfseNormal
 fz_jit_label(j,70); // .LfseParsed
 fz_jit_bytes(j,"4983f801"); // cmp    r8,0x1
 fz_jit_branch(j,133,85); // jne .LfseError
 fz_jit_bytes(j,"4889e8"); // mov    rax,rbp
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"4929c4"); // sub    r12,rax
 fz_jit_bytes(j,"4d29f4"); // sub    r12,r14
 fz_jit_bytes(j,"4d89a730010000"); // mov    QWORD PTR [r15+0x130],r12
 fz_jit_bytes(j,"49ffcb"); // dec    r11
 fz_jit_bytes(j,"4d899fb8070000"); // mov    QWORD PTR [r15+0x7b8],r11
 fz_jit_bytes(j,"4d8b8fd8070000"); // mov    r9,QWORD PTR [r15+0x7d8]
 fz_jit_bytes(j,"4489c9"); // mov    ecx,r9d
 fz_jit_bytes(j,"49c7c001000000"); // mov    r8,0x1
 fz_jit_bytes(j,"49d3e0"); // shl    r8,cl
 fz_jit_bytes(j,"4d8d50ff"); // lea    r10,[r8-0x1]
 fz_jit_bytes(j,"4d89d5"); // mov    r13,r10
 fz_jit_bytes(j,"4d89c3"); // mov    r11,r8
 fz_jit_bytes(j,"49d1eb"); // shr    r11,1
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"4d8d5c0303"); // lea    r11,[r11+rax*1+0x3]
 fz_jit_bytes(j,"4d8da7000a0000"); // lea    r12,[r15+0xa00]
 fz_jit_bytes(j,"498dbf00500000"); // lea    rdi,[r15+0x5000]
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_label(j,71); // .LfseInitialize
 fz_jit_bytes(j,"488b04de"); // mov    rax,QWORD PTR [rsi+rbx*8]
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch8(j,121,72); // jns .LfsePositive
 fz_jit_bytes(j,"43881c2c"); // mov    BYTE PTR [r12+r13*1],bl
 fz_jit_bytes(j,"49ffcd"); // dec    r13
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_label(j,72); // .LfsePositive
 fz_jit_bytes(j,"488904df"); // mov    QWORD PTR [rdi+rbx*8],rax
 fz_jit_bytes(j,"48ffc3"); // inc    rbx
 fz_jit_bytes(j,"493b9fb8070000"); // cmp    rbx,QWORD PTR [r15+0x7b8]
 fz_jit_branch8(j,118,71); // jbe .LfseInitialize
 fz_jit_bytes(j,"4531f6"); // xor    r14d,r14d
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_label(j,73); // .LfseSpreadSymbol
 fz_jit_bytes(j,"488b14de"); // mov    rdx,QWORD PTR [rsi+rbx*8]
 fz_jit_bytes(j,"31ed"); // xor    ebp,ebp
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_label(j,74); // .LfseSpreadFour
 fz_jit_bytes(j,"488d4504"); // lea    rax,[rbp+0x4]
 fz_jit_bytes(j,"4839d0"); // cmp    rax,rdx
 fz_jit_branch8(j,127,79); // jg .LfseSpread
 fz_jit_bytes(j,"43881c34"); // mov    BYTE PTR [r12+r14*1],bl
 fz_jit_label(j,75); // .LfseAdvanceFour0
 fz_jit_bytes(j,"4d01de"); // add    r14,r11
 fz_jit_bytes(j,"4d21d6"); // and    r14,r10
 fz_jit_bytes(j,"4d39ee"); // cmp    r14,r13
 fz_jit_branch8(j,119,75); // ja .LfseAdvanceFour0
 fz_jit_bytes(j,"43881c34"); // mov    BYTE PTR [r12+r14*1],bl
 fz_jit_label(j,76); // .LfseAdvanceFour1
 fz_jit_bytes(j,"4d01de"); // add    r14,r11
 fz_jit_bytes(j,"4d21d6"); // and    r14,r10
 fz_jit_bytes(j,"4d39ee"); // cmp    r14,r13
 fz_jit_branch8(j,119,76); // ja .LfseAdvanceFour1
 fz_jit_bytes(j,"43881c34"); // mov    BYTE PTR [r12+r14*1],bl
 fz_jit_label(j,77); // .LfseAdvanceFour2
 fz_jit_bytes(j,"4d01de"); // add    r14,r11
 fz_jit_bytes(j,"4d21d6"); // and    r14,r10
 fz_jit_bytes(j,"4d39ee"); // cmp    r14,r13
 fz_jit_branch8(j,119,77); // ja .LfseAdvanceFour2
 fz_jit_bytes(j,"43881c34"); // mov    BYTE PTR [r12+r14*1],bl
 fz_jit_label(j,78); // .LfseAdvanceFour3
 fz_jit_bytes(j,"4d01de"); // add    r14,r11
 fz_jit_bytes(j,"4d21d6"); // and    r14,r10
 fz_jit_bytes(j,"4d39ee"); // cmp    r14,r13
 fz_jit_branch8(j,119,78); // ja .LfseAdvanceFour3
 fz_jit_bytes(j,"4883c504"); // add    rbp,0x4
 fz_jit_branch8(j,235,74); // jmp .LfseSpreadFour
 fz_jit_label(j,79); // .LfseSpread
 fz_jit_bytes(j,"4839d5"); // cmp    rbp,rdx
 fz_jit_branch8(j,125,81); // jge .LfseNextSymbol
 fz_jit_bytes(j,"43881c34"); // mov    BYTE PTR [r12+r14*1],bl
 fz_jit_label(j,80); // .LfseAdvance
 fz_jit_bytes(j,"4d01de"); // add    r14,r11
 fz_jit_bytes(j,"4d21d6"); // and    r14,r10
 fz_jit_bytes(j,"4d39ee"); // cmp    r14,r13
 fz_jit_branch8(j,119,80); // ja .LfseAdvance
 fz_jit_bytes(j,"48ffc5"); // inc    rbp
 fz_jit_branch8(j,235,79); // jmp .LfseSpread
 fz_jit_label(j,81); // .LfseNextSymbol
 fz_jit_bytes(j,"48ffc3"); // inc    rbx
 fz_jit_bytes(j,"493b9fb8070000"); // cmp    rbx,QWORD PTR [r15+0x7b8]
 fz_jit_branch(j,134,73); // jbe .LfseSpreadSymbol
 fz_jit_bytes(j,"4d85f6"); // test   r14,r14
 fz_jit_branch(j,133,85); // jne .LfseError
 fz_jit_bytes(j,"4d89e6"); // mov    r14,r12
 fz_jit_bytes(j,"4d8ba7c8070000"); // mov    r12,QWORD PTR [r15+0x7c8]
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_bytes(j,"498bafd0070000"); // mov    rbp,QWORD PTR [r15+0x7d0]
 fz_jit_bytes(j,"4f8dacc700a00600"); // lea    r13,[r15+r8*8+0x6a000]
 fz_jit_bytes(j,"4885ed"); // test   rbp,rbp
 fz_jit_branch(j,132,83); // je .LfseRawBuild
 fz_jit_bytes(j,"660f1f840000000000"); // nop    WORD PTR [rax+rax*1+0x0]
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_label(j,82); // .LfsePackedBuild
 fz_jit_bytes(j,"410fb6141e"); // movzx  edx,BYTE PTR [r14+rbx*1]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"488b54d500"); // mov    rdx,QWORD PTR [rbp+rdx*8+0x0]
 fz_jit_bytes(j,"48c1e125"); // shl    rcx,0x25
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498914dc"); // mov    QWORD PTR [r12+rbx*8],rdx
 fz_jit_bytes(j,"410fb6541e01"); // movzx  edx,BYTE PTR [r14+rbx*1+0x1]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"488b54d500"); // mov    rdx,QWORD PTR [rbp+rdx*8+0x0]
 fz_jit_bytes(j,"48c1e125"); // shl    rcx,0x25
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc08"); // mov    QWORD PTR [r12+rbx*8+0x8],rdx
 fz_jit_bytes(j,"410fb6541e02"); // movzx  edx,BYTE PTR [r14+rbx*1+0x2]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"488b54d500"); // mov    rdx,QWORD PTR [rbp+rdx*8+0x0]
 fz_jit_bytes(j,"48c1e125"); // shl    rcx,0x25
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc10"); // mov    QWORD PTR [r12+rbx*8+0x10],rdx
 fz_jit_bytes(j,"410fb6541e03"); // movzx  edx,BYTE PTR [r14+rbx*1+0x3]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"488b54d500"); // mov    rdx,QWORD PTR [rbp+rdx*8+0x0]
 fz_jit_bytes(j,"48c1e125"); // shl    rcx,0x25
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc18"); // mov    QWORD PTR [r12+rbx*8+0x18],rdx
 fz_jit_bytes(j,"4883c304"); // add    rbx,0x4
 fz_jit_bytes(j,"4c39c3"); // cmp    rbx,r8
 fz_jit_branch(j,130,82); // jb .LfsePackedBuild
 fz_jit_branch(j,233,84); // jmp .LfseBuilt
 fz_jit_label(j,83); // .LfseRawBuild
 fz_jit_bytes(j,"410fb6141e"); // movzx  edx,BYTE PTR [r14+rbx*1]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"4889c8"); // mov    rax,rcx
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"48c1e008"); // shl    rax,0x8
 fz_jit_bytes(j,"48c1e908"); // shr    rcx,0x8
 fz_jit_bytes(j,"48c1e110"); // shl    rcx,0x10
 fz_jit_bytes(j,"4809c2"); // or     rdx,rax
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498914dc"); // mov    QWORD PTR [r12+rbx*8],rdx
 fz_jit_bytes(j,"410fb6541e01"); // movzx  edx,BYTE PTR [r14+rbx*1+0x1]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"4889c8"); // mov    rax,rcx
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"48c1e008"); // shl    rax,0x8
 fz_jit_bytes(j,"48c1e908"); // shr    rcx,0x8
 fz_jit_bytes(j,"48c1e110"); // shl    rcx,0x10
 fz_jit_bytes(j,"4809c2"); // or     rdx,rax
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc08"); // mov    QWORD PTR [r12+rbx*8+0x8],rdx
 fz_jit_bytes(j,"410fb6541e02"); // movzx  edx,BYTE PTR [r14+rbx*1+0x2]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"4889c8"); // mov    rax,rcx
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"48c1e008"); // shl    rax,0x8
 fz_jit_bytes(j,"48c1e908"); // shr    rcx,0x8
 fz_jit_bytes(j,"48c1e110"); // shl    rcx,0x10
 fz_jit_bytes(j,"4809c2"); // or     rdx,rax
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc10"); // mov    QWORD PTR [r12+rbx*8+0x10],rdx
 fz_jit_bytes(j,"410fb6541e03"); // movzx  edx,BYTE PTR [r14+rbx*1+0x3]
 fz_jit_bytes(j,"488b34d7"); // mov    rsi,QWORD PTR [rdi+rdx*8]
 fz_jit_bytes(j,"488d4601"); // lea    rax,[rsi+0x1]
 fz_jit_bytes(j,"488904d7"); // mov    QWORD PTR [rdi+rdx*8],rax
 fz_jit_bytes(j,"418b4cb500"); // mov    ecx,DWORD PTR [r13+rsi*4+0x0]
 fz_jit_bytes(j,"4889c8"); // mov    rax,rcx
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"48c1e008"); // shl    rax,0x8
 fz_jit_bytes(j,"48c1e908"); // shr    rcx,0x8
 fz_jit_bytes(j,"48c1e110"); // shl    rcx,0x10
 fz_jit_bytes(j,"4809c2"); // or     rdx,rax
 fz_jit_bytes(j,"4809ca"); // or     rdx,rcx
 fz_jit_bytes(j,"498954dc18"); // mov    QWORD PTR [r12+rbx*8+0x18],rdx
 fz_jit_bytes(j,"4883c304"); // add    rbx,0x4
 fz_jit_bytes(j,"4c39c3"); // cmp    rbx,r8
 fz_jit_branch(j,130,83); // jb .LfseRawBuild
 fz_jit_label(j,84); // .LfseBuilt
 fz_jit_bytes(j,"4c89c8"); // mov    rax,r9
 fz_jit_branch8(j,235,86); // jmp .LfseReturn
 fz_jit_label(j,85); // .LfseError
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,86); // .LfseReturn
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_encode_bits(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"4d8b9f18070000"); // mov    r11,QWORD PTR [r15+0x718]
 fz_jit_bytes(j,"49ffcb"); // dec    r11
 fz_jit_bytes(j,"4d89de"); // mov    r14,r11
 fz_jit_bytes(j,"49c1e604"); // shl    r14,0x4
 fz_jit_bytes(j,"4d03b710070000"); // add    r14,QWORD PTR [r15+0x710]
 fz_jit_bytes(j,"4d8baf20070000"); // mov    r13,QWORD PTR [r15+0x720]
 fz_jit_bytes(j,"4d8b8730070000"); // mov    r8,QWORD PTR [r15+0x730]
 fz_jit_bytes(j,"4d8b8f38070000"); // mov    r9,QWORD PTR [r15+0x738]
 fz_jit_bytes(j,"4d8b9740070000"); // mov    r10,QWORD PTR [r15+0x740]
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_bytes(j,"31ed"); // xor    ebp,ebp
 fz_jit_bytes(j,"418b760c"); // mov    esi,DWORD PTR [r14+0xc]
 fz_jit_label(j,87); // .LebExtra
 fz_jit_bytes(j,"4080fe10"); // cmp    sil,0x10
 fz_jit_branch8(j,114,88); // jb .LebSkipLiteral
 fz_jit_bytes(j,"400fb6ce"); // movzx  ecx,sil
 fz_jit_bytes(j,"498b84cf00020000"); // mov    rax,QWORD PTR [r15+rcx*8+0x200]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"418b3e"); // mov    edi,DWORD PTR [r14]
 fz_jit_bytes(j,"4829d7"); // sub    rdi,rdx
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"48c1e920"); // shr    rcx,0x20
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_label(j,88); // .LebSkipLiteral
 fz_jit_bytes(j,"89f1"); // mov    ecx,esi
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"83f920"); // cmp    ecx,0x20
 fz_jit_branch8(j,114,89); // jb .LebSkipMatch
 fz_jit_bytes(j,"498b84cf20030000"); // mov    rax,QWORD PTR [r15+rcx*8+0x320]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"418b7e04"); // mov    edi,DWORD PTR [r14+0x4]
 fz_jit_bytes(j,"4829d7"); // sub    rdi,rdx
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"48c1e920"); // shr    rcx,0x20
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_label(j,89); // .LebSkipMatch
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,90); // jb .LebOffset
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_label(j,90); // .LebOffset
 fz_jit_bytes(j,"89f1"); // mov    ecx,esi
 fz_jit_bytes(j,"c1e910"); // shr    ecx,0x10
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"85c9"); // test   ecx,ecx
 fz_jit_branch8(j,116,91); // je .LebPrevious
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"418b7e08"); // mov    edi,DWORD PTR [r14+0x8]
 fz_jit_bytes(j,"4829c7"); // sub    rdi,rax
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,91); // jb .LebPrevious
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_label(j,91); // .LebPrevious
 fz_jit_bytes(j,"49ffcb"); // dec    r11
 fz_jit_branch(j,136,92); // js .LebStates
 fz_jit_bytes(j,"4983ee10"); // sub    r14,0x10
 fz_jit_bytes(j,"418b760c"); // mov    esi,DWORD PTR [r14+0xc]
 fz_jit_bytes(j,"89f1"); // mov    ecx,esi
 fz_jit_bytes(j,"c1e910"); // shr    ecx,0x10
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"c1e106"); // shl    ecx,0x6
 fz_jit_bytes(j,"4c01c9"); // add    rcx,r9
 fz_jit_bytes(j,"498b87e8000000"); // mov    rax,QWORD PTR [r15+0xe8]
 fz_jit_bytes(j,"4c8b0cc8"); // mov    r9,QWORD PTR [rax+rcx*8]
 fz_jit_bytes(j,"89f1"); // mov    ecx,esi
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"c1e106"); // shl    ecx,0x6
 fz_jit_bytes(j,"4c01d1"); // add    rcx,r10
 fz_jit_bytes(j,"498b87f0000000"); // mov    rax,QWORD PTR [r15+0xf0]
 fz_jit_bytes(j,"4c8b14c8"); // mov    r10,QWORD PTR [rax+rcx*8]
 fz_jit_bytes(j,"400fb6ce"); // movzx  ecx,sil
 fz_jit_bytes(j,"c1e106"); // shl    ecx,0x6
 fz_jit_bytes(j,"4c01c1"); // add    rcx,r8
 fz_jit_bytes(j,"498b87e0000000"); // mov    rax,QWORD PTR [r15+0xe0]
 fz_jit_bytes(j,"4c8b04c8"); // mov    r8,QWORD PTR [rax+rcx*8]
 fz_jit_bytes(j,"4c89cf"); // mov    rdi,r9
 fz_jit_bytes(j,"48c1ef10"); // shr    rdi,0x10
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4489c9"); // mov    ecx,r9d
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_bytes(j,"4181e1ff000000"); // and    r9d,0xff
 fz_jit_bytes(j,"4c89d7"); // mov    rdi,r10
 fz_jit_bytes(j,"48c1ef10"); // shr    rdi,0x10
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4489d1"); // mov    ecx,r10d
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_bytes(j,"4181e2ff000000"); // and    r10d,0xff
 fz_jit_bytes(j,"4c89c7"); // mov    rdi,r8
 fz_jit_bytes(j,"48c1ef10"); // shr    rdi,0x10
 fz_jit_bytes(j,"c4e2d1f7ff"); // shlx   rdi,rdi,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4489c1"); // mov    ecx,r8d
 fz_jit_bytes(j,"c1e908"); // shr    ecx,0x8
 fz_jit_bytes(j,"81e1ff000000"); // and    ecx,0xff
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_bytes(j,"4181e0ff000000"); // and    r8d,0xff
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch(j,130,87); // jb .LebExtra
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_branch(j,233,87); // jmp .LebExtra
 fz_jit_label(j,92); // .LebStates
 fz_jit_bytes(j,"c4c2d1f7fa"); // shlx   rdi,r10,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4903afd8000000"); // add    rbp,QWORD PTR [r15+0xd8]
 fz_jit_bytes(j,"c4c2d1f7f9"); // shlx   rdi,r9,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4903afd0000000"); // add    rbp,QWORD PTR [r15+0xd0]
 fz_jit_bytes(j,"c4c2d1f7f8"); // shlx   rdi,r8,rbp
 fz_jit_bytes(j,"4809fb"); // or     rbx,rdi
 fz_jit_bytes(j,"4903afc8000000"); // add    rbp,QWORD PTR [r15+0xc8]
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,93); // jb .LebStop
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_label(j,93); // .LebStop
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"ffc5"); // inc    ebp
 fz_jit_label(j,94); // .LebBytes
 fz_jit_bytes(j,"41885d00"); // mov    BYTE PTR [r13+0x0],bl
 fz_jit_bytes(j,"49ffc5"); // inc    r13
 fz_jit_bytes(j,"48c1eb08"); // shr    rbx,0x8
 fz_jit_bytes(j,"83ed08"); // sub    ebp,0x8
 fz_jit_branch8(j,127,94); // jg .LebBytes
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"492b8720070000"); // sub    rax,QWORD PTR [r15+0x720]
 fz_jit_branch8(j,235,95); // jmp .LebReturn
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,95); // .LebReturn
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_match(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"4d8bb760070000"); // mov    r14,QWORD PTR [r15+0x760]
 fz_jit_bytes(j,"4d8baf68070000"); // mov    r13,QWORD PTR [r15+0x768]
 fz_jit_bytes(j,"4d8ba770070000"); // mov    r12,QWORD PTR [r15+0x770]
 fz_jit_bytes(j,"4d01ec"); // add    r12,r13
 fz_jit_bytes(j,"4d01f4"); // add    r12,r14
 fz_jit_bytes(j,"4c89eb"); // mov    rbx,r13
 fz_jit_bytes(j,"31ed"); // xor    ebp,ebp
 fz_jit_bytes(j,"4531db"); // xor    r11d,r11d
 fz_jit_bytes(j,"4d8b8790000000"); // mov    r8,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4d8b8f98000000"); // mov    r9,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"4d8b97a0000000"); // mov    r10,QWORD PTR [r15+0xa0]
 fz_jit_bytes(j,"49c7879807000000000000"); // mov    QWORD PTR [r15+0x798],0x0
 fz_jit_label(j,96); // .LmtLoop
 fz_jit_bytes(j,"4b8d442e08"); // lea    rax,[r14+r13*1+0x8]
 fz_jit_bytes(j,"4c39e0"); // cmp    rax,r12
 fz_jit_branch(j,135,117); // ja .LmtDone
 fz_jit_bytes(j,"4d85c0"); // test   r8,r8
 fz_jit_branch8(j,126,97); // jle .LmtHash
 fz_jit_bytes(j,"498d4d01"); // lea    rcx,[r13+0x1]
 fz_jit_bytes(j,"4c39c1"); // cmp    rcx,r8
 fz_jit_branch8(j,114,97); // jb .LmtHash
 fz_jit_bytes(j,"4c29c1"); // sub    rcx,r8
 fz_jit_bytes(j,"418b040e"); // mov    eax,DWORD PTR [r14+rcx*1]
 fz_jit_bytes(j,"433b442e01"); // cmp    eax,DWORD PTR [r14+r13*1+0x1]
 fz_jit_branch8(j,117,97); // jne .LmtHash
 fz_jit_bytes(j,"49ffc5"); // inc    r13
 fz_jit_bytes(j,"ba04000000"); // mov    edx,0x4
 fz_jit_bytes(j,"488d4301"); // lea    rax,[rbx+0x1]
 fz_jit_branch8(j,235,98); // jmp .LmtBack
 fz_jit_label(j,97); // .LmtHash
 fz_jit_bytes(j,"4b8b042e"); // mov    rax,QWORD PTR [r14+r13*1]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"48b9bda7351ebda7351e"); // movabs rcx,0x1e35a7bd1e35a7bd
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_bytes(j,"48c1e836"); // shr    rax,0x36
 fz_jit_bytes(j,"498b8cc700af2400"); // mov    rcx,QWORD PTR [r15+rax*8+0x24af00]
 fz_jit_bytes(j,"4889d7"); // mov    rdi,rdx
 fz_jit_bytes(j,"48c1e720"); // shl    rdi,0x20
 fz_jit_bytes(j,"418d7501"); // lea    esi,[r13+0x1]
 fz_jit_bytes(j,"4809f7"); // or     rdi,rsi
 fz_jit_bytes(j,"4989bcc700af2400"); // mov    QWORD PTR [r15+rax*8+0x24af00],rdi
 fz_jit_bytes(j,"4889ce"); // mov    rsi,rcx
 fz_jit_bytes(j,"48c1ee20"); // shr    rsi,0x20
 fz_jit_bytes(j,"39d6"); // cmp    esi,edx
 fz_jit_branch(j,133,116); // jne .LmtMiss
 fz_jit_bytes(j,"89c9"); // mov    ecx,ecx
 fz_jit_bytes(j,"85c9"); // test   ecx,ecx
 fz_jit_branch(j,132,116); // je .LmtMiss
 fz_jit_bytes(j,"48ffc9"); // dec    rcx
 fz_jit_bytes(j,"4c89ee"); // mov    rsi,r13
 fz_jit_bytes(j,"4829ce"); // sub    rsi,rcx
 fz_jit_bytes(j,"493bb778070000"); // cmp    rsi,QWORD PTR [r15+0x778]
 fz_jit_branch(j,135,116); // ja .LmtMiss
 fz_jit_bytes(j,"ba04000000"); // mov    edx,0x4
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_label(j,98); // .LmtBack
 fz_jit_bytes(j,"4939c5"); // cmp    r13,rax
 fz_jit_branch8(j,118,99); // jbe .LmtPrefix
 fz_jit_bytes(j,"4885c9"); // test   rcx,rcx
 fz_jit_branch8(j,116,99); // je .LmtPrefix
 fz_jit_bytes(j,"430fb6742eff"); // movzx  esi,BYTE PTR [r14+r13*1-0x1]
 fz_jit_bytes(j,"413a740eff"); // cmp    sil,BYTE PTR [r14+rcx*1-0x1]
 fz_jit_branch8(j,117,99); // jne .LmtPrefix
 fz_jit_bytes(j,"49ffcd"); // dec    r13
 fz_jit_bytes(j,"48ffc9"); // dec    rcx
 fz_jit_bytes(j,"48ffc2"); // inc    rdx
 fz_jit_branch8(j,235,98); // jmp .LmtBack
 fz_jit_label(j,99); // .LmtPrefix
 fz_jit_bytes(j,"498d340e"); // lea    rsi,[r14+rcx*1]
 fz_jit_bytes(j,"4801d6"); // add    rsi,rdx
 fz_jit_bytes(j,"4b8d3c2e"); // lea    rdi,[r14+r13*1]
 fz_jit_bytes(j,"4801d7"); // add    rdi,rdx
 fz_jit_bytes(j,"488d4708"); // lea    rax,[rdi+0x8]
 fz_jit_bytes(j,"4c39e0"); // cmp    rax,r12
 fz_jit_branch8(j,119,103); // ja .LmtTailCompare
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"483307"); // xor    rax,QWORD PTR [rdi]
 fz_jit_branch8(j,117,100); // jne .LmtEightDiff
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4883c208"); // add    rdx,0x8
 fz_jit_branch8(j,235,101); // jmp .LmtWideCompare
 fz_jit_label(j,100); // .LmtEightDiff
 fz_jit_bytes(j,"480fbcc0"); // bsf    rax,rax
 fz_jit_bytes(j,"c1e803"); // shr    eax,0x3
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_branch8(j,235,104); // jmp .LmtFound
 fz_jit_label(j,101); // .LmtWideCompare
 fz_jit_bytes(j,"488d4710"); // lea    rax,[rdi+0x10]
 fz_jit_bytes(j,"4c39e0"); // cmp    rax,r12
 fz_jit_branch8(j,119,103); // ja .LmtTailCompare
 fz_jit_bytes(j,"f30f6f06"); // movdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"f30f6f0f"); // movdqu xmm1,XMMWORD PTR [rdi]
 fz_jit_bytes(j,"660f74c1"); // pcmpeqb xmm0,xmm1
 fz_jit_bytes(j,"660fd7c0"); // pmovmskb eax,xmm0
 fz_jit_bytes(j,"35ffff0000"); // xor    eax,0xffff
 fz_jit_branch8(j,117,102); // jne .LmtFirstDiff
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4883c210"); // add    rdx,0x10
 fz_jit_branch8(j,235,101); // jmp .LmtWideCompare
 fz_jit_label(j,102); // .LmtFirstDiff
 fz_jit_bytes(j,"0fbcc0"); // bsf    eax,eax
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_branch8(j,235,104); // jmp .LmtFound
 fz_jit_label(j,103); // .LmtTailCompare
 fz_jit_bytes(j,"4c39e7"); // cmp    rdi,r12
 fz_jit_branch8(j,115,104); // jae .LmtFound
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"3a07"); // cmp    al,BYTE PTR [rdi]
 fz_jit_branch8(j,117,104); // jne .LmtFound
 fz_jit_bytes(j,"48ffc6"); // inc    rsi
 fz_jit_bytes(j,"48ffc7"); // inc    rdi
 fz_jit_bytes(j,"48ffc2"); // inc    rdx
 fz_jit_branch8(j,235,103); // jmp .LmtTailCompare
 fz_jit_label(j,104); // .LmtFound
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"4c29e9"); // sub    rcx,r13
 fz_jit_bytes(j,"48f7d9"); // neg    rcx
 fz_jit_bytes(j,"4d85db"); // test   r11,r11
 fz_jit_branch8(j,117,105); // jne .LmtOffset
 fz_jit_bytes(j,"49898f98070000"); // mov    QWORD PTR [r15+0x798],rcx
 fz_jit_label(j,105); // .LmtOffset
 fz_jit_bytes(j,"488d7903"); // lea    rdi,[rcx+0x3]
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch8(j,116,106); // je .LmtNotFirst
 fz_jit_bytes(j,"4c39c1"); // cmp    rcx,r8
 fz_jit_branch8(j,117,106); // jne .LmtNotFirst
 fz_jit_bytes(j,"bf01000000"); // mov    edi,0x1
 fz_jit_branch8(j,235,110); // jmp .LmtStore
 fz_jit_label(j,106); // .LmtNotFirst
 fz_jit_bytes(j,"4c39c9"); // cmp    rcx,r9
 fz_jit_branch8(j,117,107); // jne .LmtNotSecond
 fz_jit_bytes(j,"bf02000000"); // mov    edi,0x2
 fz_jit_bytes(j,"4883f801"); // cmp    rax,0x1
 fz_jit_bytes(j,"4883df00"); // sbb    rdi,0x0
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_branch8(j,235,110); // jmp .LmtStore
 fz_jit_label(j,107); // .LmtNotSecond
 fz_jit_bytes(j,"4c39d1"); // cmp    rcx,r10
 fz_jit_branch8(j,117,108); // jne .LmtNotThird
 fz_jit_bytes(j,"bf03000000"); // mov    edi,0x3
 fz_jit_bytes(j,"4883f801"); // cmp    rax,0x1
 fz_jit_bytes(j,"4883df00"); // sbb    rdi,0x0
 fz_jit_bytes(j,"4d89ca"); // mov    r10,r9
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_branch8(j,235,110); // jmp .LmtStore
 fz_jit_label(j,108); // .LmtNotThird
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch8(j,117,109); // jne .LmtNewOffset
 fz_jit_bytes(j,"498d70ff"); // lea    rsi,[r8-0x1]
 fz_jit_bytes(j,"4839f1"); // cmp    rcx,rsi
 fz_jit_branch8(j,117,109); // jne .LmtNewOffset
 fz_jit_bytes(j,"bf03000000"); // mov    edi,0x3
 fz_jit_label(j,109); // .LmtNewOffset
 fz_jit_bytes(j,"4d89ca"); // mov    r10,r9
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_label(j,110); // .LmtStore
 fz_jit_bytes(j,"4c89de"); // mov    rsi,r11
 fz_jit_bytes(j,"48c1e604"); // shl    rsi,0x4
 fz_jit_bytes(j,"498db43700200b00"); // lea    rsi,[r15+rsi*1+0xb2000]
 fz_jit_bytes(j,"8906"); // mov    DWORD PTR [rsi],eax
 fz_jit_bytes(j,"895604"); // mov    DWORD PTR [rsi+0x4],edx
 fz_jit_bytes(j,"897e08"); // mov    DWORD PTR [rsi+0x8],edi
 fz_jit_bytes(j,"49ffc3"); // inc    r11
 fz_jit_bytes(j,"483d00010000"); // cmp    rax,0x100
 fz_jit_branch8(j,115,111); // jae .LmtLongLiteral
 fz_jit_bytes(j,"410fb6840760182300"); // movzx  eax,BYTE PTR [r15+rax*1+0x231860]
 fz_jit_branch8(j,235,112); // jmp .LmtLiteralCode
 fz_jit_label(j,111); // .LmtLongLiteral
 fz_jit_bytes(j,"480fbdc0"); // bsr    rax,rax
 fz_jit_bytes(j,"83c013"); // add    eax,0x13
 fz_jit_label(j,112); // .LmtLiteralCode
 fz_jit_bytes(j,"89c7"); // mov    edi,eax
 fz_jit_bytes(j,"4889d0"); // mov    rax,rdx
 fz_jit_bytes(j,"483d00010000"); // cmp    rax,0x100
 fz_jit_branch8(j,115,113); // jae .LmtLongMatch
 fz_jit_bytes(j,"410fb6840760192300"); // movzx  eax,BYTE PTR [r15+rax*1+0x231960]
 fz_jit_branch8(j,235,114); // jmp .LmtMatchCode
 fz_jit_label(j,113); // .LmtLongMatch
 fz_jit_bytes(j,"4883e803"); // sub    rax,0x3
 fz_jit_bytes(j,"480fbdc0"); // bsr    rax,rax
 fz_jit_bytes(j,"83c024"); // add    eax,0x24
 fz_jit_label(j,114); // .LmtMatchCode
 fz_jit_bytes(j,"c1e008"); // shl    eax,0x8
 fz_jit_bytes(j,"09c7"); // or     edi,eax
 fz_jit_bytes(j,"8b4608"); // mov    eax,DWORD PTR [rsi+0x8]
 fz_jit_bytes(j,"480fbdc0"); // bsr    rax,rax
 fz_jit_bytes(j,"c1e010"); // shl    eax,0x10
 fz_jit_bytes(j,"09c7"); // or     edi,eax
 fz_jit_bytes(j,"897e0c"); // mov    DWORD PTR [rsi+0xc],edi
 fz_jit_bytes(j,"400fb6c7"); // movzx  eax,dil
 fz_jit_bytes(j,"49ff84c700180600"); // inc    QWORD PTR [r15+rax*8+0x61800]
 fz_jit_bytes(j,"89f8"); // mov    eax,edi
 fz_jit_bytes(j,"c1e808"); // shr    eax,0x8
 fz_jit_bytes(j,"25ff000000"); // and    eax,0xff
 fz_jit_bytes(j,"49ff84c7001c0600"); // inc    QWORD PTR [r15+rax*8+0x61c00]
 fz_jit_bytes(j,"89f8"); // mov    eax,edi
 fz_jit_bytes(j,"c1e810"); // shr    eax,0x10
 fz_jit_bytes(j,"49ff84c7001a0600"); // inc    QWORD PTR [r15+rax*8+0x61a00]
 fz_jit_bytes(j,"8b0e"); // mov    ecx,DWORD PTR [rsi]
 fz_jit_bytes(j,"498d341e"); // lea    rsi,[r14+rbx*1]
 fz_jit_bytes(j,"498dbc2f00200900"); // lea    rdi,[r15+rbp*1+0x92000]
 fz_jit_bytes(j,"4801cd"); // add    rbp,rcx
 fz_jit_label(j,115); // .LmtCopyLiteral
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4883e908"); // sub    rcx,0x8
 fz_jit_branch8(j,127,115); // jg .LmtCopyLiteral
 fz_jit_bytes(j,"4901d5"); // add    r13,rdx
 fz_jit_bytes(j,"4c89eb"); // mov    rbx,r13
 fz_jit_bytes(j,"4b8d442e06"); // lea    rax,[r14+r13*1+0x6]
 fz_jit_bytes(j,"4c39e0"); // cmp    rax,r12
 fz_jit_branch(j,135,96); // ja .LmtLoop
 fz_jit_bytes(j,"4b8b442efe"); // mov    rax,QWORD PTR [r14+r13*1-0x2]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"48b9bda7351ebda7351e"); // movabs rcx,0x1e35a7bd1e35a7bd
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_bytes(j,"48c1e836"); // shr    rax,0x36
 fz_jit_bytes(j,"48c1e220"); // shl    rdx,0x20
 fz_jit_bytes(j,"418d75ff"); // lea    esi,[r13-0x1]
 fz_jit_bytes(j,"4809f2"); // or     rdx,rsi
 fz_jit_bytes(j,"498994c700af2400"); // mov    QWORD PTR [r15+rax*8+0x24af00],rdx
 fz_jit_bytes(j,"4b8d442e07"); // lea    rax,[r14+r13*1+0x7]
 fz_jit_bytes(j,"4c39e0"); // cmp    rax,r12
 fz_jit_branch(j,135,96); // ja .LmtLoop
 fz_jit_bytes(j,"4b8b442eff"); // mov    rax,QWORD PTR [r14+r13*1-0x1]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_bytes(j,"48c1e836"); // shr    rax,0x36
 fz_jit_bytes(j,"48c1e220"); // shl    rdx,0x20
 fz_jit_bytes(j,"4c09ea"); // or     rdx,r13
 fz_jit_bytes(j,"498994c700af2400"); // mov    QWORD PTR [r15+rax*8+0x24af00],rdx
 fz_jit_branch(j,233,96); // jmp .LmtLoop
 fz_jit_label(j,116); // .LmtMiss
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"48c1e806"); // shr    rax,0x6
 fz_jit_bytes(j,"4d8d6c0502"); // lea    r13,[r13+rax*1+0x2]
 fz_jit_branch(j,233,96); // jmp .LmtLoop
 fz_jit_label(j,117); // .LmtDone
 fz_jit_bytes(j,"49899f88070000"); // mov    QWORD PTR [r15+0x788],rbx
 fz_jit_bytes(j,"4989af90070000"); // mov    QWORD PTR [r15+0x790],rbp
 fz_jit_bytes(j,"4d898790000000"); // mov    QWORD PTR [r15+0x90],r8
 fz_jit_bytes(j,"4d898f98000000"); // mov    QWORD PTR [r15+0x98],r9
 fz_jit_bytes(j,"4d8997a0000000"); // mov    QWORD PTR [r15+0xa0],r10
 fz_jit_bytes(j,"4c89d8"); // mov    rax,r11
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_huffman_encode(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"4d8ba758070000"); // mov    r12,QWORD PTR [r15+0x758]
 fz_jit_bytes(j,"498bb760070000"); // mov    rsi,QWORD PTR [r15+0x760]
 fz_jit_bytes(j,"4c01e6"); // add    rsi,r12
 fz_jit_bytes(j,"4d8baf68070000"); // mov    r13,QWORD PTR [r15+0x768]
 fz_jit_bytes(j,"4d8db700772200"); // lea    r14,[r15+0x227700]
 fz_jit_bytes(j,"31db"); // xor    ebx,ebx
 fz_jit_bytes(j,"31ed"); // xor    ebp,ebp
 fz_jit_label(j,118); // .LheGroup
 fz_jit_bytes(j,"4889f0"); // mov    rax,rsi
 fz_jit_bytes(j,"4c29e0"); // sub    rax,r12
 fz_jit_bytes(j,"4883f804"); // cmp    rax,0x4
 fz_jit_branch(j,130,121); // jb .LheTail
 fz_jit_bytes(j,"8b46fc"); // mov    eax,DWORD PTR [rsi-0x4]
 fz_jit_bytes(j,"4883ee04"); // sub    rsi,0x4
 fz_jit_bytes(j,"4189c0"); // mov    r8d,eax
 fz_jit_bytes(j,"41c1e818"); // shr    r8d,0x18
 fz_jit_bytes(j,"4f8b04c6"); // mov    r8,QWORD PTR [r14+r8*8]
 fz_jit_bytes(j,"4189c1"); // mov    r9d,eax
 fz_jit_bytes(j,"41c1e910"); // shr    r9d,0x10
 fz_jit_bytes(j,"4181e1ff000000"); // and    r9d,0xff
 fz_jit_bytes(j,"4f8b0cce"); // mov    r9,QWORD PTR [r14+r9*8]
 fz_jit_bytes(j,"4189c2"); // mov    r10d,eax
 fz_jit_bytes(j,"41c1ea08"); // shr    r10d,0x8
 fz_jit_bytes(j,"4181e2ff000000"); // and    r10d,0xff
 fz_jit_bytes(j,"4f8b14d6"); // mov    r10,QWORD PTR [r14+r10*8]
 fz_jit_bytes(j,"25ff000000"); // and    eax,0xff
 fz_jit_bytes(j,"4d8b1cc6"); // mov    r11,QWORD PTR [r14+rax*8]
 fz_jit_bytes(j,"4489c2"); // mov    edx,r8d
 fz_jit_bytes(j,"81e2ffff0000"); // and    edx,0xffff
 fz_jit_bytes(j,"c4e2d1f7d2"); // shlx   rdx,rdx,rbp
 fz_jit_bytes(j,"4809d3"); // or     rbx,rdx
 fz_jit_bytes(j,"49c1e810"); // shr    r8,0x10
 fz_jit_bytes(j,"4c01c5"); // add    rbp,r8
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_bytes(j,"81e2ffff0000"); // and    edx,0xffff
 fz_jit_bytes(j,"c4e2d1f7d2"); // shlx   rdx,rdx,rbp
 fz_jit_bytes(j,"4809d3"); // or     rbx,rdx
 fz_jit_bytes(j,"49c1e910"); // shr    r9,0x10
 fz_jit_bytes(j,"4c01cd"); // add    rbp,r9
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,119); // jb .LheFlush1
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_label(j,119); // .LheFlush1
 fz_jit_bytes(j,"4489d2"); // mov    edx,r10d
 fz_jit_bytes(j,"81e2ffff0000"); // and    edx,0xffff
 fz_jit_bytes(j,"c4e2d1f7d2"); // shlx   rdx,rdx,rbp
 fz_jit_bytes(j,"4809d3"); // or     rbx,rdx
 fz_jit_bytes(j,"49c1ea10"); // shr    r10,0x10
 fz_jit_bytes(j,"4c01d5"); // add    rbp,r10
 fz_jit_bytes(j,"4489da"); // mov    edx,r11d
 fz_jit_bytes(j,"81e2ffff0000"); // and    edx,0xffff
 fz_jit_bytes(j,"c4e2d1f7d2"); // shlx   rdx,rdx,rbp
 fz_jit_bytes(j,"4809d3"); // or     rbx,rdx
 fz_jit_bytes(j,"49c1eb10"); // shr    r11,0x10
 fz_jit_bytes(j,"4c01dd"); // add    rbp,r11
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,120); // jb .LheFlush3
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_label(j,120); // .LheFlush3
 fz_jit_branch(j,233,118); // jmp .LheGroup
 fz_jit_label(j,121); // .LheTail
 fz_jit_bytes(j,"4c39e6"); // cmp    rsi,r12
 fz_jit_branch8(j,118,122); // jbe .LheStop
 fz_jit_bytes(j,"48ffce"); // dec    rsi
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"498b04c6"); // mov    rax,QWORD PTR [r14+rax*8]
 fz_jit_bytes(j,"89c2"); // mov    edx,eax
 fz_jit_bytes(j,"81e2ffff0000"); // and    edx,0xffff
 fz_jit_bytes(j,"c4e2d1f7d2"); // shlx   rdx,rdx,rbp
 fz_jit_bytes(j,"4809d3"); // or     rbx,rdx
 fz_jit_bytes(j,"48c1e810"); // shr    rax,0x10
 fz_jit_bytes(j,"4801c5"); // add    rbp,rax
 fz_jit_bytes(j,"83fd20"); // cmp    ebp,0x20
 fz_jit_branch8(j,114,121); // jb .LheTail
 fz_jit_bytes(j,"41895d00"); // mov    DWORD PTR [r13+0x0],ebx
 fz_jit_bytes(j,"4983c504"); // add    r13,0x4
 fz_jit_bytes(j,"48c1eb20"); // shr    rbx,0x20
 fz_jit_bytes(j,"83ed20"); // sub    ebp,0x20
 fz_jit_branch8(j,235,121); // jmp .LheTail
 fz_jit_label(j,122); // .LheStop
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"c4e2d1f7c0"); // shlx   rax,rax,rbp
 fz_jit_bytes(j,"4809c3"); // or     rbx,rax
 fz_jit_bytes(j,"ffc5"); // inc    ebp
 fz_jit_label(j,123); // .LheBytes
 fz_jit_bytes(j,"41885d00"); // mov    BYTE PTR [r13+0x0],bl
 fz_jit_bytes(j,"49ffc5"); // inc    r13
 fz_jit_bytes(j,"48c1eb08"); // shr    rbx,0x8
 fz_jit_bytes(j,"83ed08"); // sub    ebp,0x8
 fz_jit_branch8(j,127,123); // jg .LheBytes
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"492b8768070000"); // sub    rax,QWORD PTR [r15+0x768]
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_histogram(j) {
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"488b9f58070000"); // mov    rbx,QWORD PTR [rdi+0x758]
 fz_jit_bytes(j,"488baf60070000"); // mov    rbp,QWORD PTR [rdi+0x760]
 fz_jit_bytes(j,"4c8d87002e2200"); // lea    r8,[rdi+0x222e00]
 fz_jit_bytes(j,"4c8d8f003e2200"); // lea    r9,[rdi+0x223e00]
 fz_jit_bytes(j,"4c8d9700462200"); // lea    r10,[rdi+0x224600]
 fz_jit_bytes(j,"4c8d9f004e2200"); // lea    r11,[rdi+0x224e00]
 fz_jit_bytes(j,"4c89c7"); // mov    rdi,r8
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_bytes(j,"b900010000"); // mov    ecx,0x100
 fz_jit_bytes(j,"f348ab"); // rep stos QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4c89cf"); // mov    rdi,r9
 fz_jit_bytes(j,"b900030000"); // mov    ecx,0x300
 fz_jit_bytes(j,"f348ab"); // rep stos QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4889de"); // mov    rsi,rbx
 fz_jit_bytes(j,"4889e9"); // mov    rcx,rbp
 fz_jit_bytes(j,"48c1e902"); // shr    rcx,0x2
 fz_jit_branch8(j,116,125); // je .LhistTail
 fz_jit_label(j,124); // .LhistLoop
 fz_jit_bytes(j,"8b06"); // mov    eax,DWORD PTR [rsi]
 fz_jit_bytes(j,"0fb6f8"); // movzx  edi,al
 fz_jit_bytes(j,"49ff04f8"); // inc    QWORD PTR [r8+rdi*8]
 fz_jit_bytes(j,"0fb6d4"); // movzx  edx,ah
 fz_jit_bytes(j,"49ff04d1"); // inc    QWORD PTR [r9+rdx*8]
 fz_jit_bytes(j,"c1e810"); // shr    eax,0x10
 fz_jit_bytes(j,"0fb6f8"); // movzx  edi,al
 fz_jit_bytes(j,"49ff04fa"); // inc    QWORD PTR [r10+rdi*8]
 fz_jit_bytes(j,"0fb6d4"); // movzx  edx,ah
 fz_jit_bytes(j,"49ff04d3"); // inc    QWORD PTR [r11+rdx*8]
 fz_jit_bytes(j,"4883c604"); // add    rsi,0x4
 fz_jit_bytes(j,"48ffc9"); // dec    rcx
 fz_jit_branch8(j,117,124); // jne .LhistLoop
 fz_jit_label(j,125); // .LhistTail
 fz_jit_bytes(j,"83e503"); // and    ebp,0x3
 fz_jit_branch8(j,116,127); // je .LhistMerge
 fz_jit_label(j,126); // .LhistLast
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"49ff04c0"); // inc    QWORD PTR [r8+rax*8]
 fz_jit_bytes(j,"48ffc6"); // inc    rsi
 fz_jit_bytes(j,"ffcd"); // dec    ebp
 fz_jit_branch8(j,117,126); // jne .LhistLast
 fz_jit_label(j,127); // .LhistMerge
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_label(j,128); // .LhistSum
 fz_jit_bytes(j,"f3410f6f0400"); // movdqu xmm0,XMMWORD PTR [r8+rax*1]
 fz_jit_bytes(j,"f3410f6f0c01"); // movdqu xmm1,XMMWORD PTR [r9+rax*1]
 fz_jit_bytes(j,"660fd4c1"); // paddq  xmm0,xmm1
 fz_jit_bytes(j,"f3410f6f0c02"); // movdqu xmm1,XMMWORD PTR [r10+rax*1]
 fz_jit_bytes(j,"660fd4c1"); // paddq  xmm0,xmm1
 fz_jit_bytes(j,"f3410f6f0c03"); // movdqu xmm1,XMMWORD PTR [r11+rax*1]
 fz_jit_bytes(j,"660fd4c1"); // paddq  xmm0,xmm1
 fz_jit_bytes(j,"f3410f7f0400"); // movdqu XMMWORD PTR [r8+rax*1],xmm0
 fz_jit_bytes(j,"4883c010"); // add    rax,0x10
 fz_jit_bytes(j,"3d00080000"); // cmp    eax,0x800
 fz_jit_branch8(j,114,128); // jb .LhistSum
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_huffman_table(j) {
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4989f8"); // mov    r8,rdi
 fz_jit_bytes(j,"4d8b88a8000000"); // mov    r9,QWORD PTR [r8+0xa8]
 fz_jit_bytes(j,"4d8b90f0070000"); // mov    r10,QWORD PTR [r8+0x7f0]
 fz_jit_bytes(j,"4d8d9800980000"); // lea    r11,[r8+0x9800]
 fz_jit_bytes(j,"4d8da000a00000"); // lea    r12,[r8+0xa000]
 fz_jit_bytes(j,"4d8da800580000"); // lea    r13,[r8+0x5800]
 fz_jit_bytes(j,"31d2"); // xor    edx,edx
 fz_jit_label(j,129); // .LhtFill
 fz_jit_bytes(j,"498b0cd3"); // mov    rcx,QWORD PTR [r11+rdx*8]
 fz_jit_bytes(j,"4885c9"); // test   rcx,rcx
 fz_jit_branch8(j,116,130); // je .LhtNext
 fz_jit_bytes(j,"498b3ccc"); // mov    rdi,QWORD PTR [r12+rcx*8]
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"8d59ff"); // lea    ebx,[rcx-0x1]
 fz_jit_bytes(j,"c4e2e1f7c0"); // shlx   rax,rax,rbx
 fz_jit_bytes(j,"490104cc"); // add    QWORD PTR [r12+rcx*8],rax
 fz_jit_bytes(j,"4c89cb"); // mov    rbx,r9
 fz_jit_bytes(j,"ffc3"); // inc    ebx
 fz_jit_bytes(j,"29cb"); // sub    ebx,ecx
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429c9"); // sub    ecx,r9d
 fz_jit_bytes(j,"c4e2f1f7ff"); // shlx   rdi,rdi,rcx
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"498d7cbd00"); // lea    rdi,[r13+rdi*4+0x0]
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"89d0"); // mov    eax,edx
 fz_jit_bytes(j,"c1e008"); // shl    eax,0x8
 fz_jit_bytes(j,"09d8"); // or     eax,ebx
 fz_jit_bytes(j,"f3ab"); // rep stos DWORD PTR [rdi],eax
 fz_jit_label(j,130); // .LhtNext
 fz_jit_bytes(j,"ffc2"); // inc    edx
 fz_jit_bytes(j,"4c39d2"); // cmp    rdx,r10
 fz_jit_branch8(j,114,129); // jb .LhtFill
 fz_jit_bytes(j,"41b90b000000"); // mov    r9d,0xb
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"c462b1f7d0"); // shlx   r10,rax,r9
 fz_jit_bytes(j,"4d8d5aff"); // lea    r11,[r10-0x1]
 fz_jit_bytes(j,"31d2"); // xor    edx,edx
 fz_jit_label(j,131); // .LhtDual
 fz_jit_bytes(j,"418b449500"); // mov    eax,DWORD PTR [r13+rdx*4+0x0]
 fz_jit_bytes(j,"0fb6c8"); // movzx  ecx,al
 fz_jit_bytes(j,"c4e2f1f7fa"); // shlx   rdi,rdx,rcx
 fz_jit_bytes(j,"4c21df"); // and    rdi,r11
 fz_jit_bytes(j,"418b7cbd00"); // mov    edi,DWORD PTR [r13+rdi*4+0x0]
 fz_jit_bytes(j,"400fb6df"); // movzx  ebx,dil
 fz_jit_bytes(j,"01cb"); // add    ebx,ecx
 fz_jit_bytes(j,"4439cb"); // cmp    ebx,r9d
 fz_jit_branch8(j,119,132); // ja .LhtSingle
 fz_jit_bytes(j,"2500ff0000"); // and    eax,0xff00
 fz_jit_bytes(j,"81e700ff0000"); // and    edi,0xff00
 fz_jit_bytes(j,"c1e708"); // shl    edi,0x8
 fz_jit_bytes(j,"09f8"); // or     eax,edi
 fz_jit_bytes(j,"09d8"); // or     eax,ebx
 fz_jit_bytes(j,"0d00000001"); // or     eax,0x1000000
 fz_jit_label(j,132); // .LhtSingle
 fz_jit_bytes(j,"4189849000780000"); // mov    DWORD PTR [r8+rdx*4+0x7800],eax
 fz_jit_bytes(j,"ffc2"); // inc    edx
 fz_jit_bytes(j,"4c39d2"); // cmp    rdx,r10
 fz_jit_branch8(j,114,131); // jb .LhtDual
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_huffman_weights(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4883ec08"); // sub    rsp,0x8
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"498dbf00a00000"); // lea    rdi,[r15+0xa000]
 fz_jit_bytes(j,"31c0"); // xor    eax,eax
 fz_jit_bytes(j,"b90d000000"); // mov    ecx,0xd
 fz_jit_bytes(j,"f348ab"); // rep stos QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4d8bb758070000"); // mov    r14,QWORD PTR [r15+0x758]
 fz_jit_bytes(j,"4d8baf60070000"); // mov    r13,QWORD PTR [r15+0x760]
 fz_jit_bytes(j,"4d8ba768070000"); // mov    r12,QWORD PTR [r15+0x768]
 fz_jit_bytes(j,"4d85e4"); // test   r12,r12
 fz_jit_branch(j,136,149); // js .LhwError
 fz_jit_bytes(j,"4d39ec"); // cmp    r12,r13
 fz_jit_branch(j,131,149); // jae .LhwError
 fz_jit_bytes(j,"430fb61c26"); // movzx  ebx,BYTE PTR [r14+r12*1]
 fz_jit_bytes(j,"49ffc4"); // inc    r12
 fz_jit_bytes(j,"81fb80000000"); // cmp    ebx,0x80
 fz_jit_branch(j,131,142); // jae .LhwRaw
 fz_jit_bytes(j,"85db"); // test   ebx,ebx
 fz_jit_branch(j,132,149); // je .LhwError
 fz_jit_bytes(j,"4c01e3"); // add    rbx,r12
 fz_jit_bytes(j,"4c39eb"); // cmp    rbx,r13
 fz_jit_branch(j,135,149); // ja .LhwError
 fz_jit_bytes(j,"48891c24"); // mov    QWORD PTR [rsp],rbx
 fz_jit_bytes(j,"4d89b7a0070000"); // mov    QWORD PTR [r15+0x7a0],r14
 fz_jit_bytes(j,"49899fa8070000"); // mov    QWORD PTR [r15+0x7a8],rbx
 fz_jit_bytes(j,"4d89a7b0070000"); // mov    QWORD PTR [r15+0x7b0],r12
 fz_jit_bytes(j,"49c787b8070000ff000000"); // mov    QWORD PTR [r15+0x7b8],0xff
 fz_jit_bytes(j,"49c787c007000006000000"); // mov    QWORD PTR [r15+0x7c0],0x6
 fz_jit_bytes(j,"498d8700380000"); // lea    rax,[r15+0x3800]
 fz_jit_bytes(j,"498987c8070000"); // mov    QWORD PTR [r15+0x7c8],rax
 fz_jit_bytes(j,"49c787d007000000000000"); // mov    QWORD PTR [r15+0x7d0],0x0
 fz_jit_bytes(j,"4c89ff"); // mov    rdi,r15
 fz_jit_bytes(j,"41ff9700070000"); // call   QWORD PTR [r15+0x700]
 fz_jit_bytes(j,"4885c0"); // test   rax,rax
 fz_jit_branch(j,136,149); // js .LhwError
 fz_jit_bytes(j,"4983bfb80700000c"); // cmp    QWORD PTR [r15+0x7b8],0xc
 fz_jit_branch(j,135,148); // ja .LhwSlow
 fz_jit_bytes(j,"4889c7"); // mov    rdi,rax
 fz_jit_bytes(j,"498bb730010000"); // mov    rsi,QWORD PTR [r15+0x130]
 fz_jit_bytes(j,"48ffcb"); // dec    rbx
 fz_jit_bytes(j,"4839f3"); // cmp    rbx,rsi
 fz_jit_branch(j,130,149); // jb .LhwError
 fz_jit_bytes(j,"410fb6041e"); // movzx  eax,BYTE PTR [r14+rbx*1]
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch(j,132,149); // je .LhwError
 fz_jit_bytes(j,"480fbdc0"); // bsr    rax,rax
 fz_jit_bytes(j,"4829f3"); // sub    rbx,rsi
 fz_jit_bytes(j,"48c1e303"); // shl    rbx,0x3
 fz_jit_bytes(j,"4801c3"); // add    rbx,rax
 fz_jit_bytes(j,"488d0c3f"); // lea    rcx,[rdi+rdi*1]
 fz_jit_bytes(j,"4839cb"); // cmp    rbx,rcx
 fz_jit_branch(j,130,149); // jb .LhwError
 fz_jit_bytes(j,"4901f6"); // add    r14,rsi
 fz_jit_bytes(j,"4829fb"); // sub    rbx,rdi
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0406"); // mov    rax,QWORD PTR [r14+rax*1]
 fz_jit_bytes(j,"89d9"); // mov    ecx,ebx
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"c462c0f5e0"); // bzhi   r12,rax,rdi
 fz_jit_bytes(j,"4829fb"); // sub    rbx,rdi
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"498b0406"); // mov    rax,QWORD PTR [r14+rax*1]
 fz_jit_bytes(j,"89d9"); // mov    ecx,ebx
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"c4e2f3f7c0"); // shrx   rax,rax,rcx
 fz_jit_bytes(j,"c462c0f5e8"); // bzhi   r13,rax,rdi
 fz_jit_bytes(j,"498daf00980000"); // lea    rbp,[r15+0x9800]
 fz_jit_bytes(j,"4d8d9f00380000"); // lea    r11,[r15+0x3800]
 fz_jit_bytes(j,"4531d2"); // xor    r10d,r10d
 fz_jit_bytes(j,"4531c9"); // xor    r9d,r9d
 fz_jit_bytes(j,"90"); // nop
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_bytes(j,"66662e0f1f840000000000"); // data16 cs nop WORD PTR [rax+rax*1+0x0]
 fz_jit_label(j,133); // .LhwLoop
 fz_jit_bytes(j,"4981fafe000000"); // cmp    r10,0xfe
 fz_jit_branch(j,131,149); // jae .LhwError
 fz_jit_bytes(j,"4f8b04e3"); // mov    r8,QWORD PTR [r11+r12*8]
 fz_jit_bytes(j,"4c89c7"); // mov    rdi,r8
 fz_jit_bytes(j,"48c1ef08"); // shr    rdi,0x8
 fz_jit_bytes(j,"81e7ff000000"); // and    edi,0xff
 fz_jit_bytes(j,"4839fb"); // cmp    rbx,rdi
 fz_jit_branch(j,130,136); // jb .LhwEnd1
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,134); // je .LhwSum_one
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,134); // .LhwSum_one
 fz_jit_bytes(j,"4829fb"); // sub    rbx,rdi
 fz_jit_bytes(j,"4889da"); // mov    rdx,rbx
 fz_jit_bytes(j,"48c1ea03"); // shr    rdx,0x3
 fz_jit_bytes(j,"498b1416"); // mov    rdx,QWORD PTR [r14+rdx*1]
 fz_jit_bytes(j,"89d9"); // mov    ecx,ebx
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"c4e2f3f7d2"); // shrx   rdx,rdx,rcx
 fz_jit_bytes(j,"c4e2c0f5d2"); // bzhi   rdx,rdx,rdi
 fz_jit_bytes(j,"49c1e810"); // shr    r8,0x10
 fz_jit_bytes(j,"4e8d2402"); // lea    r12,[rdx+r8*1]
 fz_jit_bytes(j,"4f8b04eb"); // mov    r8,QWORD PTR [r11+r13*8]
 fz_jit_bytes(j,"4c89c7"); // mov    rdi,r8
 fz_jit_bytes(j,"48c1ef08"); // shr    rdi,0x8
 fz_jit_bytes(j,"81e7ff000000"); // and    edi,0xff
 fz_jit_bytes(j,"4839fb"); // cmp    rbx,rdi
 fz_jit_branch(j,130,139); // jb .LhwEnd2
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,135); // je .LhwSum_two
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,135); // .LhwSum_two
 fz_jit_bytes(j,"4829fb"); // sub    rbx,rdi
 fz_jit_bytes(j,"4889da"); // mov    rdx,rbx
 fz_jit_bytes(j,"48c1ea03"); // shr    rdx,0x3
 fz_jit_bytes(j,"498b1416"); // mov    rdx,QWORD PTR [r14+rdx*1]
 fz_jit_bytes(j,"89d9"); // mov    ecx,ebx
 fz_jit_bytes(j,"83e107"); // and    ecx,0x7
 fz_jit_bytes(j,"c4e2f3f7d2"); // shrx   rdx,rdx,rcx
 fz_jit_bytes(j,"c4e2c0f5d2"); // bzhi   rdx,rdx,rdi
 fz_jit_bytes(j,"49c1e810"); // shr    r8,0x10
 fz_jit_bytes(j,"4e8d2c02"); // lea    r13,[rdx+r8*1]
 fz_jit_branch(j,233,133); // jmp .LhwLoop
 fz_jit_label(j,136); // .LhwEnd1
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,137); // je .LhwSum_end1a
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,137); // .LhwSum_end1a
 fz_jit_bytes(j,"4b8b04eb"); // mov    rax,QWORD PTR [r11+r13*8]
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,138); // je .LhwSum_end1b
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,138); // .LhwSum_end1b
 fz_jit_branch(j,233,146); // jmp .LhwFinish
 fz_jit_label(j,139); // .LhwEnd2
 fz_jit_bytes(j,"4c89c0"); // mov    rax,r8
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,140); // je .LhwSum_end2a
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,140); // .LhwSum_end2a
 fz_jit_bytes(j,"4b8b04e3"); // mov    rax,QWORD PTR [r11+r12*8]
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,141); // je .LhwSum_end2b
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,141); // .LhwSum_end2b
 fz_jit_branch(j,233,146); // jmp .LhwFinish
 fz_jit_label(j,142); // .LhwRaw
 fz_jit_bytes(j,"83eb7f"); // sub    ebx,0x7f
 fz_jit_bytes(j,"488d4301"); // lea    rax,[rbx+0x1]
 fz_jit_bytes(j,"48d1e8"); // shr    rax,1
 fz_jit_bytes(j,"4c01e0"); // add    rax,r12
 fz_jit_bytes(j,"4c39e8"); // cmp    rax,r13
 fz_jit_branch(j,135,149); // ja .LhwError
 fz_jit_bytes(j,"48890424"); // mov    QWORD PTR [rsp],rax
 fz_jit_bytes(j,"4d01e6"); // add    r14,r12
 fz_jit_bytes(j,"4989dc"); // mov    r12,rbx
 fz_jit_bytes(j,"498daf00980000"); // lea    rbp,[r15+0x9800]
 fz_jit_bytes(j,"4531d2"); // xor    r10d,r10d
 fz_jit_bytes(j,"4531c9"); // xor    r9d,r9d
 fz_jit_label(j,143); // .LhwRawLoop
 fz_jit_bytes(j,"450fb606"); // movzx  r8d,BYTE PTR [r14]
 fz_jit_bytes(j,"49ffc6"); // inc    r14
 fz_jit_bytes(j,"4489c0"); // mov    eax,r8d
 fz_jit_bytes(j,"c1e804"); // shr    eax,0x4
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"83f80c"); // cmp    eax,0xc
 fz_jit_branch(j,135,149); // ja .LhwError
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,144); // je .LhwSum_rawhi
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,144); // .LhwSum_rawhi
 fz_jit_bytes(j,"4d39e2"); // cmp    r10,r12
 fz_jit_branch8(j,115,146); // jae .LhwFinish
 fz_jit_bytes(j,"4489c0"); // mov    eax,r8d
 fz_jit_bytes(j,"83e00f"); // and    eax,0xf
 fz_jit_bytes(j,"0fb6c0"); // movzx  eax,al
 fz_jit_bytes(j,"83f80c"); // cmp    eax,0xc
 fz_jit_branch(j,135,149); // ja .LhwError
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,116,145); // je .LhwSum_rawlo
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"8d48ff"); // lea    ecx,[rax-0x1]
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f1f7d2"); // shlx   rdx,rdx,rcx
 fz_jit_bytes(j,"4901d1"); // add    r9,rdx
 fz_jit_label(j,145); // .LhwSum_rawlo
 fz_jit_bytes(j,"4d39e2"); // cmp    r10,r12
 fz_jit_branch8(j,114,143); // jb .LhwRawLoop
 fz_jit_label(j,146); // .LhwFinish
 fz_jit_bytes(j,"4d85c9"); // test   r9,r9
 fz_jit_branch(j,132,149); // je .LhwError
 fz_jit_bytes(j,"490fbdc1"); // bsr    rax,r9
 fz_jit_bytes(j,"ffc0"); // inc    eax
 fz_jit_bytes(j,"83f80b"); // cmp    eax,0xb
 fz_jit_branch(j,135,149); // ja .LhwError
 fz_jit_bytes(j,"498987a8000000"); // mov    QWORD PTR [r15+0xa8],rax
 fz_jit_bytes(j,"ba01000000"); // mov    edx,0x1
 fz_jit_bytes(j,"c4e2f9f7d2"); // shlx   rdx,rdx,rax
 fz_jit_bytes(j,"4c29ca"); // sub    rdx,r9
 fz_jit_bytes(j,"4885d2"); // test   rdx,rdx
 fz_jit_branch8(j,116,149); // je .LhwError
 fz_jit_bytes(j,"488d4aff"); // lea    rcx,[rdx-0x1]
 fz_jit_bytes(j,"4885ca"); // test   rdx,rcx
 fz_jit_branch8(j,117,149); // jne .LhwError
 fz_jit_bytes(j,"480fbdc2"); // bsr    rax,rdx
 fz_jit_bytes(j,"ffc0"); // inc    eax
 fz_jit_bytes(j,"4a8944d500"); // mov    QWORD PTR [rbp+r10*8+0x0],rax
 fz_jit_bytes(j,"49ffc2"); // inc    r10
 fz_jit_bytes(j,"49ff84c700a00000"); // inc    QWORD PTR [r15+rax*8+0xa000]
 fz_jit_bytes(j,"498b8708a00000"); // mov    rax,QWORD PTR [r15+0xa008]
 fz_jit_bytes(j,"4883f802"); // cmp    rax,0x2
 fz_jit_branch8(j,114,149); // jb .LhwError
 fz_jit_bytes(j,"a801"); // test   al,0x1
 fz_jit_branch8(j,117,149); // jne .LhwError
 fz_jit_bytes(j,"31d2"); // xor    edx,edx
 fz_jit_bytes(j,"31c9"); // xor    ecx,ecx
 fz_jit_label(j,147); // .LhwRanks
 fz_jit_bytes(j,"498b84cf08a00000"); // mov    rax,QWORD PTR [r15+rcx*8+0xa008]
 fz_jit_bytes(j,"498994cf08a00000"); // mov    QWORD PTR [r15+rcx*8+0xa008],rdx
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_bytes(j,"ffc1"); // inc    ecx
 fz_jit_bytes(j,"493b8fa8000000"); // cmp    rcx,QWORD PTR [r15+0xa8]
 fz_jit_branch8(j,114,147); // jb .LhwRanks
 fz_jit_bytes(j,"4d8997f0070000"); // mov    QWORD PTR [r15+0x7f0],r10
 fz_jit_bytes(j,"488b0424"); // mov    rax,QWORD PTR [rsp]
 fz_jit_branch8(j,235,150); // jmp .LhwReturn
 fz_jit_label(j,148); // .LhwSlow
 fz_jit_bytes(j,"48c7c0feffffff"); // mov    rax,0xfffffffffffffffe
 fz_jit_branch8(j,235,150); // jmp .LhwReturn
 fz_jit_label(j,149); // .LhwError
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,150); // .LhwReturn
 fz_jit_bytes(j,"4883c408"); // add    rsp,0x8
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_huffman_table_avx2(j) {
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4989f8"); // mov    r8,rdi
 fz_jit_bytes(j,"4d8b88a8000000"); // mov    r9,QWORD PTR [r8+0xa8]
 fz_jit_bytes(j,"4d8b90f0070000"); // mov    r10,QWORD PTR [r8+0x7f0]
 fz_jit_bytes(j,"4d8d9800980000"); // lea    r11,[r8+0x9800]
 fz_jit_bytes(j,"4d8da000a00000"); // lea    r12,[r8+0xa000]
 fz_jit_bytes(j,"4d8da800580000"); // lea    r13,[r8+0x5800]
 fz_jit_bytes(j,"31d2"); // xor    edx,edx
 fz_jit_label(j,151); // .LhtFill
 fz_jit_bytes(j,"498b0cd3"); // mov    rcx,QWORD PTR [r11+rdx*8]
 fz_jit_bytes(j,"4885c9"); // test   rcx,rcx
 fz_jit_branch8(j,116,152); // je .LhtNext
 fz_jit_bytes(j,"498b3ccc"); // mov    rdi,QWORD PTR [r12+rcx*8]
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"8d59ff"); // lea    ebx,[rcx-0x1]
 fz_jit_bytes(j,"c4e2e1f7c0"); // shlx   rax,rax,rbx
 fz_jit_bytes(j,"490104cc"); // add    QWORD PTR [r12+rcx*8],rax
 fz_jit_bytes(j,"4c89cb"); // mov    rbx,r9
 fz_jit_bytes(j,"ffc3"); // inc    ebx
 fz_jit_bytes(j,"29cb"); // sub    ebx,ecx
 fz_jit_bytes(j,"b90b000000"); // mov    ecx,0xb
 fz_jit_bytes(j,"4429c9"); // sub    ecx,r9d
 fz_jit_bytes(j,"c4e2f1f7ff"); // shlx   rdi,rdi,rcx
 fz_jit_bytes(j,"c4e2f1f7c0"); // shlx   rax,rax,rcx
 fz_jit_bytes(j,"498d7cbd00"); // lea    rdi,[r13+rdi*4+0x0]
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"89d0"); // mov    eax,edx
 fz_jit_bytes(j,"c1e008"); // shl    eax,0x8
 fz_jit_bytes(j,"09d8"); // or     eax,ebx
 fz_jit_bytes(j,"f3ab"); // rep stos DWORD PTR [rdi],eax
 fz_jit_label(j,152); // .LhtNext
 fz_jit_bytes(j,"ffc2"); // inc    edx
 fz_jit_bytes(j,"4c39d2"); // cmp    rdx,r10
 fz_jit_branch8(j,114,151); // jb .LhtFill
 fz_jit_bytes(j,"48b80000000001000000"); // movabs rax,0x100000000
 fz_jit_bytes(j,"c4e1f96ef8"); // vmovq  xmm7,rax
 fz_jit_bytes(j,"48b80200000003000000"); // movabs rax,0x300000002
 fz_jit_bytes(j,"c4e1f96ed0"); // vmovq  xmm2,rax
 fz_jit_bytes(j,"c5c16cfa"); // vpunpcklqdq xmm7,xmm7,xmm2
 fz_jit_bytes(j,"48b80400000005000000"); // movabs rax,0x500000004
 fz_jit_bytes(j,"c4e1f96ec8"); // vmovq  xmm1,rax
 fz_jit_bytes(j,"48b80600000007000000"); // movabs rax,0x700000006
 fz_jit_bytes(j,"c4e1f96ed0"); // vmovq  xmm2,rax
 fz_jit_bytes(j,"c5f16cca"); // vpunpcklqdq xmm1,xmm1,xmm2
 fz_jit_bytes(j,"c4e34538f901"); // vinserti128 ymm7,ymm7,xmm1,0x1
 fz_jit_bytes(j,"b8ff070000"); // mov    eax,0x7ff
 fz_jit_bytes(j,"c5796ec0"); // vmovd  xmm8,eax
 fz_jit_bytes(j,"c4427d58c0"); // vpbroadcastd ymm8,xmm8
 fz_jit_bytes(j,"b8ff000000"); // mov    eax,0xff
 fz_jit_bytes(j,"c5796ec8"); // vmovd  xmm9,eax
 fz_jit_bytes(j,"c4427d58c9"); // vpbroadcastd ymm9,xmm9
 fz_jit_bytes(j,"b800ff0000"); // mov    eax,0xff00
 fz_jit_bytes(j,"c5796ed0"); // vmovd  xmm10,eax
 fz_jit_bytes(j,"c4427d58d2"); // vpbroadcastd ymm10,xmm10
 fz_jit_bytes(j,"b80b000000"); // mov    eax,0xb
 fz_jit_bytes(j,"c5796ed8"); // vmovd  xmm11,eax
 fz_jit_bytes(j,"c4427d58db"); // vpbroadcastd ymm11,xmm11
 fz_jit_bytes(j,"b800000001"); // mov    eax,0x1000000
 fz_jit_bytes(j,"c5796ee0"); // vmovd  xmm12,eax
 fz_jit_bytes(j,"c4427d58e4"); // vpbroadcastd ymm12,xmm12
 fz_jit_bytes(j,"b808000000"); // mov    eax,0x8
 fz_jit_bytes(j,"c5796ee8"); // vmovd  xmm13,eax
 fz_jit_bytes(j,"c4427d58ed"); // vpbroadcastd ymm13,xmm13
 fz_jit_bytes(j,"31d2"); // xor    edx,edx
 fz_jit_bytes(j,"0f1f4000"); // nop    DWORD PTR [rax+0x0]
 fz_jit_label(j,153); // .LhtVectorDual
 fz_jit_bytes(j,"c4c17e6f449500"); // vmovdqu ymm0,YMMWORD PTR [r13+rdx*4+0x0]
 fz_jit_bytes(j,"c4c17ddbc9"); // vpand  ymm1,ymm0,ymm9
 fz_jit_bytes(j,"c4e24547d1"); // vpsllvd ymm2,ymm7,ymm1
 fz_jit_bytes(j,"c4c16ddbd0"); // vpand  ymm2,ymm2,ymm8
 fz_jit_bytes(j,"c5e576db"); // vpcmpeqd ymm3,ymm3,ymm3
 fz_jit_bytes(j,"c4c26590649500"); // vpgatherdd ymm4,DWORD PTR [r13+ymm2*4+0x0],ymm3
 fz_jit_bytes(j,"c4c15ddbe9"); // vpand  ymm5,ymm4,ymm9
 fz_jit_bytes(j,"c5d5fee9"); // vpaddd ymm5,ymm5,ymm1
 fz_jit_bytes(j,"c4c17ddbf2"); // vpand  ymm6,ymm0,ymm10
 fz_jit_bytes(j,"c4c15ddbe2"); // vpand  ymm4,ymm4,ymm10
 fz_jit_bytes(j,"c5dd72f408"); // vpslld ymm4,ymm4,0x8
 fz_jit_bytes(j,"c5cdebf4"); // vpor   ymm6,ymm6,ymm4
 fz_jit_bytes(j,"c5cdebf5"); // vpor   ymm6,ymm6,ymm5
 fz_jit_bytes(j,"c4c14debf4"); // vpor   ymm6,ymm6,ymm12
 fz_jit_bytes(j,"c4415566f3"); // vpcmpgtd ymm14,ymm5,ymm11
 fz_jit_bytes(j,"c4e34d4cf0e0"); // vpblendvb ymm6,ymm6,ymm0,ymm14
 fz_jit_bytes(j,"c4c17e7fb49000780000"); // vmovdqu YMMWORD PTR [r8+rdx*4+0x7800],ymm6
 fz_jit_bytes(j,"c4c145fefd"); // vpaddd ymm7,ymm7,ymm13
 fz_jit_bytes(j,"83c208"); // add    edx,0x8
 fz_jit_bytes(j,"81fa00080000"); // cmp    edx,0x800
 fz_jit_branch8(j,114,153); // jb .LhtVectorDual
 fz_jit_bytes(j,"c5f877"); // vzeroupper
 fz_jit_bytes(j,"b801000000"); // mov    eax,0x1
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"c3"); // ret
 return 1;
}

fn fz_emit_sequences_avx2(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"41ffb7a0060000"); // push   QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"4d8bb7b8060000"); // mov    r14,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"4d8baf98060000"); // mov    r13,QWORD PTR [r15+0x698]
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"4d8d7406f9"); // lea    r14,[r14+rax*1-0x7]
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"4d8ba7a0060000"); // mov    r12,QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"498b9fa8060000"); // mov    rbx,QWORD PTR [r15+0x6a8]
 fz_jit_bytes(j,"49039fc0060000"); // add    rbx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498bafc8060000"); // mov    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4903afb0060000"); // add    rbp,QWORD PTR [r15+0x6b0]
 fz_jit_bytes(j,"c4c17a7eb780060000"); // vmovq  xmm6,QWORD PTR [r15+0x680]
 fz_jit_bytes(j,"c4e1f97ef0"); // vmovq  rax,xmm6
 fz_jit_bytes(j,"c4c17a7e9cc700100000"); // vmovq  xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"c4c17a7ebf88060000"); // vmovq  xmm7,QWORD PTR [r15+0x688]
 fz_jit_bytes(j,"c4e1f97ef8"); // vmovq  rax,xmm7
 fz_jit_bytes(j,"c4c17a7ea4c700200000"); // vmovq  xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"c4417a7e8790060000"); // vmovq  xmm8,QWORD PTR [r15+0x690]
 fz_jit_bytes(j,"c461f97ec0"); // vmovq  rax,xmm8
 fz_jit_bytes(j,"c4c17a7eacc700280000"); // vmovq  xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"0f1f00"); // nop    DWORD PTR [rax]
 fz_jit_label(j,154); // .Lloop
 fz_jit_bytes(j,"4983fc02"); // cmp    r12,0x2
 fz_jit_branch(j,130,183); // jb .Ldone
 fz_jit_bytes(j,"4d3bb7b8060000"); // cmp    r14,QWORD PTR [r15+0x6b8]
 fz_jit_branch(j,130,183); // jb .Ldone
 fz_jit_bytes(j,"c4c1f97ed8"); // vmovq  r8,xmm3
 fz_jit_bytes(j,"c4c1f97ee1"); // vmovq  r9,xmm4
 fz_jit_bytes(j,"c4c1f97eea"); // vmovq  r10,xmm5
 fz_jit_bytes(j,"4c89c6"); // mov    rsi,r8
 fz_jit_bytes(j,"48c1ee20"); // shr    rsi,0x20
 fz_jit_bytes(j,"83e61f"); // and    esi,0x1f
 fz_jit_bytes(j,"4c89d7"); // mov    rdi,r10
 fz_jit_bytes(j,"48c1ef20"); // shr    rdi,0x20
 fz_jit_bytes(j,"83e71f"); // and    edi,0x1f
 fz_jit_bytes(j,"4c89ca"); // mov    rdx,r9
 fz_jit_bytes(j,"48c1ea20"); // shr    rdx,0x20
 fz_jit_bytes(j,"83e21f"); // and    edx,0x1f
 fz_jit_bytes(j,"8d0c3e"); // lea    ecx,[rsi+rdi*1]
 fz_jit_bytes(j,"01d1"); // add    ecx,edx
 fz_jit_bytes(j,"83f91d"); // cmp    ecx,0x1d
 fz_jit_branch(j,135,183); // ja .Ldone
 fz_jit_bytes(j,"c4e1f96ec2"); // vmovq  xmm0,rdx
 fz_jit_bytes(j,"418d4d38"); // lea    ecx,[r13+0x38]
 fz_jit_bytes(j,"4d8b1e"); // mov    r11,QWORD PTR [r14]
 fz_jit_bytes(j,"85d2"); // test   edx,edx
 fz_jit_branch8(j,116,155); // je .LofZero
 fz_jit_bytes(j,"29d1"); // sub    ecx,edx
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2e8f5c0"); // bzhi   rax,rax,rdx
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_branch8(j,235,156); // jmp .LofDone
 fz_jit_label(j,155); // .LofZero
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_label(j,156); // .LofDone
 fz_jit_bytes(j,"85ff"); // test   edi,edi
 fz_jit_branch8(j,116,157); // je .LmlZero
 fz_jit_bytes(j,"29f9"); // sub    ecx,edi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c0f5c0"); // bzhi   rax,rax,rdi
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_bytes(j,"4801c7"); // add    rdi,rax
 fz_jit_branch8(j,235,158); // jmp .LmlDone
 fz_jit_label(j,157); // .LmlZero
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_label(j,158); // .LmlDone
 fz_jit_bytes(j,"85f6"); // test   esi,esi
 fz_jit_branch(j,133,186); // jne .LllNonzero
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_label(j,159); // .LllDone
 fz_jit_bytes(j,"488d0433"); // lea    rax,[rbx+rsi*1]
 fz_jit_bytes(j,"4801f8"); // add    rax,rdi
 fz_jit_bytes(j,"4883c040"); // add    rax,0x40
 fz_jit_bytes(j,"493b87d8060000"); // cmp    rax,QWORD PTR [r15+0x6d8]
 fz_jit_branch(j,135,183); // ja .Ldone
 fz_jit_bytes(j,"49c1e825"); // shr    r8,0x25
 fz_jit_bytes(j,"4428c1"); // sub    cl,r8b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b8f5c0"); // bzhi   rax,rax,r8
 fz_jit_bytes(j,"49c1e808"); // shr    r8,0x8
 fz_jit_bytes(j,"4c01c0"); // add    rax,r8
 fz_jit_bytes(j,"c4e1f96ef0"); // vmovq  xmm6,rax
 fz_jit_bytes(j,"c4c17a7e9cc700100000"); // vmovq  xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"49c1ea25"); // shr    r10,0x25
 fz_jit_bytes(j,"4428d1"); // sub    cl,r10b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2a8f5c0"); // bzhi   rax,rax,r10
 fz_jit_bytes(j,"49c1ea08"); // shr    r10,0x8
 fz_jit_bytes(j,"4c01d0"); // add    rax,r10
 fz_jit_bytes(j,"c461f96ec0"); // vmovq  xmm8,rax
 fz_jit_bytes(j,"c4c17a7eacc700280000"); // vmovq  xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"49c1e925"); // shr    r9,0x25
 fz_jit_bytes(j,"4428c9"); // sub    cl,r9b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b0f5c0"); // bzhi   rax,rax,r9
 fz_jit_bytes(j,"49c1e908"); // shr    r9,0x8
 fz_jit_bytes(j,"4c01c8"); // add    rax,r9
 fz_jit_bytes(j,"c4e1f96ef8"); // vmovq  xmm7,rax
 fz_jit_bytes(j,"c4c17a7ea4c700200000"); // vmovq  xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"4189cd"); // mov    r13d,ecx
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"c1e903"); // shr    ecx,0x3
 fz_jit_bytes(j,"4d8d740ef9"); // lea    r14,[r14+rcx*1-0x7]
 fz_jit_bytes(j,"c4e1f97ec0"); // vmovq  rax,xmm0
 fz_jit_bytes(j,"83f801"); // cmp    eax,0x1
 fz_jit_branch8(j,118,160); // jbe .Lrepeat
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"498987a0000000"); // mov    QWORD PTR [r15+0xa0],rax
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"49898798000000"); // mov    QWORD PTR [r15+0x98],rax
 fz_jit_bytes(j,"49899790000000"); // mov    QWORD PTR [r15+0x90],rdx
 fz_jit_branch(j,233,162); // jmp .Loffset
 fz_jit_label(j,160); // .Lrepeat
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,117,161); // jne .LrepeatWide
 fz_jit_bytes(j,"498b9790000000"); // mov    rdx,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4885f6"); // test   rsi,rsi
 fz_jit_branch8(j,117,162); // jne .Loffset
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"49899798000000"); // mov    QWORD PTR [r15+0x98],rdx
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_branch8(j,235,162); // jmp .Loffset
 fz_jit_label(j,161); // .LrepeatWide
 fz_jit_bytes(j,"4883fe01"); // cmp    rsi,0x1
 fz_jit_bytes(j,"4883d200"); // adc    rdx,0x0
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"48ffc8"); // dec    rax
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_bytes(j,"490f4584d788000000"); // cmovne rax,QWORD PTR [r15+rdx*8+0x88]
 fz_jit_bytes(j,"4d8b87a0000000"); // mov    r8,QWORD PTR [r15+0xa0]
 fz_jit_bytes(j,"4d8b8f98000000"); // mov    r9,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_bytes(j,"4d0f45c1"); // cmovne r8,r9
 fz_jit_bytes(j,"4d8987a0000000"); // mov    QWORD PTR [r15+0xa0],r8
 fz_jit_bytes(j,"4d8b8790000000"); // mov    r8,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4d898798000000"); // mov    QWORD PTR [r15+0x98],r8
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_bytes(j,"4885d2"); // test   rdx,rdx
 fz_jit_branch(j,142,184); // jle .Lerror
 fz_jit_label(j,162); // .Loffset
 fz_jit_bytes(j,"4989fa"); // mov    r10,rdi
 fz_jit_bytes(j,"488d443500"); // lea    rax,[rbp+rsi*1+0x0]
 fz_jit_bytes(j,"493b8778060000"); // cmp    rax,QWORD PTR [r15+0x678]
 fz_jit_branch(j,135,184); // ja .Lerror
 fz_jit_bytes(j,"4983bf5806000000"); // cmp    QWORD PTR [r15+0x658],0x0
 fz_jit_branch8(j,117,163); // jne .LwindowOnly
 fz_jit_bytes(j,"498b8760060000"); // mov    rax,QWORD PTR [r15+0x660]
 fz_jit_bytes(j,"4801d8"); // add    rax,rbx
 fz_jit_bytes(j,"4801f0"); // add    rax,rsi
 fz_jit_bytes(j,"493b4738"); // cmp    rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"490f474738"); // cmova  rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,135,184); // ja .Lerror
 fz_jit_branch8(j,235,164); // jmp .Lvalidated
 fz_jit_label(j,163); // .LwindowOnly
 fz_jit_bytes(j,"493b5738"); // cmp    rdx,QWORD PTR [r15+0x38]
 fz_jit_branch(j,135,184); // ja .Lerror
 fz_jit_label(j,164); // .Lvalidated
 fz_jit_bytes(j,"4889f1"); // mov    rcx,rsi
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4801f3"); // add    rbx,rsi
 fz_jit_bytes(j,"4989f0"); // mov    r8,rsi
 fz_jit_bytes(j,"4889ee"); // mov    rsi,rbp
 fz_jit_bytes(j,"4c01c5"); // add    rbp,r8
 fz_jit_label(j,165); // .LliteralWide
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4883e910"); // sub    rcx,0x10
 fz_jit_branch8(j,127,165); // jg .LliteralWide
 fz_jit_branch8(j,235,166); // jmp .Lmatch
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,166); // .Lmatch
 fz_jit_bytes(j,"4983bf6806000000"); // cmp    QWORD PTR [r15+0x668],0x0
 fz_jit_branch(j,133,171); // jne .Lcopy
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b8730060000"); // sub    rax,QWORD PTR [r15+0x630]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,134,171); // jbe .Lcopy
 fz_jit_bytes(j,"4889d1"); // mov    rcx,rdx
 fz_jit_bytes(j,"4829d9"); // sub    rcx,rbx
 fz_jit_bytes(j,"49038fc0060000"); // add    rcx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"4c39d1"); // cmp    rcx,r10
 fz_jit_bytes(j,"490f47ca"); // cmova  rcx,r10
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_bytes(j,"4889d0"); // mov    rax,rdx
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"490387c0060000"); // add    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498b7740"); // mov    rsi,QWORD PTR [r15+0x40]
 fz_jit_bytes(j,"4829c6"); // sub    rsi,rax
 fz_jit_branch8(j,121,167); // jns .Lringindex
 fz_jit_bytes(j,"4903b770060000"); // add    rsi,QWORD PTR [r15+0x670]
 fz_jit_label(j,167); // .Lringindex
 fz_jit_bytes(j,"498b8f70060000"); // mov    rcx,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4829f1"); // sub    rcx,rsi
 fz_jit_bytes(j,"4c39c1"); // cmp    rcx,r8
 fz_jit_bytes(j,"490f47c8"); // cmova  rcx,r8
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4929c9"); // sub    r9,rcx
 fz_jit_bytes(j,"4c01c3"); // add    rbx,r8
 fz_jit_bytes(j,"4d29c2"); // sub    r10,r8
 fz_jit_bytes(j,"49037730"); // add    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4c29c7"); // sub    rdi,r8
 fz_jit_bytes(j,"488d440e07"); // lea    rax,[rsi+rcx*1+0x7]
 fz_jit_bytes(j,"4d8b5f30"); // mov    r11,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4d039f70060000"); // add    r11,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4c39d8"); // cmp    rax,r11
 fz_jit_branch8(j,119,169); // ja .LringExact
 fz_jit_label(j,168); // .LringWide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4883e908"); // sub    rcx,0x8
 fz_jit_branch8(j,127,168); // jg .LringWide
 fz_jit_bytes(j,"4801cf"); // add    rdi,rcx
 fz_jit_branch8(j,235,170); // jmp .LringFirstDone
 fz_jit_label(j,169); // .LringExact
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,170); // .LringFirstDone
 fz_jit_bytes(j,"4d85c9"); // test   r9,r9
 fz_jit_branch8(j,116,171); // je .Lcopy
 fz_jit_bytes(j,"498b7730"); // mov    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4c89c9"); // mov    rcx,r9
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,171); // .Lcopy
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4889fe"); // mov    rsi,rdi
 fz_jit_bytes(j,"4829d6"); // sub    rsi,rdx
 fz_jit_bytes(j,"4c01d3"); // add    rbx,r10
 fz_jit_bytes(j,"4d85d2"); // test   r10,r10
 fz_jit_branch(j,132,182); // je .Lnext
 fz_jit_bytes(j,"4883fa08"); // cmp    rdx,0x8
 fz_jit_branch(j,130,177); // jb .LsmallOffset
 fz_jit_bytes(j,"4883fa20"); // cmp    rdx,0x20
 fz_jit_branch8(j,114,173); // jb .LavxSSE
 fz_jit_label(j,172); // .LavxCopy
 fz_jit_bytes(j,"c5fe6f06"); // vmovdqu ymm0,YMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fe7f07"); // vmovdqu YMMWORD PTR [rdi],ymm0
 fz_jit_bytes(j,"4883c620"); // add    rsi,0x20
 fz_jit_bytes(j,"4883c720"); // add    rdi,0x20
 fz_jit_bytes(j,"4983ea20"); // sub    r10,0x20
 fz_jit_branch8(j,127,172); // jg .LavxCopy
 fz_jit_branch(j,233,182); // jmp .Lnext
 fz_jit_label(j,173); // .LavxSSE
 fz_jit_bytes(j,"4883fa10"); // cmp    rdx,0x10
 fz_jit_branch8(j,114,176); // jb .Lwide
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch(j,142,182); // jle .Lnext
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_label(j,174); // .Lwide32
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"c5fa6f4610"); // vmovdqu xmm0,XMMWORD PTR [rsi+0x10]
 fz_jit_bytes(j,"c5fa7f4710"); // vmovdqu XMMWORD PTR [rdi+0x10],xmm0
 fz_jit_bytes(j,"4883c620"); // add    rsi,0x20
 fz_jit_bytes(j,"4883c720"); // add    rdi,0x20
 fz_jit_bytes(j,"4983ea20"); // sub    r10,0x20
 fz_jit_branch8(j,127,174); // jg .Lwide32
 fz_jit_branch(j,233,182); // jmp .Lnext
 fz_jit_label(j,175); // .Lwide16Tail
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch8(j,127,175); // jg .Lwide16Tail
 fz_jit_branch8(j,235,182); // jmp .Lnext
 fz_jit_label(j,176); // .Lwide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,176); // jg .Lwide
 fz_jit_branch8(j,235,182); // jmp .Lnext
 fz_jit_label(j,177); // .LsmallOffset
 fz_jit_bytes(j,"4883fa01"); // cmp    rdx,0x1
 fz_jit_branch8(j,116,178); // je .Lfill1
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_branch8(j,116,179); // je .Lfill2
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_branch8(j,117,181); // jne .Lbytes
 fz_jit_bytes(j,"8b06"); // mov    eax,DWORD PTR [rsi]
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"48c1e120"); // shl    rcx,0x20
 fz_jit_bytes(j,"4809c8"); // or     rax,rcx
 fz_jit_branch8(j,235,180); // jmp .Lfill
 fz_jit_label(j,178); // .Lfill1
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"48b90101010101010101"); // movabs rcx,0x101010101010101
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_branch8(j,235,180); // jmp .Lfill
 fz_jit_label(j,179); // .Lfill2
 fz_jit_bytes(j,"0fb706"); // movzx  eax,WORD PTR [rsi]
 fz_jit_bytes(j,"48b90100010001000100"); // movabs rcx,0x1000100010001
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_label(j,180); // .Lfill
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,180); // jg .Lfill
 fz_jit_branch8(j,235,182); // jmp .Lnext
 fz_jit_label(j,181); // .Lbytes
 fz_jit_bytes(j,"4c89d1"); // mov    rcx,r10
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,182); // .Lnext
 fz_jit_bytes(j,"49ffcc"); // dec    r12
 fz_jit_branch(j,233,154); // jmp .Lloop
 fz_jit_label(j,183); // .Ldone
 fz_jit_bytes(j,"c4c179d6b780060000"); // vmovq  QWORD PTR [r15+0x680],xmm6
 fz_jit_bytes(j,"c4c179d6bf88060000"); // vmovq  QWORD PTR [r15+0x688],xmm7
 fz_jit_bytes(j,"c44179d68790060000"); // vmovq  QWORD PTR [r15+0x690],xmm8
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"492b87b8060000"); // sub    rax,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"48c1e003"); // shl    rax,0x3
 fz_jit_bytes(j,"4883c038"); // add    rax,0x38
 fz_jit_bytes(j,"4c01e8"); // add    rax,r13
 fz_jit_bytes(j,"49898798060000"); // mov    QWORD PTR [r15+0x698],rax
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b87c0060000"); // sub    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498987a8060000"); // mov    QWORD PTR [r15+0x6a8],rax
 fz_jit_bytes(j,"492bafc8060000"); // sub    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4989afb0060000"); // mov    QWORD PTR [r15+0x6b0],rbp
 fz_jit_bytes(j,"488b0424"); // mov    rax,QWORD PTR [rsp]
 fz_jit_bytes(j,"4c29e0"); // sub    rax,r12
 fz_jit_bytes(j,"4d89a7a0060000"); // mov    QWORD PTR [r15+0x6a0],r12
 fz_jit_branch8(j,235,185); // jmp .Lreturn
 fz_jit_label(j,184); // .Lerror
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,185); // .Lreturn
 fz_jit_bytes(j,"c5f877"); // vzeroupper
 fz_jit_bytes(j,"4883c408"); // add    rsp,0x8
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 fz_jit_label(j,186); // .LllNonzero
 fz_jit_bytes(j,"29f1"); // sub    ecx,esi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c8f5c0"); // bzhi   rax,rax,rsi
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_bytes(j,"4801c6"); // add    rsi,rax
 fz_jit_branch(j,233,159); // jmp .LllDone
 return 1;
}

fn fz_emit_sequences_avx2_large(j) {
 fz_jit_bytes(j,"55"); // push   rbp
 fz_jit_bytes(j,"53"); // push   rbx
 fz_jit_bytes(j,"4154"); // push   r12
 fz_jit_bytes(j,"4155"); // push   r13
 fz_jit_bytes(j,"4156"); // push   r14
 fz_jit_bytes(j,"4157"); // push   r15
 fz_jit_bytes(j,"4989ff"); // mov    r15,rdi
 fz_jit_bytes(j,"41ffb7a0060000"); // push   QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"4d8bb7b8060000"); // mov    r14,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"4d8baf98060000"); // mov    r13,QWORD PTR [r15+0x698]
 fz_jit_bytes(j,"4c89e8"); // mov    rax,r13
 fz_jit_bytes(j,"48c1e803"); // shr    rax,0x3
 fz_jit_bytes(j,"4d8d7406f9"); // lea    r14,[r14+rax*1-0x7]
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"4d8ba7a0060000"); // mov    r12,QWORD PTR [r15+0x6a0]
 fz_jit_bytes(j,"498b9fa8060000"); // mov    rbx,QWORD PTR [r15+0x6a8]
 fz_jit_bytes(j,"49039fc0060000"); // add    rbx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498bafc8060000"); // mov    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4903afb0060000"); // add    rbp,QWORD PTR [r15+0x6b0]
 fz_jit_bytes(j,"c4c17a7eb780060000"); // vmovq  xmm6,QWORD PTR [r15+0x680]
 fz_jit_bytes(j,"c4e1f97ef0"); // vmovq  rax,xmm6
 fz_jit_bytes(j,"c4c17a7e9cc700100000"); // vmovq  xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"c4c17a7ebf88060000"); // vmovq  xmm7,QWORD PTR [r15+0x688]
 fz_jit_bytes(j,"c4e1f97ef8"); // vmovq  rax,xmm7
 fz_jit_bytes(j,"c4c17a7ea4c700200000"); // vmovq  xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"c4417a7e8790060000"); // vmovq  xmm8,QWORD PTR [r15+0x690]
 fz_jit_bytes(j,"c461f97ec0"); // vmovq  rax,xmm8
 fz_jit_bytes(j,"c4c17a7eacc700280000"); // vmovq  xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"0f1f00"); // nop    DWORD PTR [rax]
 fz_jit_label(j,187); // .Lloop
 fz_jit_bytes(j,"4983fc02"); // cmp    r12,0x2
 fz_jit_branch(j,130,217); // jb .Ldone
 fz_jit_bytes(j,"4d3bb7b8060000"); // cmp    r14,QWORD PTR [r15+0x6b8]
 fz_jit_branch(j,130,217); // jb .Ldone
 fz_jit_bytes(j,"c4c1f97ed8"); // vmovq  r8,xmm3
 fz_jit_bytes(j,"c4c1f97ee1"); // vmovq  r9,xmm4
 fz_jit_bytes(j,"c4c1f97eea"); // vmovq  r10,xmm5
 fz_jit_bytes(j,"4c89c6"); // mov    rsi,r8
 fz_jit_bytes(j,"48c1ee20"); // shr    rsi,0x20
 fz_jit_bytes(j,"83e61f"); // and    esi,0x1f
 fz_jit_bytes(j,"4c89d7"); // mov    rdi,r10
 fz_jit_bytes(j,"48c1ef20"); // shr    rdi,0x20
 fz_jit_bytes(j,"83e71f"); // and    edi,0x1f
 fz_jit_bytes(j,"4c89ca"); // mov    rdx,r9
 fz_jit_bytes(j,"48c1ea20"); // shr    rdx,0x20
 fz_jit_bytes(j,"83e21f"); // and    edx,0x1f
 fz_jit_bytes(j,"8d0c3e"); // lea    ecx,[rsi+rdi*1]
 fz_jit_bytes(j,"01d1"); // add    ecx,edx
 fz_jit_bytes(j,"83f91d"); // cmp    ecx,0x1d
 fz_jit_branch(j,135,217); // ja .Ldone
 fz_jit_bytes(j,"c4e1f96ec2"); // vmovq  xmm0,rdx
 fz_jit_bytes(j,"418d4d38"); // lea    ecx,[r13+0x38]
 fz_jit_bytes(j,"4d8b1e"); // mov    r11,QWORD PTR [r14]
 fz_jit_bytes(j,"85d2"); // test   edx,edx
 fz_jit_branch8(j,116,188); // je .LofZero
 fz_jit_bytes(j,"29d1"); // sub    ecx,edx
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2e8f5c0"); // bzhi   rax,rax,rdx
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_bytes(j,"4801c2"); // add    rdx,rax
 fz_jit_branch8(j,235,189); // jmp .LofDone
 fz_jit_label(j,188); // .LofZero
 fz_jit_bytes(j,"4489ca"); // mov    edx,r9d
 fz_jit_label(j,189); // .LofDone
 fz_jit_bytes(j,"85ff"); // test   edi,edi
 fz_jit_branch8(j,116,190); // je .LmlZero
 fz_jit_bytes(j,"29f9"); // sub    ecx,edi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c0f5c0"); // bzhi   rax,rax,rdi
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_bytes(j,"4801c7"); // add    rdi,rax
 fz_jit_branch8(j,235,191); // jmp .LmlDone
 fz_jit_label(j,190); // .LmlZero
 fz_jit_bytes(j,"4489d7"); // mov    edi,r10d
 fz_jit_label(j,191); // .LmlDone
 fz_jit_bytes(j,"85f6"); // test   esi,esi
 fz_jit_branch(j,133,220); // jne .LllNonzero
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_label(j,192); // .LllDone
 fz_jit_bytes(j,"488d0433"); // lea    rax,[rbx+rsi*1]
 fz_jit_bytes(j,"4801f8"); // add    rax,rdi
 fz_jit_bytes(j,"4883c040"); // add    rax,0x40
 fz_jit_bytes(j,"493b87d8060000"); // cmp    rax,QWORD PTR [r15+0x6d8]
 fz_jit_branch(j,135,217); // ja .Ldone
 fz_jit_bytes(j,"49c1e825"); // shr    r8,0x25
 fz_jit_bytes(j,"4428c1"); // sub    cl,r8b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b8f5c0"); // bzhi   rax,rax,r8
 fz_jit_bytes(j,"49c1e808"); // shr    r8,0x8
 fz_jit_bytes(j,"4c01c0"); // add    rax,r8
 fz_jit_bytes(j,"c4e1f96ef0"); // vmovq  xmm6,rax
 fz_jit_bytes(j,"c4c17a7e9cc700100000"); // vmovq  xmm3,QWORD PTR [r15+rax*8+0x1000]
 fz_jit_bytes(j,"49c1ea25"); // shr    r10,0x25
 fz_jit_bytes(j,"4428d1"); // sub    cl,r10b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2a8f5c0"); // bzhi   rax,rax,r10
 fz_jit_bytes(j,"49c1ea08"); // shr    r10,0x8
 fz_jit_bytes(j,"4c01d0"); // add    rax,r10
 fz_jit_bytes(j,"c461f96ec0"); // vmovq  xmm8,rax
 fz_jit_bytes(j,"c4c17a7eacc700280000"); // vmovq  xmm5,QWORD PTR [r15+rax*8+0x2800]
 fz_jit_bytes(j,"49c1e925"); // shr    r9,0x25
 fz_jit_bytes(j,"4428c9"); // sub    cl,r9b
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2b0f5c0"); // bzhi   rax,rax,r9
 fz_jit_bytes(j,"49c1e908"); // shr    r9,0x8
 fz_jit_bytes(j,"4c01c8"); // add    rax,r9
 fz_jit_bytes(j,"c4e1f96ef8"); // vmovq  xmm7,rax
 fz_jit_bytes(j,"c4c17a7ea4c700200000"); // vmovq  xmm4,QWORD PTR [r15+rax*8+0x2000]
 fz_jit_bytes(j,"4189cd"); // mov    r13d,ecx
 fz_jit_bytes(j,"4183e507"); // and    r13d,0x7
 fz_jit_bytes(j,"c1e903"); // shr    ecx,0x3
 fz_jit_bytes(j,"4d8d740ef9"); // lea    r14,[r14+rcx*1-0x7]
 fz_jit_bytes(j,"c4e1f97ec0"); // vmovq  rax,xmm0
 fz_jit_bytes(j,"83f801"); // cmp    eax,0x1
 fz_jit_branch8(j,118,193); // jbe .Lrepeat
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"498987a0000000"); // mov    QWORD PTR [r15+0xa0],rax
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"49898798000000"); // mov    QWORD PTR [r15+0x98],rax
 fz_jit_bytes(j,"49899790000000"); // mov    QWORD PTR [r15+0x90],rdx
 fz_jit_branch(j,233,195); // jmp .Loffset
 fz_jit_label(j,193); // .Lrepeat
 fz_jit_bytes(j,"85c0"); // test   eax,eax
 fz_jit_branch8(j,117,194); // jne .LrepeatWide
 fz_jit_bytes(j,"498b9790000000"); // mov    rdx,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4885f6"); // test   rsi,rsi
 fz_jit_branch8(j,117,195); // jne .Loffset
 fz_jit_bytes(j,"498b8798000000"); // mov    rax,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"49899798000000"); // mov    QWORD PTR [r15+0x98],rdx
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_branch8(j,235,195); // jmp .Loffset
 fz_jit_label(j,194); // .LrepeatWide
 fz_jit_bytes(j,"4883fe01"); // cmp    rsi,0x1
 fz_jit_bytes(j,"4883d200"); // adc    rdx,0x0
 fz_jit_bytes(j,"498b8790000000"); // mov    rax,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"48ffc8"); // dec    rax
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_bytes(j,"490f4584d788000000"); // cmovne rax,QWORD PTR [r15+rdx*8+0x88]
 fz_jit_bytes(j,"4d8b87a0000000"); // mov    r8,QWORD PTR [r15+0xa0]
 fz_jit_bytes(j,"4d8b8f98000000"); // mov    r9,QWORD PTR [r15+0x98]
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_bytes(j,"4d0f45c1"); // cmovne r8,r9
 fz_jit_bytes(j,"4d8987a0000000"); // mov    QWORD PTR [r15+0xa0],r8
 fz_jit_bytes(j,"4d8b8790000000"); // mov    r8,QWORD PTR [r15+0x90]
 fz_jit_bytes(j,"4d898798000000"); // mov    QWORD PTR [r15+0x98],r8
 fz_jit_bytes(j,"49898790000000"); // mov    QWORD PTR [r15+0x90],rax
 fz_jit_bytes(j,"4889c2"); // mov    rdx,rax
 fz_jit_bytes(j,"4885d2"); // test   rdx,rdx
 fz_jit_branch(j,142,218); // jle .Lerror
 fz_jit_label(j,195); // .Loffset
 fz_jit_bytes(j,"4989fa"); // mov    r10,rdi
 fz_jit_bytes(j,"488d443500"); // lea    rax,[rbp+rsi*1+0x0]
 fz_jit_bytes(j,"493b8778060000"); // cmp    rax,QWORD PTR [r15+0x678]
 fz_jit_branch(j,135,218); // ja .Lerror
 fz_jit_bytes(j,"4983bf5806000000"); // cmp    QWORD PTR [r15+0x658],0x0
 fz_jit_branch8(j,117,196); // jne .LwindowOnly
 fz_jit_bytes(j,"498b8760060000"); // mov    rax,QWORD PTR [r15+0x660]
 fz_jit_bytes(j,"4801d8"); // add    rax,rbx
 fz_jit_bytes(j,"4801f0"); // add    rax,rsi
 fz_jit_bytes(j,"493b4738"); // cmp    rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"490f474738"); // cmova  rax,QWORD PTR [r15+0x38]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,135,218); // ja .Lerror
 fz_jit_branch8(j,235,197); // jmp .Lvalidated
 fz_jit_label(j,196); // .LwindowOnly
 fz_jit_bytes(j,"493b5738"); // cmp    rdx,QWORD PTR [r15+0x38]
 fz_jit_branch(j,135,218); // ja .Lerror
 fz_jit_label(j,197); // .Lvalidated
 fz_jit_bytes(j,"4889f1"); // mov    rcx,rsi
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4801f3"); // add    rbx,rsi
 fz_jit_bytes(j,"4989f0"); // mov    r8,rsi
 fz_jit_bytes(j,"4889ee"); // mov    rsi,rbp
 fz_jit_bytes(j,"4c01c5"); // add    rbp,r8
 fz_jit_label(j,198); // .LliteralWide
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4883e910"); // sub    rcx,0x10
 fz_jit_branch8(j,127,198); // jg .LliteralWide
 fz_jit_branch8(j,235,199); // jmp .Lmatch
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,199); // .Lmatch
 fz_jit_bytes(j,"4983bf6806000000"); // cmp    QWORD PTR [r15+0x668],0x0
 fz_jit_branch(j,133,204); // jne .Lcopy
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b8730060000"); // sub    rax,QWORD PTR [r15+0x630]
 fz_jit_bytes(j,"4839c2"); // cmp    rdx,rax
 fz_jit_branch(j,134,204); // jbe .Lcopy
 fz_jit_bytes(j,"4889d1"); // mov    rcx,rdx
 fz_jit_bytes(j,"4829d9"); // sub    rcx,rbx
 fz_jit_bytes(j,"49038fc0060000"); // add    rcx,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"4c39d1"); // cmp    rcx,r10
 fz_jit_bytes(j,"490f47ca"); // cmova  rcx,r10
 fz_jit_bytes(j,"4989c8"); // mov    r8,rcx
 fz_jit_bytes(j,"4889d0"); // mov    rax,rdx
 fz_jit_bytes(j,"4829d8"); // sub    rax,rbx
 fz_jit_bytes(j,"490387c0060000"); // add    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498b7740"); // mov    rsi,QWORD PTR [r15+0x40]
 fz_jit_bytes(j,"4829c6"); // sub    rsi,rax
 fz_jit_branch8(j,121,200); // jns .Lringindex
 fz_jit_bytes(j,"4903b770060000"); // add    rsi,QWORD PTR [r15+0x670]
 fz_jit_label(j,200); // .Lringindex
 fz_jit_bytes(j,"498b8f70060000"); // mov    rcx,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4829f1"); // sub    rcx,rsi
 fz_jit_bytes(j,"4c39c1"); // cmp    rcx,r8
 fz_jit_bytes(j,"490f47c8"); // cmova  rcx,r8
 fz_jit_bytes(j,"4d89c1"); // mov    r9,r8
 fz_jit_bytes(j,"4929c9"); // sub    r9,rcx
 fz_jit_bytes(j,"4c01c3"); // add    rbx,r8
 fz_jit_bytes(j,"4d29c2"); // sub    r10,r8
 fz_jit_bytes(j,"49037730"); // add    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4c29c7"); // sub    rdi,r8
 fz_jit_bytes(j,"488d440e07"); // lea    rax,[rsi+rcx*1+0x7]
 fz_jit_bytes(j,"4d8b5f30"); // mov    r11,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4d039f70060000"); // add    r11,QWORD PTR [r15+0x670]
 fz_jit_bytes(j,"4c39d8"); // cmp    rax,r11
 fz_jit_branch8(j,119,202); // ja .LringExact
 fz_jit_label(j,201); // .LringWide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4883e908"); // sub    rcx,0x8
 fz_jit_branch8(j,127,201); // jg .LringWide
 fz_jit_bytes(j,"4801cf"); // add    rdi,rcx
 fz_jit_branch8(j,235,203); // jmp .LringFirstDone
 fz_jit_label(j,202); // .LringExact
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,203); // .LringFirstDone
 fz_jit_bytes(j,"4d85c9"); // test   r9,r9
 fz_jit_branch8(j,116,204); // je .Lcopy
 fz_jit_bytes(j,"498b7730"); // mov    rsi,QWORD PTR [r15+0x30]
 fz_jit_bytes(j,"4c89c9"); // mov    rcx,r9
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,204); // .Lcopy
 fz_jit_bytes(j,"4889df"); // mov    rdi,rbx
 fz_jit_bytes(j,"4889fe"); // mov    rsi,rdi
 fz_jit_bytes(j,"4829d6"); // sub    rsi,rdx
 fz_jit_bytes(j,"4c01d3"); // add    rbx,r10
 fz_jit_bytes(j,"4d85d2"); // test   r10,r10
 fz_jit_branch(j,132,216); // je .Lnext
 fz_jit_bytes(j,"4883fa08"); // cmp    rdx,0x8
 fz_jit_branch(j,130,211); // jb .LsmallOffset
 fz_jit_bytes(j,"4883fa20"); // cmp    rdx,0x20
 fz_jit_branch8(j,114,207); // jb .LavxSSE
 fz_jit_bytes(j,"4983fa20"); // cmp    r10,0x20
 fz_jit_branch8(j,126,206); // jle .LavxCopy
 fz_jit_label(j,205); // .Lavx64
 fz_jit_bytes(j,"c5fe6f06"); // vmovdqu ymm0,YMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fe7f07"); // vmovdqu YMMWORD PTR [rdi],ymm0
 fz_jit_bytes(j,"c5fe6f4620"); // vmovdqu ymm0,YMMWORD PTR [rsi+0x20]
 fz_jit_bytes(j,"c5fe7f4720"); // vmovdqu YMMWORD PTR [rdi+0x20],ymm0
 fz_jit_bytes(j,"4883c640"); // add    rsi,0x40
 fz_jit_bytes(j,"4883c740"); // add    rdi,0x40
 fz_jit_bytes(j,"4983ea40"); // sub    r10,0x40
 fz_jit_branch8(j,127,205); // jg .Lavx64
 fz_jit_branch(j,233,216); // jmp .Lnext
 fz_jit_label(j,206); // .LavxCopy
 fz_jit_bytes(j,"c5fe6f06"); // vmovdqu ymm0,YMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fe7f07"); // vmovdqu YMMWORD PTR [rdi],ymm0
 fz_jit_bytes(j,"4883c620"); // add    rsi,0x20
 fz_jit_bytes(j,"4883c720"); // add    rdi,0x20
 fz_jit_bytes(j,"4983ea20"); // sub    r10,0x20
 fz_jit_branch8(j,127,206); // jg .LavxCopy
 fz_jit_branch(j,233,216); // jmp .Lnext
 fz_jit_label(j,207); // .LavxSSE
 fz_jit_bytes(j,"4883fa10"); // cmp    rdx,0x10
 fz_jit_branch8(j,114,210); // jb .Lwide
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch(j,142,216); // jle .Lnext
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_label(j,208); // .Lwide32
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"c5fa6f4610"); // vmovdqu xmm0,XMMWORD PTR [rsi+0x10]
 fz_jit_bytes(j,"c5fa7f4710"); // vmovdqu XMMWORD PTR [rdi+0x10],xmm0
 fz_jit_bytes(j,"4883c620"); // add    rsi,0x20
 fz_jit_bytes(j,"4883c720"); // add    rdi,0x20
 fz_jit_bytes(j,"4983ea20"); // sub    r10,0x20
 fz_jit_branch8(j,127,208); // jg .Lwide32
 fz_jit_branch(j,233,216); // jmp .Lnext
 fz_jit_label(j,209); // .Lwide16Tail
 fz_jit_bytes(j,"c5fa6f06"); // vmovdqu xmm0,XMMWORD PTR [rsi]
 fz_jit_bytes(j,"c5fa7f07"); // vmovdqu XMMWORD PTR [rdi],xmm0
 fz_jit_bytes(j,"4883c610"); // add    rsi,0x10
 fz_jit_bytes(j,"4883c710"); // add    rdi,0x10
 fz_jit_bytes(j,"4983ea10"); // sub    r10,0x10
 fz_jit_branch8(j,127,209); // jg .Lwide16Tail
 fz_jit_branch8(j,235,216); // jmp .Lnext
 fz_jit_label(j,210); // .Lwide
 fz_jit_bytes(j,"488b06"); // mov    rax,QWORD PTR [rsi]
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c608"); // add    rsi,0x8
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,210); // jg .Lwide
 fz_jit_branch8(j,235,216); // jmp .Lnext
 fz_jit_label(j,211); // .LsmallOffset
 fz_jit_bytes(j,"4883fa01"); // cmp    rdx,0x1
 fz_jit_branch8(j,116,212); // je .Lfill1
 fz_jit_bytes(j,"4883fa02"); // cmp    rdx,0x2
 fz_jit_branch8(j,116,213); // je .Lfill2
 fz_jit_bytes(j,"4883fa04"); // cmp    rdx,0x4
 fz_jit_branch8(j,117,215); // jne .Lbytes
 fz_jit_bytes(j,"8b06"); // mov    eax,DWORD PTR [rsi]
 fz_jit_bytes(j,"4889c1"); // mov    rcx,rax
 fz_jit_bytes(j,"48c1e120"); // shl    rcx,0x20
 fz_jit_bytes(j,"4809c8"); // or     rax,rcx
 fz_jit_branch8(j,235,214); // jmp .Lfill
 fz_jit_label(j,212); // .Lfill1
 fz_jit_bytes(j,"0fb606"); // movzx  eax,BYTE PTR [rsi]
 fz_jit_bytes(j,"48b90101010101010101"); // movabs rcx,0x101010101010101
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_branch8(j,235,214); // jmp .Lfill
 fz_jit_label(j,213); // .Lfill2
 fz_jit_bytes(j,"0fb706"); // movzx  eax,WORD PTR [rsi]
 fz_jit_bytes(j,"48b90100010001000100"); // movabs rcx,0x1000100010001
 fz_jit_bytes(j,"480fafc1"); // imul   rax,rcx
 fz_jit_label(j,214); // .Lfill
 fz_jit_bytes(j,"488907"); // mov    QWORD PTR [rdi],rax
 fz_jit_bytes(j,"4883c708"); // add    rdi,0x8
 fz_jit_bytes(j,"4983ea08"); // sub    r10,0x8
 fz_jit_branch8(j,127,214); // jg .Lfill
 fz_jit_branch8(j,235,216); // jmp .Lnext
 fz_jit_label(j,215); // .Lbytes
 fz_jit_bytes(j,"4c89d1"); // mov    rcx,r10
 fz_jit_bytes(j,"f3a4"); // rep movs BYTE PTR [rdi],BYTE PTR [rsi]
 fz_jit_label(j,216); // .Lnext
 fz_jit_bytes(j,"49ffcc"); // dec    r12
 fz_jit_branch(j,233,187); // jmp .Lloop
 fz_jit_label(j,217); // .Ldone
 fz_jit_bytes(j,"c4c179d6b780060000"); // vmovq  QWORD PTR [r15+0x680],xmm6
 fz_jit_bytes(j,"c4c179d6bf88060000"); // vmovq  QWORD PTR [r15+0x688],xmm7
 fz_jit_bytes(j,"c44179d68790060000"); // vmovq  QWORD PTR [r15+0x690],xmm8
 fz_jit_bytes(j,"4c89f0"); // mov    rax,r14
 fz_jit_bytes(j,"492b87b8060000"); // sub    rax,QWORD PTR [r15+0x6b8]
 fz_jit_bytes(j,"48c1e003"); // shl    rax,0x3
 fz_jit_bytes(j,"4883c038"); // add    rax,0x38
 fz_jit_bytes(j,"4c01e8"); // add    rax,r13
 fz_jit_bytes(j,"49898798060000"); // mov    QWORD PTR [r15+0x698],rax
 fz_jit_bytes(j,"4889d8"); // mov    rax,rbx
 fz_jit_bytes(j,"492b87c0060000"); // sub    rax,QWORD PTR [r15+0x6c0]
 fz_jit_bytes(j,"498987a8060000"); // mov    QWORD PTR [r15+0x6a8],rax
 fz_jit_bytes(j,"492bafc8060000"); // sub    rbp,QWORD PTR [r15+0x6c8]
 fz_jit_bytes(j,"4989afb0060000"); // mov    QWORD PTR [r15+0x6b0],rbp
 fz_jit_bytes(j,"488b0424"); // mov    rax,QWORD PTR [rsp]
 fz_jit_bytes(j,"4c29e0"); // sub    rax,r12
 fz_jit_bytes(j,"4d89a7a0060000"); // mov    QWORD PTR [r15+0x6a0],r12
 fz_jit_branch8(j,235,219); // jmp .Lreturn
 fz_jit_label(j,218); // .Lerror
 fz_jit_bytes(j,"48c7c0ffffffff"); // mov    rax,0xffffffffffffffff
 fz_jit_label(j,219); // .Lreturn
 fz_jit_bytes(j,"c5f877"); // vzeroupper
 fz_jit_bytes(j,"4883c408"); // add    rsp,0x8
 fz_jit_bytes(j,"415f"); // pop    r15
 fz_jit_bytes(j,"415e"); // pop    r14
 fz_jit_bytes(j,"415d"); // pop    r13
 fz_jit_bytes(j,"415c"); // pop    r12
 fz_jit_bytes(j,"5b"); // pop    rbx
 fz_jit_bytes(j,"5d"); // pop    rbp
 fz_jit_bytes(j,"c3"); // ret
 fz_jit_label(j,220); // .LllNonzero
 fz_jit_bytes(j,"29f1"); // sub    ecx,esi
 fz_jit_bytes(j,"c4c2f3f7c3"); // shrx   rax,r11,rcx
 fz_jit_bytes(j,"c4e2c8f5c0"); // bzhi   rax,rax,rsi
 fz_jit_bytes(j,"4489c6"); // mov    esi,r8d
 fz_jit_bytes(j,"4801c6"); // add    rsi,rax
 fz_jit_branch(j,233,192); // jmp .LllDone
 return 1;
}
