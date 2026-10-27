// Direct Fontconfig / FreeType / HarfBuzz adapter, Linux x86-64 LP64.
// Public structure offsets are checked by tests/tooling/font-abi.c. No SDL.
// A shape is one directional/script run, not a Unicode paragraph or editor.
import "../../../lib/ffi.flex";
import "../../../lib/bytes.flex";
global tf_error=0;
global tf_font_sequence=0;
fn tf_fail(message){tf_error=message;return 0;}
fn tf_zero(p,n){bytes_fill(p,0,n);return p;}
fn tf_i32(p){let value=bytes_load32(p);if value&0x80000000{return value-4294967296;}return value;}
fn tf_length(text){let n=0;while n<=32768 && load8(text+n){n=n+1;}return n;}
fn tf_symbols(c,library,offset,names){
    let at=0;let index=0;while load8(names+at){let n=0;while load8(names+at)!=59{store8(c+128+n,load8(names+at));at=at+1;n=n+1;}store8(c+128+n,0);at=at+1;
        let symbol=ffi_symbol(library,c+128);if !symbol{return tf_fail("A required font-library entry point is unavailable");}store64(c+offset+index*8,symbol);index=index+1;}return 1;
}
fn tf_ft(c,index,a,b,d,e,f,g){return ffi_call_i32(load64(c+256+index*8),a,b,d,e,f,g);}
fn tf_hb(c,index,a,b,d,e,f,g){return ffi_call(load64(c+512+index*8),a,b,d,e,f,g);}
fn tf_fc(c,index,a,b,d,e,f,g){return ffi_call(load64(c+768+index*8),a,b,d,e,f,g);}
// Context owns all open faces. Faces have immutable size/style and a unique ID
// so a glyph-cache key cannot alias a subsequently reused allocation address.
fn tf_context(){
    tf_error=0;let c=alloc(1024);if c<0{return tf_fail("Cannot allocate font context");}tf_zero(c,1024);
    store64(c,ffi_open("libfreetype.so.6"));store64(c+8,ffi_open("libharfbuzz.so.0"));store64(c+16,ffi_open("libfontconfig.so.1"));
    if !load64(c) || !load64(c+8) || !load64(c+16){tf_context_free(c);return tf_fail("FreeType, HarfBuzz and Fontconfig are required");}
    if !tf_symbols(c,load64(c),256,"FT_Init_FreeType;FT_Done_FreeType;FT_New_Face;FT_Done_Face;FT_Set_Pixel_Sizes;FT_Select_Size;FT_Get_Char_Index;FT_Load_Glyph;FT_Render_Glyph;") ||
       !tf_symbols(c,load64(c+8),512,"hb_ft_font_create_referenced;hb_font_destroy;hb_ft_font_set_load_flags;hb_buffer_create;hb_buffer_destroy;hb_buffer_add_utf8;hb_buffer_guess_segment_properties;hb_buffer_set_direction;hb_shape;hb_buffer_get_length;hb_buffer_get_glyph_infos;hb_buffer_get_glyph_positions;hb_buffer_get_direction;hb_unicode_funcs_get_default;hb_unicode_script;") ||
       !tf_symbols(c,load64(c+16),768,"FcNameParse;FcPatternAddInteger;FcCharSetCreate;FcCharSetAddChar;FcPatternAddCharSet;FcCharSetDestroy;FcConfigSubstitute;FcDefaultSubstitute;FcFontMatch;FcPatternGetString;FcPatternGetInteger;FcPatternDestroy;"){
        tf_context_free(c);return 0;
    }
    store64(c+40,tf_hb(c,13,0,0,0,0,0,0));if tf_ft(c,0,c+24,0,0,0,0,0){tf_context_free(c);return tf_fail("Cannot initialize FreeType");}return c;
}
// Face: FT, HB, owner, next, requested px, raster px, height, ascent, descent,
// style, unique ID. Bitmap-only faces use the nearest strike and scale at draw.
fn tf_font_open(c,family,pixels,style,codepoint){
    if !c || !family || pixels<1 || pixels>512{return tf_fail("Invalid native font request");}
    let pattern=0;let match=0;let path=family;let index=0;
    if load8(family)!=47{
        pattern=tf_fc(c,0,family,0,0,0,0,0);if !pattern{return tf_fail("Cannot parse font family");}
        if style&1{tf_fc(c,1,pattern,"weight",200,0,0,0);}if style&2{tf_fc(c,1,pattern,"slant",100,0,0,0);}
        if codepoint{let charset=tf_fc(c,2,0,0,0,0,0,0);if !charset{tf_fc(c,11,pattern,0,0,0,0,0);return tf_fail("Cannot allocate fallback charset");}
            tf_fc(c,3,charset,codepoint,0,0,0,0);tf_fc(c,4,pattern,"charset",charset,0,0,0);tf_fc(c,5,charset,0,0,0,0,0);}
        tf_fc(c,6,0,pattern,0,0,0,0);tf_fc(c,7,pattern,0,0,0,0,0);match=tf_fc(c,8,0,pattern,c+112,0,0,0);path=0;
        if match{store64(c+96,0);if tf_fc(c,9,match,"file",0,c+96,0,0)==0{path=load64(c+96);}bytes_store32(c+104,0);if tf_fc(c,10,match,"index",0,c+104,0,0)==0{index=tf_i32(c+104);}}
    }
    store64(c+96,0);let error=1;if path{error=tf_ft(c,2,load64(c+24),path,index,c+96,0,0);}let face=load64(c+96);
    if match{tf_fc(c,11,match,0,0,0,0,0);}if pattern{tf_fc(c,11,pattern,0,0,0,0,0);}
    if error || !face{return tf_fail("Cannot open requested font face");}
    error=tf_ft(c,4,face,0,pixels,0,0,0);
    if error{
        let count=tf_i32(face+56);let sizes=load64(face+64);let best=-1;let distance=2147483647;let i=0;
        while i<count{let d=load64(sizes+i*32+24)-pixels*64;if d<0{d=-d;}if d<distance{distance=d;best=i;}i=i+1;}
        if best>=0{error=tf_ft(c,5,face,best,0,0,0,0);}
    }
    if error{tf_ft(c,3,face,0,0,0,0,0);return tf_fail("Cannot select font pixel size");}
    let metrics=load64(face+160)+24;let raster=load8(metrics+2)|(load8(metrics+3)<<8);if raster<1{tf_ft(c,3,face,0,0,0,0,0);return tf_fail("Font has no usable pixel size");}
    let hb=tf_hb(c,0,face,0,0,0,0,0);if !hb{tf_ft(c,3,face,0,0,0,0,0);return tf_fail("Cannot create shaping font");}
    tf_hb(c,2,hb,0x100000,0,0,0,0);let f=alloc(96);if f<0{tf_hb(c,1,hb,0,0,0,0,0);tf_ft(c,3,face,0,0,0,0,0);return tf_fail("Cannot allocate font handle");}tf_zero(f,96);
    store64(f,face);store64(f+8,hb);store64(f+16,c);store64(f+24,load64(c+32));store64(c+32,f);store64(f+32,pixels);store64(f+40,raster);
    store64(f+48,(load64(metrics+40)*pixels/raster+63)/64);store64(f+56,(load64(metrics+24)*pixels/raster+63)/64);store64(f+64,load64(metrics+32)*pixels/raster/64);store64(f+72,style);
    tf_font_sequence=tf_font_sequence+1;store64(f+80,tf_font_sequence);return f;
}
fn tf_script(c,codepoint){return tf_hb(c,14,load64(c+40),codepoint,0,0,0,0);}
fn tf_font_has(f,codepoint){return tf_ft(load64(f+16),6,load64(f),codepoint,0,0,0,0)!=0;}
fn tf_font_close(f){
    if !f{return 0;}let c=load64(f+16);let p=load64(c+32);let previous=0;while p && p!=f{previous=p;p=load64(p+24);}if !p{return 0;}
    if previous{store64(previous+24,load64(f+24));}else{store64(c+32,load64(f+24));}tf_hb(c,1,load64(f+8),0,0,0,0,0);tf_ft(c,3,load64(f),0,0,0,0,0);syscall(11,f,96,0,0,0,0);return 0;
}
fn tf_context_free(c){
    if !c{return 0;}while load64(c+32){tf_font_close(load64(c+32));}if load64(c+24){tf_ft(c,1,load64(c+24),0,0,0,0,0);}
    if load64(c){ffi_close(load64(c));}if load64(c+8){ffi_close(load64(c+8));}if load64(c+16){ffi_close(load64(c+16));}syscall(11,c,1024,0,0,0,0);return 0;
}
// Owned shape header: count, total x/y advance (26.6), face ID, direction,
// UTF-8 byte count, allocation bytes; then glyph/cluster/xa/ya/xo/yo words.
// Clusters are UTF-8 byte offsets. Ligatures/combining marks can share a cluster.
fn tf_shape(f,text,n,direction){
    if !f || !text || n<0 || n>32768 || (direction && direction!=4 && direction!=5){return tf_fail("Invalid shaping run");}
    let c=load64(f+16);let buffer=tf_hb(c,3,0,0,0,0,0,0);if !buffer{return tf_fail("Cannot allocate shaping buffer");}
    tf_hb(c,5,buffer,text,n,0,n,0);if direction{tf_hb(c,7,buffer,direction,0,0,0,0);}tf_hb(c,6,buffer,0,0,0,0,0);tf_hb(c,8,load64(f+8),buffer,0,0,0,0);
    let count=tf_hb(c,9,buffer,0,0,0,0,0);if count>65536{tf_hb(c,4,buffer,0,0,0,0,0);return tf_fail("Shaped run exceeds glyph limit");}
    let bytes=64+count*48;let s=alloc(bytes);if s<0{tf_hb(c,4,buffer,0,0,0,0,0);return tf_fail("Cannot allocate shaped run");}tf_zero(s,64);
    store64(s,count);store64(s+24,load64(f+80));store64(s+32,tf_hb(c,12,buffer,0,0,0,0,0));store64(s+40,n);store64(s+48,bytes);
    let infos=tf_hb(c,10,buffer,0,0,0,0,0);let positions=tf_hb(c,11,buffer,0,0,0,0,0);let i=0;let ratio=load64(f+32);let divisor=load64(f+40);
    while i<count{let p=s+64+i*48;store64(p,bytes_load32(infos+i*20));store64(p+8,bytes_load32(infos+i*20+8));
        let a=tf_i32(positions+i*20)*ratio/divisor;let b=tf_i32(positions+i*20+4)*ratio/divisor;
        store64(p+16,a);store64(p+24,b);store64(p+32,tf_i32(positions+i*20+8)*ratio/divisor);store64(p+40,tf_i32(positions+i*20+12)*ratio/divisor);
        store64(s+8,load64(s+8)+a);store64(s+16,load64(s+16)+b);i=i+1;
    }tf_hb(c,4,buffer,0,0,0,0,0);return s;
}
fn tf_shape_free(s){if s{syscall(11,s,load64(s+48),0,0,0,0);}return 0;}
// Borrowed FreeType slot; valid until the next load on this face. Consumers
// must copy the bitmap before returning or doing another load.
fn tf_glyph_bitmap(f,glyph){
    let c=load64(f+16);if tf_ft(c,7,load64(f),glyph,0x100000,0,0,0){return tf_fail("Cannot load native glyph");}
    let slot=load64(load64(f)+152);if tf_ft(c,8,slot,0,0,0,0,0){return tf_fail("Cannot rasterize native glyph");}return slot;
}
