// Equal in-process timing harness. C Zstd is used only as the reference.
import "../zstd.flex";
import "../../../scripts/lib/host.flex";
fn tick(clock) {syscall(228,1,clock,0,0,0,0);return load64(clock)*1000000000+load64(clock+8);}
fn stream_bench(decoder,native,input,output,src,bytes,expected,rounds,stream,init,error) {
 let i=0;while i<rounds {if native {zstd_decoder_reset(decoder);}else {h_assert(!ffi_call(error,ffi_call(init,decoder,0,0,0,0,0),0,0,0,0,0),"reference stream init");}store64(input,src);store64(input+8,bytes);store64(input+16,0);store64(output+8,65536);let total=0;let hint=1;
  while hint {store64(output+16,0);let before=load64(input+16);if native {hint=zstd_decode(decoder,output,input);h_assert(hint>=0,"native stream decode");}else {hint=ffi_call(stream,decoder,output,input,0,0,0);h_assert(!ffi_call(error,hint,0,0,0,0,0),"C stream decode");}total=total+load64(output+16);h_assert(!hint || load64(output+16) || before!=load64(input+16),"stream progress");}
  h_assert(total==expected && load64(input+16)==bytes,"stream size");i=i+1;
 }return 0;
}
fn verify_stream(decoder,native,input,output,src,bytes,data,n,stream,init,error) {
 if native {zstd_decoder_reset(decoder);}else {h_assert(!ffi_call(error,ffi_call(init,decoder,0,0,0,0,0),0,0,0,0,0),"verify stream init");}store64(input,src);store64(input+8,bytes);store64(input+16,0);store64(output+8,65536);let total=0;let hint=1;
 while hint {store64(output+16,0);if native {hint=zstd_decode(decoder,output,input);h_assert(hint>=0,"verify native stream");}else {hint=ffi_call(stream,decoder,output,input,0,0,0);h_assert(!ffi_call(error,hint,0,0,0,0,0),"verify C stream");}let count=load64(output+16);h_assert(total+count<=n,"stream verification bounds");let i=0;while i<count {h_assert(load8(load64(output)+i)==load8(data+total+i),"stream output bytes");i=i+1;}total=total+count;}
 h_assert(total==n && load64(input+16)==bytes,"stream verification size");return 1;
}
fn main(argc,argv) {
 h_environment(argc,argv);h_assert(argc==3,"benchmark INPUT REPETITIONS");let data=h_read(load64(argv+8));let n=h_file_size;let rounds=h_number(load64(argv+16));h_assert(rounds>0 && rounds<=1000,"rounds");
 let lib=ffi_open("libzstd.so.1");h_assert(lib,"C Zstd benchmark reference");let boundfn=ffi_symbol(lib,"ZSTD_compressBound");let compress=ffi_symbol(lib,"ZSTD_compressCCtx");let decompress=ffi_symbol(lib,"ZSTD_decompressDCtx");let error=ffi_symbol(lib,"ZSTD_isError");
 let cs=ffi_symbol(lib,"ZSTD_decompressStream");let ci=ffi_symbol(lib,"ZSTD_initDStream");let cf=ffi_symbol(lib,"ZSTD_freeDStream");let cd=ffi_call(ffi_symbol(lib,"ZSTD_createDStream"),0,0,0,0,0,0);h_assert(cd,"C streaming context");
 let cc=ffi_call(ffi_symbol(lib,"ZSTD_createCCtx"),0,0,0,0,0,0);let dd=ffi_call(ffi_symbol(lib,"ZSTD_createDCtx"),0,0,0,0,0,0);h_assert(cc && dd,"C reusable contexts");
 let bound=ffi_call(boundfn,n,0,0,0,0,0);let dst=alloc(bound);let encoded=alloc(bound);let decoded=alloc(n+1);let encoder=zstd_encoder_open();let decoder=zstd_decoder_open(67108864);let input=alloc(24);let output=alloc(24);let clock=alloc(16);let i=0;
 // Equal warmup and page commitment. Timed C decoding must not pay first-touch
 // faults on output that the later native pass would inherit for free.
 fz_fill(dst,0,bound);fz_fill(encoded,0,bound);fz_fill(decoded,0,n+1);
 let warmc=ffi_call(compress,cc,dst,bound,data,n,1);h_assert(!ffi_call(error,warmc,0,0,0,0,0),"warm C compression");h_assert(zstd_compress(encoder,encoded,bound,data,n)>0,"warm native compression");
 h_assert(ffi_call(decompress,dd,decoded,n+1,dst,warmc,0)==n && zstd_decompress(decoder,decoded,n+1,dst,warmc)==n,"warm decoders");store64(output,decoded);stream_bench(cd,0,input,output,dst,warmc,n,1,cs,ci,error);stream_bench(decoder,1,input,output,dst,warmc,n,1,cs,ci,error);
 verify_stream(cd,0,input,output,dst,warmc,data,n,cs,ci,error);verify_stream(decoder,1,input,output,dst,warmc,data,n,cs,ci,error);
 let start=tick(clock);let csize=0;while i<rounds {csize=ffi_call(compress,cc,dst,bound,data,n,1);h_assert(!ffi_call(error,csize,0,0,0,0,0),"C compress");i=i+1;}let cenc=tick(clock)-start;
 start=tick(clock);i=0;let fsize=0;while i<rounds {fsize=zstd_compress(encoder,encoded,bound,data,n);h_assert(fsize>=0,"native compress");i=i+1;}let fenc=tick(clock)-start;
 start=tick(clock);i=0;while i<rounds {h_assert(ffi_call(decompress,dd,decoded,n+1,dst,csize,0)==n,"C decode");i=i+1;}let cdec=tick(clock)-start;
 start=tick(clock);i=0;while i<rounds {zstd_decoder_reset(decoder);store64(input,dst);store64(input+8,csize);store64(input+16,0);store64(output,decoded);store64(output+8,n+1);store64(output+16,0);let result=zstd_decompress(decoder,decoded,n+1,dst,csize);if result<0 {h_die(zstd_error(decoder));}h_assert(result==n,"native decode");i=i+1;}let fdec=tick(clock)-start;
 store64(output,decoded);start=tick(clock);stream_bench(cd,0,input,output,dst,csize,n,rounds,cs,ci,error);let csdec=tick(clock)-start;
 start=tick(clock);stream_bench(decoder,1,input,output,dst,csize,n,rounds,cs,ci,error);let fsdec=tick(clock)-start;
 // The bounded streaming passes reuse decoded's first 64 KiB; restore the
 // complete result outside the timer before comparing every output byte.
 h_assert(zstd_decompress(decoder,decoded,n+1,dst,csize)==n,"verify complete decode");
 h_assert(h_len("")==0,"harness");i=0;while i<n {h_assert(load8(data+i)==load8(decoded+i),"decoded bytes");i=i+1;}
 h_assert(ffi_call(decompress,dd,decoded,n+1,encoded,fsize,0)==n,"C verifies native encoding");i=0;while i<n {h_assert(load8(data+i)==load8(decoded+i),"native encoded bytes");i=i+1;}
 h_print(1,"{\"native_kernel_bytes\":");h_print(1,h_int(load64(decoder+1784)));h_print(1,",\"native_avx2\":");h_print(1,h_int(load64(decoder+344)!=0));h_print(1,",\"bytes\":");h_print(1,h_int(n));h_print(1,",\"rounds\":");h_print(1,h_int(rounds));h_print(1,",\"c_bytes\":");h_print(1,h_int(csize));h_print(1,",\"native_bytes\":");h_print(1,h_int(fsize));h_print(1,",\"c_encode_ns\":");h_print(1,h_int(cenc));h_print(1,",\"native_encode_ns\":");h_print(1,h_int(fenc));h_print(1,",\"c_decode_ns\":");h_print(1,h_int(cdec));h_print(1,",\"native_decode_ns\":");h_print(1,h_int(fdec));h_print(1,",\"c_stream_decode_ns\":");h_print(1,h_int(csdec));h_print(1,",\"native_stream_decode_ns\":");h_print(1,h_int(fsdec));h_print(1,"}\n");ffi_call(cf,cd,0,0,0,0,0);ffi_call(ffi_symbol(lib,"ZSTD_freeCCtx"),cc,0,0,0,0,0);ffi_call(ffi_symbol(lib,"ZSTD_freeDCtx"),dd,0,0,0,0,0);zstd_decoder_close(decoder);zstd_encoder_close(encoder);return 0;
}
