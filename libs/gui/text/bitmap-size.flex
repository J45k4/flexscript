// SDL_ttf interprets a non-scalable face's point-size argument as a strike
// index. Discover the closest strike through public FreeType structures/APIs,
// then scale public metrics and drawing to the caller's requested pixel size.
// No private TTF_Font structure access. Temporary face/library ownership ends
// before returning, so this adds no persistent second font/cache.
import "../../../lib/ffi.flex";
import "../../../lib/bytes.flex";
fn bs_call(lib,name,a,b,c,d){return ffi_call_i32(ffi_symbol(lib,name),a,b,c,d,0,0);}
// Output: raw font at 0 (caller fills), numerator8, denominator16,
// requested pixels24, SDL_ttf opening size/index32. Caller owns 40 bytes.
fn bs_select(path,index,pixels,out){
    store64(out+8,1);store64(out+16,1);store64(out+24,pixels);store64(out+32,pixels);
    let lib=ffi_open("libfreetype.so.6");if !lib{return 0;}let scratch=alloc(16);if scratch<0{ffi_close(lib);return 0;}store64(scratch,0);store64(scratch+8,0);let ok=bs_call(lib,"FT_Init_FreeType",scratch,0,0,0)==0;let library=load64(scratch);
    if ok{ok=bs_call(lib,"FT_New_Face",library,path,index,scratch+8)==0;}let face=load64(scratch+8);
    if ok && !(load64(face+16)&1){
        let count=bytes_load32(face+56);let sizes=load64(face+64);let best=-1;let distance=9223372036854775807;let i=0;if count>4096{ok=0;}
        while ok && i<count{let d=load64(sizes+i*32+24)-pixels*64;if d<0{d=-d;}if d<distance{distance=d;best=i;}i=i+1;}
        if best<0{ok=0;}else if ok{ok=bs_call(lib,"FT_Select_Size",face,best,0,0)==0;}
        if ok{let metrics=load64(face+160)+24;let raster=load8(metrics+2)|(load8(metrics+3)<<8);if !raster{ok=0;}else{store64(out+8,pixels);store64(out+16,raster);store64(out+32,best);}}
    }
    if face{bs_call(lib,"FT_Done_Face",face,0,0,0);}if library{bs_call(lib,"FT_Done_FreeType",library,0,0,0);}syscall(11,scratch,16,0,0,0,0);ffi_close(lib);return ok;
}
