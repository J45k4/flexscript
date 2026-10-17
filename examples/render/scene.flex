import "scene-content.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let directory=b_option(argc,argv,"--shaders","build/render");let frames=h_number(b_option(argc,argv,"--frames","0"));let capture=b_option(argc,argv,"--capture",0);
    let flags=0;let i=1;while i<argc {if h_equal(load64(argv+i*8),"--hidden") {flags=GUI_HIDDEN;}i=i+1;}demo_init(directory,flags);
    let event=gui_event();let running=1;let frame=0;
    while running && (!frames || frame<frames) {
        while gui_poll(event) {if gui_event_kind(event)==GUI_QUIT || gui_event_kind(event)==GUI_CLOSE || (gui_event_kind(event)==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE) {running=0;}}
        let w=load64(demo_device);if gui_key(w,80) {store64(demo_eye,load64(demo_eye)-40);}if gui_key(w,79) {store64(demo_eye,load64(demo_eye)+40);}
        if gui_key(w,82) {store64(demo_eye+16,load64(demo_eye+16)-40);}if gui_key(w,81) {store64(demo_eye+16,load64(demo_eye+16)+40);}
        if demo_frame(1) {if capture && frames && frame==frames-1 {demo_capture(capture);}demo_require(gui_gl_swap(w));}gui_delay(16);frame=frame+1;
    }
    render_mesh_close(demo_mesh);render_material_close(demo_material);render_target_close(demo_shadow);render_close(demo_device);gui_quit();return 0;
}
