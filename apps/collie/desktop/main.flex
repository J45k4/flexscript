// Native desktop presentation. The platform service owns TLS, lifecycle and
// dialogs; every screen and event policy comes from Collie's shared UI.
import "../../../libs/ui/desktop.flex";
import "../ui/app.flex";
import "launch.flex";
extend "../../../libs/ui/syntax.flex";
global cd_state=0;global cd_in=0;global cd_used=0;global cd_queue=0;global cd_queued=0;global cd_sent=0;global cd_child=0;global cd_running=1;global cd_ready=0;global cd_service_lost=0;global cd_script_start=-1;
global cd_sidebar_drag=0;global cd_sidebar_grab=0;global cd_sidebar_hover=0;global cd_sidebar_cursor=0;global cd_sidebar_value=252;global cd_sidebar_pending=0;global cd_sidebar_x=0;
fn cd_sidebar_feedback(active){
    let node=ud_find("desktop-sidebar-divider");if !node{active=0;}if active==cd_sidebar_hover{return 0;}cd_sidebar_hover=active;
    if active{if !cd_sidebar_cursor{cd_sidebar_cursor=gui__call("SDL_CreateSystemCursor",7,0,0,0,0,0);}if cd_sidebar_cursor{gui__call("SDL_SetCursor",cd_sidebar_cursor,0,0,0,0,0);}}
    else{gui__call("SDL_SetCursor",gui__call("SDL_GetDefaultCursor",0,0,0,0,0,0),0,0,0,0,0);}
    if node{let color="#20292f";if active{color="#78966d";}let op=j_object();j_set(op,"op",j_string("attribute"));j_set(op,"key",j_string("desktop-sidebar-divider"));j_set(op,"name",j_string("background"));j_set(op,"value",j_string(color));let packet=j_object();let ops=j_array();j_push(ops,op);j_set(packet,"version",j_int(1));j_set(packet,"ops",ops);ui_desktop_apply(packet);}return 0;
}
fn cd_sidebar_stop(){if cd_sidebar_drag{gui__call("SDL_CaptureMouse",0,0,0,0,0,0);}cd_sidebar_drag=0;cd_sidebar_pending=0;return 0;}
fn cd_sidebar_resize(x,done){
    let limit=gui_width(ud_window)-526;if limit>520{limit=520;}if limit<220{limit=220;}let width=x-cd_sidebar_grab;if width<220{width=220;}if width>limit{width=limit;}
    if !done && cd_sidebar_value==width{return 0;}
    let event=j_object();j_set(event,"key",j_string("desktop-sidebar-divider"));j_set(event,"action",j_string("sidebar_resize"));j_set(event,"value",j_int(width));let type="change";if done{type="submit";}j_set(event,"type",j_string(type));let request=j_object();j_set(request,"action",j_string("event"));j_set(request,"event",event);return cd_update(request);
}
// Coalesce motion within one event batch; reflow once per frame, never once
// per queued pixel. Release always applies the final pointer position.
fn cd_sidebar_flush(){if cd_sidebar_pending && cd_sidebar_drag{cd_sidebar_pending=0;cd_sidebar_resize(cd_sidebar_x,0);}return 0;}
fn cd_sidebar_event(event){
    let kind=gui_event_kind(event);let node=ud_find("desktop-sidebar-divider");let blocked=ud_focus_scope || !node;
    if !blocked && ud_focus==node && kind==GUI_KEY_DOWN && (gui_event_code(event)==80 || gui_event_code(event)==79){let delta=16;if gui_event_code(event)==80{delta=-16;}cd_sidebar_resize(cd_sidebar_value+cd_sidebar_grab+delta,1);return 1;}
    if cd_sidebar_drag && (blocked || kind==GUI_RESIZE || (kind==GUI_FOCUS && !gui_event_code(event)) || (kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE)){
        cd_sidebar_flush();cd_sidebar_stop();cd_sidebar_feedback(0);let command=j_object();j_set(command,"kind",j_string("sidebar_width"));j_set(command,"width",j_int(cd_sidebar_value));cd_send(command);if kind==GUI_KEY_DOWN{return 1;}return 0;
    }
    if kind==GUI_MOUSE_MOVE || kind==GUI_MOUSE_DOWN || kind==GUI_MOUSE_UP{
        let x=gui_event_x(event);let y=gui_event_y(event);let hit=0;if !blocked{hit=x>=load64(node+64) && x<load64(node+64)+load64(node+80) && y>=load64(node+72) && y<load64(node+72)+load64(node+88);}
        if cd_sidebar_drag{
            if kind==GUI_MOUSE_MOVE{cd_sidebar_x=x;cd_sidebar_pending=1;cd_sidebar_feedback(1);return 1;}
            if kind==GUI_MOUSE_UP && gui_event_button(event)==1{cd_sidebar_stop();cd_sidebar_resize(x,1);cd_sidebar_feedback(hit);return 1;}
        }
        cd_sidebar_feedback(hit);
        if kind==GUI_MOUSE_DOWN && gui_event_button(event)==1 && hit && !ud_pressed && !ud_scroll_drag{
            ud_set_focus(node);cd_sidebar_grab=x-load64(node+64);cd_sidebar_drag=1;gui__call("SDL_CaptureMouse",1,0,0,0,0,0);return 1;
        }
    }
    if kind==GUI_FOCUS && !gui_event_code(event){cd_sidebar_feedback(0);}return 0;
}
fn cd_send(command){let text=h_cat(j_dump(command),"\n");let n=h_len(text);h_assert(cd_queued-cd_sent+n<8388608,"Desktop command queue exceeded limit");if cd_sent{h_copy(cd_queue,cd_queue+cd_sent,cd_queued-cd_sent);cd_queued=cd_queued-cd_sent;cd_sent=0;}h_copy(cd_queue+cd_queued,text,n);cd_queued=cd_queued+n;return 0;}
fn cd_effect(command){if h_len(cj_text(command,"focus_key")){ui_desktop_focus(cj_text(command,"focus_key"));}let kind=cj_text(command,"kind");if h_equal(kind,"none") || h_equal(kind,"hide_keyboard"){return 0;}if h_equal(kind,"exit"){cd_running=0;return 0;}if h_equal(kind,"focus"){ui_desktop_focus(cj_text(command,"key"));return 0;}if h_equal(kind,"copy"){gui_clipboard_copy(cj_text(command,"text"));return 0;}return cd_send(command);}
fn cd_navigation(state){let nav=j_object();j_set(nav,"action",j_string("navigation"));j_set(nav,"state",state);let command=j_object();j_set(command,"kind",j_string("navigation"));j_set(command,"data",cu_ui_host(nav));return cd_send(command);}
fn cd_selection_feedback(request){
    if !h_equal(cj_text(request,"action"),"event") || ud_focus_scope{return 0;}
    let event=cj_get(request,"event");if !h_equal(cj_text(event,"action"),"desktop_open_session") || !h_equal(cj_text(event,"type"),"click") || cj_int(event,"action_id"){return 0;}
    let key=cj_text(event,"key");let target=ud_find(key);if !target || !ud_enabled(target) || !h_equal(ud_string(load64(target+16),"action"),"desktop_open_session"){return 0;}
    let ops=j_array();let slot=0;while slot<2048{let node=ud_nodes+slot*256;
        if load64(node) && h_equal(ud_string(load64(node+16),"action"),"desktop_open_session"){
            let color="#151c21";if node==target{color="#28382d";}if !h_equal(ud_s(node,"background"),color){let op=j_object();j_set(op,"op",j_string("attribute"));j_set(op,"key",j_string(load64(node)));j_set(op,"name",j_string("background"));j_set(op,"value",j_string(color));j_push(ops,op);}
        }slot=slot+1;
    }
    if j_count(ops){let packet=j_object();j_set(packet,"version",j_int(1));j_set(packet,"ops",ops);ui_desktop_apply(packet);
        // Paint cached geometry before the shared reducer parses any message
        // Markdown. The reducer then owns the durable selection/loading state.
        let root=ud_need("app-root");if load64(root+80)==gui_width(ud_window) && load64(root+88)==gui_height(ud_window){ui_desktop_repaint();}else{ui_desktop_draw();}ui_desktop_present();
    }return 0;
}
fn cd_update(request){
    let data=cu_copy(cj_get(request,"data"));j_set(data,"platform",j_string("linux"));j_set(data,"viewport_width",j_int(gui_width(ud_window)));j_set(data,"viewport_height",j_int(gui_height(ud_window)));j_set(request,"data",data);
    if cd_sidebar_drag{j_set(data,"sidebar_width",j_int(cd_sidebar_value));}
    cd_selection_feedback(request);let prior=j_parse(cd_state);let first=!cd_ready;let prior_page=cj_text(prior,"page");let prior_prompt=cj_int(cj_get(prior,"permission_request"),"request_id");j_set(request,"state",prior);j_set(request,"reset",j_bool(!cd_ready));let result=cu_ui_host(request);
    h_assert(!cj_get(result,"error"),cj_text(result,"error"));ui_desktop_apply(result);let next=j_need(result,"state");cd_sidebar_value=cj_int(next,"sidebar_width");if cd_sidebar_value<1{cd_sidebar_value=252;}let state=j_dump(next);h_assert(h_len(state)<8388608,"Desktop UI state limit");h_copy(cd_state,state,h_len(state)+1);cd_ready=1;if cd_script_start<0 && cj_int(next,"total")>0{cd_script_start=gui_ticks();}cd_focus(next,first,prior_page,prior_prompt);let command=j_need(result,"command");let kind=cj_text(command,"kind");let switching=h_equal(kind,"open_session") || h_equal(kind,"new_session") || h_equal(kind,"select_project") || h_equal(kind,"choose_project_folder");
    if switching{
        // Present the lightweight selection/loading frame before starting disk
        // or engine work. Save navigation against the conversation being left.
        ui_desktop_draw();ui_desktop_present();if !h_len(cj_text(prior,"pending_session_id")){let nav=cu_copy(prior);if h_equal(cj_text(nav,"page"),"projects") || h_equal(cj_text(nav,"page"),"settings"){j_set(nav,"page",j_string("chat"));}let mode=cj_get(next,"sidebar_mode");if mode{j_set(nav,"sidebar_mode",mode);}let closed=cj_get(next,"sidebar_closed");if closed{j_set(nav,"sidebar_closed",closed);}let width=cj_get(next,"sidebar_width");if width{j_set(nav,"sidebar_width",width);}cd_navigation(nav);}
    }
    cd_effect(command);
    let transient=cd_sidebar_drag || (h_equal(cj_text(cj_get(request,"event"),"action"),"sidebar_resize") && h_equal(cj_text(cj_get(request,"event"),"type"),"change"));
    if !switching && !transient && !h_len(cj_text(next,"pending_session_id")) && (h_equal(cj_text(request,"action"),"event") || h_equal(cj_text(request,"action"),"back") || h_equal(cj_text(request,"action"),"shortcut")){cd_navigation(next);}return 0;
}
fn cd_focus(state,first,prior_page,prior_prompt){
    let page=cj_text(state,"page");let prompt=cj_int(cj_get(state,"permission_request"),"request_id");let scope="";let focus="";
    if prompt{scope="permission-request-panel";focus="permission-request-deny";}
    else if h_equal(page,"model"){scope="model-panel";focus="model-input";}
    else if h_equal(page,"projects"){scope="projects-panel";focus="projects-add";}
    else if h_equal(page,"settings"){focus="settings-back";}
    else if h_equal(page,"attachments"){scope="attachment-panel";focus="attachment-gallery";}
    else if h_equal(page,"notice"){scope="notice-panel";focus="notice-close";}
    else if h_equal(page,"chat"){focus="composer-draft";}
    else if h_equal(page,"conversations"){focus="conversations-query";}
    else if h_equal(page,"permissions"){focus="permissions-back";}
    else if h_equal(page,"workers"){focus="workers-back";}
    else if h_equal(page,"preview"){focus="preview-close";}
    ui_desktop_focus_scope(scope);if (first || !h_equal(page,prior_page) || prompt!=prior_prompt) && h_len(focus){ui_desktop_focus(focus);}return 0;
}
fn cd_receive(){
    let fd=load64(cd_child+40);let more=1;
    while more{h_assert(cd_used<8388608,"Desktop service message limit");let n=syscall(0,fd,cd_in+cd_used,8388608-cd_used,0,0,0);if n>0{cd_used=cd_used+n;}else{more=0;if n==0{cd_running=0;cd_service_lost=1;}else{h_assert(n==-11 || n==-4,"Desktop service read failed");}}}
    let at=0;let start=0;while at<cd_used{if load8(cd_in+at)==10{store8(cd_in+at,0);let request=j_parse(cd_in+start);let images=cj_get(request,"images");if images && j_kind(images)==4{let fields=j_value(images);let i=0;while i<h_count(fields){let pair=h_at(fields,i);ui_desktop_image(load64(pair),j_value(load64(pair+8)));i=i+1;}}cd_update(request);start=at+1;}at=at+1;}
    if start{h_copy(cd_in,cd_in+start,cd_used-start);cd_used=cd_used-start;}return 0;
}
fn cd_native_event(event){if cd_sidebar_event(event){return 0;}let kind=gui_event_kind(event);if kind==GUI_QUIT || kind==GUI_CLOSE{cd_running=0;}else if kind==GUI_RESIZE{ud_dirty=1;let resize=j_object();j_set(resize,"action",j_string("update"));cd_update(resize);}else if kind==GUI_KEY_DOWN && cd_shortcut(gui_event_code(event),gui_event_modifiers(event)){}else if kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE{let request=j_object();j_set(request,"action",j_string("back"));cd_update(request);}else{let input=ui_desktop_event(event);if input{let request=j_object();j_set(request,"action",j_string("event"));j_set(request,"event",input);cd_update(request);}}return 0;}
fn cd_script(request){
    let action=cj_text(request,"action");
    if h_equal(action,"native_resize"){gui_resize(ud_window,cj_int(request,"width"),cj_int(request,"height"));ud_dirty=1;let update=j_object();j_set(update,"action",j_string("update"));return cd_update(update);}
    if h_equal(action,"native_text"){
        // The existing test fixture feeds real SDL_Event text structures to
        // gui_poll; SDL2 compatibility layers cannot PushEvent text reliably.
        let library=ffi_open(cj_text(request,"fixture"));h_assert(library,"Native input fixture required");let inject=ffi_symbol(library,"ui_fixture_text");let poll=ffi_symbol(library,"gui_fixture_poll");h_assert(inject && poll,"Invalid native input fixture");
        h_assert(ffi_call_i32(inject,load64(gui__record(ud_window)+32),cj_text(request,"text"),0,0,0,0)>0,"Cannot inject native text");let prior=gui__poll_fn;gui__poll_fn=poll;let event=gui_event();let available=gui_poll(event);gui__poll_fn=prior;h_assert(available,"Native text event unavailable");let input=ui_desktop_event(event);if input{let change=j_object();j_set(change,"action",j_string("event"));j_set(change,"event",input);return cd_update(change);}return 0;
    }
    if h_equal(action,"native_mouse"){
        let library=ffi_open(cj_text(request,"fixture"));h_assert(library,"Native mouse fixture required");let inject=ffi_symbol(library,"gui_fixture_event");let poll=ffi_symbol(library,"gui_fixture_poll");h_assert(inject && poll,"Invalid native mouse fixture");
        h_assert(ffi_call_i32(inject,cj_int(request,"kind"),load64(gui__record(ud_window)+32),cj_int(request,"a"),cj_int(request,"b"),cj_int(request,"c"),cj_int(request,"d"))>0,"Cannot inject native pointer event");let prior=gui__poll_fn;gui__poll_fn=poll;let event=gui_event();let available=gui_poll(event);gui__poll_fn=prior;h_assert(available,"Native pointer event unavailable");return cd_native_event(event);
    }
    if h_equal(action,"native_key"){let raw=h_zero(h_take(64),64);gui__put32(raw,768);gui__put32(raw+8,load64(gui__record(ud_window)+32));gui__put32(raw+16,cj_int(request,"code"));let mods=cj_int(request,"modifiers");store8(raw+24,mods&255);store8(raw+25,(mods>>8)&255);h_assert(gui__int("SDL_PushEvent",raw,0,0,0,0,0)>0,"Cannot inject keyboard event");let event=gui_event();while gui_poll(event){cd_native_event(event);}return 0;}
    return cd_update(request);
}
fn cd_dump_layout(path){
    let rows=j_array();let i=0;while i<2048{let node=ud_nodes+i*256;if load64(node){let visible=1;let parent=node;while parent && parent!=ud_mount{if ud_hidden(parent){visible=0;}parent=load64(parent+24);}if visible{let row=j_object();j_set(row,"key",j_string(load64(node)));j_set(row,"focused",j_bool(node==ud_focus));if load64(node+8)==8 || ud_n(node,"selectable",0){j_set(row,"caret",j_int(load64(node+144)));j_set(row,"anchor",j_int(load64(node+152)));}if load64(node+8)==4 || load64(node+8)==5{j_set(row,"scroll_x",j_int(load64(node+128)));j_set(row,"scroll_y",j_int(load64(node+136)));j_set(row,"content_width",j_int(load64(node+112)));j_set(row,"content_height",j_int(load64(node+120)));}j_set(row,"x",j_int(load64(node+64)));j_set(row,"y",j_int(load64(node+72)));j_set(row,"width",j_int(load64(node+80)));j_set(row,"height",j_int(load64(node+88)));j_push(rows,row);}}i=i+1;}return h_save(path,j_dump(rows));
}
fn cd_shortcut(code,mods){
    if !(mods&0xc0){return 0;}if code==20{cd_running=0;return 1;}
    let key="";if code==17{key="new";}else if code==14{key="search";}else if code==5{key="sidebar";}else if code==18{key="attach";}else if code==54{key="model";}else if code==15{key="composer";}
    if !h_len(key){return 0;}let request=j_object();j_set(request,"action",j_string("shortcut"));j_set(request,"shortcut",j_string(key));cd_update(request);return 1;
}
fn cd_option(argc,argv,key,fallback){let i=1;while i<argc{if h_equal(load64(argv+i*8),key){h_assert(i+1<argc,"Option needs a value");return load64(argv+(i+1)*8);}i=i+1;}return fallback;}
fn cd_video_report(){
    let keys=h_args("WAYLAND_DISPLAY","DISPLAY","XDG_RUNTIME_DIR","XDG_SESSION_TYPE","SDL_VIDEODRIVER","SDL_VIDEO_DRIVER");let i=0;
    while i<h_count(keys){let key=h_at(keys,i);h_print(2,h_cat3(key,"=",h_getenv(key)));h_print(2,"\n");i=i+1;}
    if gui__sdl{let n=gui__int("SDL_GetNumVideoDrivers",0,0,0,0,0,0);h_print(2,"SDL video backends:");i=0;while i<n{h_print(2," ");h_print(2,gui__call("SDL_GetVideoDriver",i,0,0,0,0,0));i=i+1;}h_print(2,"\nSelected backend: ");h_print(2,gui__call("SDL_GetCurrentVideoDriver",0,0,0,0,0,0));h_print(2,"\n");}return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);cd_display_environment(argc,argv);if cd_has_option(argc,argv,"--display-environment"){return cd_display_report();}let help=1;while help<argc{if h_equal(load64(argv+help*8),"--help"){h_print(1,"Usage: collie [--data DIRECTORY] [--auth auth.json] [--width W] [--height H]\nShortcuts: Ctrl+N new, Ctrl+K search, Ctrl+B sidebar, Ctrl+O attach, Ctrl+, model, Ctrl+Q quit\nVideo initialization only (no window): --video-diagnostics\nHeadless checks: --hidden --frames N --capture FILE.rgba --dump-state FILE.json\n");return 0;}if h_equal(load64(argv+help*8),"--video-diagnostics"){let ok=gui_init();if !ok{h_print(2,h_cat("SDL initialization failed: ",gui_error));h_print(2,"\n");}cd_video_report();gui_quit();return !ok;}help=help+1;}let here=h_dir(h_real(load64(argv)));let root=h_real(h_join(here,"../.."));let service=cd_option(argc,argv,"--service",h_join(here,"service-native"));let app=h_join(here,"resources/collie/desktop");if !h_isdir(app){app=h_join(root,"apps/collie/desktop");}app=cd_option(argc,argv,"--app",app);
    let flags=GUI_RESIZABLE|GUI_HIGH_DPI;let i=1;while i<argc{if h_equal(load64(argv+i*8),"--hidden"){flags=flags|GUI_HIDDEN;}i=i+1;}
    let width=h_number(cd_option(argc,argv,"--width","1280"));let height=h_number(cd_option(argc,argv,"--height","860"));
    let window=ui_desktop_open("Collie",width,height,flags);if !window{h_print(2,h_cat("Collie could not open a window: ",gui_error));h_print(2,"\n");cd_video_report();h_print(2,"Run Collie from a graphical terminal, or set WAYLAND_DISPLAY/DISPLAY for the intended session.\n");gui_quit();return 1;}
    rt_cache_open();
    let args=h_args(service,"--engine",h_join(here,"engine"),"--app",app,0);i=1;while i<argc{let arg=load64(argv+i*8);if h_equal(arg,"--data") || h_equal(arg,"--auth") || h_equal(arg,"--fixture"){h_assert(i+1<argc,"Option needs a value");h_add(args,arg);i=i+1;h_add(args,load64(argv+i*8));}i=i+1;}
    cd_child=h_spawn(args,0,root);cd_state=alloc(8388609);store8(cd_state,123);store8(cd_state+1,125);store8(cd_state+2,0);cd_in=alloc(8388609);cd_queue=alloc(8388609);
    let limit=h_number(cd_option(argc,argv,"--frames","0"));let capture=cd_option(argc,argv,"--capture","");let events_path=cd_option(argc,argv,"--events","");let events_text="[]";if h_len(events_path){events_text=h_read(events_path);}let events=h_slice(events_text,h_len(events_text));let event_index=0;let status=alloc(8);let event=gui_event();let frame=0;let start=gui_ticks();let base=h_mark();
    while cd_running && (!limit || frame<limit){
        cd_receive();let scripted=j_parse(events);while cd_script_start>=0 && event_index<j_count(scripted) && cj_int(j_at(scripted,event_index),"at")<=gui_ticks()-cd_script_start{cd_script(j_need(j_at(scripted,event_index),"request"));event_index=event_index+1;}
        while gui_poll(event){cd_native_event(event); }cd_sidebar_flush();
        if cd_sent<cd_queued{let n=syscall(1,load64(cd_child+32),cd_queue+cd_sent,cd_queued-cd_sent,0,0,0);if n>0{cd_sent=cd_sent+n;}else{h_assert(n==-11 || n==-4,"Desktop service closed");}}
        if cd_ready && ui_desktop_needs_draw(){ui_desktop_draw();ui_desktop_present();}
        if syscall(61,load64(cd_child),status,1,0,0,0)>0{store64(cd_child+8,load64(status));cd_running=0;}
        m_reset(0);h_reset(base);if limit{gui_delay(16);}else{gui_wait(16);}frame=frame+1;
    }
    if cd_ready && h_len(capture){ui_desktop_draw();let pw=gui_pixel_width(window);let ph=gui_pixel_height(window);let bytes=pw*ph*4;let pixels=alloc(bytes);h_assert(gui_read_pixels(window,pixels,pw*4,bytes),gui_error);let fd=syscall(2,capture,0x241,384,0,0,0);h_assert(fd>=0,"Cannot save capture");h_write(fd,pixels,bytes);h_close(fd);}
    // Closing stdin gives the service a chance to cancel, journal and release
    // native resources before a bounded forced shutdown.
    cd_sidebar_stop();cd_sidebar_feedback(0);if cd_sidebar_cursor{gui__call("SDL_FreeCursor",cd_sidebar_cursor,0,0,0,0,0);cd_sidebar_cursor=0;}h_close(load64(cd_child+32));store64(cd_child+32,-1);let until=gui_ticks()+4000;let ended=load64(cd_child+8)!=-999;
    let scratch=alloc(8192);
    while !ended && gui_ticks()<until{
        let channel=0;while channel<2{let n=syscall(0,load64(cd_child+40+channel*8),scratch,8192,0,0,0);while n>0{if channel{h_write(2,scratch,n);}n=syscall(0,load64(cd_child+40+channel*8),scratch,8192,0,0,0);}channel=channel+1;}
        if syscall(61,load64(cd_child),status,1,0,0,0)>0{store64(cd_child+8,load64(status));ended=1;}gui_delay(10);
    }
    let error_bytes=syscall(0,load64(cd_child+48),scratch,8192,0,0,0);if error_bytes>0{h_write(2,scratch,error_bytes);}
    syscall(11,scratch,8192,0,0,0,0);
    let layout=cd_option(argc,argv,"--dump-layout","");if cd_ready && h_len(layout){ui_desktop_draw();cd_dump_layout(layout);}
    let dump=cd_option(argc,argv,"--dump-state","");if cd_ready && h_len(dump){h_save(dump,cd_state);}h_stop(cd_child);rt_cache_close();ui_desktop_close();gui_quit();if !cd_ready || cd_service_lost || load64(cd_child+8)!=0{return 1;}return 0;
}
