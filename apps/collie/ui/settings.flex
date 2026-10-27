// Desktop settings use ordinary page navigation, not a modal menu.
import "pages.flex";
fn cu_settings_section(){let section=cu_s("settings_section");if h_equal(section,"access") || h_equal(section,"account"){return section;}return "model";}
fn cu_settings_rail(){return cu_main_width()>=900;}
fn cu_settings_content_width(){let width=cu_main_width()-40;if cu_settings_rail(){width=width-184;}return width;}
fn cu_settings_visible(){return h_equal(cu_s("page"),"settings") || (h_equal(cu_s("page"),"model") && h_equal(cu_s("model_return"),"settings"));}
fn cu_settings_nav_bg(section){if h_equal(cu_settings_section(),section){return "#28382d";}return "#151c21";}
fn cu_settings_nav_weight(){if cu_settings_rail(){return 0;}return 1;}
fn cu_settings_model_label(){if cu_settings_rail(){return "Model & context";}return "Model";}
fn cu_settings_access_label(){return "Permissions";}
fn cu_settings_login_label(){return "Add OpenAI account…";}
fn cu_account_login_running(){return cj_int(cj_get(cu_state,"account_login"),"running");}
fn cu_account_login_color(){if h_equal(cj_text(cj_get(cu_state,"account_login"),"status"),"error"){return "#f1aaa6";}return "#c5e3ae";}
view desktop_account_login(){
    let login=cj_get(cu_state,"account_login");
    column("settings-signin",padding:18,gap:12,background:"#191f25",radius:12){
        text("settings-signin-title",text:"Sign in with ChatGPT",size:17,font:"medium",color:"#edf2ed");
        text("settings-signin-message",text:cj_text(login,"message"),size:14,color:"#a4b2b5");
        if h_len(cj_text(login,"code")){
            text("settings-signin-code-label",text:"Enter this one-time code on the sign-in page:",size:13,color:"#a4b2b5");
            text("settings-signin-code",text:cj_text(login,"code"),selectable:1,font:"mono",size:25,color:"#c5e3ae");
        }
        if h_len(cj_text(login,"url")){
            button("settings-signin-open",text:"Open sign-in page",action:"open_account_login",min_height:42,padding_x:12,size:14,color:"#10151a",background:"#c5e3ae",radius:9);
            button("settings-signin-copy",text:"Copy sign-in link",action:"copy_account_login",min_height:36,padding_x:12,size:13,color:"#a4b2b5");
        }
        if h_equal(cj_text(login,"method"),"browser"){button("settings-signin-device",text:"Use device code instead",action:"start_account_login",action_id:1,min_height:38,padding_x:12,size:13,color:"#c5e3ae");}
        else{button("settings-signin-browser",text:"Use browser sign-in instead",action:"start_account_login",action_id:0,min_height:38,padding_x:12,size:13,color:"#c5e3ae");}
        button("settings-signin-cancel",text:"Cancel sign-in",action:"cancel_account_login",min_height:38,padding_x:12,size:13,color:"#edf2ed",background:"#242d34",radius:9);
    }
}
fn cu_saved_account_name(entry){let name=cj_text(entry,"name");if !h_len(name){name=cj_text(entry,"email");}if !h_len(name){name=cj_text(entry,"account_id");}if !h_len(name){name="Saved account";}return name;}
fn cu_saved_account_border(entry){if cj_int(entry,"active"){return "#54734b";}return "#2c353b";}
view desktop_saved_account(entry){
    let key=cu_key("settings-saved-",cj_text(entry,"id"));
    column(key,padding:16,gap:10,background:"#191f25",radius:12,border_width:1,border_color:cu_saved_account_border(entry)){
        row(cu_key(key,"-heading"),gap:12){
            text(cu_key(key,"-name"),text:cu_saved_account_name(entry),size:16,font:"medium",color:"#edf2ed",weight:1,selectable:1);
            if cj_int(entry,"active"){text(cu_key(key,"-selected"),text:"Selected",size:13,color:"#c5e3ae");}
            else{button(cu_key("settings-account-use-",cj_text(entry,"id")),text:"Use account",description:cu_key("Use ",cu_saved_account_name(entry)),action:"select_account",enabled:!cu_n("busy") && !cu_n("account_busy") && !cu_account_login_running() && cj_int(entry,"available"),min_height:36,padding_x:12,size:13,color:"#edf2ed",background:"#28382d",radius:8);}
        }
        if h_len(cj_text(entry,"email")){text(cu_key(key,"-email"),text:cj_text(entry,"email"),selectable:1,size:14,color:"#a4b2b5");}
        if h_len(cj_text(entry,"plan")){text(cu_key(key,"-plan"),text:m_cat("Plan · ",cj_text(entry,"plan")),size:13,color:"#a4b2b5");}
        if !cj_int(entry,"available"){text(cu_key(key,"-missing"),text:"Login unavailable. Import this account again to reconnect.",size:13,color:"#f1aaa6");}
    }
}
view desktop_settings_nav_item(key,section,label,id){
    button(key,text:label,action:"settings_section",action_id:id,weight:cu_settings_nav_weight(),min_height:44,padding_x:10,max_lines:1,size:13,color:"#edf2ed",background:cu_settings_nav_bg(section),radius:9);
}
view desktop_settings_content(){
    column("settings-content",gap:18){
        if h_equal(cu_settings_section(),"model"){
            text("settings-model-title",text:"Model & context",size:24,font:"medium",color:"#edf2ed");
            text("settings-model-detail",text:"Choose the model for new replies and manage this conversation’s context.",size:14,color:"#a4b2b5");
            column("settings-model-card",padding:18,gap:12,background:"#191f25",radius:12){
                text("settings-model-label",text:"Response model",size:14,font:"medium",color:"#edf2ed");
                text("settings-model-current",text:cu_current_model_label(),size:16,color:"#c5e3ae");
                button("settings-model-change",text:"Choose model…",action:"model",enabled:!cu_n("busy"),min_height:42,padding_x:12,size:14,color:"#edf2ed",background:"#242d34",radius:9);
            }
            column("settings-context-card",padding:18,gap:12,background:"#191f25",radius:12){
                text("settings-context-title",text:"Conversation context",size:14,font:"medium",color:"#edf2ed");
                text("settings-context-usage",text:cu_context(),size:14,color:"#a4b2b5");
                text("settings-context-detail",text:"Summarize earlier messages to make room for new replies. Saved history and workspace files are kept.",size:13,color:"#a4b2b5");
                button("settings-context-compact",text:"Compact this conversation",action:"compact",enabled:!cu_n("busy"),min_height:42,padding_x:12,size:14,color:"#edf2ed",background:"#242d34",radius:9);
            }
        }
        if h_equal(cu_settings_section(),"access"){
            text("settings-access-title",text:"Permissions",size:24,font:"medium",color:"#edf2ed");
            text("settings-access-detail",text:"Permissions for this conversation and its workers. Choose Ask, Allow or Deny for each capability.",size:14,color:"#a4b2b5");
            text("settings-access-summary",text:cu_summary(),size:13,color:"#c5e3ae");
            each entry in cu_rows(){use permission_row(entry);}
            text("settings-access-note",text:"Changes are saved automatically for this conversation. Denying access blocks future calls; it does not erase information already in the chat.",size:12,color:"#a4b2b5");
        }
        if h_equal(cu_settings_section(),"account"){
            text("settings-account-title",text:"OpenAI accounts",size:24,font:"medium",color:"#edf2ed");
            text("settings-account-scope",text:"The selected account is used for messages, image generation and workers. Adding a login keeps your current selection.",size:14,color:"#a4b2b5");
            if cu_account_login_running(){use desktop_account_login();}
            if j_count(cu_a("accounts")){
                each entry in cu_items(cu_a("accounts")){use desktop_saved_account(entry);}
            }else{
            column("settings-account-card",padding:18,gap:12,background:"#191f25",radius:12){
                text("settings-account-provider",text:"ChatGPT",size:16,font:"medium",color:"#edf2ed");
                if cu_n("authenticated"){
                    if h_len(cj_text(cj_get(cu_state,"account"),"name")){text("settings-account-name",text:cj_text(cj_get(cu_state,"account"),"name"),selectable:1,size:18,font:"medium",color:"#edf2ed");}
                    if h_len(cj_text(cj_get(cu_state,"account"),"email")){text("settings-account-email",text:cj_text(cj_get(cu_state,"account"),"email"),selectable:1,size:14,color:"#edf2ed");}
                    if h_len(cj_text(cj_get(cu_state,"account"),"plan")){text("settings-account-plan",text:m_cat("Plan · ",cj_text(cj_get(cu_state,"account"),"plan")),size:13,color:"#a4b2b5");}
                    if !h_len(cj_text(cj_get(cu_state,"account"),"email")) && !h_len(cj_text(cj_get(cu_state,"account"),"name")) && h_len(cj_text(cj_get(cu_state,"account"),"account_id")){text("settings-account-id",text:m_cat("Account · ",cj_text(cj_get(cu_state,"account"),"account_id")),selectable:1,size:13,color:"#a4b2b5");}
                }
                if cu_n("authenticated"){text("settings-account-status",text:"Connected with your Codex login",size:14,color:"#c5e3ae");}
                else{text("settings-account-status",text:"Connect ChatGPT to send messages and generate images.",size:14,color:"#a4b2b5");}
            }
            }
            if !cu_account_login_running(){
                if h_len(cj_text(cj_get(cu_state,"account_login"),"message")){text("settings-account-login-result",text:cj_text(cj_get(cu_state,"account_login"),"message"),size:14,color:cu_account_login_color());}
                button("settings-account-login",text:cu_settings_login_label(),action:"start_account_login",action_id:0,enabled:!cu_n("busy") && !cu_n("account_busy"),min_height:44,padding_x:12,size:14,color:"#10151a",background:"#c5e3ae",radius:9);
                button("settings-account-device",text:"Sign in with device code",action:"start_account_login",action_id:1,enabled:!cu_n("busy") && !cu_n("account_busy"),min_height:40,padding_x:12,size:14,color:"#c5e3ae",background:"#191f25",radius:9);
                button("settings-account-import",text:"Import an existing login file…",action:"import_auth",enabled:!cu_n("busy") && !cu_n("account_busy"),min_height:36,padding_x:12,size:12,color:"#a4b2b5");
            }
            text("settings-account-detail",text:"Sign in securely through Codex using your browser or a one-time device code. Existing accounts stay selected until you choose Use account.",size:13,color:"#a4b2b5");
            if cu_n("account_busy"){text("settings-account-busy",text:"Stop active replies and workers before adding or switching accounts.",size:13,color:"#c5e3ae");}
        }
    }
}
view desktop_settings_screen(){
    column("settings",height:-1,background:"#10151a"){
        row("settings-header",padding_x:20,padding_y:12,gap:12){
            button("settings-back",text:"‹",description:"Back to conversation",action:"back",width:38,height:42,align:"center",size:28,color:"#c5e3ae");
            text("settings-title",text:"Settings",size:24,font:"medium",color:"#edf2ed",weight:1);
        }
        if cu_settings_rail(){
            row("settings-body",weight:1,padding:20,gap:24){
                column("settings-navigation",width:160,height:-1,gap:6){
                    use desktop_settings_nav_item("settings-nav-model","model",cu_settings_model_label(),0);
                    use desktop_settings_nav_item("settings-nav-access","access",cu_settings_access_label(),1);
                    use desktop_settings_nav_item("settings-nav-account","account","Account",2);
                }
                scroll("settings-scroll",weight:1,height:-1){use desktop_settings_content();}
            }
        }else{
            row("settings-navigation",padding_x:20,gap:4){
                use desktop_settings_nav_item("settings-nav-model","model",cu_settings_model_label(),0);
                use desktop_settings_nav_item("settings-nav-access","access",cu_settings_access_label(),1);
                use desktop_settings_nav_item("settings-nav-account","account","Account",2);
            }
            scroll("settings-scroll",weight:1){column("settings-body",padding:20){use desktop_settings_content();}}
        }
    }
}
