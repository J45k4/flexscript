// Linux terminal lifecycle and UTF-8 display primitives. No model dependencies.
import "../../scripts/lib/host.flex";
import "../../lib/ffi.flex";
global tu_escape=0;
global tu_original=0;
global tu_signal_fd=-1;
global tu_old_mask=0;
global tu_cols=80;
global tu_rows=24;
// Optional left viewport. Clear only its cells when another pane shares rows.
global tu_clip=0;
global tu_libc=0;
global tu_width_fn=0;
global tu_mark_fn=0;
fn tu_unicode() {
    if !tu_libc {tu_libc=ffi_open("libc.so.6");ffi_call(ffi_symbol(tu_libc,"setlocale"),0,"",0,0,0,0);tu_width_fn=ffi_symbol(tu_libc,"wcwidth");tu_mark_fn=ffi_symbol(ffi_open("libglib-2.0.so.0"),"g_unichar_ismark");}return 0;
}
// Scoped rendering scratch restores the arena cursor, avoiding per-frame leaks.
fn tu_mark() {let p=alloc(24);store64(p,h_blocks);store64(p+8,h_used);store64(p+16,h_capacity);h_mark();return p;}
fn tu_reset(p) {h_reset(load64(p));h_used=load64(p+8);h_capacity=load64(p+16);syscall(11,p,24,0,0,0,0);return 0;}
fn tu_ansi(text) {
    if !tu_escape {tu_escape=h_take(2);store8(tu_escape,27);store8(tu_escape+1,0);}
    return h_replace(text,"@",tu_escape);
}
fn tu_open() {
    tu_ansi("");
    tu_original=h_zero(h_take(64),64);
    if syscall(16,0,0x5401,tu_original,0,0,0)!=0 {return 0;}
    let raw=h_zero(h_take(64),64);h_copy(raw,tu_original,36);
    // Keep output processing; disable input translations, echo and ISIG.
    store64(raw,load64(raw)&(~(0x5eb)));store64(raw+8,load64(raw+8)&(~(0x804b<<32)));
    store8(raw+22,0);store8(raw+23,1);
    let mask=h_take(8);tu_old_mask=h_take(8);store64(mask,0x4003);
    if syscall(14,0,mask,tu_old_mask,8,0,0)!=0 {return 0;}
    tu_signal_fd=syscall(289,-1,mask,8,0x80800,0,0);
    if tu_signal_fd<0 {syscall(14,2,tu_old_mask,0,8,0,0);return 0;}
    if syscall(16,0,0x5402,raw,0,0,0)!=0 {tu_close();return 0;}
    tu_unicode();
    h_print(1,tu_ansi("@[?1049h@[?25l@[?2004h@[?1002h@[?1006h"));tu_size();return 1;
}
fn tu_close() {
    if tu_original {syscall(16,0,0x5402,tu_original,0,0,0);h_print(1,tu_ansi("@[0m@[?1006l@[?1002l@[?2004l@[?25h@[?1049l"));tu_original=0;}
    if tu_signal_fd>=0 {h_close(tu_signal_fd);tu_signal_fd=-1;syscall(14,2,tu_old_mask,0,8,0,0);}return 0;
}
fn tu_size() {
    let size=h_take(8);store64(size,0);if syscall(16,1,0x5413,size,0,0,0)==0 {let v=load64(size);if (v&65535)>=6 {tu_rows=v&65535;}if ((v>>16)&65535)>=20 {tu_cols=(v>>16)&65535;}}
    return 0;
}
fn tu_code(text,at) {
    let c=load8(text+at);if c<128 {return c;}let left=1;let value=c&31;if c>=224 {left=2;value=c&15;}if c>=240 {left=3;value=c&7;}
    let i=1;while i<=left {let b=load8(text+at+i);if (b&192)!=128 {return 65533;}value=(value<<6)|(b&63);i=i+1;}return value;
}
fn tu_rune_next(text,at) {if !load8(text+at) {return at;}at=at+1;while (load8(text+at)&192)==128 {at=at+1;}return at;}
fn tu_next(text,at) {
    let first=tu_code(text,at);let next=tu_rune_next(text,at);if next==at {return at;}let regional=first>=0x1f1e6 && first<=0x1f1ff;
    while load8(text+next) {let code=tu_code(text,next);let mark=code>=0xfe00 && code<=0xfe0f;mark=mark || (code>=0x1f3fb && code<=0x1f3ff) || (code>=0xe0100 && code<=0xe01ef);
        if tu_mark_fn {mark=mark || ffi_call_i32(tu_mark_fn,code,0,0,0,0,0);}
        if mark {next=tu_rune_next(text,next);}else if code==0x200d {next=tu_rune_next(text,next);next=tu_rune_next(text,next);}
        else if regional && code>=0x1f1e6 && code<=0x1f1ff {next=tu_rune_next(text,next);regional=0;}else {return next;}}
    return next;
}
fn tu_prev(text,at) {let pos=0;let prev=0;while pos<at {prev=pos;pos=tu_next(text,pos);}return prev;}
fn tu_width(code) {if code==10 {return 0;}if code==9 {return 1;}if code<32 || code==127 {return 0;}if tu_width_fn {let w=ffi_call_i32(tu_width_fn,code,0,0,0,0,0);if w>=0 {return w;}}return 1;}
fn tu_clean(text) {
    let out=h_buffer();let i=0;while load8(text+i) {let c=load8(text+i);if c>=32 && c!=127 {h_append(out,text+i,1);}else if c==10 || c==9 {h_append(out,text+i,1);}i=i+1;}return h_data(out);
}
fn tu_pos(out,row,col) {h_text(out,h_cat3(tu_escape,"[",h_cat3(h_int(row),";",h_cat(h_int(col),"H"))));return 0;}
fn tu_clear_line(out) {if tu_clip {h_text(out,h_cat3(tu_escape,"[",h_cat(h_int(tu_cols),"X")));}else {h_text(out,h_cat(tu_escape,"[2K"));}return 0;}
fn tu_line(out,row,text,color) {
    tu_pos(out,row,1);tu_clear_line(out);if color {h_text(out,h_cat3(tu_escape,"[",h_cat(color,"m")));}
    let i=0;let col=0;let more=1;while more && load8(text+i) && load8(text+i)!=10 {let next=tu_next(text,i);let w=tu_width(tu_code(text,i));if col+w>tu_cols {more=0;}else {if w || load8(text+i)>=128 {h_append(out,text+i,next-i);}col=col+w;i=next;}}
    h_text(out,h_cat(tu_escape,"[0m"));return 0;
}
