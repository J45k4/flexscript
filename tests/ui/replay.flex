// Backend-neutral test replay. OS delivery has independent protocol suites.
import "../../libs/ui/desktop.flex";
global ur_modifiers=0;
fn ur_ready(event){
    ui_desktop_draw();ui_desktop_present();let until=gui_ticks()+3000;
    let input=load64(load64(gui__record(ud_window))+192);
    while !load64(input+240) && gui_ticks()<until{while gui_poll(event){}gui_wait(5);}
    h_assert(load64(input+240),"Private compositor did not deliver a real clipboard input serial");return 0;
}
fn ur_event(event,kind,a,b,c,d){
    gui__zero(event,128);store64(event+8,ud_window);store64(event+72,ur_modifiers);
    if kind==768{store64(event,GUI_KEY_DOWN);store64(event+16,a);store64(event+72,c);}
    else{if kind==1024{store64(event,GUI_MOUSE_MOVE);store64(event+24,a);store64(event+32,b);store64(event+40,c);store64(event+48,d);}
    else{if kind==1025 || kind==1026{store64(event,GUI_MOUSE_DOWN+(kind==1026));store64(event+24,b);store64(event+32,c);store64(event+56,a);}
    else{if kind==1027{store64(event,GUI_WHEEL);store64(event+40,a);store64(event+48,b);}
    else{h_assert(kind==512 && (a==12 || a==13),"Unknown normalized fixture event");store64(event,GUI_FOCUS);store64(event+16,a==12);}}}}
    let result=ui_desktop_event(event);let until=gui_ticks()+2000;
    while ud_paste_token && gui_ticks()<until{while gui_poll(event){let next=ui_desktop_event(event);if next{result=next;}}if ud_paste_token{gui_wait(5);}}
    h_assert(!ud_paste_token,"Native clipboard completion timed out");return result;
}
