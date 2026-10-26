import "core.flex";

fn im_png(c) {
    if !load64(c+8) {store64(c+8,ffi_open("libpng16.so.16"));}
    if !load64(c+8) {return im_fail(c,"libpng16 is required for PNG images");}return load64(c+8);
}
fn im_jpeg(c) {
    if !load64(c+16) {store64(c+16,ffi_open("libturbojpeg.so.0"));}
    if !load64(c+16) {return im_fail(c,"libturbojpeg is required for JPEG images");}return load64(c+16);
}
fn im_webp(c) {
    if !load64(c+24) {store64(c+24,ffi_open("libwebp.so.7"));}
    if !load64(c+24) {return im_fail(c,"libwebp is required for WebP images");}return load64(c+24);
}
fn im_decode_png(c,p,n) {
    let lib=im_png(c);if !lib {return 0;}let state=load64(c+48);bytes_fill(state,0,104);bytes_store32(state+8,1);
    if ffi_call_i32(ffi_symbol(lib,"png_image_begin_read_from_memory"),state,p,n,0,0,0)!=1 {
        ffi_call(ffi_symbol(lib,"png_image_free"),state,0,0,0,0,0);return im_fail(c,"Invalid PNG image");
    }
    let w=bytes_load32(state+12);let h=bytes_load32(state+16);let alpha=bytes_load32(state+20)&1;
    let image=image_create(c,w,h,alpha);
    if !image {ffi_call(ffi_symbol(lib,"png_image_free"),state,0,0,0,0,0);return 0;}
    let format=3;let stride=w*4;if !alpha {format=2;stride=w*3;}
    bytes_store32(state+20,format); // RGB expands backwards in the same owned buffer.
    bytes_store32(state+24,bytes_load32(state+24)|4); // Unmarked 16-bit data is sRGB.
    let ok=ffi_call_i32(ffi_symbol(lib,"png_image_finish_read"),state,0,load64(image+24),stride,0,0);
    ffi_call(ffi_symbol(lib,"png_image_free"),state,0,0,0,0,0);
    if ok!=1 {image_free(image);return im_fail(c,"Invalid or truncated PNG image");}if !alpha {im_expand_rgb(c,image);}return image;
}
fn im_decode_jpeg(c,p,n) {
    let lib=im_jpeg(c);if !lib {return 0;}
    if !load64(c+32) {store64(c+32,ffi_call(ffi_symbol(lib,"tjInitDecompress"),0,0,0,0,0,0));}
    let handle=load64(c+32);if !handle {return im_fail(c,"Cannot create JPEG decoder");}
    let state=load64(c+48);bytes_fill(state,0,64);
    im_arg(c,1,handle);im_arg(c,2,p);im_arg(c,3,n);im_arg(c,4,state);im_arg(c,5,state+8);im_arg(c,6,state+16);im_arg(c,7,state+24);
    if (im_call(c,ffi_symbol(lib,"tjDecompressHeader3"))&0xffffffff)!=0 {return im_fail(c,"Invalid JPEG header");}
    let w=bytes_load32(state);let h=bytes_load32(state+8);let color=bytes_load32(state+24);
    let image=image_create(c,w,h,0);if !image {return 0;}
    let format=7; // TJPF_RGBA fills opaque alpha without a conversion pass.
    if color==3 || color==4 {format=11;} // CMYK/YCCK
    im_arg(c,4,load64(image+24));im_arg(c,5,w);im_arg(c,6,w*4);im_arg(c,7,h);im_arg(c,8,format);im_arg(c,9,12288);
    if (im_call(c,ffi_symbol(lib,"tjDecompress2"))&0xffffffff)!=0 {image_free(image);return im_fail(c,"Invalid or truncated JPEG image");}
    if format==11 {
        let bytes=load64(image+24);let at=0;while at<w*h*4 {
            let k=load8(bytes+at+3);let r=load8(bytes+at)*k;let g=load8(bytes+at+1)*k;let b=load8(bytes+at+2)*k;
            store8(bytes+at,(r+127)/255);store8(bytes+at+1,(g+127)/255);store8(bytes+at+2,(b+127)/255);store8(bytes+at+3,255);at=at+4;
        }
    }return image;
}
fn im_decode_webp(c,p,n) {
    let lib=im_webp(c);if !lib {return 0;}let state=load64(c+48);bytes_fill(state,0,64);
    if ffi_call_i32(ffi_symbol(lib,"WebPGetFeaturesInternal"),p,n,state,0x0209,0,0)!=0 {return im_fail(c,"Invalid WebP header");}
    let w=bytes_load32(state);let h=bytes_load32(state+4);let alpha=bytes_load32(state+8);
    let image=image_create(c,w,h,alpha);if !image {return 0;}
    let source=p;let size=n;let dmux=0;
    if bytes_load32(state+12) {
        if !load64(c+64) {store64(c+64,ffi_open("libwebpdemux.so.2"));}
        let demux=load64(c+64);if !demux {image_free(image);return im_fail(c,"libwebpdemux is required for animated WebP");}
        // Use the animation decoder's composited first canvas frame, retaining
        // offsets, background and alpha blending rather than decoding a fragment.
        store64(state+128,p);store64(state+136,n);
        dmux=ffi_call(ffi_symbol(demux,"WebPAnimDecoderNewInternal"),state+128,0,0x0107,0,0,0);
        if !dmux {image_free(image);return im_fail(c,"Invalid animated WebP");}
        let ok=ffi_call_i32(ffi_symbol(demux,"WebPAnimDecoderGetNext"),dmux,state+144,state+152,0,0,0);
        if ok {bytes_copy(load64(image+24),load64(state+144),w*h*4);}
        ffi_call(ffi_symbol(demux,"WebPAnimDecoderDelete"),dmux,0,0,0,0,0);
        if !ok {image_free(image);return im_fail(c,"Invalid animated WebP frame");}return image;
    }
    if !ffi_call(ffi_symbol(lib,"WebPDecodeRGBAInto"),source,size,load64(image+24),w*h*4,w*4,0) {
        image_free(image);return im_fail(c,"Invalid or truncated WebP image");
    }return image;
}
fn image_decode(c,p,n) {
    im_ok(c);if !p || n<8 || n>67108864 {return im_fail(c,"Invalid image input size");}
    if bytes_load32(p)==0x474e5089 && bytes_load32(p+4)==0x0a1a0a0d {return im_decode_png(c,p,n);}
    if load8(p)==255 && load8(p+1)==216 {return im_decode_jpeg(c,p,n);}
    if n>=12 && bytes_load32(p)==0x46464952 && bytes_load32(p+8)==0x50424557 {return im_decode_webp(c,p,n);}
    return im_fail(c,"Use a PNG, JPEG or WebP image");
}
fn image_encode_jpeg(c,image,quality) {
    im_ok(c);if quality<1 || quality>100 {return im_fail(c,"JPEG quality must be 1 to 100");}
    let lib=im_jpeg(c);if !lib {return 0;}
    if !load64(c+40) {store64(c+40,ffi_call(ffi_symbol(lib,"tjInitCompress"),0,0,0,0,0,0));}
    let handle=load64(c+40);if !handle {return im_fail(c,"Cannot create JPEG encoder");}
    let state=load64(c+48);store64(state+400,0);store64(state+408,0);
    im_arg(c,1,handle);im_arg(c,2,load64(image+24));im_arg(c,3,load64(image));im_arg(c,4,load64(image+16));im_arg(c,5,load64(image+8));im_arg(c,6,7);
    im_arg(c,7,state+400);im_arg(c,8,state+408);im_arg(c,9,2);im_arg(c,10,quality);im_arg(c,11,4096);
    let ok=(im_call(c,ffi_symbol(lib,"tjCompress2"))&0xffffffff)==0;let encoded=0;
    if ok {encoded=im_blob(c,load64(state+408),2);if encoded {bytes_copy(load64(encoded),load64(state+400),load64(state+408));}}
    if load64(state+400) {ffi_call(ffi_symbol(lib,"tjFree"),load64(state+400),0,0,0,0,0);}
    if !ok {return im_fail(c,"JPEG encoding failed");}
    if encoded {store64(encoded+24,2|(quality<<8));store64(encoded+32,load64(image));store64(encoded+40,load64(image+8));}return encoded;
}
fn image_encode_png(c,image) {
    im_ok(c);let lib=im_png(c);if !lib {return 0;}let state=load64(c+48);bytes_fill(state,0,104);
    bytes_store32(state+8,1);bytes_store32(state+12,load64(image));bytes_store32(state+16,load64(image+8));bytes_store32(state+20,3);
    store64(state+400,0);im_arg(c,1,state);im_arg(c,2,0);im_arg(c,3,state+400);im_arg(c,4,0);im_arg(c,5,load64(image+24));im_arg(c,6,load64(image+16));im_arg(c,7,0);
    if (im_call(c,ffi_symbol(lib,"png_image_write_to_memory"))&0xffffffff)!=1 {return im_fail(c,"Cannot size encoded PNG");}
    let blob=im_blob(c,load64(state+400),1);if !blob {return 0;}im_arg(c,2,load64(blob));
    if (im_call(c,ffi_symbol(lib,"png_image_write_to_memory"))&0xffffffff)!=1 {image_blob_free(blob);return im_fail(c,"PNG encoding failed");}
    store64(blob+8,load64(state+400));store64(blob+32,load64(image));store64(blob+40,load64(image+8));return blob;
}
