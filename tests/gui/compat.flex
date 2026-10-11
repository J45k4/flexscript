// Old and new entry points can coexist without duplicating definitions.
import "../../lib/gui.flex";
import "../../lib/gui/window.flex";
import "../../lib/gui/canvas.flex";
import "../../lib/gui/gl.flex";
import "../../libs/gui.flex";
fn main() {
    let window=gui_open("GUI compatibility",16,16,GUI_HIDDEN);
    if !window {return 1;}
    if !gui_clear(window,0x123456) || !gui_present(window) {gui_quit();return 1;}
    gui_close(window);gui_quit();return 0;
}
