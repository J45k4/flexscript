import "../../lib/bytes.flex";
import "../../lib/native.flex";
import "../../lib/ffi.flex";
import "native-x86.flex";

// Context: error, PNG library, JPEG library, WebP library, JPEG decoder/encoder,
// 1024-byte scratch, executable SysV stack-argument adapter, optional demux lib.
// Images: width, height, stride, pixels, allocation bytes, has alpha (48 bytes).
// Encoded buffers: data, length, allocation bytes, format, width, height (48).
fn image_error(c) {if !c {return "Image context allocation failed";}return load64(c);}
fn im_fail(c,message) {if c {store64(c,message);}return 0;}
fn im_ok(c) {store64(c,0);return 0;}
fn image_width(i) {return load64(i);}
fn image_height(i) {return load64(i+8);}
fn image_stride(i) {return load64(i+16);}
fn image_pixels(i) {return load64(i+24);}
fn image_has_alpha(i) {return load64(i+40);}
fn im_valid(w,h) {return w>0 && h>0 && w<=40000000/h;}
fn image_create(c,w,h,alpha) {
    if !im_valid(w,h) {return im_fail(c,"Image dimensions exceed 40 megapixels");}
    let i=alloc(48);let p=alloc(w*h*4);
    if i<0 || p<0 {if i>0 {syscall(11,i,48,0,0,0,0);}if p>0 {syscall(11,p,w*h*4,0,0,0,0);}return im_fail(c,"Cannot allocate image");}
    store64(i,w);store64(i+8,h);store64(i+16,w*4);store64(i+24,p);
    store64(i+32,w*h*4);store64(i+40,alpha!=0);return i;
}
fn image_free(i) {if i {syscall(11,load64(i+24),load64(i+32),0,0,0,0);syscall(11,i,48,0,0,0,0);}return 0;}
fn image_clone(c,i) {
    let out=image_create(c,load64(i),load64(i+8),load64(i+40));
    if out {bytes_copy(load64(out+24),load64(i+24),load64(i+32));}return out;
}
fn image_blob_data(b) {return load64(b);}
fn image_blob_size(b) {return load64(b+8);}
fn image_blob_width(b) {return load64(b+32);}
fn image_blob_height(b) {return load64(b+40);}
fn image_blob_quality(b) {return load64(b+24)>>8;}
fn image_blob_free(b) {if b {syscall(11,load64(b),load64(b+16),0,0,0,0);syscall(11,b,48,0,0,0,0);}return 0;}
fn im_blob(c,n,format) {
    if n<1 || n>67108864 {return im_fail(c,"Encoded image exceeds 64 MiB");}
    let b=alloc(48);let p=alloc(n);
    if b<0 || p<0 {if b>0 {syscall(11,b,48,0,0,0,0);}if p>0 {syscall(11,p,n,0,0,0,0);}return im_fail(c,"Cannot allocate encoded image");}
    store64(b,p);store64(b+8,n);store64(b+16,n);store64(b+24,format);return b;
}
fn im_be16(p) {return (load8(p)<<8)|load8(p+1);}
fn im_be32(p) {return (im_be16(p)<<16)|im_be16(p+2);}
fn im_le16(p) {return load8(p)|(load8(p+1)<<8);}
fn im_t16(p,be) {if be {return im_be16(p);}return im_le16(p);}
fn im_t32(p,be) {if be {return im_be32(p);}return bytes_load32(p);}

// Bounded TIFF IFD0 metadata. Invalid/missing orientation has no pixel effect.
fn im_tiff(p,n) {
    if n<8 {return 1;}let be=load8(p)==77 && load8(p+1)==77;
    if !be && !(load8(p)==73 && load8(p+1)==73) {return 1;}
    if im_t16(p+2,be)!=42 {return 1;}let at=im_t32(p+4,be);
    if at<8 || at>n-2 {return 1;}let count=im_t16(p+at,be);at=at+2;
    if count>(n-at)/12 {return 1;}let i=0;while i<count {
        let entry=p+at+i*12;
        if im_t16(entry,be)==274 && im_t16(entry+2,be)==3 && im_t32(entry+4,be)==1 {
            let value=im_t16(entry+8,be);if value>=1 && value<=8 {return value;}return 1;
        }i=i+1;
    }return 1;
}
fn im_exif(p,n) {if n>=6 && bytes_load32(p)==0x66697845 && im_le16(p+4)==0 {p=p+6;n=n-6;}return im_tiff(p,n);}
fn image_orientation(p,n) {
    if n>=2 && load8(p)==255 && load8(p+1)==216 {
        let at=2;while at<n {
            if load8(p+at)!=255 {return 1;}while at<n && load8(p+at)==255 {at=at+1;}
            if at>=n {return 1;}let marker=load8(p+at);at=at+1;
            if marker==218 || marker==217 {return 1;}
            if marker!=1 && !(marker>=208 && marker<=215) {
                if at>n-2 {return 1;}let len=im_be16(p+at);if len<2 || len>n-at {return 1;}
                if marker==225 {let o=im_exif(p+at+2,len-2);if o!=1 {return o;}}at=at+len;
            }
        }
    }else if n>=8 && bytes_load32(p)==0x474e5089 {
        let at=8;while at<=n-12 {let len=im_be32(p+at);if len>n-at-12 {return 1;}
            if bytes_load32(p+at+4)==0x66495865 {return im_exif(p+at+8,len);}at=at+len+12;
        }
    }else if n>=12 && bytes_load32(p)==0x46464952 && bytes_load32(p+8)==0x50424557 {
        let at=12;while at<=n-8 {let len=bytes_load32(p+at);let tag=len;len=bytes_load32(p+at+4);
            if len>n-at-8 {return 1;}if tag==0x46495845 {return im_exif(p+at+8,len);}at=at+8+len+(len&1);
        }
    }return 1;
}
fn image_orient(c,i,o) {
    if o<1 || o>8 {return im_fail(c,"Invalid image orientation");}
    if o==1 {return image_clone(c,i);}
    let w=load64(i);let h=load64(i+8);let ow=w;let oh=h;if o>=5 {ow=h;oh=w;}
    let out=image_create(c,ow,oh,load64(i+40));if !out {return 0;}
    // Resolve each orientation to an affine walk once, outside the pixel loop.
    let start=load64(i+24);let dx=4;let dy=w*4;
    if o==2 {start=start+(w-1)*4;dx=-4;}
    else if o==3 {start=start+(w*h-1)*4;dx=-4;dy=-w*4;}
    else if o==4 {start=start+(h-1)*w*4;dy=-w*4;}
    else if o==5 {dx=w*4;dy=4;}
    else if o==6 {start=start+(h-1)*w*4;dx=-w*4;dy=4;}
    else if o==7 {start=start+(w*h-1)*4;dx=-w*4;dy=-4;}
    else if o==8 {start=start+(w-1)*4;dx=w*4;dy=-4;}
    let dest=load64(out+24);
    if load64(c+96) {
        let args=load64(c+48)+704;store64(args,start);store64(args+8,dest);store64(args+16,ow);store64(args+24,oh);store64(args+32,dx);store64(args+40,dy);
        native_call1(load64(c+96),args);return out;
    }
    let y=0;while y<oh {let source=start;let x=0;while x<ow {
        bytes_store32(dest,bytes_load32(source));source=source+dx;dest=dest+4;x=x+1;
    }start=start+dy;y=y+1;}return out;
}

// Trusted SysV adapter for up to twelve integer/pointer arguments. Generated
// in Flexscript, RW while written then RX, with no assembler/C runtime shim.
fn im_call(c,function) {let args=load64(c+48)+256;store64(args,function);return native_call1(load64(c+56),args);}
fn im_arg(c,index,value) {store64(load64(c+48)+256+index*8,value);return 0;}
fn im_code(code,hex) {
    let at=0;while load8(hex+at*2) {let a=load8(hex+at*2);let b=load8(hex+at*2+1);if a>57 {a=a-87;}else {a=a-48;}if b>57 {b=b-87;}else {b=b-48;}store8(code+at,(a<<4)|b);at=at+1;}return 0;
}
fn image_context() {
    let c=alloc(128);let scratch=alloc(1024);let code=alloc(4096);
    if c<0 || scratch<0 || code<0 {if c>0 {syscall(11,c,128,0,0,0,0);}if scratch>0 {syscall(11,scratch,1024,0,0,0,0);}if code>0 {syscall(11,code,4096,0,0,0,0);}return 0;}
    store64(c+48,scratch);store64(c+56,code);
    let hex="4989fa4883ec38498b423848890424498b42404889442408498b42484889442410498b42504889442418498b42584889442420498b42604889442428498b7a08498b7210498b5218498b4a204d8b42284d8b4a30498b02ffd04883c438c3";
    im_code(code,hex);im_native_emit(code);
    if syscall(10,code,4096,5,0,0,0)<0 {syscall(11,code,4096,0,0,0,0);syscall(11,scratch,1024,0,0,0,0);syscall(11,c,128,0,0,0,0);return 0;}
    image_acceleration(c,1);return c;
}
fn image_context_free(c) {
    if !c {return 0;}
    if load64(c+32) {ffi_call(ffi_symbol(load64(c+16),"tjDestroy"),load64(c+32),0,0,0,0,0);}
    if load64(c+40) {ffi_call(ffi_symbol(load64(c+16),"tjDestroy"),load64(c+40),0,0,0,0,0);}
    let at=8;while at<=24 {if load64(c+at) {ffi_close(load64(c+at));}at=at+8;}
    if load64(c+64) {ffi_close(load64(c+64));}
    syscall(11,load64(c+48),1024,0,0,0,0);syscall(11,load64(c+56),4096,0,0,0,0);syscall(11,c,128,0,0,0,0);return 0;
}
