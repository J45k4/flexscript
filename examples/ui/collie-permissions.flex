// The actual Android permissions view, served unchanged in a browser.
import "../../apps/collie/ui/permissions.flex";
import "../../libs/ui/web.flex";
extend "../../libs/ui/syntax.flex";
view app_view(){use permission_screen();}
fn app_init(path){cu_policy=j_get(cp_permissions(0),"policy");cu_rows();return 0;}
fn app_tick(){return 0;}
fn app_action(action,id){
    let saved=cu_policy;let mark=h_mark();
    let event=j_object();j_set(event,"action",j_string(action));j_set(event,"key",j_string(mono_field("ui_key")));j_set(event,"type",j_string(mono_field("ui_type")));j_set(event,"value",j_bool(m_eq(mono_field("ui_value"),"true")));
    let request=j_object();j_set(request,"policy",cu_policy);j_set(request,"event",event);let reply=cu_permissions(request);let command=j_get(reply,"command");
    let code=200;cu_policy=saved;
    if j_get(reply,"error") || !command{code=422;}
    else if m_eq(j_s(command,"kind"),"permission"){store64(j_get(saved,j_s(command,"key"))+8,j_value(j_need(command,"allowed")));}
    h_reset(mark);return code;
}
fn main(argc,argv){return mono_run(argc,argv,"Collie · portable permissions",8092,"");}
