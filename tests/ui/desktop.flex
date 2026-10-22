// Actual SDL renderer, real fonts/pixels and independent SDL input structures.
import "../../libs/ui/desktop.flex";
import "../../apps/collie/ui/permissions.flex";
extend "../../libs/ui/syntax.flex";
global dt_fixture=0;
global dt_id=0;
global dt_event=0;
global dt_checks=0;
view app_view(){use permission_screen();}
fn dt_check(ok,text){h_assert(ok,text);dt_checks=dt_checks+1;return 0;}
fn dt_inject(kind,a,b,c,d){h_assert(ffi_call_i32(ffi_symbol(dt_fixture,"gui_fixture_event"),kind,dt_id,a,b,c,d)>0,"SDL event injection");h_assert(gui_poll(dt_event),"SDL poll");return ui_desktop_event(dt_event);}
fn dt_text(text){h_assert(ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_text"),dt_id,text,0,0,0,0),"SDL text input injection");h_assert(gui_poll(dt_event),"SDL text poll");return ui_desktop_event(dt_event);}
fn dt_shot(path){let w=gui_pixel_width(ud_window);let h=gui_pixel_height(ud_window);let pixels=h_take(w*h*4);dt_check(gui_read_pixels(ud_window,pixels,w*4,w*h*4),"native rendered pixel capture");h_save_bytes(path,pixels,w*h*4,420);return 0;}
fn dt_pool_bytes(){let n=0;let p=ud_pool;while p{n=n+load64(p+8);p=load64(p);}return n;}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2 || argc==3,"Usage: desktop-tests SDL-FIXTURE-LIBRARY [--x11]");dt_fixture=ffi_open(load64(argv+8));h_assert(dt_fixture,"SDL fixture library");
    let window=ui_desktop_open("Flexscript desktop UI verification",640,760,GUI_RESIZABLE);dt_check(window,"native window creation");dt_event=gui_event();dt_id=load64(gui__record(window)+32);gui__poll_fn=ffi_symbol(dt_fixture,"gui_fixture_poll");
    let packets=j_parse(h_read("build/ui-portable-packets.json"));ui_desktop_apply(j_at(packets,0));ui_desktop_draw();dt_inject(768,43,0,0,0);dt_check(ud_focus==ud_find("act"),"Tab focuses the first interactive control");let identity=ui_desktop_identity("input-2");ui_desktop_focus("input-2");
    let typed=dt_text("你好");dt_check(h_equal(j_s(typed,"value"),"initial你好") && h_equal(j_s(typed,"type"),"change"),"actual SDL UTF-8 text becomes a portable input event");
    dt_inject(768,80,0,0,0);dt_inject(768,42,0,0,0);
    dt_check(h_equal(ui_desktop_value("input-2"),"initial好"),"arrow/backspace remove a complete UTF-8 code point");let caret=load64(ud_focus+144);
    ui_desktop_apply(j_at(packets,1));ui_desktop_apply(j_at(packets,2));ui_desktop_apply(j_at(packets,3));ui_desktop_draw();
    dt_check(identity==ui_desktop_identity("input-2") && h_equal(ui_desktop_value("input-2"),"initial好") && ud_focus==ud_find("input-2") && load64(ud_focus+144)==caret,"keyed move and property patches preserve editor identity, draft, focus and selection");
    dt_check(load64(ud_find("rows")+32)==ud_find("row-2") && load64(ud_find("branch")+8)==7 && ud_hidden(ud_find("hidden")),"keyed reorder, conditional replacement and visibility");
    let bounds=h_take(32);ui_desktop_bounds("act",bounds);let x=load64(bounds)+load64(bounds+16)/2;let y=load64(bounds+8)+load64(bounds+24)/2;
    dt_inject(1025,1,x,y,0);let clicked=dt_inject(1026,1,x,y,0);dt_check(clicked && h_equal(j_s(clicked,"action"),"changed") && j_n(clicked,"action_id")==2,"real SDL mouse click resolves the updated action binding");
    if argc==3{
        ui_desktop_focus("input-2");ui_desktop_draw();ui_desktop_present();gui__poll_fn=gui__symbol("SDL_PollEvent");
        dt_check(ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_native"),load64(gui__record(window)),x,y,1,0,0)==1,"native desktop window is actually mapped on the isolated X server");
        let typed_native=0;let clicked_native=0;let until=gui_ticks()+200;
        while gui_ticks()<until{while gui_poll(dt_event){ui_desktop_event(dt_event);}gui_delay(5);}
        ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_native"),load64(gui__record(window)),x,y,2,0,0);until=gui_ticks()+1000;
        while gui_ticks()<until && !typed_native{while gui_poll(dt_event){let reply=ui_desktop_event(dt_event);if reply && h_equal(j_s(reply,"type"),"change") && h_equal(j_s(reply,"value"),"initiala好"){typed_native=1;}}gui_delay(5);}
        ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_native"),load64(gui__record(window)),x,y,3,0,0);until=gui_ticks()+1000;
        while gui_ticks()<until && !clicked_native{while gui_poll(dt_event){let reply=ui_desktop_event(dt_event);if reply && h_equal(j_s(reply,"action"),"changed") && j_n(reply,"action_id")==2{clicked_native=1;}}gui_delay(5);}
        dt_check(typed_native && clicked_native,"real X11 keyboard and pointer input traverse SDL and the portable event adapter");gui__poll_fn=ffi_symbol(dt_fixture,"gui_fixture_poll");
    }
    ui_desktop_apply(j_at(packets,4));ui_desktop_apply(j_at(packets,5));dt_check(identity==ui_desktop_identity("input-2") && !ui_desktop_identity("row-1") && ui_desktop_identity("input-3"),"insert/remove preserves surviving native records");
    ui_desktop_apply(j_at(packets,6));dt_check(!ui_desktop_identity("input-2") && !load64(ud_find("rows")+32),"recursive removal clears children and focused editors");
    ui_desktop_apply(j_at(packets,7));ui_desktop_focus("draft");dt_text(" local draft");identity=ui_desktop_identity("draft");ui_desktop_apply(j_at(packets,8));dt_check(identity==ui_desktop_identity("draft") && h_equal(ui_desktop_value("draft"),"initial local draft"),"reconnect snapshot retains uncontrolled local draft");
    ui_desktop_apply(j_at(packets,9));dt_check(h_equal(ui_desktop_value("draft"),"controlled"),"explicit controlled value replaces the editor text");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"draft\",\"name\":\"value\",\"value\":null}]}"));dt_text("local");ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"draft\",\"name\":\"value\",\"value\":\"\"}]}"));dt_check(h_equal(ui_desktop_value("draft"),""),"setting an explicit empty value clears an uncontrolled draft");ui_desktop_apply(j_at(packets,9));
    dt_inject(768,4,0,0x40,0);dt_inject(768,6,0,0x40,0);dt_text("replace");dt_inject(768,4,0,0x40,0);dt_inject(768,25,0,0x40,0);dt_check(h_equal(ui_desktop_value("draft"),"controlled"),"select-all, copy and paste use the platform clipboard");
    let before=dt_pool_bytes();let i=0;while i<100{ui_desktop_apply(j_at(packets,9));i=i+1;}dt_check(dt_pool_bytes()<=before+1048576,"retained model arena remains bounded through repeated snapshots");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"remove\",\"key\":\"app\"}]}"));
    let policy=j_need(cp_permissions(0),"policy");let request=j_object();j_set(request,"policy",policy);j_set(request,"reset",j_bool(1));ui_desktop_apply(cu_permissions(request));ui_desktop_draw();
    ui_desktop_bounds("permission-internet",bounds);x=load64(bounds)+30;y=load64(bounds+8)+load64(bounds+24)/2;dt_inject(1025,1,x,y,0);let permission=dt_inject(1026,1,x,y,0);
    let next=j_parse(j_dump(policy));j_set(next,"internet",j_bool(0));request=j_object();j_set(request,"policy",policy);j_set(request,"next_policy",next);j_set(request,"event",permission);let changed=cu_permissions(request);ui_desktop_apply(changed);ui_desktop_draw();
    dt_check(h_equal(ui_desktop_value("permissions-summary"),"6 of 7 permissions enabled") && !j_value(j_need(j_need(changed,"command"),"allowed")),"actual desktop input round-trips through the compiled shared permission view/reducer");
    ui_desktop_close();dt_check(ui_desktop_open("Collie shared UI on desktop",430,932,GUI_RESIZABLE),"renderer can close and reopen");
    dt_id=load64(gui__record(ud_window)+32);
    ui_desktop_image("resource:mipmap/ic_launcher","apps/collie/android/res/drawable-nodpi/collie_border_collie.png");
    ui_desktop_image("preview:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","apps/collie/android/res/drawable-nodpi/collie_border_collie.png");
    let app=j_parse(h_read("build/collie-ui-packets.json"));let seen=j_object();let code=0;let image=0;i=0;
    while i<j_count(app){let packet=j_at(app,i);ui_desktop_apply(packet);ui_desktop_draw();let page=j_s(packet,"page");j_set(seen,page,j_bool(1));if ud_find("card-1-source-numbers"){code=1;}if h_equal(page,"preview"){image=load64(ud_need("preview-image")+160)!=0;dt_shot("build/ui-desktop-preview.rgba");}if h_equal(page,"permissions"){dt_shot("build/ui-desktop-permissions.rgba");}i=i+1;}
    dt_check(j_count(seen)==9,j_dump(seen));dt_check(code,"shared highlighted code and gutter");dt_check(image,gui_error);
    dt_check(h_equal(ui_desktop_value("card-179-body"),"Historical message 179"),"shared history paging renders the final message");
    dt_check(load64(ud_need("chat-mark")+160)!=0,"virtual app resource resolves to decoded desktop pixels");
    ui_desktop_draw();dt_shot("build/ui-desktop-collie.rgba");ui_desktop_present();
    let scroll=ud_need("chat-scroll");let old_scroll=load64(scroll+136);ui_desktop_bounds("chat-scroll",bounds);dt_inject(1024,load64(bounds)+20,load64(bounds+8)+20,0,0);dt_inject(1027,0,2,0,0);ui_desktop_draw();dt_check(load64(scroll+136)<old_scroll,"native wheel input scrolls the clipped chat viewport");
    ui_desktop_bounds("composer-send",bounds);x=load64(bounds)+load64(bounds+16)/2;y=load64(bounds+8)+load64(bounds+24)/2;dt_inject(1025,1,x,y,0);dt_check(!dt_inject(1026,1,x,y,0),"disabled controls emit no action");
    gui_resize(ud_window,520,740);ui_desktop_draw();ui_desktop_bounds("composer",bounds);dt_check(load64(bounds+8)+load64(bounds+24)<=740 && load64(ud_need("app-root")+80)==520,"window resize reflows the shared layout and keeps the composer visible");
    ui_desktop_close();gui_quit();
    h_print(1,h_cat3("PASS: ",h_int(dt_checks)," native desktop UI checks\n"));return 0;
}
