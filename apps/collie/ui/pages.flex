import "thinking.flex";
view conversation_row(entry){
    let key=cu_key("session-",cj_text(entry,"id"));let bg=cu_session_bg(entry);
    column(key,padding:16,gap:9,background:bg,radius:16,border_width:1,border_color:"#2c353b",action:"open_session",description:cj_text(entry,"title")){
        row(cu_key(key,"-heading")){
            text(cu_key(key,"-title"),text:cj_text(entry,"title"),max_lines:1,font:"medium",size:16,color:"#edf2ed",weight:1);
            if cj_int(entry,"current"){text(cu_key(key,"-current"),text:"Current",size:10,color:"#c5e3ae");}
        }
        text(cu_key(key,"-preview"),text:cj_text(entry,"preview"),max_lines:2,size:13,color:"#8e9d9f",line_height:3);
        text(cu_key(key,"-date"),timestamp:cj_int(entry,"updated"),size:11,color:"#8e9d9f");
    }
}
view conversations_screen(){
    let rows=cu_filter_sessions();
    column("conversations",height:-1,background:"#10151a"){
        use cu_header("conversations","Conversations","Back to conversation");
        row("conversations-controls",padding_x:18,gap:8){
            input("conversations-query",text:"Search conversations",description:"Search conversations",value:cu_s("query"),action:"query",weight:1,single_line:1,ime:"done",size:15,color:"#edf2ed",hint_color:"#8e9d9f",padding:12,background:"#191f25",radius:16);
            button("conversations-clear",text:"×",description:"Clear search",action:"clear_search",align:"center",width:42,height:44,color:"#c5e3ae",size:22);
            button("conversations-new",text:"＋",description:"New conversation",action:"new_session",align:"center",width:44,height:44,color:"#c5e3ae",size:24);
        }
        text("conversations-count",text:cu_session_count(),size:12,color:"#8e9d9f",padding:18);
        scroll("conversations-scroll",weight:1){
            column("conversations-list",padding_x:18,padding_y:8,gap:10){
                if h_len(cu_s("sessions_error")){text("conversations-error",text:cu_s("sessions_error"),size:14,color:"#f1aaa6");}
                if !load64(rows){
                    if cu_n("sessions_loading"){text("conversations-empty",text:"Loading conversations…",size:20,color:"#edf2ed");}
                    else{if h_len(cu_s("query")){text("conversations-empty",text:"No conversations found",size:20,color:"#edf2ed");text("conversations-empty-detail",text:"Try a different title or message.",size:14,color:"#8e9d9f");}
                    else{text("conversations-empty",text:"No conversations yet",size:20,color:"#edf2ed");text("conversations-empty-detail",text:"Start a new conversation with the + button.",size:14,color:"#8e9d9f");}}
                }
                each entry in rows{use conversation_row(entry);}
                row("conversations-pager",gap:12){
                    if cu_n("session_offset")>0{use cu_action("conversations-previous","Previous","sessions_previous",0);}
                    if cu_n("session_offset")+50<cu_entries_matches{use cu_action("conversations-next","Next","sessions_next",0);}
                }
            }
        }
    }
}
view worker_row(row){
    let id=j_value(j_at(row,0));let v=j_at(row,1);let status=j_value(j_at(v,2));let title=m_cat(j_value(j_at(v,0)),m_cat(" · ",status));let body=m_cat(m_cat("#",m_int(id)),m_cat("\n",cu_worker_preview(v)));
    column(cu_k("worker-",id),padding:16,gap:7,background:"#191f25",radius:16,border_width:1,border_color:"#2c353b",action:"worker",action_id:id,description:m_cat(title,m_cat(". ",m_cat(body,". Open worker")))){
        text(cu_k("worker-title-",id),text:title,size:16,color:"#c5e3ae",font:"medium");
        text(cu_k("worker-preview-",id),text:body,size:14,color:"#8e9d9f",max_lines:4);
    }
}
view workers_screen(){
    let selected=cu_worker();let title=cu_worker_title();let subtitle=cu_worker_subtitle();
    column("workers-page",height:-1,background:"#10151a"){
        use cu_header("workers",title,"Back from workers");
        text("workers-subtitle",text:subtitle,padding_x:22,padding_y:10,size:13,color:"#8e9d9f");
        if selected{
            row("workers-actions",padding_x:18,padding_y:8,gap:8){
                if h_equal(j_value(j_at(selected,2)),"paused"){use cu_action("worker-resume","Resume worker","resume_worker",cu_n("worker"));}
                if !cu_terminal(j_value(j_at(selected,2))){use cu_action("worker-stop","Stop worker","cancel_worker",cu_n("worker"));}
            }
        }
        scroll("workers-scroll",weight:1){
            column("workers-content",padding:18,gap:12){
                if h_len(cu_s("workers_error")){text("workers-problem",text:cu_s("workers_error"),color:"#f1aaa6",size:14);}
                if selected{
                    if h_len(j_value(j_at(selected,4))){text("worker-error",text:j_value(j_at(selected,4)),color:"#f1aaa6",size:14);}
                    use cu_timeline(cu_worker_cards(),0,1000,cu_worker_live(),cu_k("worker-",cu_n("worker")));
                    if h_len(cj_text(cu_worker_live(),"text")){text("worker-stream-reply",text:cj_text(cu_worker_live(),"text"),runs:cu_text_runs(cj_text(cu_worker_live(),"text")),size:15,color:"#edf2ed");}
                }else{
                    if !j_count(cu_a("workers")){
                        text("workers-welcome",text:"A little help from the pack",color:"#c5e3ae",size:20);
                        text("workers-welcome-detail",text:"Collie can start workers for independent tasks. Their progress and conversations appear here.",color:"#8e9d9f",size:14);
                    }
                    each row in cu_worker_rows(){use worker_row(row);}
                }
            }
        }
    }
}
view preview_screen(){
    let file=cj_get(cu_state,"preview");let path=cj_text(file,"path");let image=h_len(cj_text(file,"image_id"));
    column("preview-page",height:-1,background:"#10151a",padding:18,gap:12){
        row("preview-header",gap:10){text("preview-title",text:path,size:18,color:"#edf2ed",weight:1);button("preview-close",text:"Close",description:"Close preview",action:"back",min_height:48,color:"#c5e3ae",size:14);}
        if image{
            text("preview-size",text:m_cat(m_cat(m_int(cj_int(file,"width")),m_cat(" × ",m_int(cj_int(file,"height"))))," · Pinch to zoom"),size:12,color:"#8e9d9f");
            image("preview-image",source:cu_key("preview:",cj_text(file,"image_id")),description:cu_key("Full image: ",path),zoom:1,weight:1);
        }else{
            text("preview-range",text:m_cat(m_cat("Bytes ",m_int(cj_int(file,"offset"))),m_cat("–",m_int(cj_int(file,"offset")+cj_int(file,"bytes")))),size:12,color:"#8e9d9f");
            scroll("preview-scroll",weight:1){text("preview-text",text:cj_text(file,"text"),font:"monospace",selectable:1,size:14,color:"#edf2ed",padding_y:16,line_height:4);}
        }
    }
}
view model_screen(){
    column("model-overlay",height:-1,background:"#99000000"){
        column("model-spacer",weight:1,action:"back");
        column("model-panel",padding:20,gap:14,background:"#191f25",radius:24){
            text("model-title",text:"Choose a model",size:22,font:"medium",color:"#edf2ed");
            input("model-input",text:"Model",description:"Model",value:cu_s("model_input"),action:"model_input",single_line:1,color:"#edf2ed",hint_color:"#8e9d9f",size:16,padding:12,background:"#232c33",radius:12);
            if h_len(cu_s("model_error")){text("model-error",text:cu_s("model_error"),color:"#f1aaa6",size:13);}
            text("model-network-label",text:"Model connection",size:14,color:"#8e9d9f");
            text("model-network-detail",text:"Choose the internet connection Collie uses. Programs select their own networks separately.",size:12,color:"#8e9d9f");
            row("model-network-choices",gap:6){
                button("model-network-default",text:"Auto",action:"model_network",action_id:0,weight:1,min_height:48,color:"#c5e3ae",background:cu_model_network_bg("default"),radius:10,align:"center");
                button("model-network-wifi",text:"Wi-Fi",action:"model_network",action_id:1,weight:1,min_height:48,color:"#c5e3ae",background:cu_model_network_bg("wifi"),radius:10,align:"center");
                button("model-network-cellular",text:"Cellular",action:"model_network",action_id:2,weight:1,min_height:48,color:"#c5e3ae",background:cu_model_network_bg("cellular"),radius:10,align:"center");
                button("model-network-ethernet",text:"Ethernet",action:"model_network",action_id:3,weight:1,min_height:48,color:"#c5e3ae",background:cu_model_network_bg("ethernet"),radius:10,align:"center");
            }
            use cu_action("model-save","Save","save_model",0);
            use cu_action("model-cancel","Cancel","back",0);
        }
    }
}
view menu_screen(){
    column("menu-overlay",height:-1,background:"#99000000"){
        column("menu-spacer",weight:1,action:"back");
        column("menu-panel",padding:20,gap:10,background:"#191f25",radius:24){
            text("menu-title",text:"Your workspace",size:22,font:"medium",color:"#edf2ed");
            if cu_n("authenticated"){text("menu-login",text:m_cat("ChatGPT login saved · ",cu_s("model")),size:13,color:"#8e9d9f");}
            else{text("menu-login",text:"Connect ChatGPT to start a conversation.",size:13,color:"#8e9d9f");}
            use cu_action("menu-new","New conversation","new_session",0);
            use cu_action("menu-conversations","Conversations","conversations",0);
            use cu_action("menu-permissions","Permissions","permissions",0);
            use cu_action("menu-model",m_cat("Model · ",cu_s("model")),"model",0);
            use cu_action("menu-compact","Compact context","compact",0);
            if cu_n("authenticated"){use cu_action("menu-login-button","Update ChatGPT login","import_auth",0);}
            else{use cu_action("menu-login-button","Connect ChatGPT","import_auth",0);}
        }
    }
}
view attachment_menu(){
    column("attachment-overlay",height:-1,background:"#99000000"){
        column("attachment-spacer",weight:1,action:"back");
        column("attachment-panel",padding:20,gap:12,background:"#191f25",radius:24){
            text("attachment-title",text:"Add attachment",size:22,font:"medium",color:"#edf2ed");
            text("attachment-subtitle",text:"Choose a photo, take one, or attach a file.",size:13,color:"#8e9d9f");
            use cu_action("attachment-gallery","Gallery","gallery",0);
            use cu_action("attachment-camera","Camera","camera",0);
            use cu_action("attachment-files","Files","files",0);
            use cu_action("attachment-cancel","Cancel","back",0);
        }
    }
}
