// Entire Collie application UI: declarative screens, navigation and event policy.
import "chat.flex";
import "pages.flex";
fn cu_notice(text){cu_set("notice_return",cu_s("page"));cu_set("notice",text);cu_set("page","notice");return 0;}
view notice_screen(){
    column("notice-overlay",height:-1,background:"#99000000"){
        column("notice-spacer",weight:1,action:"back");
        column("notice-panel",padding:24,gap:16,background:"#191f25",radius:24){text("notice-message",text:cu_s("notice"),size:16,color:"#edf2ed");use cu_action("notice-close","Got it","back",0);}
    }
}
view app_view(){
    stack("app-root",height:-1,background:"#10151a"){
        use chat_screen();
        if h_equal(cu_s("page"),"conversations"){use conversations_screen();}
        if h_equal(cu_s("page"),"workers"){use workers_screen();}
        if h_equal(cu_s("page"),"permissions"){use permission_screen();}
        if h_equal(cu_s("page"),"preview"){use preview_screen();}
        if h_equal(cu_s("page"),"menu"){use menu_screen();}
        if h_equal(cu_s("page"),"attachments"){use attachment_menu();}
        if h_equal(cu_s("page"),"model"){use model_screen();}
        if h_equal(cu_s("page"),"notice"){use notice_screen();}
    }
}
fn cu_prepare(){cu_policy=j_get(cp_permissions(cj_get(cu_state,"policy")),"policy");cu_previews=ui_items();cu_copies=ui_items();return app_view();}
fn cu_command(kind){let command=j_object();j_set(command,"kind",j_string(kind));
    if h_equal(kind,"new_session") || h_equal(kind,"open_session") || h_equal(kind,"save_model") || h_equal(kind,"read_preview"){j_set(command,"keyboard",j_string("hide"));}return command;}
fn cu_back(){
    let page=cu_s("page");
    if h_equal(page,"workers") && cu_n("worker"){cu_int("worker",0);j_set(cu_state,"worker_messages",j_array());return cu_command("none");}
    if h_equal(page,"preview"){let back=cu_s("preview_back");if !h_len(back){back="chat";}cu_set("page",back);return cu_command("none");}
    if h_equal(page,"notice"){let back=cu_s("notice_return");if !h_len(back){back="chat";}cu_set("page",back);return cu_command("none");}
    if !h_equal(page,"chat"){cu_set("page","chat");return cu_command("hide_keyboard");}
    return cu_command("exit");
}
fn cu_event(event){
    let action=cj_text(event,"action");let key=cj_text(event,"key");let value=cj_get(event,"value");let id=cj_int(event,"action_id");let type=cj_text(event,"type");let command=cu_command("none");
    if h_equal(action,"fold"){cu_toggle(key);return command;}
    if h_equal(action,"back"){return cu_back();}
    if h_equal(action,"copy"){
        if id<1 || id>load64(cu_copies){return c_error("Invalid clipboard binding.");}
        command=cu_command("copy");j_set(command,"text",j_string(load64(cu_copies+id*8)));return command;
    }
    if h_equal(action,"preview"){
        if id<1 || id>load64(cu_previews){return c_error("Invalid preview binding.");}
        let file=load64(cu_previews+id*8);let image=h_len(cj_text(file,"image_id"));
        if !image && !cj_get(file,"text"){command=cu_command("read_preview");j_set(command,"file",file);return command;}
        cu_set("preview_back",cu_s("page"));cu_set("page","preview");j_set(cu_state,"preview",file);return cu_command("hide_keyboard");
    }
    if h_equal(action,"draft"){
        if !value || j_kind(value)!=2{return c_error("Draft event requires text.");}cu_set("draft",j_value(value));
        if !h_equal(type,"submit"){return command;}action="send";
    }
    if h_equal(action,"send"){
        if cu_n("busy"){return cu_command("cancel");}
        let text=h_trim(cu_s("draft"));if !h_len(text) && !j_count(cu_a("attachments")){return command;}
        command=cu_command("submit");j_set(command,"text",j_string(text));cu_set("draft","");return command;
    }
    if h_equal(action,"suggest_plan"){cu_set("draft","Help me break down a project into clear next steps.");command=cu_command("focus");j_set(command,"key",j_string("composer-draft"));return command;}
    if h_equal(action,"suggest_workspace"){cu_set("draft","Show me what’s in my workspace.");command=cu_command("focus");j_set(command,"key",j_string("composer-draft"));return command;}
    if h_equal(action,"workers"){cu_set("page","workers");cu_int("worker",0);return cu_command("hide_keyboard");}
    if h_equal(action,"worker"){
        cu_int("worker",id);j_set(cu_state,"worker_messages",j_array());command=cu_command("load_worker");j_set(command,"id",j_int(id));return command;
    }
    if h_equal(action,"resume_worker") || h_equal(action,"cancel_worker"){
        command=cu_command("worker_action");let operation="resume";if h_equal(action,"cancel_worker"){operation="cancel";}j_set(command,"action",j_string(operation));j_set(command,"id",j_int(id));return command;
    }
    if h_equal(action,"query"){if !value || j_kind(value)!=2{return c_error("Search event requires text.");}cu_set("query",j_value(value));cu_int("session_offset",0);return command;}
    if h_equal(action,"clear_search"){cu_set("query","");cu_int("session_offset",0);return command;}
    if h_equal(action,"sessions_next"){cu_int("session_offset",cu_n("session_offset")+50);return command;}
    if h_equal(action,"sessions_previous"){let n=cu_n("session_offset")-50;if n<0{n=0;}cu_int("session_offset",n);return command;}
    if h_equal(action,"open_session"){
        if !h_starts(key,"session-"){return c_error("Invalid conversation binding.");}command=cu_command("open_session");j_set(command,"id",j_string(key+8));cu_set("page","chat");return command;
    }
    if h_equal(action,"older"){let offset=cu_n("card_offset")+40;let max=j_count(cu_a("cards"))-40;if max<0{max=0;}if offset>max{offset=max;}cu_int("card_offset",offset);return command;}
    if h_equal(action,"newer"){let offset=cu_n("card_offset")-40;if offset<0{offset=0;}cu_int("card_offset",offset);return command;}
    if h_equal(action,"remove_attachment"){
        if cu_n("busy"){return command;}if id<1 || id>j_count(cu_a("attachments")){return c_error("Invalid attachment binding.");}command=cu_command("remove_attachment");j_set(command,"index",j_int(id-1));return command;
    }
    if h_equal(action,"model_input"){if !value || j_kind(value)!=2{return c_error("Model event requires text.");}cu_set("model_input",j_value(value));cu_set("model_error","");return command;}
    if h_equal(action,"save_model"){
        let model=h_trim(cu_s("model_input"));if !cu_model_valid(model){cu_set("model_error","Use 1–120 letters, digits, dots, underscores or hyphens.");return command;}
        command=cu_command("save_model");j_set(command,"model",j_string(model));cu_set("page","chat");return command;
    }
    if h_equal(cu_s("page"),"permissions") && cj_get(cu_policy,action){
        if h_equal(type,"click"){value=j_bool(!cu_allowed(action));}
        else if !value || j_kind(value)!=5{return c_error("Permission event requires a boolean.");}
        let next=cu_copy(cu_policy);j_set(next,action,value);j_set(cu_state,"policy",next);command=cu_command("permission");j_set(command,"key",j_string(action));j_set(command,"allowed",value);return command;
    }
    // Settings/session changes and file pickers are gated by the shared model.
    if cu_n("busy"){cu_notice("Stop the current reply to change conversations or settings.");return command;}
    if h_equal(action,"menu"){cu_set("page","menu");return cu_command("hide_keyboard");}
    if h_equal(action,"attachments"){
        if j_count(cu_a("attachments"))>=4{cu_notice("Attach up to four files per message.");return command;}cu_set("page","attachments");return cu_command("hide_keyboard");
    }
    if h_equal(action,"conversations"){cu_set("page","conversations");cu_int("sessions_loading",1);cu_set("sessions_error","");return cu_command("load_sessions");}
    if h_equal(action,"permissions"){cu_set("page","permissions");return cu_command("hide_keyboard");}
    if h_equal(action,"model"){cu_set("model_input",cu_s("model"));cu_set("model_error","");cu_set("page","model");return cu_command("hide_keyboard");}
    if h_equal(action,"new_session") || h_equal(action,"compact") || h_equal(action,"resume_main") || h_equal(action,"import_auth") || h_equal(action,"gallery") || h_equal(action,"camera") || h_equal(action,"files"){
        cu_set("page","chat");return cu_command(action);
    }
    return c_error("Unknown UI action.");
}
fn cu_session_summary(saved){
    let history=cu_array(saved,"messages");let title="New conversation";let preview="Start a conversation in this workspace.";let titled=0;let i=0;
    while i<j_count(history){let item=j_at(history,i);let role=cj_text(item,"role");let text=cj_text(item,"content");if (h_equal(role,"user") || h_equal(role,"assistant")) && h_len(h_trim(text)){if !titled && h_equal(role,"user"){title=text;titled=1;}preview=rt_plain(text);}i=i+1;}
    let result=j_object();j_set(result,"title",j_string(cu_clip(title,256)));j_set(result,"preview",j_string(cu_clip(preview,180)));return result;
}
fn cu_ui_host(request){
    let action=cj_text(request,"action");if h_equal(action,"summary"){return cu_session_summary(cj_get(request,"saved"));}
    if h_equal(action,"navigation"){
        let state=cj_get(request,"state");let out=j_object();let keys=j_parse("[\"page\",\"draft\",\"query\",\"worker\",\"expanded\",\"model_input\",\"preview\",\"preview_back\",\"card_offset\",\"session_offset\",\"notice_return\",\"notice\"]");let i=0;
        while i<j_count(keys){let key=j_value(j_at(keys,i));let value=cj_get(state,key);if value{j_set(out,key,value);}i=i+1;}return out;
    }
    let state=cj_get(request,"state");cu_state=cu_copy(state);if !h_len(cu_s("page")){cu_set("page","chat");}if !h_len(cu_s("model")){cu_set("model","gpt-6.1-sol");}
    let old=0;let index=0;if !c_flag(request,"reset"){old=cu_prepare();index=ui_index;}
    let before=cu_state;cu_state=cu_copy(before);let command=cu_command("none");let data=cj_get(request,"data");
    // Ignore messages that completed after the user selected a different worker.
    if data && cj_get(data,"worker_owner") && cj_int(data,"worker_owner")!=cu_n("worker"){data=0;}
    cu_merge(cu_state,data);
    if h_equal(action,"restore"){
        if h_equal(cu_s("page"),"conversations"){cu_int("sessions_loading",1);command=cu_command("load_sessions");}
        else if h_equal(cu_s("page"),"workers") && cu_n("worker"){command=cu_command("load_worker");j_set(command,"id",j_int(cu_n("worker")));}
    }
    if h_equal(action,"append") || cj_get(request,"append_cards"){
        let array=j_array();let prior=cu_a("cards");let i=0;while i<j_count(prior){j_push(array,j_at(prior,i));i=i+1;}let card=cj_get(request,"card");if card{j_push(array,card);}let added=cu_array(request,"append_cards");i=0;while i<j_count(added){j_push(array,j_at(added,i));i=i+1;}j_set(cu_state,"cards",array);
    }
    if h_equal(action,"clear"){j_set(cu_state,"cards",j_array());j_set(cu_state,"expanded",j_object());j_set(cu_state,"worker_messages",j_array());j_set(cu_state,"worker_streams",j_object());j_set(cu_state,"live",j_object());cu_int("worker",0);cu_set("page","chat");cu_set("stream","");cu_set("draft","");cu_int("card_offset",0);}
    if data && cj_get(data,"busy") && !cu_n("busy"){cu_set("status","");cu_set("stream","");j_set(cu_state,"live",j_object());}
    if h_equal(action,"notice"){cu_notice(cj_text(request,"text"));}
    if h_equal(action,"event"){
        let event=cj_get(request,"event");let key=cj_text(event,"key");let node=ui_find(index,key);let type=cj_text(event,"type");
        if !node || !h_equal(load64(node+32),cj_text(event,"action")) || load64(node+88)!=cj_int(event,"action_id"){return c_error("Stale or invalid UI event binding.");}
        if !h_equal(type,"click") && !h_equal(type,"change") && !h_equal(type,"submit"){return c_error("Invalid UI event type.");}
        command=cu_event(event);if j_get(command,"error"){return command;}
    }else if h_equal(action,"back"){command=cu_back();}
    else if h_equal(action,"preview"){
        cu_set("preview_back",cu_s("page"));cu_set("page","preview");j_set(cu_state,"preview",j_need(request,"file"));
    }
    if data && cj_get(data,"workers") && h_equal(cu_s("page"),"workers") && cu_n("worker"){
        command=cu_command("load_worker");j_set(command,"id",j_int(cu_n("worker")));
    }
    let next=cu_prepare();let out=j_object();j_set(out,"version",j_int(1));j_set(out,"state",cu_state);j_set(out,"ops",j_parse(ui_compiled_diff(old,next,index,ui_index)));j_set(out,"command",command);return out;
}
