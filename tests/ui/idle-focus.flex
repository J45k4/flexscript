// A separate visible window takes real compositor keyboard focus while Collie
// remains mapped. This is test-only, and is run only on a private compositor.
import "../../libs/gui/draw.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc==2,"Provide readiness JSON path");h_assert(gui_backend_select("wayland"),gui_error);let window=gui_open("Idle focus sink",200,120,GUI_RESIZABLE|GUI_HIGH_DPI);h_assert(window && gui_canvas_open(window,0),gui_error);let event=gui_event();let dirty=1;let running=1;let ready=0;
    while running{
        while gui_poll(event){let kind=gui_event_kind(event);if kind==GUI_CLOSE || kind==GUI_QUIT || (kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE){running=0;}if kind==GUI_RESIZE || kind==GUI_EXPOSE{dirty=1;}}
        if running && dirty && gui_frame_ready(window){h_assert(gui_clear(window,0x202a24) && gui_present(window),gui_error);dirty=0;}
        if !ready && gui_focused(window){let row=j_object();j_set(row,"focused",j_bool(1));j_set(row,"pid",j_int(syscall(39,0,0,0,0,0,0)));h_save(load64(argv+8),j_dump(row));ready=1;}
        if running{gui_wait(1000);}
    }
    gui_close(window);gui_quit();syscall(11,event,128,0,0,0,0);return 0;
}
