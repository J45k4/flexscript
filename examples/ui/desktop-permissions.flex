// Actual Collie permissions view/reducer in a native desktop window.
// This standalone example keeps policy in memory; Back closes its window.
import "ui/desktop.flex";
import "../../apps/collie/ui/permissions.flex";
extend "ui/syntax.flex";
global dp_policy=0;
view app_view(){use permission_screen();}
fn dp_update(event){
    cu_entries=0;let policy=j_parse(dp_policy);let request=j_object();j_set(request,"policy",policy);j_set(request,"reset",j_bool(!event));
    let next=j_parse(dp_policy);
    if event{j_set(request,"event",event);let key=j_s(event,"action");if j_get(next,key){let value=cp_choice(key,j_s(event,"key"));if value{j_set(next,key,value);}}j_set(request,"next_policy",next);}
    let result=cu_permissions(request);h_assert(!j_get(result,"error"),ud_string(result,"error"));ui_desktop_apply(result);let text=j_dump(next);h_assert(h_len(text)<4096,"Permission state limit");h_copy(dp_policy,text,h_len(text)+1);
    let back=h_equal(ud_string(j_need(result,"command"),"kind"),"back");m_reset(0);h_reset(0);return !back;
}
fn main(argc,argv){
    h_environment(argc,argv);h_assert(argc<=2,"Usage: desktop-permissions [FRAMES]");let limit=0;if argc==2{limit=h_number(load64(argv+8));h_assert(limit>0,"Frame count must be positive");}
    let window=ui_desktop_open("Collie portable permissions",480,960,GUI_RESIZABLE|GUI_HIGH_DPI);h_assert(window,gui_error);dp_policy=h_zero(alloc(4096),4096);let initial=j_dump(j_need(cp_permissions(0),"policy"));h_copy(dp_policy,initial,h_len(initial)+1);h_reset(0);dp_update(0);let event=gui_event();let running=1;let frame=0;
    h_print(1,"Native shared permissions ready.\n");
    while running && (!limit || frame<limit){while gui_poll(event){let kind=gui_event_kind(event);if kind==GUI_QUIT || kind==GUI_CLOSE || (kind==GUI_KEY_DOWN && gui_event_code(event)==GUI_KEY_ESCAPE){running=0;}let input=ui_desktop_event(event);if input{running=dp_update(input);}}
        if ui_desktop_needs_draw(){ui_desktop_draw();ui_desktop_present();}gui_delay(16);frame=frame+1;
    }ui_desktop_close();gui_quit();syscall(11,dp_policy,4096,0,0,0,0);return 0;
}
