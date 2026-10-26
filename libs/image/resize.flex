import "core.flex";

// A separable coverage-area filter for shrinking and center-aligned linear
// interpolation for enlargement. Every axis sums to exactly 65536. Packed
// R/B and G/A lanes use independent 32-bit accumulators inside a word.
fn im_plan(c,src,dst) {
    let bytes=dst*24+(src+dst*2)*8+32;
    if bytes>268435456 {return im_fail(c,"Resize axis exceeds workspace limit");}
    let plan=alloc(bytes);if plan<0 {return im_fail(c,"Cannot allocate resize plan");}
    store64(plan,bytes);let weights=plan+32+dst*24;let at=0;let x=0;
    while x<dst {
        let p=plan+32+x*24;
        if dst>=src {
            let numerator=(x*2+1)*src-dst;let position=0;
            if numerator>0 {position=numerator*65536/(dst*2);}
            let start=position>>16;let fraction=position&65535;
            if start>=src-1 {start=src-1;fraction=0;}
            let count=1;if fraction {count=2;}
            store64(p,start);store64(p+8,count);store64(p+16,weights+at*8);
            store64(weights+at*8,65536-fraction);at=at+1;
            if fraction {store64(weights+at*8,fraction);at=at+1;}
        }else {
            let left=x*src;let right=(x+1)*src;let start=left/dst;let end=(right+dst-1)/dst;
            store64(p,start);store64(p+8,end-start);store64(p+16,weights+at*8);
            let j=start;let previous=0;
            while j<end {
                let edge=(j+1)*dst;if edge>right {edge=right;}
                let cumulative=((edge-left)*65536+src/2)/src;
                store64(weights+at*8,cumulative-previous);previous=cumulative;at=at+1;j=j+1;
            }
        }x=x+1;
    }return plan;
}
fn im_horizontal(c,source,destination,plan,width,alpha) {
    if load64(c+72) {
        let args=load64(c+48)+512;store64(args,source);store64(args+8,destination);store64(args+16,plan+32);store64(args+24,width);store64(args+32,alpha);
        native_call1(load64(c+72),args);return 0;
    }
    let x=0;while x<width {
        let entry=plan+32+x*24;let start=load64(entry);let count=load64(entry+8);let weights=load64(entry+16);
        let rb=0;let ga=0;let j=0;
        while j<count {
            let p=bytes_load32(source+(start+j)*4);let a=p>>24;
            if alpha && a!=255 {
                let r=((p&255)*a+127)/255;let g=(((p>>8)&255)*a+127)/255;let b=(((p>>16)&255)*a+127)/255;
                p=r|(g<<8)|(b<<16)|(a<<24);
            }
            let weight=load64(weights+j*8);
            rb=rb+((p&255)|((p&0x00ff0000)<<16))*weight;
            ga=ga+(((p>>8)&255)|((p&0xff000000)<<8))*weight;j=j+1;
        }
        rb=((rb+0x0000800000008000)>>16)&0x000000ff000000ff;
        ga=((ga+0x0000800000008000)>>16)&0x000000ff000000ff;
        bytes_store32(destination+x*4,(rb&255)|((ga&255)<<8)|(((rb>>32)&255)<<16)|(((ga>>32)&255)<<24));x=x+1;
    }return 0;
}
fn image_resize(c,image,w,h) {
    im_ok(c);if !im_valid(w,h) {return im_fail(c,"Invalid resize dimensions");}
    let sw=load64(image);let sh=load64(image+8);if sw==w && sh==h {return image_clone(c,image);}
    let out=image_create(c,w,h,load64(image+40));if !out {return 0;}
    let xp=im_plan(c,sw,w);let yp=im_plan(c,sh,h);
    let slots=(sh+h-1)/h+2;if slots>sh {slots=sh;}
    let cache_bytes=slots*w*4;let cache=-1;let tags=-1;let rows=-1;
    if xp && yp && cache_bytes<=268435456 {cache=alloc(cache_bytes);tags=alloc(slots*8);rows=alloc(slots*16);}
    if !xp || !yp || cache<0 || tags<0 || rows<0 {
        if xp {syscall(11,xp,load64(xp),0,0,0,0);}if yp {syscall(11,yp,load64(yp),0,0,0,0);}
        if cache>0 {syscall(11,cache,cache_bytes,0,0,0,0);}if tags>0 {syscall(11,tags,slots*8,0,0,0,0);}if rows>0 {syscall(11,rows,slots*16,0,0,0,0);}
        image_free(out);return im_fail(c,"Cannot allocate bounded resize workspace");
    }
    bytes_fill(tags,255,slots*8);let y=0;let alpha=load64(image+40);
    while y<h {
        let entry=yp+32+y*24;let start=load64(entry);let count=load64(entry+8);let weights=load64(entry+16);let j=0;
        while j<count {
            let sy=start+j;let index=sy%slots;let row=cache+index*w*4;
            if load64(tags+index*8)!=sy {
                im_horizontal(c,load64(image+24)+sy*load64(image+16),row,xp,w,alpha);store64(tags+index*8,sy);
            }
            store64(rows+j*16,row);store64(rows+j*16+8,load64(weights+j*8));j=j+1;
        }
        let x=0;let dst=load64(out+24)+y*w*4;
        if load64(c+80) {
            let args=load64(c+48)+576;store64(args,rows);store64(args+8,dst);store64(args+16,w);store64(args+24,count);store64(args+32,alpha);native_call1(load64(c+80),args);
        }else{while x<w {
            let rb=0;let ga=0;j=0;
            while j<count {let row=load64(rows+j*16)+x*4;let weight=load64(rows+j*16+8);let p=bytes_load32(row);
                rb=rb+((p&255)|((p&0x00ff0000)<<16))*weight;ga=ga+(((p>>8)&255)|((p&0xff000000)<<8))*weight;j=j+1;
            }
            rb=((rb+0x0000800000008000)>>16)&0x000000ff000000ff;
            ga=((ga+0x0000800000008000)>>16)&0x000000ff000000ff;
            let r=rb&255;let g=ga&255;let b=(rb>>32)&255;let a=(ga>>32)&255;
            if alpha {
                if a>0 && a<255 {r=(r*255+a/2)/a;g=(g*255+a/2)/a;b=(b*255+a/2)/a;if r>255 {r=255;}if g>255 {g=255;}if b>255 {b=255;}}
                if !a {r=0;g=0;b=0;}
            }else {a=255;}
            bytes_store32(dst+x*4,r|(g<<8)|(b<<16)|(a<<24));x=x+1;
        }}y=y+1;
    }
    syscall(11,xp,load64(xp),0,0,0,0);syscall(11,yp,load64(yp),0,0,0,0);
    syscall(11,cache,cache_bytes,0,0,0,0);syscall(11,tags,slots*8,0,0,0,0);syscall(11,rows,slots*16,0,0,0,0);return out;
}
fn image_fit(c,image,side) {
    if side<1 || side>16384 {return im_fail(c,"Invalid image fit limit");}
    let w=load64(image);let h=load64(image+8);if w<=side && h<=side {return image_clone(c,image);}
    let nw=side;let nh=h*side/w;if h>w {nh=side;nw=w*side/h;}if nw<1 {nw=1;}if nh<1 {nh=1;}
    return image_resize(c,image,nw,nh);
}
fn image_preview(c,bytes,n,side,limit) {
    if side<1 || side>16384 || limit<1 || limit>67108864 {return im_fail(c,"Invalid preview bounds");}
    let image=image_decode(c,bytes,n);if !image {return 0;}
    let orientation=image_orientation(bytes,n);
    if orientation>1 {let next=image_orient(c,image,orientation);image_free(image);image=next;if !image {return 0;}}
    if load64(image)>side || load64(image+8)>side {let next=image_fit(c,image,side);image_free(image);image=next;if !image {return 0;}}
    let quality=85;let attempt=0;let encoded=0;
    while attempt<3 {
        encoded=image_encode_jpeg(c,image,quality);if !encoded {image_free(image);return 0;}
        if load64(encoded+8)<=limit {image_free(image);return encoded;}
        image_blob_free(encoded);encoded=0;quality=70;if attempt {quality=50;}attempt=attempt+1;
    }image_free(image);return im_fail(c,"Normalized image exceeds snapshot limit");
}
