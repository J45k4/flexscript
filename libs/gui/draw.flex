// Optional SDL canvas resources: Unicode fonts, text layers and local images.
// All FFI remains here; callers own and release each font/texture handle.
import "canvas.flex";
import "../image.flex";
global gui__ttf=0;
global gui__fc=0;
global gui__image_decoder=0;
fn gui__length(text){let n=0;while load8(text+n){n=n+1;}return n;}
fn gui__font_symbol(name){let p=ffi_symbol(gui__ttf,name);if !p{gui__fail(name);}return p;}
fn gui__font_open(family,size,style,codepoint){
    if !gui_init() || !family || size<1 || size>256{return gui__fail("Invalid font family or size");}
    if !gui__ttf{gui__ttf=ffi_open("libSDL2_ttf-2.0.so.0");if !gui__ttf{return gui__fail("SDL2_ttf runtime is required");}if ffi_call_i32(gui__font_symbol("TTF_Init"),0,0,0,0,0,0)<0{return gui__sdl_error();}}
    let path=family;let pattern=0;let match=0;
    if load8(family)!=47{
        if !gui__fc{gui__fc=ffi_open("libfontconfig.so.1");}if !gui__fc{return gui__fail("Fontconfig runtime is required");}
        pattern=ffi_call(ffi_symbol(gui__fc,"FcNameParse"),family,0,0,0,0,0);
        // Select the real bold face before considering synthetic font styling.
        if style&1{ffi_call_i32(ffi_symbol(gui__fc,"FcPatternAddInteger"),pattern,"weight",200,0,0,0);}
        if style&2{ffi_call_i32(ffi_symbol(gui__fc,"FcPatternAddInteger"),pattern,"slant",100,0,0,0);}
        if codepoint{let charset=ffi_call(ffi_symbol(gui__fc,"FcCharSetCreate"),0,0,0,0,0,0);ffi_call_i32(ffi_symbol(gui__fc,"FcCharSetAddChar"),charset,codepoint,0,0,0,0);ffi_call_i32(ffi_symbol(gui__fc,"FcPatternAddCharSet"),pattern,"charset",charset,0,0,0);ffi_call(ffi_symbol(gui__fc,"FcCharSetDestroy"),charset,0,0,0,0,0);}
        ffi_call_i32(ffi_symbol(gui__fc,"FcConfigSubstitute"),0,pattern,0,0,0,0);
        ffi_call(ffi_symbol(gui__fc,"FcDefaultSubstitute"),pattern,0,0,0,0,0);
        match=ffi_call(ffi_symbol(gui__fc,"FcFontMatch"),0,pattern,gui__scratch,0,0,0);
        store64(gui__scratch,0);
        if match{ffi_call_i32(ffi_symbol(gui__fc,"FcPatternGetString"),match,"file",0,gui__scratch,0,0);}path=load64(gui__scratch);
    }
    let font=0;if path{font=ffi_call(gui__font_symbol("TTF_OpenFont"),path,size,0,0,0,0);}
    if match{ffi_call(ffi_symbol(gui__fc,"FcPatternDestroy"),match,0,0,0,0,0);}if pattern{ffi_call(ffi_symbol(gui__fc,"FcPatternDestroy"),pattern,0,0,0,0,0);}
    if !font{return gui__fail("Cannot open requested font");}
    ffi_call(gui__font_symbol("TTF_SetFontStyle"),font,style,0,0,0,0);return font;
}
fn gui_font_open(family,size,style){return gui__font_open(family,size,style,0);}
fn gui_font_fallback(family,size,style,codepoint){return gui__font_open(family,size,style,codepoint);}
fn gui_font_has(font,codepoint){return ffi_call_i32(gui__font_symbol("TTF_GlyphIsProvided32"),font,codepoint,0,0,0,0)!=0;}
fn gui_font_close(font){if font{ffi_call(gui__font_symbol("TTF_CloseFont"),font,0,0,0,0,0);}return 0;}
fn gui_font_height(font){return ffi_call_i32(gui__font_symbol("TTF_FontHeight"),font,0,0,0,0,0);}
fn gui_font_ascent(font){return ffi_call_i32(gui__font_symbol("TTF_FontAscent"),font,0,0,0,0,0);}
fn gui_text_width(font,text){if !load8(text){return 0;}if ffi_call_i32(gui__font_symbol("TTF_SizeUTF8"),font,text,gui__scratch,gui__scratch+4,0,0)<0{return -1;}return gui__i32(gui__scratch);}
fn gui_canvas_size(window,width,height){let p=gui__canvas(window);if !p{return 0;}return gui__int("SDL_RenderSetLogicalSize",load64(p+8),width,height,0,0,0)==0;}
fn gui_canvas_clip(window,x,y,w,h){let p=gui__canvas(window);if !p{return 0;}gui__put32(gui__scratch,x);gui__put32(gui__scratch+4,y);gui__put32(gui__scratch+8,w);gui__put32(gui__scratch+12,h);return gui__int("SDL_RenderSetClipRect",load64(p+8),gui__scratch,0,0,0,0)==0;}
fn gui_canvas_unclip(window){let p=gui__canvas(window);if !p{return 0;}return gui__int("SDL_RenderSetClipRect",load64(p+8),0,0,0,0,0)==0;}
fn gui_canvas_rgba(window,x,y,w,h,rgba){
    let p=gui__canvas(window);if !p{return 0;}
    gui__int("SDL_SetRenderDrawBlendMode",load64(p+8),1,0,0,0,0);
    gui__int("SDL_SetRenderDrawColor",load64(p+8),(rgba>>16)&255,(rgba>>8)&255,rgba&255,(rgba>>24)&255,0);
    gui__put32(gui__scratch,x);gui__put32(gui__scratch+4,y);gui__put32(gui__scratch+8,w);gui__put32(gui__scratch+12,h);
    return gui__int("SDL_RenderFillRect",load64(p+8),gui__scratch,0,0,0,0)==0;
}
fn gui_texture_close(texture){if texture{gui__call("SDL_DestroyTexture",texture,0,0,0,0,0);}return 0;}
fn gui_texture_alpha(texture,alpha){return gui__int("SDL_SetTextureAlphaMod",texture,alpha,0,0,0,0)==0;}
fn gui_text_area(x,y,w,h){gui__put32(gui__scratch,x);gui__put32(gui__scratch+4,y);gui__put32(gui__scratch+8,w);gui__put32(gui__scratch+12,h);gui__call("SDL_SetTextInputRect",gui__scratch,0,0,0,0,0);return 0;}
fn gui_clipboard_copy(text){return gui__int("SDL_SetClipboardText",text,0,0,0,0,0)==0;}
// Returns a Flexscript-owned UTF-8 allocation; release with gui_clipboard_release.
fn gui_clipboard_read(){let raw=gui__call("SDL_GetClipboardText",0,0,0,0,0,0);if !raw{return 0;}let n=gui__length(raw);if n>1048576{gui__call("SDL_free",raw,0,0,0,0,0);return gui__fail("Clipboard text exceeds 1 MiB");}let copy=alloc(n+1);let i=0;while i<=n{store8(copy+i,load8(raw+i));i=i+1;}gui__call("SDL_free",raw,0,0,0,0,0);return copy;}
fn gui_clipboard_release(text){if text{syscall(11,text,gui__length(text)+1,0,0,0,0);}return 0;}
fn gui_texture_draw(window,texture,x,y,w,h){let p=gui__canvas(window);if !p || !texture{return 0;}gui__put32(gui__scratch,x);gui__put32(gui__scratch+4,y);gui__put32(gui__scratch+8,w);gui__put32(gui__scratch+12,h);return gui__int("SDL_RenderCopy",load64(p+8),texture,0,gui__scratch,0,0)==0;}
fn gui_texture_layer(window,w,h){
    let p=gui__canvas(window);if !p || w<1 || h<1 || w>8192 || h>16384{return gui__fail("Invalid text layer size");}
    let texture=gui__call("SDL_CreateTexture",load64(p+8),0x16762004,2,w,h,0);if !texture{return gui__sdl_error();}
    gui__int("SDL_SetTextureBlendMode",texture,1,0,0,0,0);
    gui__int("SDL_SetTextureScaleMode",texture,1,0,0,0,0);return texture;
}
fn gui_texture_target(window,texture){let p=gui__canvas(window);if !p{return 0;}return gui__int("SDL_SetRenderTarget",load64(p+8),texture,0,0,0,0)==0;}
fn gui_texture_clear(window){let p=gui__canvas(window);if !p{return 0;}gui__int("SDL_SetRenderDrawColor",load64(p+8),0,0,0,0,0);return gui__int("SDL_RenderClear",load64(p+8),0,0,0,0,0)==0;}
fn gui_text_draw(window,font,text,rgb,x,y){return gui__text_draw(window,font,text,rgb,x,y,0);}
// Glyph runs occupy separate rectangles in a text-only transparent layer.
// Copy straight alpha so glyph coverage is applied exactly once at composition.
fn gui_text_layer_draw(window,font,text,rgb,x,y){return gui__text_draw(window,font,text,rgb,x,y,1);}
fn gui__text_draw(window,font,text,rgb,x,y,text_layer){
    if !load8(text){return 1;}let p=gui__canvas(window);if !p{return 0;}
    // SDL_Color is a four-byte by-value structure (R,G,B,A).
    let color=0xff000000|((rgb&255)<<16)|(rgb&0xff00)|((rgb>>16)&255);
    let surface=ffi_call(gui__font_symbol("TTF_RenderUTF8_Blended"),font,text,color,0,0,0);if !surface{return gui__sdl_error();}
    let w=gui__i32(surface+16);let h=gui__i32(surface+20);
    let texture=gui__call("SDL_CreateTextureFromSurface",load64(p+8),surface,0,0,0,0);gui__call("SDL_FreeSurface",surface,0,0,0,0,0);
    if !texture{return gui__sdl_error();}
    if text_layer{gui__int("SDL_SetTextureBlendMode",texture,0,0,0,0,0);}
    let ok=gui_texture_draw(window,texture,x,y,w,h);gui_texture_close(texture);return ok;
}
// Decode approved local raster files directly into RGBA, then upload once.
// Textures retain their own SDL copy; the decoder owns no live image pointers.
fn gui_image_decoder_close(){image_context_free(gui__image_decoder);gui__image_decoder=0;return 0;}
fn gui_image_load(window,path,dimensions){
    let p=gui__canvas(window);if !p{return 0;}
    if !gui__image_decoder{gui__image_decoder=image_context();}if !gui__image_decoder{return gui__fail("Cannot initialize image decoder");}
    let fd=syscall(2,path,0x80800,0,0,0,0);if fd<0{return gui__fail("Cannot open local image");}
    let st=alloc(144);let valid=st>0 && syscall(5,fd,st,0,0,0,0)==0;let n=0;
    if valid{n=load64(st+48);valid=(load64(st+24)&61440)==32768 && n>0 && n<=67108864;}
    if st>0{syscall(11,st,144,0,0,0,0);}if !valid{syscall(3,fd,0,0,0,0,0);return gui__fail("Choose a regular image up to 64 MiB");}
    let data=alloc(n);if data<0{syscall(3,fd,0,0,0,0,0);return gui__fail("Cannot allocate image input");}
    let at=0;let more=1;while at<n && more{let got=syscall(0,fd,data+at,n-at,0,0,0);if got>0{at=at+got;}else if got!=-4{more=0;}}
    syscall(3,fd,0,0,0,0,0);let image=0;if at==n{image=image_decode(gui__image_decoder,data,n);}syscall(11,data,n,0,0,0,0);
    if !image{return gui__fail("Cannot decode local PNG, JPEG or WebP image");}
    let w=image_width(image);let h=image_height(image);let texture=0;
    if w>0 && h>0 && w<=8192 && h<=8192 && w*h<=24000000{
        texture=gui__call("SDL_CreateTexture",load64(p+8),0x16762004,0,w,h,0);
        if texture{if gui__int("SDL_UpdateTexture",texture,0,image_pixels(image),image_stride(image),0,0)!=0{gui_texture_close(texture);texture=0;gui__sdl_error();}else{gui__int("SDL_SetTextureBlendMode",texture,1,0,0,0,0);store64(dimensions,w);store64(dimensions+8,h);}}
        else{gui__sdl_error();}
    }else{gui__fail("Image exceeds texture dimensions");}
    image_free(image);return texture;
}
