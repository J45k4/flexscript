// Desktop clipboard adapters use argv vectors, never shell commands.
import "terminal.flex";
global tc_error=0;
fn tc_available(name) {return syscall(21,h_executable(name),1,0,0,0,0)==0;}
fn tc_command(copy) {
    let name="wl-paste";if copy {name="wl-copy";}
    if h_getenv("WAYLAND_DISPLAY") && tc_available(name) {let args=h_args(name,0,0,0,0,0);if !copy {h_add(args,"--no-newline");}return args;}
    if h_getenv("DISPLAY") && tc_available("xclip") {let args=h_args("xclip","-selection","clipboard",0,0,0);if !copy {h_add(args,"-o");}return args;}
    tc_error="Clipboard unavailable: install wl-clipboard or xclip.";return 0;
}
fn tc_copy(text) {let args=tc_command(1);if !args {return 0;}let p=h_wait(h_spawn(args,text,0));if h_status(p) {tc_error="Clipboard copy failed.";return 0;}return 1;}
fn tc_paste() {let args=tc_command(0);if !args {return 0;}let p=h_run(args);if h_status(p) {tc_error="Clipboard paste failed.";return 0;}return tu_clean(h_out(p));}
