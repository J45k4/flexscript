// A real, window-backed OpenGL triangle. GLSL is compiled by the device driver.
import "../../libs/gui.flex";
global gl_window=0;
fn say(text) {let n=0;while text && load8(text+n) {n=n+1;}syscall(1,1,text,n,0,0,0);return 0;}
fn required(ok) {if !ok {say("OpenGL: ");say(gui_error);say("\n");gui_quit();syscall(231,1,0,0,0,0,0);}return 0;}
fn gl(name,a,b,c,d,e,f) {
    let p=gui_gl_cached_proc(gl_window,name);required(p);return ffi_call(p,a,b,c,d,e,f);
}
fn main(argc,argv) {
    let limit=0;if argc>1 {let s=load64(argv+8);let i=0;while load8(s+i) {
        let c=load8(s+i);if c<48 || c>57 || limit>100000 {say("Usage: opengl [FRAMES]\n");return 1;}limit=limit*10+c-48;i=i+1;
    }if limit<1 {return 1;}}
    gl_window=gui_gl_open("Flexscript Native OpenGL - Esc closes",800,500,GUI_RESIZABLE|GUI_HIGH_DPI,3,3,0);required(gl_window);
    // Vsync is optional: some compositors/drivers reject changing the interval.
    gui_gl_swap_interval(gl_window,1);
    let program=gui_gl_program(gl_window,
        "#version 330 core\nvoid main(){vec2 p[3]=vec2[](vec2(-0.7,-0.6),vec2(0.7,-0.6),vec2(0,0.7));gl_Position=vec4(p[gl_VertexID],0,1);}",
        "#version 330 core\nout vec4 color;void main(){color=vec4(0.91,0.74,0.48,1);}");required(program);
    let value=alloc(8);
    gl("glGenVertexArrays",1,value,0,0,0,0);let vao=gui__u32(value);gl("glBindVertexArray",vao,0,0,0,0,0);gl("glUseProgram",program,0,0,0,0,0);
    say("OpenGL renderer: ");say(gl("glGetString",0x1f01,0,0,0,0,0));say("\n");
    let event=gui_event();let running=1;let frame=0;
    while running && (!limit || frame<limit) {
        while gui_poll(event) {if gui_event_kind(event)==GUI_QUIT || gui_event_kind(event)==GUI_CLOSE || (gui_event_kind(event)==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE) {running=0;}}
        gl("glViewport",0,0,gui_pixel_width(gl_window),gui_pixel_height(gl_window),0,0);
        gl("glClear",0x4000,0,0,0,0,0);gl("glDrawArrays",4,0,3,0,0,0);
        required(!gl("glGetError",0,0,0,0,0,0));required(gui_gl_swap(gl_window));gui_delay(16);frame=frame+1;
    }
    gui__put32(value,vao);gl("glDeleteVertexArrays",1,value,0,0,0,0);gl("glDeleteProgram",program,0,0,0,0,0);gui_close(gl_window);gui_quit();return 0;
}
