// Interoperate with an independent wl-copy/wl-paste process on a private seat.
import "../../libs/ui/desktop.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==5,"copy|paste payload-file ready-file result-file");let copy=h_equal(load64(argv+8),"copy");let expected=h_read(load64(argv+16));h_assert(gui_backend_select("wayland"),gui_error);let window=0;
    if copy{window=gui_open("Native clipboard fixture",800,600,GUI_RESIZABLE);h_assert(window && gui_canvas_open(window,0),gui_error);gui_text_input(1);gui_clear(window,0x10151a);gui_present(window);}
    else{window=ui_desktop_open("Native editor paste fixture",800,600,GUI_RESIZABLE);h_assert(window,gui_error);ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"field\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"key\":\"field\",\"kind\":\"input\",\"props\":{\"value\":\"\",\"width\":600,\"height\":80},\"children\":[]}}]}"));ui_desktop_focus("field");ui_desktop_draw();ui_desktop_present();}
    let record=gui__record(window);let c=load64(record);let w=load64(c+192);let clipboard=load64(w+224);let event=gui_event();let token=0;let copied=0;let received=0;let until=gui_ticks()+10000;h_save(load64(argv+24),"ready");
    while gui_ticks()<until && !received{
        while gui_poll(event){if copy && !copied && gui_event_kind(event)==GUI_KEY_DOWN{h_assert(gui_clipboard_copy(expected),gui_error);copied=1;h_save(load64(argv+24),"copied");}
            if !copy && gui_event_kind(event)==GUI_FOCUS{ui_desktop_event(event);}
            if !copy && gui_event_kind(event)==GUI_CLIPBOARD && gui_event_code(event)==token{ui_desktop_event(event);h_assert(h_equal(ui_desktop_value("field"),expected),"External clipboard payload did not reach the editor");received=1;}}
        if copy && copied && load64(clipboard+704)>0 && h_exists(h_cat(load64(argv+24),".done")){received=1;}
        if !copy && !token && load64(clipboard+32){ud_paste_begin(ud_need("field"));token=ud_paste_token;h_assert(token,gui_error);}
        if !received{gui_wait(250);}
    }
    let maps=h_read("/proc/self/maps");h_assert(h_find(maps,"libSDL2")<0,"Clipboard fixture loaded SDL");let report=j_object();j_set(report,"mode",j_string(load64(argv+8)));j_set(report,"success",j_bool(received));j_set(report,"bytes",j_int(h_len(expected)));j_set(report,"completed_sends",j_int(load64(clipboard+704)));h_save(load64(argv+32),j_dump(report));if copy{gui_close(window);}else{ui_desktop_close();}gui_quit();h_assert(received,"Clipboard peer did not complete before deadline");return 0;
}
