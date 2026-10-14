// Trusted Linux x86-64 IEEE CRC32 helper, emitted entirely in Flexscript.
// Same slicing-by-eight tables/polynomial as fd_crc; no optional CPU ISA.
// System V arguments: RDI=crc, RSI=bytes, RDX=length, RCX=table. Only volatile
// RAX/R8/R9 and the pointer/length registers change. No buffer overreads.
// One code page transitions RW -> RX; an executable-memory failure falls back.
global fd_crc_code=0;
fn fd_crc_emit(code,state,byte) {store8(code+load64(state),byte);store64(state,load64(state)+1);return 0;}
fn fd_crc_emit32(code,state,word) {let i=0;while i<4 {fd_crc_emit(code,state,(word>>(i*8))&255);i=i+1;}return 0;}
fn fd_crc_hex(code,state,text) {let i=0;while load8(text+i) {let a=load8(text+i);let b=load8(text+i+1);if a>=97 {a=a-87;}else {a=a-48;}if b>=97 {b=b-87;}else {b=b-48;}fd_crc_emit(code,state,a*16+b);i=i+2;}return 0;}
fn fd_crc_native_init() {
 if fd_crc_code {return fd_crc_code;}fd_crc_code=-1;let code=alloc(4096);if code<=0 {return -1;}let state=alloc(8);if state<=0 {syscall(11,code,4096,0,0,0,0);return -1;}
 fd_crc_hex(code,state,"89f8"); // mov eax,edi: zero-extend the CRC
 let loop=load64(state);fd_crc_hex(code,state,"4883fa080f82");let to_tail=load64(state);fd_crc_emit32(code,state,0); // cmp rdx,8; jb tail
 fd_crc_hex(code,state,"4c8b064931c0"); // mov r8,[rsi]; xor r8,rax
 let slice=7;while slice>=0 {
  fd_crc_hex(code,state,"450fb6c8"); // movzx r9d,r8b
  if slice==7 {fd_crc_hex(code,state,"428b84c9");}else {fd_crc_hex(code,state,"423384c9");} // mov/xor eax,[rcx+r9*8+slice*2048]
  fd_crc_emit32(code,state,slice*2048);if slice {fd_crc_hex(code,state,"49c1e808");} // shr r8,8
  slice=slice-1;
 }
 fd_crc_hex(code,state,"4883c6084883ea08e9"); // advance by eight and repeat
 let back=load64(state);fd_crc_emit32(code,state,loop-back-4);
 let tail=load64(state);let rel=tail-to_tail-4;let i=0;while i<4 {store8(code+to_tail+i,(rel>>(i*8))&255);i=i+1;}
 fd_crc_hex(code,state,"4885d20f84");let to_done=load64(state);fd_crc_emit32(code,state,0); // test rdx; jz done
 let byte_loop=load64(state);fd_crc_hex(code,state,"440fb6064131c04181e0ff000000c1e808423304c148ffc648ffca0f85");
 // movzx r8d,[rsi]; xor r8d,eax; and r8d,255; shr eax,8;
 // xor eax,[rcx+r8*8]; inc rsi; dec rdx; jne byte_loop
 back=load64(state);fd_crc_emit32(code,state,byte_loop-back-4);let done=load64(state);fd_crc_hex(code,state,"c3");
 rel=done-to_done-4;i=0;while i<4 {store8(code+to_done+i,(rel>>(i*8))&255);i=i+1;}syscall(11,state,8,0,0,0,0);
 if syscall(10,code,4096,5,0,0,0)<0 {syscall(11,code,4096,0,0,0,0);return -1;}fd_crc_code=code;return code;
}
