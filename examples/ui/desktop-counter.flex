import "ui/desktop.flex";
import "counter-view.flex";
extend "ui/syntax.flex";
global dc_root=0;
global dc_index=0;
global dc_arena=0;
fn dc_refresh(){
    let previous=dc_arena;m_fresh();let root=app_view();let index=ui_index;let patch=ui_compiled_diff(dc_root,root,dc_index,index);let packet=j_object();j_set(packet,"version",j_int(1));j_set(packet,"ops",j_parse(patch));ui_desktop_apply(packet);
    dc_root=root;dc_index=index;dc_arena=m_state();if previous{m_free_state(previous);}return 0;
}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc<=2,"Usage: desktop-counter [FRAMES]");let limit=0;if argc==2{limit=h_number(load64(argv+8));h_assert(limit>0,"Frame count must be positive");}
    let window=ui_desktop_open("Flexscript portable counter",640,460,GUI_RESIZABLE|GUI_HIGH_DPI);h_assert(window,gui_error);let event=gui_event();let running=1;let frame=0;dc_refresh();h_reset(0);
    h_print(1,"Native portable UI ready.\n");
    while running && (!limit || frame<limit){
        while gui_poll(event){let kind=gui_event_kind(event);if kind==GUI_QUIT || kind==GUI_CLOSE || (kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE){running=0;}
            let input=ui_desktop_event(event);if input && app_action(j_s(input,"action"),j_n(input,"action_id"))==200{dc_refresh();}h_reset(0);
        }
        if ui_desktop_needs_draw(){ui_desktop_draw();ui_desktop_present();}gui_delay(16);frame=frame+1;
    }ui_desktop_close();gui_quit();return 0;
}
