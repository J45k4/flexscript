// Optional SDL canvas resources: Unicode fonts, text layers and local images.
// All FFI remains here; callers own and release each font/texture handle.
import "canvas.flex";
global gui__ttf=0;
global gui__fc=0;
global gui__pixbuf=0;
global gui__gobject=0;
fn gui__length(text){let n=0;while load8(text+n){n=n+1;}return n;}
fn gui__font_symbol(name){let p=ffi_symbol(gui__ttf,name);if !p{gui__fail(name);}return p;}
fn gui__font_open(family,size,style,codepoint){
    if !gui_init() || !family || size<1 || size>256{return gui__fail("Invalid font family or size");}
    if !gui__ttf{gui__ttf=ffi_open("libSDL2_ttf-2.0.so.0");if !gui__ttf{return gui__fail("SDL2_ttf runtime is required");}if ffi_call_i32(gui__font_symbol("TTF_Init"),0,0,0,0,0,0)<0{return gui__sdl_error();}}
    let path=family;let pattern=0;let match=0;
    if load8(family)!=47{
        if !gui__fc{gui__fc=ffi_open("libfontconfig.so.1");}if !gui__fc{return gui__fail("Fontconfig runtime is required");}
        pattern=ffi_call(ffi_symbol(gui__fc,"FcNameParse"),family,0,0,0,0,0);
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
fn gui_texture_layer(window,w,h){let p=gui__canvas(window);if !p || w<1 || h<1 || w>8192 || h>16384{return gui__fail("Invalid text layer size");}let texture=gui__call("SDL_CreateTexture",load64(p+8),0x16762004,2,w,h,0);if !texture{return gui__sdl_error();}gui__int("SDL_SetTextureBlendMode",texture,1,0,0,0,0);return texture;}
fn gui_texture_target(window,texture){let p=gui__canvas(window);if !p{return 0;}return gui__int("SDL_SetRenderTarget",load64(p+8),texture,0,0,0,0)==0;}
fn gui_texture_clear(window){let p=gui__canvas(window);if !p{return 0;}gui__int("SDL_SetRenderDrawColor",load64(p+8),0,0,0,0,0);return gui__int("SDL_RenderClear",load64(p+8),0,0,0,0,0)==0;}
fn gui_text_draw(window,font,text,rgb,x,y){
    if !load8(text){return 1;}let p=gui__canvas(window);if !p{return 0;}
    // SDL_Color is a four-byte by-value structure (R,G,B,A).
    let color=0xff000000|((rgb&255)<<16)|(rgb&0xff00)|((rgb>>16)&255);
    let surface=ffi_call(gui__font_symbol("TTF_RenderUTF8_Blended"),font,text,color,0,0,0);if !surface{return gui__sdl_error();}
    let w=gui__i32(surface+16);let h=gui__i32(surface+20);
    let texture=gui__call("SDL_CreateTextureFromSurface",load64(p+8),surface,0,0,0,0);gui__call("SDL_FreeSurface",surface,0,0,0,0,0);
    if !texture{return gui__sdl_error();}let ok=gui_texture_draw(window,texture,x,y,w,h);gui_texture_close(texture);return ok;
}
// Loads PNG/JPEG/etc with the system decoder, then owns an SDL texture copy.
// dimensions points to two words. No network fetching or virtual path policy.
fn gui_image_load(window,path,dimensions){
    let p=gui__canvas(window);if !p{return 0;}
    if !gui__pixbuf{gui__pixbuf=ffi_open("libgdk_pixbuf-2.0.so.0");gui__gobject=ffi_open("libgobject-2.0.so.0");}
    if !gui__pixbuf || !gui__gobject{return gui__fail("GdkPixbuf runtime is required for images");}
    let image=ffi_call(ffi_symbol(gui__pixbuf,"gdk_pixbuf_new_from_file"),path,0,0,0,0,0);if !image{return gui__fail("Cannot decode local image");}
    let w=ffi_call_i32(ffi_symbol(gui__pixbuf,"gdk_pixbuf_get_width"),image,0,0,0,0,0);let h=ffi_call_i32(ffi_symbol(gui__pixbuf,"gdk_pixbuf_get_height"),image,0,0,0,0,0);
    let texture=0;
    if w>0 && h>0 && w<=8192 && h<=8192 && w*h<=24000000{
        let channels=ffi_call_i32(ffi_symbol(gui__pixbuf,"gdk_pixbuf_get_n_channels"),image,0,0,0,0,0);
        let stride=ffi_call_i32(ffi_symbol(gui__pixbuf,"gdk_pixbuf_get_rowstride"),image,0,0,0,0,0);
        let pixels=ffi_call(ffi_symbol(gui__pixbuf,"gdk_pixbuf_get_pixels"),image,0,0,0,0,0);
        let rgba=alloc(w*h*4);let y=0;
        while y<h{let x=0;while x<w{let src=pixels+y*stride+x*channels;let dst=rgba+(y*w+x)*4;store8(dst,load8(src));store8(dst+1,load8(src+1));store8(dst+2,load8(src+2));let a=255;if channels==4{a=load8(src+3);}store8(dst+3,a);x=x+1;}y=y+1;}
        texture=gui__call("SDL_CreateTexture",load64(p+8),0x16762004,0,w,h,0);
        if texture{gui__int("SDL_UpdateTexture",texture,0,rgba,w*4,0,0);gui__int("SDL_SetTextureBlendMode",texture,1,0,0,0,0);store64(dimensions,w);store64(dimensions+8,h);}
        syscall(11,rgba,w*h*4,0,0,0,0);
    }
    ffi_call(ffi_symbol(gui__gobject,"g_object_unref"),image,0,0,0,0,0);return texture;
}
