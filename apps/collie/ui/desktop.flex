// Desktop presentation shares chat cards, composer, pages and event policy.
import "chat.flex";
import "sidebar.flex";
import "settings.flex";
view desktop_project_row(entry){
    let id=cj_text(entry,"id");let key=cu_key("project-",id);
    column(key,padding:12,gap:5,background:cu_project_bg(id),radius:10,action:"select_project",description:cj_text(entry,"path")){
        text(cu_key(key,"-name"),text:cj_text(entry,"name"),font:"medium",size:15,color:"#edf2ed");
        text(cu_key(key,"-path"),text:cj_text(entry,"path"),size:12,color:"#a4b2b5");
    }
}
view desktop_projects_screen(){
    column("projects-overlay",height:-1,background:cu_overlay_bg()){
        column("projects-spacer",weight:1,action:"back");
        column("projects-panel",padding:22,gap:14,background:"#191f25",radius:20){
            text("projects-title",text:"Projects",size:24,font:"medium",color:"#edf2ed");
            text("projects-detail",text:"Choose a folder for a project. Its conversations share the files in that folder.",size:14,color:"#a4b2b5");
            button("project-personal",text:"Personal chats",action:"select_project",padding:12,min_height:44,size:15,color:"#edf2ed",background:cu_project_bg(""),radius:10);
            scroll("projects-scroll",height:cu_project_list_height()){
                column("projects-list",gap:8){each index in cu_indices(cu_a("projects"),0,128){use desktop_project_row(j_at(cu_a("projects"),index));}}
            }
            button("projects-add",text:"Choose folder…",action:"choose_project_folder",padding:12,min_height:44,size:15,color:"#10151a",background:"#c5e3ae",radius:10);
            button("projects-cancel",text:"Cancel",action:"back",min_height:38,size:14,color:"#c5e3ae");
        }
        column("projects-bottom",weight:1);
    }
}
view desktop_welcome(){
    column("desktop-welcome",padding_y:28,gap:18){
        column("desktop-welcome-space",height:36);
        row("desktop-welcome-brand-row"){
            column("desktop-welcome-brand-left",weight:1);
            image("desktop-welcome-mark",source:"resource:mipmap/ic_launcher",width:64,height:64);
            column("desktop-welcome-brand-right",weight:1);
        }
        text("welcome-title",text:"What are we working on?",size:30,font:"medium",align:"center",color:"#edf2ed");
        text("welcome-subtitle",text:"Ask a question, bring a file, or start a project.",size:14,align:"center",color:"#a4b2b5");
        row("desktop-welcome-actions-row"){
            column("desktop-welcome-actions-left",weight:1);
            column("desktop-welcome-actions",width:cu_welcome_width(),gap:10){
                row("desktop-welcome-actions-buttons",gap:10){
                    button("suggest-plan",text:"Make a plan",action:"suggest_plan",weight:1,min_height:44,padding_x:14,size:14,color:"#edf2ed",background:"#202c33",radius:10,align:"center");
                    button("suggest-workspace",text:"Explore workspace",action:"suggest_workspace",weight:1,min_height:44,padding_x:14,size:14,color:"#edf2ed",background:"#202c33",radius:10,align:"center");
                }
                if !cu_n("authenticated"){button("welcome-connect",text:"Connect ChatGPT",action:"start_account_login",min_height:44,padding_x:14,size:14,color:"#10151a",background:"#c5e3ae",radius:10,align:"center");}
            }
            column("desktop-welcome-actions-right",weight:1);
        }
    }
}
fn cu_desktop_transcript_align(){if cu_welcome(){return "center";}return "start";}
view desktop_chat_transcript(){
    column("chat-transcript",width:cu_content_width(),height:-1,align:cu_desktop_transcript_align(),padding:18,gap:18){
        if cu_welcome(){use desktop_welcome();}
        if cu_card_begin()>0{use cu_action("chat-older","Show earlier messages","older",0);}
        use cu_timeline(cu_a("cards"),cu_card_begin(),40,cu_chat_live(),"card-");
        if cu_n("card_offset")>0{use cu_action("chat-newer","Show newer messages","newer",0);}
        if h_len(cu_s("stream")){
            column("chat-stream",gap:10){text("chat-stream-author",text:"Collie",size:14,color:"#c5e3ae");text("chat-stream-body",text:cu_s("stream"),runs:cu_text_runs(cu_s("stream")),selectable:1,size:16,color:"#edf2ed",line_height:5);}
        }
    }
}
view desktop_session_loading(){
    column("desktop-session-loading",width:cu_content_width(),padding:24){
        text("desktop-session-loading-label",text:"Loading conversation…",size:14,color:"#a4b2b5");
    }
}
view desktop_chat_screen(){
    column("chat",height:-1,background:"#10151a",hidden:cu_chat_hidden()){
        row("chat-header",padding_x:20,padding_y:12,gap:12){
            button("desktop-toggle",text:"☰",description:"Toggle sidebar · Ctrl+B",action:"desktop_sidebar",width:34,height:34,align:"center",size:18,color:"#a4b2b5");
            text("chat-title",text:cu_chat_title(),max_lines:1,size:15,font:"medium",color:"#edf2ed",weight:1);
            if !cm_enabled() && !cu_sidebar(){button("chat-project",text:cu_project_name(),action:"projects",enabled:!cu_n("busy"),min_height:34,padding_x:8,size:12,color:"#c5e3ae");}
            if !cm_enabled() && !cu_sidebar(){button("chat-conversations",text:"Chats",description:"Conversations · Ctrl+K",action:"conversations",min_height:34,size:12,color:"#c5e3ae");button("chat-new",text:"＋",description:"New conversation · Ctrl+N",action:"new_session",enabled:!cu_n("busy"),width:34,height:34,align:"center",size:22,color:"#c5e3ae");}
            if (!cm_enabled() && cu_main_width()>=640) || (cm_enabled() && cu_n("panel_width")>=420){
            button("desktop-model",text:cu_current_model_label(),description:"Choose model · Ctrl+,",action:"model",enabled:!cu_n("busy"),min_height:34,padding_x:10,size:12,color:"#c5e3ae",background:"#19232a",radius:8);
            }
            if !cm_enabled() && !cu_sidebar(){use desktop_settings_icon("chat-menu");}
        }
        row("chat-status-row",padding_x:26,padding_y:5,gap:8){text("chat-dot",text:"●",size:8,color:cu_send_color());text("chat-status",text:cu_status(),size:12,color:"#a4b2b5",weight:1);if !cu_sidebar(){button("chat-workers",text:m_cat("Workers · ",m_int(cu_active())),action:"workers",size:12,min_height:24,color:"#a4b2b5");}text("chat-context",text:cu_context(),size:12,color:"#a4b2b5");}
        if cu_n("continuation") && !cu_n("busy"){button("chat-continue",text:"Resume saved program  ›",description:"Resume saved program",action:"resume_main",size:14,color:"#c5e3ae",min_height:36,padding_x:26);}
        progress("chat-context-meter",progress:cu_progress(),height:1,color:"#5e8065",background:"#1d272e");
        scroll("chat-scroll",weight:1,follow:1,selection_scope:1){
            row("desktop-transcript-lane"){
                column("desktop-transcript-left",weight:1);
                if cu_session_loading(){use desktop_session_loading();}else{use desktop_chat_transcript();}
                column("desktop-transcript-right",weight:1);
            }
        }
        if !cu_session_loading(){row("desktop-composer-lane",padding_y:6){
            column("desktop-composer-left",weight:1);
            column("desktop-composer",width:cu_content_width(),gap:2){
                use chat_composer();
                text("desktop-composer-help",text:"Enter to send · Shift+Enter for a new line · Ctrl+O to attach",size:12,color:"#9aabb0",align:"center",padding_y:5);
            }
            column("desktop-composer-right",weight:1);
        }}
    }
}
