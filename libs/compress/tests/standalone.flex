// No libc/FFI/imported host harness: a complete native codec executable.
import "../zstd.flex";
fn main() {
 let n=300000;let input=alloc(n);let out=alloc(n);let bound=zstd_compress_bound(n);let packed=alloc(bound);let enc=zstd_encoder_open();let dec=zstd_decoder_open(67108864);if !input || !out || !packed || !enc || !dec {return 1;}
 let i=0;while i<n {store8(input+i,(i%251)^(i/7919));i=i+1;}let size=zstd_compress(enc,packed,bound,input,n);if size<0 || zstd_decompress(dec,out,n,packed,size)!=n {return 2;}i=0;while i<n {if load8(input+i)!=load8(out+i) {return 3;}i=i+1;}zstd_encoder_close(enc);zstd_decoder_close(dec);return 0;
}
