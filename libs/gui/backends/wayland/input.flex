// Native seat input. wl_keyboard keymaps/masks feed xkbcommon client state;
// button grabs follow Wayland implicit-grab semantics. One seat/window for now.
import "keyboard.flex";
import "clipboard.flex";
import "cursor.flex";
import "ime.flex";
fn wi_release(c,proxy,opcode){if !proxy{return 0;}if wl_call(c,"wl_proxy_get_version",proxy,0,0,0,0,0)<3{opcode=-1;}return wl_destroy(c,proxy,opcode);}
fn wi_emit(w,kind,code,x,y,dx,dy,button,repeat){
    if !load64(w+8){return 0;}let e=w+512;bytes_fill(e,0,128);store64(e,kind);store64(e+8,load64(w+8));store64(e+16,code);store64(e+24,x);store64(e+32,y);store64(e+40,dx);store64(e+48,dy);store64(e+56,button);store64(e+64,repeat);store64(e+72,xk_mods(load64(w+16)));if kind==GUI_KEY_DOWN || kind==GUI_KEY_UP || kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP{store64(e+80,load64(w+232));}return gui_event_enqueue(e);
}
// Input-only seats can focus text_input without creating wl_keyboard.
fn wi_focus(w,focused){if load64(w+64)==focused{return 0;}store64(w+64,focused);return wi_emit(w,GUI_FOCUS,focused,0,0,0,0,0,0);}
fn wi_key(w,key,pressed,repeat){
    let code=xk_scan(key);if code{let kind=GUI_KEY_UP;if pressed{kind=GUI_KEY_DOWN;}wi_emit(w,kind,code,0,0,0,0,0,repeat);}
    let k=load64(w+16);if pressed && gn_text_enabled && !load64(load64(w+256)+248) && !(xk_mods(k)&0xfc0){let n=xk_text(k,key,!repeat,w+640,48);if n{let e=w+512;bytes_fill(e,0,128);store64(e,GUI_TEXT);store64(e+8,load64(w+8));bytes_copy(e+80,w+640,n+1);gui_event_enqueue(e);}}
    return 0;
}
fn wi_repeat(w){
    if !load64(w+96) || !load64(w+64){return 0;}let now=gui_monotonic_ns();if now<load64(w+112){return 0;}wi_key(w,load64(w+96)-1,1,1);store64(w+112,now+load64(w+104));return 1;
}
fn wi_timeout(w,ms){if !load64(w+96){return ms;}let left=(load64(w+112)-gui_monotonic_ns()+999999)/1000000;if left<0{left=0;}if left<ms{return left;}return ms;}
fn wi_blur(w){
    store64(w+64,0);store64(w+96,0);store64(w+112,0);let k=load64(w+16);xk_update(k,0,0,0,0);if load64(k+40){xk_call(k,18,load64(k+40),0,0,0,0,0);}return wi_emit(w,GUI_FOCUS,0,0,0,0,0,0,0);
}
fn wi_buttons_release(w){
    let buttons=load64(w+264);store64(w+264,0);let serial=load64(w+232);store64(w+232,0);let i=0;while i<32{if buttons&(1<<i){wi_emit(w,GUI_MOUSE_UP,0,-1,-1,0,0,i+1,0);}i=i+1;}store64(w+232,serial);return 0;
}
fn wi_pointer_drop(c,w){
    wn_pointer(c,load64(w+248),0);wi_release(c,load64(w+32),1);store64(w+32,0);store64(w+56,0);store64(w+216,0);bytes_fill(w+128,0,88);wi_buttons_release(w);return wi_motion(w,-1,-1);
}
fn wi_keyboard_drop(c,w){wi_release(c,load64(w+40),0);store64(w+40,0);wi_blur(w);return xk_clear(load64(w+16));}
fn wi_motion(w,x,y){let dx=x-load64(w+72);let dy=y-load64(w+80);store64(w+72,x);store64(w+80,y);return wi_emit(w,GUI_MOUSE_MOVE,0,x,y,dx,dy,0,0);}
fn wi_scroll(w){
    let dx=0;let dy=0;let flags=load64(w+176);
    if flags&1{store64(w+184,load64(w+184)+load64(w+160));dx=-load64(w+184)/120;store64(w+184,load64(w+184)%120);}else if flags&4{dx=-load64(w+144);}else{store64(w+200,load64(w+200)+load64(w+128));dx=-load64(w+200)/2560;store64(w+200,load64(w+200)%2560);}
    if flags&2{store64(w+192,load64(w+192)+load64(w+168));dy=-load64(w+192)/120;store64(w+192,load64(w+192)%120);}else if flags&8{dy=-load64(w+152);}else{store64(w+208,load64(w+208)+load64(w+136));dy=-load64(w+208)/2560;store64(w+208,load64(w+208)%2560);}
    bytes_fill(w+128,0,56);if dx || dy{wi_emit(w,GUI_WHEEL,0,load64(w+72),load64(w+80),dx,dy,0,0);}return 0;
}
fn wi_dispatch(metadata,proxy,opcode,message,args,unused){
    let c=load64(metadata+16);let w=load64(c+192);let kind=load64(metadata+8);let lib=load64(c);
    if kind==1 && opcode==0{let name=load64(args+8);if wl_equal(name,"wl_seat") && !load64(w+24){let version=bytes_load32(args+16);if version>8{version=8;}store64(w+24,wl_bind(c,bytes_load32(args),ffi_symbol(lib,"wl_seat_interface"),version,20));store64(w+48,bytes_load32(args));}}
    else if kind==1 && opcode==1{if load64(w+24) && bytes_load32(args)==load64(w+48){wi_pointer_drop(c,w);wi_keyboard_drop(c,w);let seat=load64(w+24);let release=-1;if wl_call(c,"wl_proxy_get_version",seat,0,0,0,0,0)>=5{release=3;}wl_destroy(c,seat,release);store64(w+24,0);store64(w+48,0);store64(w+88,0);store64(w+232,0);store64(w+240,0);}}
    else if kind==20 && opcode==0{let caps=bytes_load32(args);
        if caps&1{if !load64(w+32){let pointer=wl_req(c,proxy,0,ffi_symbol(lib,"wl_pointer_interface"),wl_args(c,0,0,0,0,0,0),0);store64(w+32,wl_watch(c,pointer,21,0));}}
        else if load64(w+32){wi_pointer_drop(c,w);}
        if caps&2{if !load64(w+40){let keyboard=wl_req(c,proxy,1,ffi_symbol(lib,"wl_keyboard_interface"),wl_args(c,0,0,0,0,0,0),0);store64(w+40,wl_watch(c,keyboard,22,0));}}
        else if load64(w+40){wi_keyboard_drop(c,w);if load64(load64(w+256)+32){wi_focus(w,1);}}
    }else if kind==21{
        if opcode==0{store64(w+56,1);store64(w+88,bytes_load32(args));store64(w+216,bytes_load32(args));wi_motion(w,tf_i32(args+16)/256,tf_i32(args+24)/256);}
        else if opcode==1{store64(w+56,0);wi_buttons_release(w);wi_motion(w,-1,-1);}
        else if opcode==2{wi_motion(w,tf_i32(args+8)/256,tf_i32(args+16)/256);}
        else if opcode==3{store64(w+88,bytes_load32(args));store64(w+232,bytes_load32(args));let button=bytes_load32(args+16);let code=0;if button==272{code=1;}else if button==273{code=3;}else if button==274{code=2;}else if button>=275 && button<=303{code=button-271;}
            if code{let event=GUI_MOUSE_UP;let mask=1<<(code-1);if bytes_load32(args+24){event=GUI_MOUSE_DOWN;store64(w+264,load64(w+264)|mask);}else{store64(w+264,load64(w+264)&~mask);}wi_emit(w,event,0,load64(w+72),load64(w+80),0,0,code,0);}}
        else if opcode==4{let axis=bytes_load32(args+8);if axis<=1{let at=136;if axis{at=128;}store64(w+at,load64(w+at)+tf_i32(args+16));if wl_call(c,"wl_proxy_get_version",proxy,0,0,0,0,0)<5{wi_scroll(w);}}}
        else if opcode==5{wi_scroll(w);}
        else if opcode==8{let axis=bytes_load32(args);if axis<=1{let at=152;let mask=8;if axis{at=144;mask=4;}store64(w+at,load64(w+at)+tf_i32(args+8));store64(w+176,load64(w+176)|mask);}}
        else if opcode==9{let axis=bytes_load32(args);if axis<=1{let at=168;let mask=2;if axis{at=160;mask=1;}store64(w+at,load64(w+at)+tf_i32(args+8));store64(w+176,load64(w+176)|mask);}}
    }else if kind==22{
        if opcode==0{let format=bytes_load32(args);let fd=tf_i32(args+8);let n=bytes_load32(args+16);let ok=0;if format==0{xk_clear(load64(w+16));ok=1;}
            if format==1 && n>0 && n<=4194304{let mapping=syscall(9,0,n,1,2,fd,0);if mapping>0{if !load8(mapping+n-1){ok=xk_map(load64(w+16),mapping);}syscall(11,mapping,n,0,0,0,0);}}
            syscall(3,fd,0,0,0,0,0);store64(w+96,0);if !ok{wl_fail(c,"Cannot load compositor keyboard map");}
        }else if opcode==1{store64(w+64,1);store64(w+88,bytes_load32(args));wi_emit(w,GUI_FOCUS,1,0,0,0,0,0,0);let array=load64(args+16);let n=load64(array);let keys=load64(array+16);let i=0;let record=gui__record(load64(w+8));while i+4<=n && i<4096{let code=xk_scan(bytes_load32(keys+i));if record && code{store8(record+128+code,1);}i=i+4;}}
        else if opcode==2{wi_blur(w);}
        else if opcode==3{store64(w+88,bytes_load32(args));store64(w+232,bytes_load32(args));let key=bytes_load32(args+16);let pressed=bytes_load32(args+24);wi_key(w,key,pressed,0);
            if pressed && xk_repeats(load64(w+16),key) && load64(w+104){store64(w+96,key+1);store64(w+112,gui_monotonic_ns()+load64(w+120)*1000000);}else if !pressed && load64(w+96)==key+1{store64(w+96,0);}}
        else if opcode==4{xk_update(load64(w+16),bytes_load32(args+8),bytes_load32(args+16),bytes_load32(args+24),bytes_load32(args+32));}
        else if opcode==5{let rate=tf_i32(args);let delay=tf_i32(args+8);if rate<0 || delay<0{wl_fail(c,"Invalid compositor keyboard repeat parameters");}else{if rate>1000{rate=1000;}let interval=0;if rate{interval=1000000000/rate;}store64(w+104,interval);store64(w+120,delay);if !rate{store64(w+96,0);}}}
    }wm_dispatch(c,w,metadata,proxy,opcode,args);wc_dispatch(c,load64(w+224),w,metadata,proxy,opcode,args);wn_dispatch(c,w,metadata,opcode,args);return 0;
}
fn wi_client_open(title,width,height){return wi_client_open_flags(title,width,height,1);}
fn wi_client_open_flags(title,width,height,flags){
    let w=alloc(1024);if w<0{return wl_fail(0,"Cannot allocate native input context");}bytes_fill(w,0,1024);store64(w+104,40000000);store64(w+120,600);let k=xk_open(0);store64(w+16,k);if !k{syscall(11,w,1024,0,0,0,0);return wl_fail(0,xk_error);}
    let clipboard=wc_context();store64(w+224,clipboard);if !clipboard{xk_free(k);syscall(11,w,1024,0,0,0,0);return 0;}
    let cursor=wn_context();store64(w+248,cursor);if !cursor{wc_close(0,clipboard);xk_free(k);syscall(11,w,1024,0,0,0,0);return 0;}
    let ime=wm_context();store64(w+256,ime);if !ime{wn_close(0,cursor);wc_close(0,clipboard);xk_free(k);syscall(11,w,1024,0,0,0,0);return wl_fail(0,"Cannot allocate native IME state");}
    let c=wl_client_open_flags(0,title,width,height,native_callback(wi_dispatch),w,flags);if !c{wm_close(0,ime);wn_close(0,cursor);wc_close(0,clipboard);xk_free(k);syscall(11,w,1024,0,0,0,0);return 0;}store64(w,c);return c;
}
fn wi_close(c){let w=load64(c+192);if w{wm_close(c,load64(w+256));wn_close(c,load64(w+248));wc_close(c,load64(w+224));xk_free(load64(w+16));syscall(11,w,1024,0,0,0,0);store64(c+184,0);store64(c+192,0);}return 0;}
