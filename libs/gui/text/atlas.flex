// Four bounded 1024-square GPU pages, with generation-based eviction and a
// 256-set, four-way glyph metadata cache. Maximum GPU allocation is 16 MiB;
// monochrome coverage normally uses one 1 MiB R8 page. No per-run textures.
import "font.flex";
import "../renderer/gl.flex";
fn ta_context(renderer){
    let a=alloc(512);let entries=alloc(1024*96);if a<0 || entries<0{if a>0{syscall(11,a,512,0,0,0,0);}if entries>0{syscall(11,entries,1024*96,0,0,0,0);}return tf_fail("Cannot allocate glyph atlas");}
    tf_zero(a,512);tf_zero(entries,1024*96);store64(a,renderer);store64(a+8,entries);return a;
}
fn ta_context_free(a){
    if !a{return 0;}let i=0;while i<4{gr_texture_free(load64(a+128+i*64));i=i+1;}syscall(11,load64(a+8),1024*96,0,0,0,0);syscall(11,a,512,0,0,0,0);return 0;
}
fn ta_page_reset(a,page,mode){
    let g=load64(a);gr_flush(g);let texture=load64(page);if texture && load64(page+8)!=mode{gr_texture_free(texture);store64(page,0);texture=0;}
    let channels=1;if mode==4{channels=4;}let bytes=1024*1024*channels;let zero=alloc(bytes);if zero<0{return tf_fail("Cannot clear glyph atlas");}bytes_fill(zero,0,bytes);
    if !texture{texture=gr_texture(g,1024,1024,zero,0,mode);store64(page,texture);}else{gr_texture_patch(g,texture,0,0,1024,1024,zero);}
    syscall(11,zero,bytes,0,0,0,0);if !texture{return tf_fail(gr_error);}store64(page+8,mode);store64(page+16,load64(page+16)+1);store64(page+24,1);store64(page+32,1);store64(page+40,0);store64(page+48,load64(a+16));return page;
}
// Shelf allocation reserves a transparent pixel around every glyph. Reusing a
// page first flushes queued draws, then invalidates its old metadata generation.
fn ta_place(a,width,height,mode){
    let i=0;while i<4{let page=a+128+i*64;if load64(page) && load64(page+8)==mode{
        let x=load64(page+24);let y=load64(page+32);let shelf=load64(page+40);if x+width+1>1024{x=1;y=y+shelf+1;shelf=0;}
        if y+height+1<=1024{store64(page+24,x);store64(page+32,y);store64(page+40,shelf);return page;}
    }i=i+1;}
    let chosen=0;let oldest=9223372036854775807;i=0;while i<4{let page=a+128+i*64;if !load64(page){chosen=page;i=4;}else{if load64(page+48)<oldest{oldest=load64(page+48);chosen=page;}i=i+1;}}
    if load64(chosen){store64(a+64,load64(a+64)+1);}else{store64(a+24,load64(a+24)+1);}return ta_page_reset(a,chosen,mode);
}
// Returned metadata is borrowed until the next lookup; callers draw it before
// requesting another glyph. Zero-area glyphs retain advances without uploads.
fn ta_glyph(a,font,glyph){
    store64(a+16,load64(a+16)+1);let tick=load64(a+16);let id=load64(font+80);let bucket=((id*31)^glyph)&255;let base=load64(a+8)+bucket*384;let chosen=base;let oldest=9223372036854775807;let i=0;
    while i<4{let e=base+i*96;let page=load64(e+16);let valid=load64(e) && (!page || load64(e+24)==load64(page+16));
        if valid && load64(e)==id && load64(e+8)==glyph{store64(e+80,tick);if page{store64(page+48,tick);}store64(a+32,load64(a+32)+1);return e;}
        let age=load64(e+80);if !valid{age=-1;}if age<oldest{oldest=age;chosen=e;}i=i+1;
    }
    store64(a+40,load64(a+40)+1);let raster_start=gui_metrics_start();let slot=tf_glyph_bitmap(font,glyph);gui_metrics_end(8,raster_start);gui_metrics_add(6,1);if !slot{return 0;}store64(a+48,load64(a+48)+1);
    let b=slot+152;let width=bytes_load32(b+4);let height=bytes_load32(b);let pitch=tf_i32(b+8);let mode=load8(b+26);let channels=1;let texturemode=3;
    if mode==7{channels=4;texturemode=4;}else if mode!=1 && mode!=2 && width && height{return tf_fail("Unsupported native glyph bitmap format");}
    if width>1022 || height>1022{return tf_fail("Glyph exceeds atlas page size");}let page=0;let x=0;let y=0;
    if width && height{
        page=ta_place(a,width,height,texturemode);if !page{return 0;}x=load64(page+24);y=load64(page+32);let bytes=width*height*channels;let pixels=alloc(bytes);if pixels<0{return tf_fail("Cannot allocate glyph upload");}
        let row=0;while row<height{let source=load64(b+16)+row*pitch;let target=pixels+row*width*channels;let col=0;
            if mode==2{bytes_copy(target,source,width);}else{while col<width{if mode==7{store8(target+col*4,load8(source+col*4+2));store8(target+col*4+1,load8(source+col*4+1));store8(target+col*4+2,load8(source+col*4));store8(target+col*4+3,load8(source+col*4+3));}
                else{let coverage=0;if load8(source+col/8)&(128>>(col%8)){coverage=255;}store8(target+col,coverage);}col=col+1;}}row=row+1;
        }
        let ok=gr_texture_patch(load64(a),load64(page),x,y,width,height,pixels);syscall(11,pixels,bytes,0,0,0,0);if !ok{return tf_fail(gr_error);}
        store64(page+24,x+width+1);if height>load64(page+40){store64(page+40,height);}store64(page+48,tick);store64(a+56,load64(a+56)+bytes);
    }
    tf_zero(chosen,96);store64(chosen,id);store64(chosen+8,glyph);store64(chosen+16,page);if page{store64(chosen+24,load64(page+16));}store64(chosen+32,x);store64(chosen+40,y);store64(chosen+48,width);store64(chosen+56,height);store64(chosen+64,tf_i32(slot+192));store64(chosen+72,tf_i32(slot+196));store64(chosen+80,tick);return chosen;
}
fn ta_round(value){if value<0{return -((-value+32)/64);}return (value+32)/64;}
// Origin is the baseline. Shape offsets and bitmap bearings share the same
// scale, including scaled fixed-strike color emoji. Color glyphs keep their RGB.
fn ta_draw(a,font,shape,x,baseline,rgb){
    if load64(shape+24)!=load64(font+80){return tf_fail("Shape belongs to another font");}let penx=x*64;let peny=baseline*64;let i=0;let ratio=load64(font+32);let divisor=load64(font+40);
    while i<load64(shape){let p=shape+64+i*48;let e=ta_glyph(a,font,load64(p));if !e{return 0;}let page=load64(e+16);
        if page{let texture=load64(page);let color=0xff000000|(rgb&0xffffff);if load64(page+8)==4{color=0xffffffff;}
            let left=ta_round(penx+load64(p+32)+load64(e+64)*64*ratio/divisor);let top=ta_round(peny-load64(p+40)-load64(e+72)*64*ratio/divisor);
            let width=ta_round(load64(e+48)*64*ratio/divisor);let height=ta_round(load64(e+56)*64*ratio/divisor);
            gr_quad(load64(a),load64(texture),left,top,width,height,load64(e+32),load64(e+40),load64(e+48),load64(e+56),color,load64(page+8));
        }
        penx=penx+load64(p+16);peny=peny-load64(p+24);i=i+1;
    }return 1;
}
