// XKB client state: compositor masks are authoritative. Never update client
// state from key presses as if this were the keyboard server.
import "../../../../lib/ffi-words.flex";
import "../../../../lib/ffi.flex";
import "../../../../lib/bytes.flex";
global xk_error=0;
fn xk_call(k,index,a,b,c,d,e,f){return ffi_call(load64(k+512+index*8),a,b,c,d,e,f);}
fn xk_free(k){
    if !k{return 0;}if load64(k+40){xk_call(k,14,load64(k+40),0,0,0,0,0);}if load64(k+32){xk_call(k,12,load64(k+32),0,0,0,0,0);}
    if load64(k+24){xk_call(k,5,load64(k+24),0,0,0,0,0);}if load64(k+16){xk_call(k,3,load64(k+16),0,0,0,0,0);}if load64(k+8){xk_call(k,1,load64(k+8),0,0,0,0,0);}ffi_words_free(load64(k+48));if load64(k){ffi_close(load64(k));}syscall(11,k,1024,0,0,0,0);return 0;
}
fn xk_open(locale){
    let k=alloc(1024);if k<0{return 0;}bytes_fill(k,0,1024);store64(k,ffi_open("libxkbcommon.so.0"));store64(k+48,ffi_words_context());if !load64(k) || !load64(k+48){xk_free(k);xk_error="xkbcommon runtime is required";return 0;}
    let names="xkb_context_new;xkb_context_unref;xkb_keymap_new_from_string;xkb_keymap_unref;xkb_state_new;xkb_state_unref;xkb_state_update_mask;xkb_state_key_get_utf8;xkb_state_mod_name_is_active;xkb_state_key_get_one_sym;xkb_keymap_key_repeats;xkb_compose_table_new_from_locale;xkb_compose_table_unref;xkb_compose_state_new;xkb_compose_state_unref;xkb_compose_state_feed;xkb_compose_state_get_status;xkb_compose_state_get_utf8;xkb_compose_state_reset;";
    let at=0;let index=0;while load8(names+at){let n=0;while load8(names+at)!=59{store8(k+256+n,load8(names+at));n=n+1;at=at+1;}store8(k+256+n,0);at=at+1;let symbol=ffi_symbol(load64(k),k+256);if !symbol{xk_free(k);xk_error="Required xkbcommon entry point is unavailable";return 0;}store64(k+512+index*8,symbol);index=index+1;}
    store64(k+8,xk_call(k,0,0,0,0,0,0,0));if !load64(k+8){xk_free(k);return 0;}if !locale{locale="C.UTF-8";}
    store64(k+32,xk_call(k,11,load64(k+8),locale,0,0,0,0));if load64(k+32){store64(k+40,xk_call(k,13,load64(k+32),0,0,0,0,0));}return k;
}
fn xk_map(k,text){
    let map=xk_call(k,2,load64(k+8),text,1,0,0,0);if !map{return 0;}let state=xk_call(k,4,map,0,0,0,0,0);if !state{xk_call(k,3,map,0,0,0,0,0);return 0;}
    if load64(k+24){xk_call(k,5,load64(k+24),0,0,0,0,0);}if load64(k+16){xk_call(k,3,load64(k+16),0,0,0,0,0);}store64(k+16,map);store64(k+24,state);if load64(k+40){xk_call(k,18,load64(k+40),0,0,0,0,0);}return 1;
}
fn xk_clear(k){if load64(k+24){xk_call(k,5,load64(k+24),0,0,0,0,0);store64(k+24,0);}if load64(k+16){xk_call(k,3,load64(k+16),0,0,0,0,0);store64(k+16,0);}if load64(k+40){xk_call(k,18,load64(k+40),0,0,0,0,0);}return 0;}
fn xk_update(k,depressed,latched,locked,group){
    if !load64(k+24){return 0;}store64(k+128,load64(k+24));store64(k+136,depressed);store64(k+144,latched);store64(k+152,locked);store64(k+160,0);store64(k+168,0);store64(k+176,group);return ffi_words_call(load64(k+48),load64(k+512+6*8),k+128,7);
}
fn xk_mods(k){
    if !k || !load64(k+24){return 0;}let state=load64(k+24);let mods=0;
    if xk_call(k,8,state,"Shift",8,0,0,0)==1{mods=mods|3;}if xk_call(k,8,state,"Control",8,0,0,0)==1{mods=mods|192;}
    if xk_call(k,8,state,"Mod1",8,0,0,0)==1{mods=mods|768;}if xk_call(k,8,state,"Mod4",8,0,0,0)==1{mods=mods|3072;}
    if xk_call(k,8,state,"Lock",8,0,0,0)==1{mods=mods|8192;}if xk_call(k,8,state,"Mod2",8,0,0,0)==1{mods=mods|4096;}if xk_call(k,8,state,"Mod5",8,0,0,0)==1{mods=mods|16384;}return mods;
}
fn xk_text(k,evdev,compose,out,capacity){
    if !k || !load64(k+24) || capacity<2{return 0;}store8(out,0);let n=0;let composed=0;
    if compose && load64(k+40){let state=load64(k+40);let symbol=xk_call(k,9,load64(k+24),evdev+8,0,0,0,0);xk_call(k,15,state,symbol,0,0,0,0);let status=xk_call(k,16,state,0,0,0,0,0);
        if status==1{return 0;}if status==3{xk_call(k,18,state,0,0,0,0,0);return 0;}if status==2{n=xk_call(k,17,state,out,capacity,0,0,0);xk_call(k,18,state,0,0,0,0,0);composed=1;}
    }
    if !composed{n=xk_call(k,7,load64(k+24),evdev+8,out,capacity,0,0);}if n<1 || n>=capacity{store8(out,0);return 0;}
    // Tab, Enter, Escape and control sequences belong to physical key actions.
    if load8(out)<32 || load8(out)==127{store8(out,0);return 0;}return n;
}
fn xk_repeats(k,evdev){if !k || !load64(k+16){return 0;}return xk_call(k,10,load64(k+16),evdev+8,0,0,0,0)!=0;}
// Linux evdev physical positions -> existing GUI USB HID/SDL scancode ABI.
// Alphabetic positions remain stable when the logical layout changes.
fn xk_scan(evdev){
    if evdev<0 || evdev>127{return 0;}
    let table="00291e1f20212223242526272d2e2a2b141a0815171c180c12132f3028e0041607090a0b0d0e0f333435e1311d1b0619051110363738e555e22c393a3b3c3d3e3f4041424353475f6061565c5d5e57595a5b626300006444450000000000000058e45446e6004a524b504f4d514e494c00000000000000480000000000e3e765";
    let a=load8(table+evdev*2);let b=load8(table+evdev*2+1);if a>57{a=a-87;}else{a=a-48;}if b>57{b=b-87;}else{b=b-48;}return (a<<4)|b;
}
