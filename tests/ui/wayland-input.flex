import "../../libs/gui/draw.flex";
import "../../scripts/lib/json.flex";
fn main(argc,argv){
    h_environment(argc,argv);h_assert(gui_backend_select("wayland"),gui_error);let window=gui_open("Native input delivery fixture",800,600,GUI_RESIZABLE);h_assert(window,gui_error);h_assert(gui_canvas_open(window,0),gui_error);gui_text_input(1);gui_clear(window,0x10151a);gui_present(window);
    let event=gui_event();let key_down=0;let key_up=0;let text=0;let motion=0;let down=0;let up=0;let wheel=0;let until=gui_ticks()+5000;
    while gui_ticks()<until && !(key_down && key_up && text && motion && down && up && wheel){
        while gui_poll(event){let kind=gui_event_kind(event);if kind==GUI_KEY_DOWN && gui_event_code(event)==4{key_down=1;}if kind==GUI_KEY_UP && gui_event_code(event)==4{key_up=1;}if kind==GUI_TEXT && h_equal(gui_event_text(event),"a"){text=1;}
            if kind==GUI_MOUSE_MOVE && gui_event_x(event)==500 && gui_event_y(event)==300{motion=1;}if kind==GUI_MOUSE_DOWN && gui_event_button(event)==1{down=1;}if kind==GUI_MOUSE_UP && gui_event_button(event)==1{up=1;}if kind==GUI_WHEEL && gui_event_dy(event)==-1{wheel=1;}}
        gui_wait(50);
    }
    let result=j_object();j_set(result,"key_down",j_bool(key_down));j_set(result,"key_up",j_bool(key_up));j_set(result,"text",j_bool(text));j_set(result,"motion",j_bool(motion));j_set(result,"button_down",j_bool(down));j_set(result,"button_up",j_bool(up));j_set(result,"wheel",j_bool(wheel));let maps=h_read("/proc/self/maps");h_assert(h_find(maps,"libSDL2")<0,"Native input fixture loaded SDL");gui_close(window);gui_quit();h_print(1,h_cat(j_dump(result),"\n"));return !(key_down && key_up && text && motion && down && up && wheel);
}
