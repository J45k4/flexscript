import "../zstd.flex";
import "../../../scripts/lib/host.flex";
import "acceleration.flex";
fn main(argc,argv) {
 h_environment(argc,argv);h_assert(argc>=2,"usage: decoder INPUT [input-chunk output-chunk]");let file=h_read(load64(argv+8));let bytes=h_file_size;let input=alloc(24);let output=alloc(24);let buf=alloc(131072);let chunk=65536;let outchunk=65536;
 if argc>2 {chunk=h_number(load64(argv+16));}if argc>3 {outchunk=h_number(load64(argv+24));}h_assert(chunk>0 && outchunk>0 && outchunk<=131072,"chunk sizes");
 if argc>4 && load8(load64(argv+32))==99 {
 h_assert(argc==6,"complete output capacity");let capacity=h_number(load64(argv+40));let target=alloc(capacity+1);let decoder=zstd_decoder_open(67108864);test_acceleration(decoder,0);let size=zstd_decompress(decoder,target,capacity,file,bytes);if size<0 {h_print(2,zstd_error(decoder));h_print(2,"\n");return 1;}h_write(1,target,size);zstd_decoder_close(decoder);return 0;
 }
 if argc>4 {
 let encoder=zstd_encoder_open();h_assert(encoder,"encoder allocation");test_acceleration(encoder,1);let bound=zstd_compress_bound(bytes);let encoded=alloc(bound);let size=zstd_compress(encoder,encoded,bound,file,bytes);if size<0 {h_die(zstd_error(encoder));}h_write(1,encoded,size);zstd_encoder_close(encoder);return 0;
 }
 let c=zstd_decoder_open(67108864);h_assert(c,"open decoder");test_acceleration(c,0);let offset=0;let result=1;let frames=0;
 while offset<bytes || result {
  let take=fz_min(bytes-offset,chunk);store64(input,file+offset);store64(input+8,take);store64(input+16,0);store64(output,buf);store64(output+8,outchunk);store64(output+16,0);
  result=zstd_decode(c,output,input);if result<0 {h_print(2,zstd_error(c));h_print(2,"\n");return 1;}offset=offset+load64(input+16);h_write(1,buf,load64(output+16));if !result {frames=frames+1;}
  if result && !load64(input+16) && !load64(output+16) {h_die("truncated stream");}
 }
 h_assert(frames>0,"no frames");zstd_decoder_close(c);return 0;
}
