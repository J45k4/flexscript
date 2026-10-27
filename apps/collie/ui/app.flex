// Entire Collie application UI: declarative screens, navigation and event policy.
import "workspace-events.flex";
fn cu_notice(text){cu_set("notice_return",cu_s("page"));cu_set("notice",text);cu_set("page","notice");return 0;}
view notice_screen(){
    column("notice-overlay",height:-1,background:cu_overlay_bg()){
        column("notice-spacer",weight:1,action:"back");
        column("notice-panel",padding:24,gap:16,background:"#191f25",radius:24){text("notice-message",text:cu_s("notice"),size:16,color:"#edf2ed");use cu_action("notice-close","Got it","back",0);}
        if cu_desktop(){column("notice-desktop-bottom",weight:1);}
    }
}
view permission_request_screen(){
    let request=cj_get(cu_state,"permission_request");
    column("permission-request-overlay",height:-1,background:cu_overlay_bg(),padding:20,gap:16){
        column("permission-request-spacer",weight:1);
        column("permission-request-panel",padding:24,gap:16,background:"#191f25",radius:24){
            text("permission-request-heading",text:"Allow access?",size:24,font:"medium",color:"#edf2ed");
            text("permission-request-title",text:cj_text(request,"title"),size:18,font:"medium",color:"#c5e3ae");
            text("permission-request-detail",text:cj_text(request,"detail"),size:15,color:"#edf2ed");
            text("permission-request-operation",text:m_cat("Requested by: ",cj_text(request,"operation")),size:13,color:"#8e9d9f");
            text("permission-request-scope",text:"Your choice applies to this conversation and its workers. Change it later in Permissions.",size:13,color:"#8e9d9f");
            row("permission-request-actions",gap:12){
                button("permission-request-deny",text:"Deny",description:"Deny requested access",action:"permission_decision",action_id:cj_int(request,"request_id"),weight:1,min_height:52,align:"center",background:"#242d34",color:"#edf2ed",radius:12);
                button("permission-request-allow",text:"Allow",description:"Allow requested access",action:"permission_decision",action_id:cj_int(request,"request_id"),weight:1,min_height:52,align:"center",background:"#c5e3ae",color:"#10151a",radius:12);
            }
            button("permission-request-stop",text:"Stop this task",action:"permission_stop",action_id:cj_int(request,"request_id"),min_height:48,color:"#f1aaa6",align:"center");
        }
        column("permission-request-bottom",weight:1);
    }
}
view mobile_app_view(){
    stack("mobile-shell",height:-1,background:"#10151a"){
        use chat_screen();
        if h_equal(cu_s("page"),"conversations"){use conversations_screen();}
        if h_equal(cu_s("page"),"workers"){use workers_screen();}
        if h_equal(cu_s("page"),"permissions"){use permission_screen();}
        if h_equal(cu_s("page"),"preview"){use preview_screen();}
        if h_equal(cu_s("page"),"menu"){use menu_screen();}
        if h_equal(cu_s("page"),"attachments"){use attachment_menu();}
        if h_equal(cu_s("page"),"model"){use model_screen();}
        if h_equal(cu_s("page"),"notice"){use notice_screen();}
        if cj_int(cj_get(cu_state,"permission_request"),"request_id"){use permission_request_screen();}
    }
}
view app_view(){
    stack("app-root",height:-1,background:"#10151a"){
        if cu_desktop(){
            row("desktop-shell",height:-1){
                if cu_sidebar(){use workspace_sidebar();column("desktop-sidebar-divider",width:6,height:-1,background:"#20292f",focus_background:"#78966d",action:"sidebar_resize",description:"Resize sidebar · Drag or use Left/Right when focused");}
                stack("desktop-main",weight:1,height:-1){
                    use desktop_workspace();
                    if h_equal(cu_s("page"),"conversations"){use conversations_screen();}
                    if h_equal(cu_s("page"),"workers"){use workers_screen();}
                    if h_equal(cu_s("page"),"permissions"){use permission_screen();}
                    if h_equal(cu_s("page"),"preview"){use preview_screen();}
                    if cu_settings_visible(){use desktop_settings_screen();}
                    if h_equal(cu_s("page"),"attachments") || h_equal(cu_s("page"),"model") || h_equal(cu_s("page"),"notice") || h_equal(cu_s("page"),"projects"){
                        stack("desktop-dialog-dimmer",height:-1,background:"#88000000"){
                            stack("desktop-dialog-slot",width:cu_dialog_width(),height:-1,position:"center"){
                                if h_equal(cu_s("page"),"attachments"){use attachment_menu();}
                                if h_equal(cu_s("page"),"model"){use model_screen();}
                                if h_equal(cu_s("page"),"notice"){use notice_screen();}
                                if h_equal(cu_s("page"),"projects"){use desktop_projects_screen();}
                            }
                        }
                    }
                }
            }
            if !cu_sidebar() && cu_n("workspace_drawer"){
                stack("workspace-drawer-overlay",height:-1,background:"#88000000",action:"workspace_drawer_close"){
                    stack("workspace-drawer-slot",width:cu_sidebar_width(),height:-1){use workspace_sidebar();}
                }
            }
            if cj_int(cj_get(cu_state,"permission_request"),"request_id"){
                stack("desktop-permission-dimmer",height:-1,background:"#aa000000"){
                    stack("desktop-permission-slot",width:cu_dialog_width(),height:-1,position:"center"){use permission_request_screen();}
                }
            }
        }else{use mobile_app_view();}
    }
}

fn cu_prepare(){cws_prepare();cm_prepare();cu_policy=j_get(cp_permissions(cj_get(cu_state,"policy")),"policy");cu_entries=cj_get(cu_state,"permission_entries");cu_platform=cu_s("platform");let width=cu_main_width();if cu_settings_visible(){width=cu_settings_content_width();}cu_permission_compact=cu_desktop() && width>=700;cu_previews=ui_items();cu_copies=ui_items();return app_view();}
fn cu_model_return(){let page="chat";if cu_desktop() && h_equal(cu_s("model_return"),"settings"){page="settings";}cu_set("model_return","");cu_set("page",page);return 0;}
fn cu_desktop_settings_restore(){if cu_desktop(){if h_equal(cu_s("page"),"menu"){cu_set("page","settings");}if h_equal(cu_s("page"),"permissions"){cu_set("page","settings");cu_set("settings_section","access");}}return 0;}
fn cu_command(kind){let command=j_object();j_set(command,"kind",j_string(kind));
    if h_equal(kind,"new_session") || h_equal(kind,"open_session") || h_equal(kind,"save_model") || h_equal(kind,"read_preview"){j_set(command,"keyboard",j_string("hide"));}return command;}
fn cu_back(){
    if cj_int(cj_get(cu_state,"permission_request"),"request_id"){return cu_permission_decision(0,0);}
    let page=cu_s("page");
    if cu_desktop() && h_equal(page,"model"){cu_model_return();return cu_command("hide_keyboard");}
    if h_equal(page,"workers") && cu_n("worker"){cu_int("worker",0);j_set(cu_state,"worker_messages",j_array());return cu_command("none");}
    if h_equal(page,"preview"){let back=cu_s("preview_back");if !h_len(back){back="chat";}cu_set("page",back);return cu_command("none");}
    if h_equal(page,"notice"){let back=cu_s("notice_return");if !h_len(back){back="chat";}cu_set("page",back);return cu_command("none");}
    if !h_equal(page,"chat"){cu_set("page","chat");return cu_command("hide_keyboard");}
    if cu_desktop(){let command=cu_command("focus");j_set(command,"key",j_string("composer-draft"));return command;}
    return cu_command("exit");
}
fn cu_permission_decision(allow,stop){
    let pending=cj_get(cu_state,"permission_request");let id=cj_int(pending,"request_id");if !id{return c_error("No access request is pending.");}
    let command=cu_command("permission_decision");j_set(command,"request_id",j_int(id));j_set(command,"allowed",j_bool(allow));j_set(command,"stop",j_bool(stop));return command;
}
fn cu_event(event){
    let action=cj_text(event,"action");let key=cj_text(event,"key");let value=cj_get(event,"value");let id=cj_int(event,"action_id");let type=cj_text(event,"type");let command=cu_command("none");
    let pending_id=cj_int(cj_get(cu_state,"permission_request"),"request_id");
    if h_equal(action,"permission_decision") || h_equal(action,"permission_stop"){
        if !pending_id || id!=pending_id{return c_error("Stale permission request.");}
        return cu_permission_decision(h_equal(key,"permission-request-allow"),h_equal(action,"permission_stop"));
    }
    if pending_id{if h_equal(action,"back"){return cu_permission_decision(0,0);}return command;}
    if cu_desktop() && h_starts(action,"workspace_"){return cws_event(event);}
    if cu_desktop() && cu_session_loading() && !h_equal(action,"desktop_open_session") && !h_equal(action,"query") && !h_equal(action,"sessions_next") && !h_equal(action,"sessions_previous") && !h_equal(action,"desktop_sidebar") && !h_equal(action,"desktop_search") && !h_equal(action,"sidebar_resize"){return command;}
    if cu_desktop() && h_equal(action,"sidebar_resize"){
        if h_equal(type,"click"){return command;}
        if !value || j_kind(value)!=1{return c_error("Invalid sidebar width.");}let width=j_value(value);if width<220{width=220;}if width>520{width=520;}cu_int("sidebar_width",width);if h_equal(type,"submit"){command=cu_command("sidebar_width");j_set(command,"width",j_int(width));}return command;
    }
    if cu_desktop() && h_equal(action,"sidebar_mode"){
        if id<0 || id>1{return c_error("Invalid sidebar mode.");}let mode="projects";if id{mode="timeline";}cu_set("sidebar_mode",mode);cu_int("session_offset",0);return command;
    }
    if cu_desktop() && h_equal(action,"sidebar_group"){
        if !h_starts(key,"sidebar-fold-"){return c_error("Invalid project group.");}let closed=cu_copy(cj_get(cu_state,"sidebar_closed"));j_set(closed,key+13,j_bool(!cj_int(closed,key+13)));j_set(cu_state,"sidebar_closed",closed);return command;
    }
    if (h_equal(cu_s("page"),"permissions") || (cu_desktop() && h_equal(cu_s("page"),"settings") && h_equal(cu_settings_section(),"access"))) && cj_get(cu_policy,action){
        // Navigation can share a grant name (Workers). Only an actual
        // Ask/Allow/Deny binding changes policy; other controls keep routing.
        let choice=cp_choice(action,key);if choice{
            if !h_equal(type,"click"){return c_error("Invalid permission choice.");}
            let next=cu_copy(cu_policy);j_set(next,action,choice);j_set(cu_state,"policy",next);command=cu_command("permission");j_set(command,"key",j_string(action));j_set(command,"allowed",choice);return command;
        }
    }
    if cu_desktop() && h_equal(action,"settings_section"){
        if id<0 || id>2{return c_error("Invalid settings section.");}let section="model";if id==1{section="access";}if id==2{section="account";command=cu_command("refresh_account");}cu_set("settings_section",section);return command;
    }
    if cu_desktop() && h_equal(action,"select_account"){
        if cu_n("busy") || cu_n("account_busy") || cu_account_login_running(){return command;}if !h_starts(key,"settings-account-use-"){return c_error("Invalid account selection.");}
        let rows=cu_a("accounts");let i=0;while i<j_count(rows){let row=j_at(rows,i);if h_equal(cj_text(row,"id"),key+21) && cj_int(row,"available") && !cj_int(row,"active"){command=cu_command("select_account");j_set(command,"id",j_need(row,"id"));return command;}i=i+1;}return c_error("Saved account is no longer available.");
    }
    if cu_desktop() && (h_equal(action,"cancel_account_login") || h_equal(action,"open_account_login")){return cu_command(action);}
    if cu_desktop() && h_equal(action,"copy_account_login"){
        let url=cj_text(cj_get(cu_state,"account_login"),"url");if !h_len(url){return command;}command=cu_command("copy");j_set(command,"text",j_string(url));return command;
    }
    if cu_desktop() && h_equal(action,"desktop_sidebar"){
        if cu_n("viewport_width")<960{cu_int("workspace_drawer",!cu_n("workspace_drawer"));return command;}
        cu_int("sidebar_collapsed",!cu_n("sidebar_collapsed"));return command;
    }
    if cu_desktop() && (h_equal(action,"desktop_chat") || h_equal(action,"desktop_search")){
        cu_set("page","chat");command=cu_command("focus");let focus="composer-draft";
        if h_equal(action,"desktop_search"){
            if !cu_sidebar(){cu_set("page","conversations");command=cu_command("load_sessions");focus="conversations-query";}else{focus="desktop-search";}
        }
        j_set(command,"focus_key",j_string(focus));j_set(command,"key",j_string(focus));return command;
    }
    if cu_desktop() && h_equal(action,"desktop_open_session"){
        if cu_n("busy"){return command;}if !h_starts(key,"desktop-session-"){return c_error("Invalid desktop conversation binding.");}
        cu_set("page","chat");if h_equal(key+16,cu_selected_session()){return command;}cu_set("pending_session_id",key+16);cu_int("session_request",cu_n("session_request")+1);command=cu_command("open_session");j_set(command,"id",j_string(key+16));j_set(command,"request_id",j_int(cu_n("session_request")));return command;
    }
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
    if h_equal(action,"model_network"){
        if !h_equal(cu_s("page"),"model") || id<0 || id>3{return c_error("Invalid model network choice.");}
        let modes=h_args("default","wifi","cellular","ethernet",0,0);let mode=h_at(modes,id);cu_set("model_network",mode);command=cu_command("save_model_network");j_set(command,"network",j_string(mode));return command;
    }
    if cu_desktop() && h_equal(action,"model_query"){
        if !value || j_kind(value)!=2{return c_error("Model search requires text.");}cu_set("model_query",j_value(value));if !h_equal(type,"submit"){return command;}
        if cu_model_matches(1) && (!cu_model_matches(0) || h_equal(cu_s("model"),cu_model_id(1))){id=1;}else if cu_model_matches(0){id=0;}else{return command;}action="choose_model";
    }
    if cu_desktop() && h_equal(action,"choose_model"){
        if cu_n("busy"){return command;}if id<0 || id>1 || !cu_model_matches(id){return c_error("Invalid model selection.");}cu_set("model_input",cu_model_id(id));cu_model_return();command=cu_command("save_model");j_set(command,"model",j_string(cu_model_id(id)));return command;
    }
    if h_equal(action,"model_input"){if !value || j_kind(value)!=2{return c_error("Model event requires text.");}cu_set("model_input",j_value(value));cu_set("model_error","");return command;}
    if h_equal(action,"save_model"){
        let model=h_trim(cu_s("model_input"));if !cu_model_valid(model){cu_set("model_error","Use 1–120 letters, digits, dots, underscores or hyphens.");return command;}
        command=cu_command("save_model");j_set(command,"model",j_string(model));cu_model_return();return command;
    }
    // Settings/session changes and file pickers are gated by the shared model.
    if cu_n("busy"){cu_notice("Stop the current reply to change conversations or settings.");return command;}
    if cu_desktop() && h_equal(action,"start_account_login"){
        if cu_n("account_busy"){return command;}if id<0 || id>1{return c_error("Invalid sign-in method.");}let method="browser";if id==1{method="device";}cu_set("page","settings");cu_set("settings_section","account");command=cu_command("start_account_login");j_set(command,"method",j_string(method));return command;
    }
    if cu_desktop() && h_equal(action,"projects"){cu_set("page","projects");return cu_command("hide_keyboard");}
    if cu_desktop() && h_equal(action,"project_new_chat"){
        if !h_starts(key,"sidebar-new-"){return c_error("Invalid project chat binding.");}cu_sidebar_reveal(key+12);cu_set("page","chat");command=cu_command("new_session");j_set(command,"project_id",j_string(key+12));return command;
    }
    if cu_desktop() && h_equal(action,"choose_project_folder"){cu_set("query","");cu_int("session_offset",0);return cu_command("choose_project_folder");}
    if cu_desktop() && h_equal(action,"select_project"){
        let project="";if !h_equal(key,"project-personal"){if !h_starts(key,"project-"){return c_error("Invalid project binding.");}project=key+8;}
        cu_sidebar_reveal(project);cu_set("page","chat");command=cu_command("select_project");j_set(command,"id",j_string(project));return command;
    }
    if h_equal(action,"menu"){let page="menu";if cu_desktop(){page="settings";}cu_set("page",page);if cu_desktop() && h_equal(cu_settings_section(),"account"){return cu_command("refresh_account");}return cu_command("hide_keyboard");}
    if h_equal(action,"attachments"){
        if j_count(cu_a("attachments"))>=4{cu_notice("Attach up to four files per message.");return command;}cu_set("page","attachments");return cu_command("hide_keyboard");
    }
    if h_equal(action,"conversations"){cu_set("page","conversations");cu_int("sessions_loading",1);cu_set("sessions_error","");return cu_command("load_sessions");}
    if h_equal(action,"permissions"){let page="permissions";if cu_desktop(){page="settings";cu_set("settings_section","access");}cu_set("page",page);return cu_command("hide_keyboard");}
    if h_equal(action,"model"){cu_set("model_return",cu_s("page"));cu_set("model_input",cu_s("model"));cu_set("model_query","");cu_set("model_error","");cu_set("page","model");return cu_command("hide_keyboard");}
    if h_equal(action,"new_session") || h_equal(action,"compact") || h_equal(action,"resume_main") || h_equal(action,"import_auth") || h_equal(action,"gallery") || h_equal(action,"camera") || h_equal(action,"files"){
        if cu_desktop() && h_equal(action,"new_session"){cu_sidebar_reveal(cu_s("project_id"));}
        if !(cu_desktop() && h_equal(cu_s("page"),"settings") && h_equal(action,"import_auth")){cu_set("page","chat");}return cu_command(action);
    }
    return c_error("Unknown UI action.");
}
fn cu_session_summary(saved){
    let history=cu_array(saved,"messages");let title="New conversation";let preview="Start a conversation in this workspace.";let titled=0;let i=0;
    while i<j_count(history){let item=j_at(history,i);let role=cj_text(item,"role");let text=cj_text(item,"content");if (h_equal(role,"user") || h_equal(role,"assistant")) && h_len(h_trim(text)){if !titled && h_equal(role,"user"){title=text;titled=1;}preview=rt_plain(text);}i=i+1;}
    let result=j_object();j_set(result,"title",j_string(cu_clip(title,256)));j_set(result,"preview",j_string(cu_clip(preview,180)));return result;
}
fn cu_open_link(node,event){
    let href=cj_text(event,"value");if !cu_desktop() || !rt_href(href){return c_error("Invalid message link.");}
    let attr=load64(node+96);while attr{if h_equal(load64(attr),"runs"){let runs=j_parse(load64(attr+8));let i=0;while i<j_count(runs){if h_equal(cj_text(j_at(runs,i),"href"),href){let command=cu_command("open_link");j_set(command,"href",j_string(href));return command;}i=i+1;}}attr=load64(attr+16);}return c_error("Stale message link.");
}
fn cu_ui_host(request){
    let action=cj_text(request,"action");if h_equal(action,"summary"){return cu_session_summary(cj_get(request,"saved"));}
    if h_equal(action,"navigation"){
        let state=cj_get(request,"state");let out=j_object();let keys=j_parse("[\"page\",\"draft\",\"query\",\"worker\",\"expanded\",\"model_input\",\"model_query\",\"model_return\",\"settings_section\",\"preview\",\"preview_back\",\"card_offset\",\"session_offset\",\"notice_return\",\"notice\",\"sidebar_collapsed\",\"sidebar_width\",\"sidebar_mode\",\"sidebar_closed\",\"workspace\",\"workspace_side\"]");let i=0;
        while i<j_count(keys){let key=j_value(j_at(keys,i));let value=cj_get(state,key);if value{j_set(out,key,value);}i=i+1;}let prior=cu_state;cu_state=state;out=cm_navigation(out);cu_state=prior;return out;
    }
    let state=cj_get(request,"state");cu_state=cu_copy(state);if cj_int(cj_get(request,"data"),"multi_chat"){cu_int("multi_chat",1);}if !h_len(cu_s("page")){cu_set("page","chat");}if !h_len(cu_s("model")){cu_set("model","gpt-6.1-sol");}cu_desktop_settings_restore();if cm_enabled(){cws_prepare();cm_prepare();request=cm_filter_request(request);action=cj_text(request,"action");}
    // A previous load can finish after another sidebar selection. Keep the
    // latest local selection visible and ignore the older session's packets.
    if cu_desktop() && !cm_enabled() && cj_get(request,"session_request") && cj_int(request,"session_request")!=cu_n("session_request"){
        let out=j_object();j_set(out,"version",j_int(1));j_set(out,"state",cu_state);j_set(out,"ops",j_array());j_set(out,"command",cu_command("none"));return out;
    }
    let old=0;let index=0;if !c_flag(request,"reset"){old=cu_prepare();index=ui_index;}
    let before=cu_state;cu_state=cu_copy(before);let command=cu_command("none");let chat_frame=cm_packet_begin(request);let data=cj_get(request,"data");
    // Ignore messages that completed after the user selected a different worker.
    if data && cj_get(data,"worker_owner") && cj_int(data,"worker_owner")!=cu_n("worker"){data=0;}
    if cu_desktop() && !cu_sidebar() && data && cj_get(data,"project_id") && !h_equal(cj_text(data,"project_id"),cu_s("project_id")){cu_set("query","");cu_int("session_offset",0);}
    cu_merge(cu_state,data);
    cu_desktop_settings_restore();cws_update(data);
    if cu_desktop() && h_equal(cu_s("page"),"chat") && data && (cj_get(data,"workspace_file") || cj_get(data,"workspace_saved") || cj_get(data,"workspace")){j_set(command,"focus_key",j_string(cws_focus_key(cws_focused())));}
    if h_equal(action,"restore"){
        if h_equal(cu_s("page"),"conversations"){cu_int("sessions_loading",1);command=cu_command("load_sessions");}
        else if h_equal(cu_s("page"),"workers") && cu_n("worker"){command=cu_command("load_worker");j_set(command,"id",j_int(cu_n("worker")));}
    }
    if h_equal(action,"append") || cj_get(request,"append_cards"){
        let array=j_array();let prior=cu_a("cards");let i=0;while i<j_count(prior){j_push(array,j_at(prior,i));i=i+1;}let card=cj_get(request,"card");if card{j_push(array,card);}let added=cu_array(request,"append_cards");i=0;while i<j_count(added){j_push(array,j_at(added,i));i=i+1;}j_set(cu_state,"cards",array);
    }
    if h_equal(action,"clear"){j_set(cu_state,"permission_request",j_object());j_set(cu_state,"cards",j_array());j_set(cu_state,"expanded",j_object());j_set(cu_state,"worker_messages",j_array());j_set(cu_state,"worker_streams",j_object());j_set(cu_state,"live",j_object());cu_int("worker",0);cu_set("page","chat");cu_set("stream","");cu_set("draft","");cu_int("card_offset",0);}
    if data && cj_get(data,"busy") && !cu_n("busy"){cu_set("status","");cu_set("stream","");j_set(cu_state,"live",j_object());}
    if h_equal(action,"notice"){cu_set("pending_session_id","");cu_notice(cj_text(request,"text"));}
    if h_equal(action,"health_rationale"){cu_notice("Collie reads health sensor data only after this conversation has Sensors access and Android grants the required permission. Programs can return readings to the AI model and save them in this conversation. Revoke access in Collie Permissions or Android settings. No health sensors are accessed just by opening Collie.");}
    if h_equal(action,"event"){
        let event=cj_get(request,"event");let key=cj_text(event,"key");let node=ui_find(index,key);let type=cj_text(event,"type");
        if !node{return c_error("Stale or invalid UI event binding.");}let bound_action=load64(node+32);if !bound_action{bound_action="";}if !h_equal(bound_action,cj_text(event,"action")) || load64(node+88)!=cj_int(event,"action_id"){return c_error("Stale or invalid UI event binding.");}
        if h_equal(type,"link"){let p=cm_for_key(key);if !p && cm_enabled(){let ancestor=node;while ancestor && !p{if h_equal(load64(ancestor+8),"workspace-chat-body"){p=cws_panel(1);}ancestor=load64(ancestor+64);}}if p{cm_activate(cj_int(p,"id"));}command=cu_open_link(node,event);if cm_enabled(){command=cm_command(command,p);}}else{if !h_equal(type,"click") && !h_equal(type,"change") && !h_equal(type,"submit"){return c_error("Invalid UI event type.");}command=cm_event(event);}if j_get(command,"error"){return command;}
    }else if h_equal(action,"chat_focus") && cm_enabled(){
        let p=cws_panel(cj_int(request,"panel"));if p && h_equal(cj_text(p,"kind"),"chat"){cm_activate(cj_int(p,"id"));command=cm_command(cu_command("chat_activate"),p);}
    }else if h_equal(action,"workspace_dock") && cu_desktop(){
        if !cu_n("workspace_close") && !cu_n("workspace_menu") && !cj_int(cj_get(cu_state,"permission_request"),"request_id"){cws_move(cj_int(request,"panel"),cj_int(request,"group"),cj_int(request,"edge"));cu_int("workspace_drag_group",0);}
    }else if h_equal(action,"workspace_ratio") && cu_desktop(){
        let split=cws_find(cws_root(),cj_int(request,"split"));let ratio=cj_int(request,"ratio");if split && cj_get(split,"first"){if ratio<150{ratio=150;}if ratio>850{ratio=850;}j_set(split,"ratio",j_int(ratio));}
    }else if h_equal(action,"shortcut") && cu_desktop(){
        let shortcut=cj_text(request,"shortcut");let name="";
        if h_equal(shortcut,"new"){name="new_session";}else if h_equal(shortcut,"search"){name="desktop_search";}else if h_equal(shortcut,"sidebar"){name="desktop_sidebar";}else if h_equal(shortcut,"attach"){name="files";}else if h_equal(shortcut,"model"){name="model";}else if h_equal(shortcut,"composer"){name="desktop_chat";}
        if h_equal(shortcut,"terminal"){name="workspace_terminal";}else if h_equal(shortcut,"save"){name="workspace_save_active";}else if h_equal(shortcut,"find"){name="workspace_find_active";}else if h_equal(shortcut,"undo"){name="workspace_undo";}else if h_equal(shortcut,"redo"){name="workspace_redo";}
        if !h_len(name){return c_error("Unknown desktop shortcut.");}let event=j_object();j_set(event,"action",j_string(name));j_set(event,"type",j_string("click"));command=cm_event(event);
    }else if h_equal(action,"back"){if cu_desktop() && cu_n("workspace_close"){cu_int("workspace_close",0);}else if cu_desktop() && cu_n("workspace_menu"){cu_int("workspace_menu",0);}else if cu_desktop() && cu_n("workspace_drawer"){cu_int("workspace_drawer",0);}else{command=cu_back();}}
    else if h_equal(action,"preview"){
        cu_set("preview_back",cu_s("page"));cu_set("page","preview");j_set(cu_state,"preview",j_need(request,"file"));
    }
    if data && cj_get(data,"workers") && h_equal(cu_s("page"),"workers") && cu_n("worker"){
        command=cu_command("load_worker");j_set(command,"id",j_int(cu_n("worker")));
    }
    cm_packet_end(chat_frame,request);let next=cu_prepare();let out=j_object();j_set(out,"version",j_int(1));j_set(out,"state",cu_state);j_set(out,"ops",j_parse(ui_compiled_diff(old,next,index,ui_index)));j_set(out,"command",command);return out;
}
