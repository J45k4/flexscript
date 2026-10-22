// Collie's first shared screen. The same view compiles for Android and the DOM.
import "../../../libs/ui/runtime.flex";
import "../core/permissions.flex";
global cu_policy=0;
global cu_entries=0;
fn cu_key(prefix,key){return m_cat(prefix,key);}
fn cu_rows(){let rows=ui_items();if !cu_entries{cu_entries=j_get(cp_permissions(0),"entries");}let entries=cu_entries;let i=0;while i<j_count(entries){ui_item_add(rows,j_at(entries,i));i=i+1;}return rows;}
fn cu_allowed(key){let value=j_get(cu_policy,key);return value && j_value(value);}
fn cu_summary(){let rows=cu_rows();let i=0;let count=0;while i<load64(rows){if cu_allowed(j_s(load64(rows+8+i*8),"key")){count=count+1;}i=i+1;}return m_cat(m_cat(m_int(count),m_cat(" of ",m_int(load64(rows))))," permissions enabled");}
view permission_row(entry){
    let key=j_s(entry,"key");
    row(cu_key("permission-",key),action:key,description:j_s(entry,"title"),padding:16,gap:10,background:"#191f25",radius:16,border_width:1,border_color:"#2c353b"){
        column(cu_key("labels-",key),weight:1,gap:6){
            text(cu_key("title-",key),text:j_s(entry,"title"),size:16,color:"#edf2ed",font:"medium");
            text(cu_key("detail-",key),text:j_s(entry,"detail"),size:13,color:"#8e9d9f");
        }
        check(cu_key("toggle-",key),text:j_s(entry,"title"),checked:cu_allowed(key),action:key,min_height:48,color:"#c5e3ae");
    }
}
view permission_screen(){
    column("permissions",height:-1,background:"#10151a"){
        row("permissions-header",padding_x:16,padding_y:12,gap:12){
            button("permissions-back",text:"‹",description:"Back to conversation",action:"back",size:28,align:"center",width:46,height:46,color:"#c5e3ae");
            text("permissions-heading",text:"Permissions",size:23,font:"medium",color:"#edf2ed");
        }
        text("permissions-summary",text:cu_summary(),size:13,color:"#c5e3ae",padding_x:22,padding_y:10);
        scroll("permissions-scroll",weight:1){
            column("permissions-content",padding:18,gap:10){
                text("permissions-intro",text:"Choose what Collie can access in this conversation.",size:15,color:"#8e9d9f");
                each entry in cu_rows(){use permission_row(entry);}
                text("permissions-note",text:"Saved automatically for this conversation. Turning access off blocks future program calls; it does not erase information already in the chat.",size:12,color:"#8e9d9f",padding_y:10);
                text("permissions-private",text:"Login credentials, other apps, shared storage, USB and host processes remain unavailable to programs.",size:12,color:"#8e9d9f");
            }
        }
    }
}
fn cu_permission_tree(){ui_compiled_begin();return ui_compiled_snapshot(permission_screen());}
// Explicit models cross the embedding boundary; native calls need no live pointers.
// Only the current policy is authoritative. An event is resolved against this
// view's actual action IDs, and a change is returned as an effect for persistence.
fn cu_permissions(request){
    let old=j_get(cp_permissions(cj_get(request,"policy")),"policy");cu_policy=old;let prior=0;let index=0;
    if !c_flag(request,"reset"){prior=cu_permission_tree();index=ui_index;}
    let event=cj_get(request,"event");let action=cj_text(event,"action");let key=cj_text(event,"key");let command=j_object();
    if h_len(action){
        if h_equal(action,"back") && h_equal(key,"permissions-back"){j_set(command,"kind",j_string("back"));}
        else {
            let value=cj_get(event,"value");let found=j_get(old,action);
            if found && h_equal(key,cu_key("permission-",action)) && h_equal(cj_text(event,"type"),"click"){value=j_bool(!j_value(found));}
            else if !found || !h_equal(key,cu_key("toggle-",action)) || !h_equal(cj_text(event,"type"),"change") || !value || j_kind(value)!=5{return c_error("Invalid permissions UI event.");}
            j_set(command,"kind",j_string("permission"));j_set(command,"key",j_string(action));j_set(command,"allowed",value);
        }
    }
    let next=cj_get(request,"next_policy");if next && j_kind(next)==4{cu_policy=j_get(cp_permissions(next),"policy");}
    let tree=cu_permission_tree();let patch=ui_compiled_diff(prior,tree,index,ui_index);let out=j_object();j_set(out,"version",j_int(1));j_set(out,"ops",j_parse(patch));j_set(out,"command",command);return out;
}
