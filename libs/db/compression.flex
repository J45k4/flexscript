// Compression backend adapter. C Zstd stays the default; native is explicit.
import "../compress/zstd.flex";
global fd_zstd=0;
global fd_z_bound=0;
global fd_z_compress=0;
global fd_z_error=0;
global fd_z_create=0;
global fd_z_init=0;
global fd_z_stream=0;
global fd_z_free=0;
global fd_z_parameter=0;
fn fd_zstd_init() {
 if fd_zstd {return fd_zstd>0;}fd_zstd=-1;let lib=ffi_open("libzstd.so.1");if !lib {return 0;}
 fd_z_bound=ffi_symbol(lib,"ZSTD_compressBound");fd_z_compress=ffi_symbol(lib,"ZSTD_compress");fd_z_error=ffi_symbol(lib,"ZSTD_isError");fd_z_create=ffi_symbol(lib,"ZSTD_createDStream");fd_z_init=ffi_symbol(lib,"ZSTD_initDStream");fd_z_stream=ffi_symbol(lib,"ZSTD_decompressStream");fd_z_free=ffi_symbol(lib,"ZSTD_freeDStream");
 fd_z_parameter=ffi_symbol(lib,"ZSTD_DCtx_setParameter");if !fd_z_bound || !fd_z_compress || !fd_z_error || !fd_z_create || !fd_z_init || !fd_z_stream || !fd_z_free || !fd_z_parameter {return 0;}fd_zstd=lib;return 1;
}

// Decoder handle: backend (1 native), decoder pointer. Existing readers keep
// their selected backend even when a connection changes its execution policy.
fn fd_codec_decoder(native) {
 let inner=0;
 if native {inner=zstd_decoder_open(67108864);}else {
  if !fd_zstd_init() {return 0;}inner=ffi_call(fd_z_create,0,0,0,0,0,0);if !inner {return 0;}
  let result=ffi_call(fd_z_init,inner,0,0,0,0,0);if !ffi_call(fd_z_error,result,0,0,0,0,0) {result=ffi_call(fd_z_parameter,inner,100,26,0,0,0);}
  if ffi_call(fd_z_error,result,0,0,0,0,0) {ffi_call(fd_z_free,inner,0,0,0,0,0);return 0;}
 }
 if !inner {return 0;}let d=alloc(16);if d<=0 {if native {zstd_decoder_close(inner);}else {ffi_call(fd_z_free,inner,0,0,0,0,0);}return 0;}store64(d,native);store64(d+8,inner);return d;
}
fn fd_codec_decode(d,out,input) {
 if load64(d) {return zstd_decode(load64(d+8),out,input);}let result=ffi_call(fd_z_stream,load64(d+8),out,input,0,0,0);if ffi_call(fd_z_error,result,0,0,0,0,0) {return -1;}return result;
}
fn fd_codec_decoder_close(d) {if !d {return 0;}if load64(d) {zstd_decoder_close(load64(d+8));}else {ffi_call(fd_z_free,load64(d+8),0,0,0,0,0);}syscall(11,d,16,0,0,0,0);return 1;}
// Connection-local execution policy, never changes the file-format codec ID.
// Native encoding currently supports the fast level-1 strategy only. Reading
// frames written at any level is supported (without external dictionaries).
fn flexdb_blob_native_zstd(db,enabled) {
 if !fd_ready(db) || load64(db+48) {return fd_error(db,"codec selection requires an idle database");}if enabled!=0 && enabled!=1 {return fd_error(db,"invalid codec backend");}store64(fd_blob_state(db)+96,enabled);return 1;
}
fn fd_codec_native(db) {if !db {return 0;}let s=load64(db+232);return s && load64(s+96);}
