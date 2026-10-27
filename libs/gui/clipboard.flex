// One asynchronous clipboard request. Completion events contain only a token;
// the GUI owns the result until gui_clipboard_take or cancellation. No owning
// pointers are embedded in the bounded event queue.
global gui__clipboard_id=0;
global gui__clipboard_window=0;
global gui__clipboard_result=0;
fn gui__clipboard_length(text){let n=0;while n<=1048576 && load8(text+n){n=n+1;}return n;}
fn gui_clipboard_release(text){if text{syscall(11,text,gui__clipboard_length(text)+1,0,0,0,0);}return 0;}
fn gui_clipboard_copy(text){
    if !text{return gui__fail("Clipboard text is null");}if gui__clipboard_length(text)>1048576{return gui__fail("Clipboard text exceeds 1 MiB");}
    if gui__native{let p=gui__records;if !p || !load64(p){return 0;}let c=load64(p);return wc_copy(c,load64(c+192),text);}return gui__int("SDL_SetClipboardText",text,0,0,0,0,0)==0;
}
// Synchronous compatibility helper. On Wayland it can read our own selection;
// use gui_clipboard_request for text supplied by another application.
fn gui_clipboard_read(){
    if gui__native{let p=gui__records;if !p || !load64(p){return 0;}let result=wc_local(load64(load64(p)+192));if !result{gui__fail("Use asynchronous clipboard requests for external selections");}return result;}
    let raw=gui__call("SDL_GetClipboardText",0,0,0,0,0,0);if !raw{return 0;}let n=gui__clipboard_length(raw);if n>1048576{gui__call("SDL_free",raw,0,0,0,0,0);return gui__fail("Clipboard text exceeds 1 MiB");}
    let copy=alloc(n+1);if copy>0{bytes_copy(copy,raw,n+1);}else{copy=0;}gui__call("SDL_free",raw,0,0,0,0,0);return copy;
}
fn gui_clipboard_cancel(token){
    if token!=gui__clipboard_id{return 0;}if gui__native && gui__records && load64(gui__records){let c=load64(gui__records);wc_cancel(load64(load64(c+192)+224));}
    gui_clipboard_release(gui__clipboard_result);gui__clipboard_result=0;gui__clipboard_window=0;gui__clipboard_id=gui__clipboard_id+1;return 0;
}
fn gui__clipboard_complete(token,text,n,success){
    if token!=gui__clipboard_id || !gui__clipboard_window{if text{syscall(11,text,n+1,0,0,0,0);}return 0;}
    gui_clipboard_release(gui__clipboard_result);gui__clipboard_result=text;let event=gui_event();store64(event,GUI_CLIPBOARD);store64(event+8,gui__clipboard_window);store64(event+16,token);store64(event+24,success);
    let ok=gui_event_enqueue(event);syscall(11,event,128,0,0,0,0);if !ok{gui_clipboard_release(gui__clipboard_result);gui__clipboard_result=0;}return ok;
}
fn gui_clipboard_request(window){
    if !gui__record(window){return 0;}gui_clipboard_cancel(gui__clipboard_id);gui__clipboard_window=window;let token=gui__clipboard_id;
    if gui__native{let c=load64(gui__record(window));if !wc_request(c,load64(c+192),token){gui__clipboard_complete(token,0,0,0);}}
    else{let text=gui_clipboard_read();let n=0;if text{n=gui__clipboard_length(text);}gui__clipboard_complete(token,text,n,text!=0);}return token;
}
// The returned UTF-8 string is caller-owned; release with gui_clipboard_release.
fn gui_clipboard_take(token){if token!=gui__clipboard_id{return 0;}let text=gui__clipboard_result;gui__clipboard_result=0;return text;}
