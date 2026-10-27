import "thinking.flex";
fn cu_chat_hidden(){let page=cu_s("page");return h_equal(page,"settings") || (cu_desktop() && h_equal(page,"model") && h_equal(cu_s("model_return"),"settings")) || h_equal(page,"conversations") || h_equal(page,"workers") || h_equal(page,"permissions") || h_equal(page,"preview");}
fn cu_welcome(){let cards=cu_a("cards");let i=0;while i<j_count(cards){let card=j_at(cards,i);if !h_equal(cj_text(card,"kind"),"info") || !h_starts(cj_text(card,"text"),"App-private workspace ready."){return 0;}i=i+1;}return !h_len(cu_s("stream"));}
view welcome_screen(){
    column("welcome",padding:20,gap:16,align:"center"){
        image("welcome-mark",source:"resource:mipmap/ic_launcher",width:64,height:64);
        text("welcome-eyebrow",text:"A LITTLE HELP. A LOT POSSIBLE.",size:10,color:"#8e9d9f",align:"center");
        text("welcome-title",text:"What are we\nworking on?",size:29,color:"#edf2ed",font:"medium",align:"center");
        text("welcome-subtitle",text:"A thought partner with a workspace of its own.",size:14,color:"#8e9d9f",align:"center");
        use cu_action("suggest-plan","Make a plan","suggest_plan",0);
        use cu_action("suggest-workspace","Explore my workspace","suggest_workspace",0);
        if !cu_n("authenticated"){use cu_action("welcome-connect","Connect ChatGPT","import_auth",0);}
    }
}
view chat_screen(){
    column("chat",height:-1,background:"#10151a",hidden:cu_chat_hidden()){
        row("chat-header",padding_x:18,padding_y:12,gap:8){
            image("chat-mark",source:"resource:mipmap/ic_launcher",width:42,height:42);
            column("chat-identity",weight:1,gap:3){text("chat-title",text:"Collie",size:23,font:"medium",color:"#edf2ed");text("chat-model",text:cu_s("model"),size:12,color:"#8e9d9f");}
            button("chat-conversations",text:"☰",description:"Conversations",action:"conversations",align:"center",width:44,height:44,size:22,color:"#c5e3ae");
            button("chat-new",text:"＋",description:"New conversation",action:"new_session",align:"center",width:44,height:44,size:24,color:"#c5e3ae");
            button("chat-menu",text:"⋮",description:"Menu",action:"menu",align:"center",width:40,height:44,size:24,color:"#c5e3ae");
        }
        row("chat-status-row",padding_x:22,padding_y:5,gap:8){text("chat-dot",text:"●",size:9,color:cu_send_color());text("chat-status",text:cu_status(),size:12,color:"#8e9d9f",weight:1);text("chat-context",text:cu_context(),size:12,color:"#8e9d9f");}
        button("chat-workers",text:m_cat(m_cat("Workers · ",m_int(cu_active())),m_cat(" active · ",m_cat(m_int(j_count(cu_a("workers")))," total  ›"))),description:"View workers",action:"workers",color:"#c5e3ae",size:13,padding_x:22,min_height:40);
        if cu_n("continuation") && !cu_n("busy"){button("chat-continue",text:"Resume saved program  ›",description:"Resume saved program",action:"resume_main",size:14,color:"#c5e3ae",min_height:44);}
        progress("chat-context-meter",progress:cu_progress(),height:2,color:"#c5e3ae",background:"#232c33");
        scroll("chat-scroll",weight:1,follow:1,selection_scope:1){
            use chat_transcript();
        }
        use chat_composer();
    }
}

view chat_transcript(){
            column("chat-transcript",padding:18,gap:16){
                if cu_welcome(){use welcome_screen();}
                if cu_card_begin()>0{use cu_action("chat-older","Show earlier messages","older",0);}
                use cu_timeline(cu_a("cards"),cu_card_begin(),40,cu_chat_live(),"card-");
                if cu_n("card_offset")>0{use cu_action("chat-newer","Show newer messages","newer",0);}
                if h_len(cu_s("stream")){
                    column("chat-stream",gap:10){text("chat-stream-author",text:"Collie",size:13,color:"#c5e3ae");use cm_text("chat-stream-body",cu_s("stream"),16,"#edf2ed");}
                }
            }
}
view chat_composer(){
        column("composer",padding_x:16,padding_y:10,gap:8){
            if j_count(cu_a("attachments")){
                hscroll("composer-attachments"){
                    row("composer-attachment-row",gap:8){each index in cu_indices(cu_a("attachments"),0,4){use cu_file_tile(cu_k("attachment-",index),j_at(cu_a("attachments"),index),1,index);}}
                }
            }
            row("composer-input-row",padding:6,gap:4,background:"#191f25",radius:26,border_width:1,border_color:"#2c353b",focus_within:cu_desktop(),focus_border_width:2,focus_border_color:"#add98f",focus_background:"#1d2928"){
                button("composer-attach",text:"＋",description:"Attach file",action:"attachments",enabled:!cu_n("busy"),align:"center",width:44,height:44,color:"#c5e3ae",size:24);
                input("composer-draft",autocapitalize:"sentences",text:"Message Collie…",description:"Message Collie",value:cu_s("draft"),action:"draft",weight:1,max_lines:5,min_lines:1,ime:"send",padding:10,size:16,color:"#edf2ed",hint_color:"#8e9d9f");
                button("composer-send",text:cu_send_icon(),description:cu_send_label(),action:"send",enabled:cu_send_enabled(),align:"center",width:44,height:44,color:"#10151a",background:cu_send_color(),radius:22,size:22);
            }
        }
}
