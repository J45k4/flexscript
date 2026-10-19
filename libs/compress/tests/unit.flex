import "../zstd.flex";
import "acceleration.flex";
import "../../../scripts/lib/host.flex";
fn guarded_frames(enc,dec,input) {
 let source=alloc(12288);let target=alloc(8192);h_assert(source>0 && target>0 && syscall(10,source+8192,4096,0,0,0,0)==0 && syscall(10,target+4096,4096,0,0,0,0)==0,"complete-frame guard pages");let scratch=alloc(8192);let size=0;
 while size<=4096 {let encoded=zstd_compress(enc,scratch,8192,input,size);h_assert(encoded>0 && encoded<=8192,"guarded frame encode");let frame=source+8192-encoded;fz_copy(frame,scratch,encoded);let output=target+4096-size;h_assert(zstd_decompress(dec,output,size,frame,encoded)==size,"complete buffers end at guard");let i=0;while i<size {h_assert(load8(output+i)==load8(input+i),"guarded exact bytes");i=i+1;}if size {h_assert(zstd_decompress(dec,target+4096-(size-1),size-1,frame,encoded)<0,"small output ends at guard");}
  if size==4096 {size=4097;}else {if size<40 {size=size+1;}else {size=size*2;if size>4096 {size=4096;}}} }
 // Compressed block with RLE literals and no sequences: validates capacity
 // before copying literals even though the compressed payload is tiny.
 let n=1024;let frame=source+8192-18;fz_le(frame,0xfd2fb528,4);store8(frame+4,128);store8(frame+5,56);fz_le(frame+6,n,4);fz_le(frame+10,45,3);fz_le(frame+13,(n<<4)|13,3);store8(frame+16,67);store8(frame+17,0);
 h_assert(zstd_decompress(dec,target+4096-n,n,frame,18)==n && zstd_decompress(dec,target+4096-(n-1),n-1,frame,18)<0,"zero-sequence literal capacity at guard");syscall(11,source,12288,0,0,0,0);syscall(11,target,8192,0,0,0,0);syscall(11,scratch,8192,0,0,0,0);return 1;
}
fn branch_fixups() {
 let j=alloc(64);let code=alloc(16384);let labels=alloc(4096);let fixes=alloc(8192);store64(j,code);store64(j+16,labels);store64(j+24,fixes);fz_fill(labels,255,4096);
 fz_jit_label(j,0);fz_jit_branch8(j,235,1);fz_jit_byte(j,144);fz_jit_label(j,1);fz_jit_branch8(j,235,0);h_assert(fz_jit_finish(j) && load8(code+1)==1 && load8(code+4)==251,"signed short branch fixups");
 fz_jit_label(j,0);h_assert(!fz_jit_finish(j),"duplicate labels rejected");store64(j+56,0);store64(j+8,0);store64(j+32,0);fz_fill(labels,255,4096);fz_jit_branch8(j,235,0);let i=0;while i<128 {fz_jit_byte(j,144);i=i+1;}fz_jit_label(j,0);h_assert(!fz_jit_finish(j),"short displacement overflow rejected");
 store64(j+8,0);store64(j+32,0);fz_fill(labels,255,4096);fz_jit_branch(j,233,0);h_assert(!fz_jit_finish(j),"unbound label rejected");fz_jit_label(j,0);h_assert(fz_jit_finish(j) && bytes_load32(code+1)==0,"near branch fixup");
 syscall(11,j,64,0,0,0,0);syscall(11,code,16384,0,0,0,0);syscall(11,labels,4096,0,0,0,0);syscall(11,fixes,8192,0,0,0,0);return 1;
}
fn main(argc,argv) {
 h_environment(argc,argv);branch_fixups();let x=alloc(80);fz_xreset(x);h_assert(fz_xdigest(x)==0xef46db3751d8e999,"XXH64 empty reference");fz_xupdate(x,"hello",5);h_assert(fz_xdigest(x)==0x26c7827d889f6da3,"XXH64 hello reference");
 let i=0;while i<65536 {h_assert(fz_ll_code(i)<=35 && (fz_ll_base(fz_ll_code(i))&0xffffffff)<=i,"literal code lower bound");if fz_ll_code(i)<35 {h_assert(i<(fz_ll_base(fz_ll_code(i)+1)&0xffffffff),"literal code upper bound");}if i>=3 {h_assert((fz_ml_base(fz_ml_code(i))&0xffffffff)<=i,"match code lower bound");if fz_ml_code(i)<52 {h_assert(i<(fz_ml_base(fz_ml_code(i)+1)&0xffffffff),"match code upper bound");}}i=i+1;}
 let enc=zstd_encoder_open();let dec=zstd_decoder_open(67108864);let input=alloc(50000);let bound=zstd_compress_bound(50000);let packed=alloc(bound*2);let out=alloc(100001);i=0;while i<50000 {store8(input+i,i%37);i=i+1;}
 h_assert(enc && dec,"contexts");let mode=h_getenv("FLEX_ZSTD_ACCELERATION");if mode && load8(mode)==48 {zstd_encoder_acceleration(enc,0);zstd_decoder_acceleration(dec,0);}let initial=zstd_encoder_acceleration(enc,-1);h_assert(zstd_encoder_acceleration(enc,0)==0 && !zstd_encoder_acceleration(enc,-1),"disable encoder acceleration");if initial {h_assert(zstd_encoder_acceleration(enc,1)==1,"re-enable encoder acceleration");}let decoder_initial=zstd_decoder_acceleration(dec,-1);h_assert(zstd_decoder_acceleration(dec,0)==0 && !zstd_decoder_acceleration(dec,-1),"disable decoder acceleration");if decoder_initial {h_assert(zstd_decoder_acceleration(dec,1)==1,"re-enable decoder acceleration");}test_acceleration(enc,1);test_acceleration(dec,0);let n=zstd_compress(enc,packed,bound,input,50000);h_assert(n>0,"compress");h_assert(zstd_compress(enc,packed,bound-1,input,50000)<0 && zstd_error(enc),"short encoder destination");n=zstd_compress(enc,packed,bound,input,50000);h_assert(n>0 && !zstd_error(enc),"encoder reuse clears prior error");
 h_assert(zstd_decompress(dec,out,100001,packed,n)==50000,"complete decode");h_assert(zstd_decompress(dec,out,49999,packed,n)<0 && zstd_error(dec),"short decoder destination");h_assert(zstd_decompress(dec,out,100001,packed,n)==50000 && !zstd_error(dec),"decoder reuse clears prior error");i=0;while i<50000 {h_assert(load8(out+i)==load8(input+i),"roundtrip byte");i=i+1;}
 fz_copy(packed+n,packed,n);h_assert(zstd_decompress(dec,out,100001,packed,n*2)==100000,"complete concatenated frames");h_assert(zstd_decompress(dec,out,100001,packed,n-1)<0,"truncated complete frame");
 let inbuf=alloc(24);let outbuf=alloc(24);zstd_decoder_reset(dec);store64(inbuf+8,1);store64(inbuf+16,2);h_assert(zstd_decode(dec,outbuf,inbuf)<0,"invalid stream positions");store64(inbuf+16,0);h_assert(zstd_decode(dec,outbuf,inbuf)<0,"stream errors are sticky");
 h_assert(!zstd_decoder_open(0) && zstd_compress_bound(-1)<0 && zstd_compress_bound(2147483648)<0,"allocation/size limits");guarded_frames(enc,dec,input);zstd_encoder_close(enc);zstd_decoder_close(dec);h_print(1,"Native Zstd API, size-code and XXH64 checks pass\n");return 0;
}
