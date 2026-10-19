// Stream a file through a fixed 64 KiB input/output pair and report the kernel's
// own VmHWM from inside the executable, avoiding launcher RSS inheritance.
import "../zstd.flex";
import "../../../scripts/lib/host.flex";
fn main(argc,argv) {
 h_assert(argc==4,"memory INPUT native|c ROUNDS");let native=load8(load64(argv+16))==110;let rounds=h_number(load64(argv+24));let fd=syscall(2,load64(argv+8),524288,0,0,0,0);h_assert(fd>=0 && rounds>0,"memory fixture");
 let create=0;let init=0;let stream=0;let error=0;let free=0;let decoder=0;
 if native {decoder=zstd_decoder_open(67108864);}else {let lib=ffi_open("libzstd.so.1");h_assert(lib,"reference library");create=ffi_symbol(lib,"ZSTD_createDStream");init=ffi_symbol(lib,"ZSTD_initDStream");stream=ffi_symbol(lib,"ZSTD_decompressStream");error=ffi_symbol(lib,"ZSTD_isError");free=ffi_symbol(lib,"ZSTD_freeDStream");decoder=ffi_call(create,0,0,0,0,0,0);}
 h_assert(decoder,"memory decoder");let input=alloc(65560);let output=alloc(65560);store64(input,input+24);store64(output,output+24);store64(output+8,65536);let round=0;
 while round<rounds {
  h_assert(syscall(8,fd,0,0,0,0,0)==0,"rewind");if native {zstd_decoder_reset(decoder);}else {h_assert(!ffi_call(error,ffi_call(init,decoder,0,0,0,0,0),0,0,0,0,0),"reference reset");}
  store64(input+8,0);store64(input+16,0);let eof=0;let hint=1;let more=1;
  while more {
   if load64(input+16)==load64(input+8) && !eof {let got=syscall(0,fd,input+24,65536,0,0,0);h_assert(got>=0,"read");store64(input+8,got);store64(input+16,0);if !got {eof=1;}}
   if eof && !hint {more=0;}else {
    let before=load64(input+16);store64(output+16,0);if native {hint=zstd_decode(decoder,output,input);h_assert(hint>=0,"native decode");}else {hint=ffi_call(stream,decoder,output,input,0,0,0);h_assert(!ffi_call(error,hint,0,0,0,0,0),"reference decode");}
    h_assert(!hint || load64(output+16) || before!=load64(input+16),"truncated/stalled decode");
   }
  }
  round=round+1;
 }
 // Read before freeing the decoder; VmHWM also retains any earlier peak.
 let status=syscall(2,"/proc/self/status",524288,0,0,0,0);let p=alloc(8192);let n=syscall(0,status,p,8192,0,0,0);h_assert(n>0,"process status");h_write(1,p,n);syscall(3,status,0,0,0,0,0);syscall(3,fd,0,0,0,0,0);if native {zstd_decoder_close(decoder);}else {ffi_call(free,decoder,0,0,0,0,0);}return 0;
}
