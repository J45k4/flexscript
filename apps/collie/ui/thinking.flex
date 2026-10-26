import "components.flex";
fn cu_activity(card){let k=cj_text(card,"kind");return h_equal(k,"thinking") || h_equal(k,"source") || h_equal(k,"result") || h_equal(k,"worker_result") || h_equal(k,"progress") || h_equal(k,"feedback");}
fn cu_live_activity(live){return cj_int(live,"active") || j_count(cu_array(live,"summaries")) || h_len(cj_text(live,"source")) || h_len(cj_text(live,"feedback"));}
fn cu_chat_live(){let live=cu_copy(cj_get(cu_state,"live"));if cu_n("busy"){j_set(live,"active",j_int(1));j_set(live,"status",j_string(cu_s("status")));}return live;}
fn cu_panel(entries,prefix,turn,latest){let p=j_object();j_set(p,"kind",j_string("panel"));j_set(p,"key",j_string(cu_k(m_cat(prefix,"thinking-"),turn)));j_set(p,"latest",j_string(latest));j_set(p,"items",j_array());j_push(entries,p);return p;}
fn cu_timeline_items(cards,start,limit,live,prefix){
    let entries=j_array();let turn=0;let latest="";let panel=0;let i=0;
    while i<j_count(cards){let card=j_at(cards,i);let kind=cj_text(card,"kind");let visible=i>=start && i<start+limit;
        if h_equal(kind,"user"){turn=i;latest="";panel=0;}
        if h_equal(kind,"thinking"){latest=cj_text(card,"text");}
        if cu_activity(card){
            if visible && !panel{panel=cu_panel(entries,prefix,turn,latest);}
            if panel{j_set(panel,"latest",j_string(latest));}
            if visible{let row=j_object();let key=cj_text(card,"display_key");if !h_len(key){key=cu_k(prefix,i);}j_set(row,"key",j_string(key));j_set(row,"card",card);j_push(j_need(panel,"items"),row);}
        }else if visible{let row=j_object();j_set(row,"kind",j_string("message"));let key=cj_text(card,"display_key");if !h_len(key){key=cu_k(prefix,i);}j_set(row,"key",j_string(key));j_set(row,"card",card);j_push(entries,row);}
        i=i+1;
    }
    if start+limit>=j_count(cards) && cu_live_activity(live){
        if !panel{panel=cu_panel(entries,prefix,turn,latest);}j_set(panel,"live",live);let parts=cu_array(live,"summaries");i=0;while i<j_count(parts){let text=cj_text(j_at(parts,i),"text");if h_len(text){latest=text;}i=i+1;}j_set(panel,"latest",j_string(latest));
    }
    return cu_items(entries);
}
fn cu_thinking_description(key){if cu_expanded(cu_key(key,"-toggle")){return "Collapse thinking";}return "Expand thinking";}
fn cu_thinking_chevron(key){if cu_expanded(cu_key(key,"-toggle")){return "⌄";}return "›";}
fn cu_thinking_preview(panel){let text=cj_text(panel,"latest");if h_len(text){return cu_clip(h_trim(text),240);}let live=cj_get(panel,"live");if cj_int(live,"active"){if h_len(cj_text(live,"status")){return cj_text(live,"status");}if h_len(cj_text(live,"text")){return "Writing reply…";}return "Waiting for the model…";}if cu_live_activity(live){return "Working…";}return "Flexscript activity";}
view cu_activity_card(key,card){
    column(cu_key(key,"-activity"),gap:8){
    if h_equal(cj_text(card,"kind"),"thinking"){
        column(key,gap:6){text(cu_key(key,"-label"),text:"Summary",size:11,color:"#8e9d9f");text(cu_key(key,"-body"),text:cj_text(card,"text"),runs:cu_text_runs(cj_text(card,"text")),size:14,color:"#d8e2e7",selectable:1,line_height:4);}
    }else{if h_equal(cj_text(card,"kind"),"worker_result"){use cu_fold(cu_key(key,"-result"),"Show result",cj_text(card,"text"),0);}else{use cu_card(key,card);}}
    }
}
view cu_thinking_panel(panel){
    let key=cj_text(panel,"key");let live=cj_get(panel,"live");let preview=cu_thinking_preview(panel);
    column(key,padding:12,gap:12,background:"#191f25",radius:16,border_width:1,border_color:"#2c353b"){
        column(cu_key(key,"-toggle"),gap:6,min_height:44,action:"fold",description:cu_thinking_description(key)){
            row(cu_key(key,"-heading")){text(cu_key(key,"-title"),text:"Thinking",size:14,font:"medium",color:"#c5e3ae",weight:1);text(cu_key(key,"-arrow"),text:cu_thinking_chevron(key),size:20,color:"#8e9d9f");}
            text(cu_key(key,"-preview"),text:preview,runs:cu_text_runs(preview),size:13,color:"#8e9d9f",max_lines:2,line_height:3);
        }
        if cu_expanded(cu_key(key,"-toggle")){
            if cj_int(live,"active") && !j_count(cu_array(live,"summaries")) && !h_len(cj_text(live,"source")) && !h_len(cj_text(live,"feedback")) && !h_len(cj_text(panel,"latest")){
                text(cu_key(key,"-waiting"),text:"The model has not sent a public summary yet.",selectable:1,size:13,color:"#a4b2b5");
            }
            each row in cu_items(cu_array(panel,"items")){use cu_activity_card(cj_text(row,"key"),j_need(row,"card"));}
            each index in cu_indices(cu_array(live,"summaries"),0,128){
                let text=cj_text(j_at(cu_array(live,"summaries"),index),"text");
                if h_len(text){text(cu_key(key,cu_k("-live-summary-",index)),text:text,runs:cu_text_runs(text),selectable:1,size:14,color:"#d8e2e7",line_height:4);}
            }
            if h_len(cj_text(live,"source")){use cu_fold(cu_key(key,"-live-source"),"Generating Flexscript",cj_text(live,"source"),1);}
            if h_len(cj_text(live,"feedback")){text(cu_key(key,"-live-feedback"),text:cj_text(live,"feedback"),selectable:1,size:14,color:"#d8e2e7");}
        }
    }
}
view cu_timeline(cards,start,limit,live,prefix){
    column(cu_key(prefix,"timeline"),gap:16){
    each entry in cu_timeline_items(cards,start,limit,live,prefix){
        if h_equal(cj_text(entry,"kind"),"panel"){use cu_thinking_panel(entry);}else{use cu_card(cj_text(entry,"key"),j_need(entry,"card"));}
    }
    }
}
fn cu_worker_cards(){let rows=cu_a("worker_messages");let out=j_array();let i=0;while i<j_count(rows){let row=j_at(rows,i);let v=j_at(row,1);let kind=j_value(j_at(v,3));if h_equal(kind,"message"){kind="assistant";if h_equal(j_value(j_at(v,1)),"user"){kind="user";}}if h_equal(kind,"result"){kind="worker_result";}let card=j_object();j_set(card,"kind",j_string(kind));j_set(card,"text",j_at(v,2));j_set(card,"display_key",j_string(cu_k("worker-message-",j_value(j_at(row,0)))));j_push(out,card);i=i+1;}return out;}
fn cu_worker_live(){return cj_get(cj_get(cu_state,"worker_streams"),m_int(cu_n("worker")));}
