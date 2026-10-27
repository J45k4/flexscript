// Shared UI state helpers. Native hosts pass facts; events and effects live here.
import "permissions.flex";
import "../../../libs/ui/markdown-cache.flex";
global cu_state=0;
global cu_previews=0;
global cu_copies=0;
global cu_entries_all=0;
global cu_entries_matches=0;
fn cu_s(key){return cj_text(cu_state,key);}
fn cu_n(key){return cj_int(cu_state,key);}
fn cu_desktop(){return h_equal(cu_s("platform"),"linux");}
fn cu_sidebar(){return cu_desktop() && cu_n("viewport_width")>=960 && !cu_n("sidebar_collapsed");}
fn cu_sidebar_width(){let n=cu_n("sidebar_width");if n<1{n=252;}let limit=cu_n("viewport_width")-526;if limit>520{limit=520;}if limit<220{limit=220;}if n>limit{n=limit;}if n<220{n=220;}return n;}
fn cu_main_width(){let n=cu_n("viewport_width");if n<1{n=1000;}if cu_sidebar(){n=n-cu_sidebar_width()-6;}return n;}
fn cu_content_width(){let width=cu_n("panel_width");if width<1{width=cu_main_width();}let n=width-48;if n<160{n=160;}if n>820{n=820;}return n;}
fn cu_welcome_width(){let n=cu_content_width()-36;if n>480{n=480;}return n;}
fn cu_dialog_width(){let n=cu_main_width()-32;if n>560{n=560;}if n<240{n=240;}return n;}
fn cu_overlay_bg(){if cu_desktop(){return "#00000000";}return "#99000000";}
fn cu_model_id(index){if index==1{return "gpt-6-astra";}return "gpt-6.1-sol";}
fn cu_model_name(index){if index==1{return "GPT-6 Astra";}return "GPT-6.1 Sol";}
fn cu_current_model_label(){if h_equal(cu_s("model"),cu_model_id(0)){return cu_model_name(0);}if h_equal(cu_s("model"),cu_model_id(1)){return cu_model_name(1);}return cu_s("model");}
fn cu_model_search(text){let b=m_buffer();let i=0;while load8(text+i){let c=load8(text+i);if c>=65 && c<=90{c=c+32;}if (c>=97 && c<=122) || (c>=48 && c<=57){let p=m_take(1);store8(p,c);m_append(b,p,1);}i=i+1;}return m_data(b);}
fn cu_model_matches(index){let query=cu_model_search(cu_s("model_query"));if h_len(h_trim(cu_s("model_query"))) && !h_len(query){return 0;}return h_find(cu_model_search(m_cat(cu_model_name(index),cu_model_id(index))),query)>=0;}
fn cu_model_option_label(index){let prefix="";if h_equal(cu_s("model"),cu_model_id(index)){prefix="✓  ";}return m_cat(prefix,m_cat(cu_model_name(index),m_cat("\n",cu_model_id(index))));}
fn cu_model_option_bg(index){if h_equal(cu_s("model"),cu_model_id(index)){return "#28382d";}return "#232c33";}
fn cu_session_loading(){return h_len(cu_s("pending_session_id"))>0;}
fn cu_selected_session(){if cu_session_loading(){return cu_s("pending_session_id");}return cu_s("session_id");}
fn cu_project_name(){let name=cu_s("project_name");if h_len(name){return name;}return "Personal chats";}
fn cu_project_bg(id){if h_equal(id,cu_s("project_id")){return "#28382d";}return "#232c33";}
fn cu_project_list_height(){let n=j_count(cu_a("projects"))*100;let cap=cu_n("viewport_height")-390;if cap<96{cap=96;}if cap>360{cap=360;}if n>cap{n=cap;}return n;}
fn cu_chat_title(){let rows=cu_a("sessions");let i=0;while i<j_count(rows){let row=j_at(rows,i);if h_equal(cj_text(row,"id"),cu_selected_session()){return cu_clip(cj_text(row,"title"),70);}i=i+1;}return "New conversation";}
fn cu_array(o,key){let value=cj_get(o,key);if !value || j_kind(value)!=3{return j_array();}return value;}
fn cu_a(key){return cu_array(cu_state,key);}
fn cu_set(key,text){j_set(cu_state,key,j_string(text));return 0;}
fn cu_int(key,n){j_set(cu_state,key,j_int(n));return 0;}
fn cu_copy(o){let n=j_object();if o && j_kind(o)==4{let fields=j_value(o);let i=0;while i<h_count(fields){let pair=h_at(fields,i);j_set(n,load64(pair),load64(pair+8));i=i+1;}}return n;}
fn cu_merge(o,patch){if patch && j_kind(patch)==4{let fields=j_value(patch);let i=0;while i<h_count(fields){let pair=h_at(fields,i);j_set(o,load64(pair),load64(pair+8));i=i+1;}}return o;}
fn cu_k(prefix,id){return cu_key(prefix,m_int(id));}
fn cu_clip(text,limit){let n=h_len(text);if n<=limit{return text;}n=limit;while n>0 && (load8(text+n)&192)==128{n=n-1;}return m_cat(h_slice(text,n),"…");}
fn cu_lower(text){let n=h_len(text);let p=m_take(n+1);let i=0;while i<n{let c=load8(text+i);if c>=65 && c<=90{c=c+32;}store8(p+i,c);i=i+1;}return p;}
fn cu_has(text,query){return h_find(cu_lower(text),cu_lower(query))>=0;}
fn cu_items(array){let list=ui_items();let i=0;while i<j_count(array){ui_item_add(list,j_at(array,i));i=i+1;}return list;}
fn cu_indices(array,start,limit){let list=ui_items();let i=start;while i<j_count(array) && i<start+limit{ui_item_add(list,i);i=i+1;}return list;}
fn cu_expanded(key){let object=cj_get(cu_state,"expanded");if !object || j_kind(object)!=4{return 0;}return cj_int(object,key);}
fn cu_toggle(key){let object=cu_copy(cj_get(cu_state,"expanded"));j_set(object,key,j_bool(!cu_expanded(key)));j_set(cu_state,"expanded",object);return 0;}
fn cu_text_runs(text){if cu_desktop(){return rt_cached_markdown_tables(text);}return rt_markdown(text);}
fn cu_code_runs(text){return rt_code(text,"#c5e3ae","#e6c3a6","#c9b5e8","#8e9d9f");}
fn cu_line_count(text){let n=h_len(text);let count=1;let i=0;while i<n{if load8(text+i)==10{count=count+1;}i=i+1;}return count;}
fn cu_line_numbers(text){let b=m_buffer();let count=cu_line_count(text);let i=1;while i<=count{if i>1{m_text(b,"\n");}m_text(b,m_int(i));i=i+1;}return m_data(b);}
fn cu_line_label(text){let count=cu_line_count(text);let suffix=" lines";if count==1{suffix=" line";}return m_cat(m_int(count),suffix);}
fn cu_fold_label(title,expanded){if !expanded{return title;}if h_equal(title,"Show program"){return "Hide program";}if h_starts(title,"▸ "){return m_cat("▾ ",title+4);}return title;}
fn cu_copy_label(code){if code{return "Copy program";}return "Copy result";}
fn cu_register(list,value){ui_item_add(list,value);return load64(list);}
fn cu_preview(view){return cu_register(cu_previews,view);}
fn cu_copy_text(text){return cu_register(cu_copies,text);}
fn cu_size(n){if n<1024{return m_cat(m_int(n)," B");}return m_cat(m_int((n+512)/1024)," KB");}
fn cu_short(n){if n<1000{return m_int(n);}if n<10000{return m_cat(m_cat(m_int(n/1000),m_cat(".",m_int(n/100%10))),"k");}return m_cat(m_int((n+500)/1000),"k");}
fn cu_context(){if cu_n("context_unavailable"){return "Context unavailable";}return m_cat(m_cat(m_cat(m_cat("Context ",cu_context_estimate()),cu_short(cu_n("used"))),m_cat(" / ",cu_short(cu_n("total")))),"");}
fn cu_status(){let s=cu_s("status");if h_len(s){return s;}if cu_n("busy"){return "Working…";}return "Ready";}
fn cu_active(){let rows=cu_a("workers");let i=0;let n=0;while i<j_count(rows){let value=j_at(j_at(rows,i),1);if !cu_terminal(j_value(j_at(value,2))){n=n+1;}i=i+1;}return n;}
fn cu_terminal(status){return h_equal(status,"done") || h_equal(status,"failed") || h_equal(status,"cancelled") || h_equal(status,"paused");}
fn cu_worker(){let rows=cu_a("workers");let i=0;while i<j_count(rows){let row=j_at(rows,i);if j_value(j_at(row,0))==cu_n("worker"){return j_at(row,1);}i=i+1;}return 0;}
fn cu_worker_rows(){let rows=cu_a("workers");let out=ui_items();let phase=0;while phase<2{let i=j_count(rows);while i>0{i=i-1;let row=j_at(rows,i);let v=j_at(row,1);let status=j_value(j_at(v,2));let first=!cu_terminal(status) || h_equal(status,"paused");if first==(phase==0){ui_item_add(out,row);}}phase=phase+1;}return out;}
fn cu_worker_preview(v){let text=j_value(j_at(v,4));if !h_len(text){text=j_value(j_at(v,3));}if !h_len(text){text=j_value(j_at(v,1));}return cu_clip(text,180);}
fn cu_filter_sessions(){
    let rows=cu_a("sessions");let out=ui_items();let query=h_trim(cu_s("query"));let skip=cu_n("session_offset");let matches=0;let all=0;let i=0;
    while i<j_count(rows){let row=j_at(rows,i);if !cu_desktop() || h_equal(cj_text(row,"project_id"),cu_s("project_id")){all=all+1;if !h_len(query) || cu_has(m_cat(cj_text(row,"title"),cj_text(row,"preview")),query){if matches>=skip && load64(out)<50{ui_item_add(out,row);}matches=matches+1;}}i=i+1;}
    cu_entries_all=all;cu_entries_matches=matches;return out;
}
fn cu_session_count(){if cu_n("sessions_loading"){return "Loading conversations…";}if h_len(h_trim(cu_s("query"))){return m_cat(m_cat(m_int(cu_entries_matches),m_cat(" of ",m_int(cu_entries_all)))," conversations");}let suffix=" conversations";if cu_entries_all==1{suffix=" conversation";}return m_cat(m_int(cu_entries_all),suffix);}
fn cu_observation(card){let o=cj_get(card,"observation");if !o || j_kind(o)!=4{return 0;}return o;}
fn cu_result_state(o){let state=cj_text(o,"state");if h_equal(state,"rejected"){return "Rejected";}if h_equal(state,"error"){return "Error";}if h_equal(state,"waiting"){return "Waiting";}if cj_int(o,"exit_code")==0{return "Completed";}return m_cat("Exit ",uv_number(cj_int(o,"exit_code")));}
fn cu_send_enabled(){return cu_n("busy") || h_len(h_trim(cu_s("draft"))) || j_count(cu_a("attachments"));}
fn cu_send_label(){if cu_n("busy"){return "Stop response";}return "Send message";}
fn cu_send_icon(){if cu_n("busy"){return "■";}return "↑";}
fn cu_send_color(){if cu_n("busy"){return "#f1aaa6";}return "#c5e3ae";}
fn cu_card_begin(){let n=j_count(cu_a("cards"));let start=n-40-cu_n("card_offset");if start<0{start=0;}return start;}
fn cu_model_valid(text){let n=h_len(text);if n<1 || n>120{return 0;}let i=0;while i<n{let c=load8(text+i);if !((c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)||c==46||c==95||c==45){return 0;}i=i+1;}return 1;}

fn cu_session_bg(entry){if cj_int(entry,"current"){return "#202c25";}return "#191f25";}
fn cu_role_title(role){if h_equal(role,"user"){return "Task from Collie";}return "Assistant";}
fn cu_view_label(file,mode){let image=h_equal(cj_text(file,"type"),"image");if mode==0{if image{return "Open image: ";}return "Open file: ";}if mode==1{if image{return "Image · ";}return "File · ";}if image{return "Open image";}return "Open file";}
fn cu_worker_title(){let selected=cu_worker();if selected{return j_value(j_at(selected,0));}return "Workers";}
fn cu_worker_subtitle(){let selected=cu_worker();if selected{return m_cat(m_cat("Worker #",m_int(cu_n("worker"))),m_cat(" · ",j_value(j_at(selected,2))));}return m_cat(m_cat(m_int(cu_active())," active · "),m_cat(m_int(j_count(cu_a("workers")))," total · tap a worker to view messages"));}

fn cu_context_estimate(){if cu_n("estimated"){return "~";}return "";}
fn cu_progress(){let total=cu_n("total");if total<1{return 0;}let value=cu_n("used")*1000/total;if value>1000{value=1000;}return value;}

fn cu_model_network_bg(mode){let current=cu_s("model_network");if !h_len(current){current="default";}if h_equal(current,mode){return "#354b3a";}return "#242d34";}

fn cu_preview_hint(){if cu_desktop(){return " · Scroll to zoom, drag to pan";}return " · Pinch to zoom";}
