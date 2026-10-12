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
fn tc_copy(text) {
    let args=tc_command(1);if !args {return 0;}
    // wl-copy/xclip can leave a background selection owner holding stderr.
    // Wait for the launcher, not EOF from its descendants, and keep that owner
    // alive after success. A broken or stalled helper must not terminate the UI.
    let p=h_spawn(args,0,0);let size=h_len(text);let sent=0;let started=net_now();
    while h_status(p)==-999 {
        let fd=load64(p+32);
        if fd>=0 {
            if sent<size {let n=syscall(1,fd,text+sent,size-sent,0,0,0);
                if n>0 {sent=sent+n;}
                else if n!=-11 && n!=-4 {h_close(fd);store64(p+32,-1);}}
            if sent==size {h_close(load64(p+32));store64(p+32,-1);}
        }
        h_pump(p,10);
        if h_status(p)==-999 && net_now()-started>=2000 {
            h_stop(p);tc_error="Clipboard copy timed out.";return 0;
        }
    }
    let status=h_status(p);h_stop(p);
    if status || sent!=size {tc_error="Clipboard copy failed.";return 0;}return 1;
}
fn tc_paste() {let args=tc_command(0);if !args {return 0;}let p=h_run(args);if h_status(p) {tc_error="Clipboard paste failed.";return 0;}return tu_clean(h_out(p));}
