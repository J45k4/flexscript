// Repeated native teardown: own GUI/driver handles and OS descriptors.
import "../../libs/ui/desktop.flex";
fn main(argc,argv){
    h_environment(argc,argv);let baseline=0;let last=0;let i=0;
    while i<40{
        h_assert(gui_backend_select("wayland"),gui_error);
        h_assert(ui_desktop_open("Native lifetime checks",320,240,GUI_HIDDEN),gui_error);
        ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"text\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"key\":\"text\",\"kind\":\"text\",\"text\":\"Häät 中文 👋\",\"props\":{\"size\":16},\"children\":[]}}]}"));
        ui_desktop_draw();let old=ud_window;let renderer=load64(gui__record(old)+8);
        h_assert(gr_gl(renderer,48,0,0,0,0,0,0)==0,"Lifetime draw raised a GL error");
        ui_desktop_close();gui_quit();
        h_assert(!gui__record(old) && !ud_nodes && !ud_pool && !ud_measures && !ud_focus && !ud_paste_token && !gn_fonts && !gn_shapes,"Native teardown retained an owned GUI handle");
        last=h_count(h_entries("/proc/self/fd"));if i==3{baseline=last;}if i>=4{h_assert(last<=baseline,"Native close leaked OS file descriptors");}i=i+1;
    }
    h_assert(h_find(h_read("/proc/self/maps"),"libSDL2")<0,"Native lifetime test loaded SDL");
    h_print(1,h_cat3("PASS 40 native create/draw/close/quit cycles: no stale owned handles, GL errors or FD growth; final FDs ",h_int(last),"\n"));return 0;
}
