import "../../libs/gui.flex";
fn say(text) {let n=0;while load8(text+n) {n=n+1;}syscall(1,1,text,n,0,0,0);return 0;}
fn required(ok) {
    if !ok {say("GUI: ");if gui_error {say(gui_error);}say("\n");gui_quit();syscall(231,1,0,0,0,0,0);}return 0;
}
fn main(argc,argv) {
    // Optional frame limit is useful for launch checks; normal use stays open.
    let limit=0;if argc>1 {let s=load64(argv+8);let i=0;while load8(s+i) {
        let c=load8(s+i);if c<48 || c>57 || limit>100000 {say("Usage: window [FRAMES]\n");return 1;}limit=limit*10+c-48;i=i+1;
    }if limit<1 {return 1;}}
    let window=gui_open("Flexscript Native Window - arrows move, click recolors, Esc closes",800,500,GUI_RESIZABLE|GUI_HIGH_DPI);
    required(window);required(gui_canvas_open(window,0));let event=gui_event();let running=1;let frame=0;let x=120;let y=120;let color=0xe9bd7c;
    say("Native window ready. Arrow keys move; click changes color; Escape closes.\n");
    while running && (!limit || frame<limit) {
        while gui_poll(event) {
            let kind=gui_event_kind(event);
            if kind==GUI_QUIT || kind==GUI_CLOSE {running=0;}
            if kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE {running=0;}
            if kind==GUI_MOUSE_DOWN {color=color^0x65ac39;}
        }
        if gui_key(window,GUI_KEY_LEFT) {x=x-4;}if gui_key(window,GUI_KEY_RIGHT) {x=x+4;}
        if gui_key(window,GUI_KEY_UP_ARROW) {y=y-4;}if gui_key(window,GUI_KEY_DOWN_ARROW) {y=y+4;}
        let w=gui_pixel_width(window);let h=gui_pixel_height(window);
        if x<0 {x=0;}if y<0 {y=0;}if x>w-80 {x=w-80;}if y>h-80 {y=h-80;}
        required(gui_clear(window,0x102c2a));
        required(gui_fill(window,24,24,w-48,8,0x4a8d83));
        required(gui_fill(window,x,y,80,80,color));
        required(gui_fill(window,24,h-32,(frame%180)*3,8,0x4a8d83));
        required(gui_present(window));gui_delay(16);frame=frame+1;
    }
    gui_close(window);gui_quit();return 0;
}
