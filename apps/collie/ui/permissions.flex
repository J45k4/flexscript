// Collie's first shared screen. The same view compiles for Android and the DOM.
import "../../../libs/ui/runtime.flex";
import "../core/permissions.flex";
global cu_policy=0;
global cu_entries=0;
global cu_platform=0;
global cu_permission_compact=0;
fn cu_permission_privacy(){if cu_platform && h_equal(cu_platform,"linux"){return "Login credentials remain private. Linux device access also requires OS permissions. An allowed grant does not enable an unavailable desktop adapter.";}return "Login credentials remain private. Android may ask separately before opening a device, sharing a screen, or accessing files outside this workspace.";}
fn cu_key(prefix,key){return m_cat(prefix,key);}
fn cu_rows(){let rows=ui_items();if !cu_entries{cu_entries=j_get(cp_permissions(0),"entries");}let entries=cu_entries;let i=0;while i<j_count(entries){ui_item_add(rows,j_at(entries,i));i=i+1;}return rows;}
fn cu_allowed(key){return h_equal(cp_mode(cu_policy,key),"allow");}
fn cu_permission_bg(key,mode){if h_equal(cp_mode(cu_policy,key),mode){return "#354b3a";}return "#242d34";}
fn cu_summary(){let rows=cu_rows();let i=0;let allowed=0;let ask=0;while i<load64(rows){let key=j_s(load64(rows+8+i*8),"key");if cu_allowed(key){allowed=allowed+1;}if h_equal(cp_mode(cu_policy,key),"ask"){ask=ask+1;}i=i+1;}if ask{return m_cat(m_cat(m_cat(m_int(allowed)," allowed · "),m_cat(m_int(ask)," ask · ")),m_cat(m_int(load64(rows)-allowed-ask)," denied"));}return m_cat(m_cat(m_int(allowed),m_cat(" of ",m_int(load64(rows))))," permissions enabled");}
view permission_row(entry){
    let key=j_s(entry,"key");
    column(cu_key("permission-",key)){
    if cu_permission_compact{
        row(cu_key("permission-row-",key),padding:14,gap:18,background:"#191f25",radius:10,border_width:1,border_color:"#2c353b"){
            column(cu_key("permission-description-",key),weight:1,gap:6){
                text(cu_key("title-",key),text:j_s(entry,"title"),size:14,color:"#edf2ed",font:"medium");
                text(cu_key("detail-",key),text:j_s(entry,"detail"),size:12,color:"#8e9d9f");
            }
            row(cu_key("choices-",key),gap:5){
                button(cu_key("ask-",key),text:"Ask",description:cu_key("Ask for ",j_s(entry,"title")),action:key,width:58,min_height:34,align:"center",background:cu_permission_bg(key,"ask"),color:"#c5e3ae",radius:7,size:12);
                button(cu_key("allow-",key),text:"Allow",description:cu_key("Allow ",j_s(entry,"title")),action:key,width:58,min_height:34,align:"center",background:cu_permission_bg(key,"allow"),color:"#c5e3ae",radius:7,size:12);
                button(cu_key("deny-",key),text:"Deny",description:cu_key("Deny ",j_s(entry,"title")),action:key,width:58,min_height:34,align:"center",background:cu_permission_bg(key,"deny"),color:"#c5e3ae",radius:7,size:12);
            }
        }
    }else{
    column(cu_key("permission-body-",key),padding:16,gap:10,background:"#191f25",radius:16,border_width:1,border_color:"#2c353b"){
        text(cu_key("title-",key),text:j_s(entry,"title"),size:16,color:"#edf2ed",font:"medium");
        text(cu_key("detail-",key),text:j_s(entry,"detail"),size:13,color:"#8e9d9f");
        row(cu_key("choices-",key),gap:8){
            button(cu_key("ask-",key),text:"Ask",description:cu_key("Ask for ",j_s(entry,"title")),action:key,weight:1,min_height:48,align:"center",background:cu_permission_bg(key,"ask"),color:"#c5e3ae",radius:10);
            button(cu_key("allow-",key),text:"Allow",description:cu_key("Allow ",j_s(entry,"title")),action:key,weight:1,min_height:48,align:"center",background:cu_permission_bg(key,"allow"),color:"#c5e3ae",radius:10);
            button(cu_key("deny-",key),text:"Deny",description:cu_key("Deny ",j_s(entry,"title")),action:key,weight:1,min_height:48,align:"center",background:cu_permission_bg(key,"deny"),color:"#c5e3ae",radius:10);
        }
    }
    }
    }
}
view permission_screen(){
    column("permissions",height:-1,background:"#10151a"){
        row("permissions-header",padding_x:16,padding_y:12,gap:12){
            button("permissions-back",text:"‹",description:"Back to conversation",action:"back",size:28,align:"center",width:46,height:46,color:"#c5e3ae");
            text("permissions-heading",text:cu_permission_heading(),size:23,font:"medium",color:"#edf2ed");
        }
        text("permissions-summary",text:cu_summary(),size:13,color:"#c5e3ae",padding_x:22,padding_y:10);
        scroll("permissions-scroll",weight:1){
            column("permissions-content",padding:18,gap:10){
                text("permissions-intro",text:cu_permission_intro(),size:15,color:"#8e9d9f");
                each entry in cu_rows(){use permission_row(entry);}
                text("permissions-note",text:"Saved automatically for this conversation and inherited by its workers. Denying access blocks future calls; it does not erase information already in the chat.",size:12,color:"#8e9d9f",padding_y:10);
                text("permissions-private",text:cu_permission_privacy(),size:12,color:"#8e9d9f");
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
            let value=cp_choice(action,key);let found=j_get(old,action);
            if !found || !value || !h_equal(cj_text(event,"type"),"click"){return c_error("Invalid permissions UI event.");}
            j_set(command,"kind",j_string("permission"));j_set(command,"key",j_string(action));j_set(command,"allowed",value);
        }
    }
    let next=cj_get(request,"next_policy");if next && j_kind(next)==4{cu_policy=j_get(cp_permissions(next),"policy");}
    let tree=cu_permission_tree();let patch=ui_compiled_diff(prior,tree,index,ui_index);let out=j_object();j_set(out,"version",j_int(1));j_set(out,"ops",j_parse(patch));j_set(out,"command",command);return out;
}

fn cu_permission_heading(){return "Permissions";}
fn cu_permission_intro(){if cu_platform && h_equal(cu_platform,"linux"){return "Available desktop capabilities. Choose when this conversation and its workers can use them.";}return "Ask when first used, allow future calls, or deny access in this conversation.";}
