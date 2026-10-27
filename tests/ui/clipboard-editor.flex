// Async paste lifetime checks; completion can arrive after other UI actions.
import "../../libs/ui/desktop.flex";
fn ce_key(event,code){gui__zero(event,128);store64(event,GUI_KEY_DOWN);store64(event+8,ud_window);store64(event+16,code);store64(event+72,64);return ui_desktop_event(event);}
fn ce_drain(event){while gui_poll(event){ui_desktop_event(event);}return 0;}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(ui_desktop_open("Clipboard editor checks",640,480,GUI_HIDDEN),gui_error);
    ui_desktop_apply(j_parse("{\"version\":1,\"ops\":[{\"op\":\"insert\",\"key\":\"page\",\"parent\":\"mount\",\"after\":\"\",\"node\":{\"key\":\"page\",\"kind\":\"column\",\"props\":{},\"children\":[{\"key\":\"a\",\"kind\":\"input\",\"props\":{\"value\":\"base\"},\"children\":[]},{\"key\":\"b\",\"kind\":\"input\",\"props\":{\"value\":\"other\"},\"children\":[]}]}}]}"));
    let event=gui_event();ui_desktop_focus("a");let node=ud_need("a");store64(node+144,2);store64(node+152,2);h_assert(gui_clipboard_copy("中文"),gui_error);ce_key(event,25);h_assert(ud_paste_token && h_equal(ui_desktop_value("a"),"base"),"Paste did not wait for completion");ce_drain(event);h_assert(h_equal(ui_desktop_value("a"),"ba中文se") && load64(node+144)==8,"Paste did not preserve its insertion point");
    ce_key(event,25);ui_desktop_focus("b");ce_drain(event);h_assert(h_equal(ui_desktop_value("a"),"ba中文se") && h_equal(ui_desktop_value("b"),"other"),"Delayed paste crossed a focus change");
    ui_desktop_focus("a");ce_key(event,25);gui__zero(event,128);store64(event,GUI_TEXT);store64(event+8,ud_window);gui_event_text_set(event,"X");ui_desktop_event(event);ce_drain(event);h_assert(h_equal(ui_desktop_value("a"),"ba中文Xse"),"Delayed paste replaced newer typing");
    ce_key(event,25);store64(node+144,0);store64(node+152,0);ce_drain(event);h_assert(h_equal(ui_desktop_value("a"),"ba中文Xse"),"Delayed paste ignored a selection change");
    h_assert(gui_clipboard_copy("first"),gui_error);ce_key(event,25);h_assert(gui_clipboard_copy("second"),gui_error);ce_key(event,25);ce_drain(event);h_assert(h_equal(ui_desktop_value("a"),"secondba中文Xse"),"Stale paste completed after a newer request");
    ce_key(event,25);ui_desktop_close();h_assert(!ud_paste_token && !ud_paste_value && !gui__clipboard_result,"Closing the editor retained a paste result");gui_quit();syscall(11,event,128,0,0,0,0);h_print(1,"PASS asynchronous paste: Unicode insertion, focus/typing/selection races, stale tokens and close cleanup\n");return 0;
}
