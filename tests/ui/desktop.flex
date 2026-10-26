// Actual SDL renderer, real fonts/pixels and independent SDL input structures.
import "../../libs/ui/desktop.flex";
import "../../libs/ui/richtext.flex";
import "../../apps/collie/ui/permissions.flex";
extend "../../libs/ui/syntax.flex";
global dt_fixture=0;
global dt_id=0;
global dt_event=0;
global dt_checks=0;
view app_view(){use permission_screen();}
fn dt_check(ok,text){h_assert(ok,text);dt_checks=dt_checks+1;h_print(1,h_cat3("PASS ",text,"\n"));return 0;}
fn dt_inject(kind,a,b,c,d){h_assert(ffi_call_i32(ffi_symbol(dt_fixture,"gui_fixture_event"),kind,dt_id,a,b,c,d)>0,"SDL event injection");h_assert(gui_poll(dt_event),"SDL poll");return ui_desktop_event(dt_event);}
fn dt_text(text){h_assert(ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_text"),dt_id,text,0,0,0,0),"SDL text input injection");h_assert(gui_poll(dt_event),"SDL text poll");return ui_desktop_event(dt_event);}
fn dt_shot(path){let w=gui_pixel_width(ud_window);let h=gui_pixel_height(ud_window);let pixels=h_take(w*h*4);dt_check(gui_read_pixels(ud_window,pixels,w*4,w*h*4),"native rendered pixel capture");h_save_bytes(path,pixels,w*h*4,420);return 0;}
fn dt_rgb(x,y){let w=gui_pixel_width(ud_window);let h=gui_pixel_height(ud_window);let pixels=h_take(w*h*4);h_assert(gui_read_pixels(ud_window,pixels,w*4,w*h*4),gui_error);let p=pixels+(y*w+x)*4;return (load8(p)<<16)|(load8(p+1)<<8)|load8(p+2);}
fn dt_pool_bytes(){let n=0;let p=ud_pool;while p{n=n+load64(p+8);p=load64(p);}return n;}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2 || argc==3,"Usage: desktop-tests SDL-FIXTURE-LIBRARY [--x11]");dt_fixture=ffi_open(load64(argv+8));h_assert(dt_fixture,"SDL fixture library");
    let window=ui_desktop_open("Flexscript desktop UI verification",640,760,GUI_RESIZABLE);dt_check(window,"native window creation");dt_event=gui_event();dt_id=load64(gui__record(window)+32);gui__poll_fn=ffi_symbol(dt_fixture,"gui_fixture_poll");
    let packets=j_parse(h_read("build/ui-portable-packets.json"));ui_desktop_apply(j_at(packets,0));ui_desktop_draw();ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[]}"));dt_check(!ud_dirty,"empty update batches leave the rendered window idle");dt_inject(768,43,0,0,0);dt_check(ud_focus==ud_find("act"),"Tab focuses the first interactive control");let identity=ui_desktop_identity("input-2");ui_desktop_focus("input-2");
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
    ui_desktop_bounds("deny-internet",bounds);x=load64(bounds)+30;y=load64(bounds+8)+load64(bounds+24)/2;dt_inject(1025,1,x,y,0);let permission=dt_inject(1026,1,x,y,0);
    let next=j_parse(j_dump(policy));j_set(next,"internet",j_bool(0));request=j_object();j_set(request,"policy",policy);j_set(request,"next_policy",next);j_set(request,"event",permission);let changed=cu_permissions(request);ui_desktop_apply(changed);ui_desktop_draw();
    dt_check(h_equal(ui_desktop_value("permissions-summary"),"0 allowed · 30 ask · 1 denied") && !j_value(j_need(j_need(changed,"command"),"allowed")),"actual desktop input round-trips through the compiled shared permission view/reducer");
    ui_desktop_close();dt_check(ui_desktop_open("Collie shared UI on desktop",430,932,GUI_RESIZABLE),"renderer can close and reopen");
    dt_id=load64(gui__record(ud_window)+32);
    ui_desktop_image("resource:mipmap/ic_launcher","apps/collie/android/res/drawable-nodpi/collie_border_collie.png");
    ui_desktop_image("preview:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","apps/collie/android/res/drawable-nodpi/collie_border_collie.png");
    let app=j_parse(h_read("build/collie-ui-packets.json"));let seen=j_object();let code=0;let image=0;i=0;
    while i<j_count(app){let packet=j_at(app,i);ui_desktop_apply(packet);ui_desktop_draw();let page=j_s(packet,"page");j_set(seen,page,j_bool(1));if ud_find("card-1-source-numbers"){code=1;}if h_equal(page,"preview"){image=load64(ud_need("preview-image")+160)!=0;dt_shot("build/ui-desktop-preview.rgba");}if h_equal(page,"permissions"){dt_shot("build/ui-desktop-permissions.rgba");}i=i+1;}
    dt_check(j_count(seen)==11 && j_get(seen,"projects") && j_get(seen,"settings"),j_dump(seen));dt_check(code,"shared highlighted code and gutter");dt_check(image,gui_error);
    dt_check(h_equal(ui_desktop_value("card-179-body"),"Historical message 179"),"shared history paging renders the final message");
    dt_check(load64(ud_need("chat-mark")+160)!=0,"virtual app resource resolves to decoded desktop pixels");
    ui_desktop_draw();dt_shot("build/ui-desktop-collie.rgba");ui_desktop_present();
    let scroll=ud_need("chat-scroll");let old_scroll=load64(scroll+136);ui_desktop_bounds("chat-scroll",bounds);dt_inject(1024,load64(bounds)+20,load64(bounds+8)+20,0,0);dt_inject(1027,0,2,0,0);ui_desktop_draw();dt_check(load64(scroll+136)<old_scroll,"native wheel input scrolls the clipped chat viewport");
    ui_desktop_bounds("composer-send",bounds);x=load64(bounds)+load64(bounds+16)/2;y=load64(bounds+8)+load64(bounds+24)/2;dt_inject(1025,1,x,y,0);dt_check(!dt_inject(1026,1,x,y,0),"disabled controls emit no action");
    gui_resize(ud_window,520,740);ui_desktop_draw();ui_desktop_bounds("composer",bounds);dt_check(load64(bounds+8)+load64(bounds+24)<=740 && load64(ud_need("app-root")+80)==520,"window resize reflows the shared layout and keeps the composer visible");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"composer-input-row\",\"name\":\"focus_within\",\"value\":1}]}"));
    ui_desktop_focus("chat-menu");ui_desktop_draw();let editor=ud_need("composer-draft");let row=ud_need("composer-input-row");let row_y=load64(row+72);let row_h=load64(row+88);let center=load64(row+64)+load64(row+80)/2;
    dt_check(dt_rgb(center,row_y)==0x2c353b,"unfocused composer keeps its quiet border");
    // Click while the caret is in its hidden half-cycle: feedback must be immediate.
    ud_caret_epoch=gui_ticks()-750;x=load64(editor+64)+20;y=load64(editor+72)+load64(editor+88)/2;dt_inject(1025,1,x,y,0);dt_inject(1026,1,x,y,0);
    dt_check(ud_focus==editor && ud_caret_phase()==0 && ui_desktop_needs_draw(),"click focuses the editor and immediately restarts its visible caret");ui_desktop_draw();
    dt_check(dt_rgb(center,row_y)==0xadd98f && dt_rgb(center,row_y+1)==0xadd98f && dt_rgb(center,row_y+3)==0x1d2928,"focused composer paints a two-pixel green outline and active background");
    dt_check(load64(row+72)==row_y && load64(row+88)==row_h,"focus indicator does not move or resize the composer");
    dt_inject(1025,1,2,2,0);dt_inject(1026,1,2,2,0);ui_desktop_draw();dt_check(ud_focus!=editor && dt_rgb(center,row_y)==0x2c353b,"clicking outside removes the composer focus indicator");
    dt_shot("build/ui-desktop-focus-off.rgba");ui_desktop_focus("composer-draft");ui_desktop_draw();dt_shot("build/ui-desktop-focus-on.rgba");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"remove\",\"key\":\"app-root\"}]}"));
    let markdown="## Project\nCreated [**tetris.html**](tetris.html) with *controls*, ~~old~~ and `score`.\n\n- First item\n- 你好 second item";
    let packet=j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"markdown-page\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"key\":\"markdown-page\",\"kind\":\"column\",\"props\":{\"padding\":20,\"height\":-1,\"selection_scope\":1},\"children\":[{\"key\":\"markdown-body\",\"kind\":\"text\",\"text\":\"\",\"action\":\"\",\"action_id\":0,\"props\":{\"selectable\":1,\"size\":16,\"color\":\"#edf2ed\",\"line_height\":5},\"children\":[]}]}}]}");
    let desc=j_at(j_get(j_get(j_at(j_get(packet,"ops"),0),"node"),"children"),0);j_set(desc,"text",j_string(markdown));j_set(j_get(desc,"props"),"runs",j_string(rt_markdown(markdown)));ui_desktop_apply(packet);ui_desktop_draw();let text_node=ud_need("markdown-body");let visible=ud_content(text_node);
    dt_check(h_equal(visible,"Project\nCreated tetris.html with controls, old and score.\n\n•  First item\n•  你好 second item"),"desktop selection offsets use rendered Markdown text including UTF-8");
    let text_layout=ud_edit_layout(text_node);let pieces=j_get(text_layout,"pieces");let link=0;i=0;while i<j_count(pieces){let p=j_at(pieces,i);if h_equal(ud_string(p,"href"),"tetris.html"){link=p;}i=i+1;}dt_check(link,"relative file link survives wrapping and font-run layout");let origin=ud_text_origin(text_node);x=load64(origin)+j_n(link,"x")+3;y=load64(origin+8)+j_n(link,"y")+j_n(text_layout,"line")/2;
    dt_inject(1025,1,x,y,0);let activated=dt_inject(1026,1,x,y,0);dt_check(activated && h_equal(j_s(activated,"type"),"link") && h_equal(j_s(activated,"value"),"tetris.html"),"native click on a rendered Markdown link emits its actual destination");
    dt_inject(1025,1,x,y,0);dt_inject(1024,x+30,y,30,0);let dragged=dt_inject(1026,1,x+30,y,0);dt_check(!dragged && load64(text_node+144)!=load64(text_node+152),"dragging over link text selects it without opening the link");
    dt_inject(768,4,0,0x40,0);dt_inject(768,6,0,0x40,0);let copied=gui_clipboard_read();dt_check(h_equal(copied,visible),"Ctrl+A and Ctrl+C copy displayed Markdown text without markup characters");gui_clipboard_release(copied);ui_desktop_draw();dt_shot("build/ui-desktop-markdown-selected.rgba");
    let tx=load64(text_node+64);let ty=load64(text_node+72);let tw=load64(text_node+80);let th=load64(text_node+88);let first_y=ty+j_n(text_layout,"line")/2;
    dt_inject(1025,1,tx-10,first_y,0);dt_check(ud_selection_pending==text_node && !ud_pressed,"pressing the document gutter arms selection without starting a control drag");
    dt_inject(1024,tx+35,first_y,45,0);let margin_release=dt_inject(1026,1,tx+35,first_y,0);dt_check(!margin_release && ud_focus==text_node && load64(text_node+152)==0 && load64(text_node+144)>0,"dragging from the left gutter selects into the first text line");
    dt_inject(768,6,0,0x40,0);copied=gui_clipboard_read();dt_check(h_equal(copied,h_slice(visible,load64(text_node+144))),"gutter-started selection copies the correct rendered prefix");gui_clipboard_release(copied);
    dt_inject(1025,1,tx+tw+10,first_y,0);dt_inject(1024,tx+15,first_y,-tw,0);dt_inject(1026,1,tx+15,first_y,0);dt_check(ud_focus==text_node && load64(text_node+144)<load64(text_node+152),"dragging from the right gutter selects backward from the line end");
    dt_inject(1025,1,tx+40,ty-10,0);dt_inject(1024,x,y,20,30);dt_check(!dt_inject(1026,1,x,y,0) && load64(text_node+152)==0 && load64(text_node+144)>0,"dragging from above a message selects onto a link without opening it");
    dt_inject(1025,1,tx+40,ty+th+12,0);dt_inject(1024,tx+30,ty+th-15,-10,-27);dt_inject(1026,1,tx+30,ty+th-15,0);dt_check(load64(text_node+152)==h_len(visible) && load64(text_node+144)<load64(text_node+152),"dragging from below a message selects backward from its text end");
    dt_inject(1025,1,tx-10,first_y,0);dt_check(!dt_inject(1026,1,tx-10,first_y,0) && !ud_selection_pending && !ud_focus,"a blank-space click cancels the pending drag and leaves controls unfocused");dt_inject(1024,tx+30,first_y,40,0);dt_check(!ud_focus,"moving after release does not revive a blank-space selection");
    dt_inject(1025,1,tx-10,first_y,0);dt_inject(512,13,0,0,0);dt_inject(1024,tx+30,first_y,40,0);dt_check(!ud_selection_pending && !ud_pressed,"losing window focus cancels a pending blank-space drag");dt_inject(512,12,0,0,0);
    ui_desktop_focus("markdown-body");dt_inject(768,4,0,0x40,0);
    let patch=j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"markdown-body\",\"name\":\"runs\",\"value\":\"\"}]}");j_set(j_at(j_get(patch,"ops"),0),"value",j_string(rt_markdown("**你好**")));ui_desktop_apply(patch);dt_check(load64(text_node+144)==6 && load64(text_node+152)==0,"streaming Markdown changes clamp selection to valid rendered UTF-8 offsets");
    dt_inject(768,6,0,0x40,0);copied=gui_clipboard_read();dt_check(h_equal(copied,"你好"),"copy remains valid after a selected formatted message changes");gui_clipboard_release(copied);
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"selection-control\",\"parent\":\"markdown-page\",\"after\":\"markdown-body\",\"node\":{\"key\":\"selection-control\",\"kind\":\"button\",\"text\":\"A control\",\"action\":\"control\",\"action_id\":0,\"props\":{\"height\":40},\"children\":[]}}]}"));ui_desktop_draw();let control=ud_need("selection-control");x=load64(control+64)+20;y=load64(control+72)+20;
    dt_inject(1025,1,x,y,0);let control_click=dt_inject(1026,1,x,y,0);dt_check(control_click && h_equal(j_s(control_click,"action"),"control"),"document selection scope preserves ordinary button clicks");
    dt_inject(1025,1,x,y,0);dt_inject(1024,tx+30,ty+10,10,-20);dt_check(!dt_inject(1026,1,tx+30,ty+10,0) && ud_focus==control && !ud_selection_pending,"a drag started on a button does not become text selection");
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"attribute\",\"key\":\"selection-control\",\"name\":\"enabled\",\"value\":\"false\"}]}"));ui_desktop_draw();dt_inject(1025,1,x,y,0);dt_inject(1024,tx+30,ty+10,10,-20);dt_check(!dt_inject(1026,1,tx+30,ty+10,0) && !ud_selection_pending && ud_focus!=text_node,"disabled controls also block blank-space selection starts");
    // Removal must cancel the candidate before its stable slot can be reused.
    dt_inject(1025,1,tx-10,ty+5,0);dt_check(ud_selection_pending==text_node,"pending selection has a live candidate");ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"remove\",\"key\":\"markdown-body\"}]}"));dt_inject(1024,tx+30,ty+10,40,5);dt_check(!ud_selection_pending && !ud_pressed,"removing the pending text cancels the drag safely");dt_inject(1026,1,tx+30,ty+10,0);
    gui__poll_fn=gui__symbol("SDL_PollEvent");while gui_poll(dt_event){}h_assert(ffi_call_i32(ffi_symbol(dt_fixture,"ui_fixture_push_key"),dt_id,80,0,0,0,0)>0,"native queued key");
    dt_check(gui_wait(200) && gui_poll(dt_event) && gui_event_kind(dt_event)==GUI_KEY_DOWN && gui_event_code(dt_event)==80,"event wait wakes for queued input without consuming the key");gui__poll_fn=ffi_symbol(dt_fixture,"gui_fixture_poll");
    ui_desktop_close();gui_quit();ffi_call(ffi_symbol(dt_fixture,"ui_fixture_release"),0,0,0,0,0,0);
    h_print(1,h_cat3("PASS: ",h_int(dt_checks)," native desktop UI checks\n"));return 0;
}
