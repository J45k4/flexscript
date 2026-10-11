// Chat application built on libs/tui; inference lives in a reusable child worker.
import "chat.flex";
import "../../tui/tui.flex";
global lc_binary=0;
global lc_checkpoint=0;
global lc_compiler=0;
global lc_backend=0;
global lc_weights=0;
global lc_device=0;
global lc_capacity=4096;
global lc_capacity_auto=1;
global lc_maximum=0;
global lc_temperature=0;
global lc_thinking=0;
global lc_demo=0;
global lc_history=0;
global lc_session=0;
global lc_messages=0;
global lc_worker=0;
global lc_ready=0;
global lc_busy=0;
global lc_downloading=0;
global lc_status=0;
global lc_stats=0;
global lc_reply=0;
global lc_reply_buffer=0;
global lc_scroll=0;
global lc_clear_at=0;
global lc_select_scope=0;
global lc_select_start=0;
global lc_select_end=0;
global lc_dirty=1;
global lc_running=1;
global lc_log=0;
global lc_show_log=0;
global lc_scratch=0;
global lc_commands=0;
global lc_send_buffer=0;
global lc_sent=0;
global lc_panel_title=0;
global lc_panel_text=0;
global lc_panel_scroll=0;
global lc_panel_top=0;
global lc_panel_preview=0;
global lc_progress_done=0;
global lc_progress_total=0;
global lc_stage_started=0;
global lc_activity_tick=0;
global lc_worker_error=0;
fn lc_active() {return lc_worker && (!lc_ready || lc_busy || lc_downloading);}
fn lc_stage(text,done,total) {if !lc_status || !h_equal(text,lc_status) {lc_stage_started=net_now();}lc_status=text;lc_progress_done=done;lc_progress_total=total;lc_dirty=1;return 0;}
fn lc_activity(out,tick) {
    if lc_active() {let spinner=h_slice("|/-\\"+(tick/100)%4,1);let seconds=(tick-lc_stage_started)/1000;
        tu_line(out,2,h_cat3(spinner," ",h_cat3(tu_clean(lc_status)," | ",h_cat(h_int(seconds),"s | Esc stop"))),"33");tw_progress(out,3,lc_progress_done,lc_progress_total,tick);}
    else {tu_line(out,2,tu_clean(lc_status),"33");tu_line(out,3,h_repeat("-",tu_cols),"90");}return 0;
}
fn lc_animate(tick) {let mark=tu_mark();let out=h_buffer();h_text(out,tu_ansi("@[s@[?25l"));lc_activity(out,tick);h_text(out,tu_ansi("@[u@[?25h"));h_print(1,h_data(out));tu_reset(mark);lc_activity_tick=tick;return 0;}
fn lc_queue(text) {if !lc_send_buffer {lc_send_buffer=h_buffer();}h_text(lc_send_buffer,text);return 0;}
fn lc_menu(title,text) {lc_panel_title=title;lc_panel_text=tu_clean(text);lc_panel_scroll=0;lc_panel_preview=0;lc_select_scope=0;lc_dirty=1;return 0;}
fn lc_models_text() {let state="missing; /download to install";if lc_checkpoint_ready() || lc_demo {state="downloaded";}return h_cat3("qwen3-1.7b | ",state,h_cat3("\nCheckpoint: ",lc_checkpoint,"\nQwen3 text recipe; 16-bit weights, FP32 KV cache."));}
fn lc_preview_update() {
    let text=h_trim(h_data(te_text));if h_equal(text,"/models") || h_equal(text,"/model") || h_starts(text,"/model ") {if !lc_panel_preview {lc_menu("Models",lc_models_text());lc_panel_preview=1;}}
    else if lc_panel_preview {lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;}return 0;
}
fn lc_menu_scroll(delta) {let mark=tu_mark();let eh=h_count(ts_wrap(h_data(te_text),tu_cols));if eh>5 {eh=5;}let body=tu_rows-eh-7;let last=h_count(ts_wrap(lc_panel_text,tu_cols))-body;if last<0 {last=0;}
    lc_panel_scroll=lc_panel_scroll+delta;if lc_panel_scroll>last {lc_panel_scroll=last;}if lc_panel_scroll<0 {lc_panel_scroll=0;}tu_reset(mark);lc_dirty=1;return 0;}
fn lc_save() {
    let data=j_object();j_set(data,"version",j_int(1));j_set(data,"id",j_string(lc_session));j_set(data,"model",j_string("qwen3-1.7b"));j_set(data,"thinking",j_int(lc_thinking));j_set(data,"messages",lc_messages);
    let file=h_join(lc_history,h_cat(lc_session,".json"));let temporary=h_cat(file,".tmp");let text=j_dump(data);let fd=syscall(2,temporary,0x80241,384,0,0,0);
    if fd<0 {lc_status="Could not save this session.";return 0;}let written=h_write(fd,text,h_len(text));let synced=syscall(74,fd,0,0,0,0,0);h_close(fd);
    if written<0 || synced<0 || syscall(82,temporary,file,0,0,0,0)!=0 {syscall(87,temporary,0,0,0,0,0);lc_status="Could not save this session.";}return 0;
}
fn lc_new() {lc_session=h_cat3(h_int(syscall(201,0,0,0,0,0,0)),"-",h_cat3(h_int(syscall(39,0,0,0,0,0,0)),"-",h_int(net_now())));lc_messages=j_array();lc_clear_at=0;lc_scroll=0;lc_select_scope=0;lc_reply=0;lc_stats="";lc_dirty=1;return 0;}
fn lc_valid_id(id) {let i=0;while load8(id+i) {let c=load8(id+i);if !(c>=48 && c<=57) && !(c>=97 && c<=122) && c!=45 {return 0;}i=i+1;}return i>0 && i<=80;}
fn lc_session_list() {
    let files=h_entries(lc_history);let ids=h_vec();let i=0;while i<h_count(files) {let name=h_at(files,i);let n=h_len(name);if n>5 && h_equal(name+n-5,".json") {let id=h_slice(name,n-5);if lc_valid_id(id) {h_add(ids,id);}}i=i+1;}
    i=1;while i<h_count(ids) {let value=h_at(ids,i);let j=i;while j>0 && b_compare(h_at(ids,j-1),value)<0 {store64(ids+8+j*8,h_at(ids,j-1));j=j-1;}store64(ids+8+j*8,value);i=i+1;}return ids;
}
fn lc_read_session(path) {
    let data=j_parse(h_read(path));h_assert(j_n(data,"version")==1 && h_equal(j_s(data,"model"),"qwen3-1.7b"),"unsupported session version or model");let messages=j_need(data,"messages");h_assert(j_count(messages)<=1024,"too many saved messages");let i=0;let expected=0;
    while i<j_count(messages) {let m=j_at(messages,i);let role=j_s(m,"role");h_assert(h_equal(role,"user") || h_equal(role,"assistant") || h_equal(role,"notice"),"invalid saved role");h_assert(h_len(j_s(m,"content"))<=131072,"saved message too long");if h_equal(role,"user") {h_assert(!expected,"invalid saved turn order");expected=1;}else if h_equal(role,"assistant") {h_assert(expected,"invalid saved turn order");expected=0;}i=i+1;}h_assert(!expected,"incomplete saved turn pair");
    h_print(1,j_dump(data));return 0;
}
fn lc_resume(id) {
    if lc_busy {lc_status="Stop generation before resuming a chat.";return 0;}if h_equal(id,"latest") {let ids=lc_session_list();if !h_count(ids) {lc_status="No saved chats yet.";return 0;}id=h_at(ids,0);}
    if !lc_valid_id(id) {lc_status="Invalid session ID.";return 0;}let file=h_join(lc_history,h_cat(id,".json"));if !h_exists(file) {lc_status="Session not found.";return 0;}
    let p=h_run(h_args(lc_binary,"--read-session",file,0,0,0));if h_status(p) {lc_status="Cannot resume this session: invalid or unsupported file.";return 0;}
    let data=j_parse(h_out(p));lc_session=id;lc_messages=j_need(data,"messages");lc_thinking=j_n(data,"thinking");lc_clear_at=0;lc_scroll=0;lc_select_scope=0;lc_status="Resumed saved conversation.";lc_stats="";lc_dirty=1;return 0;
}
fn lc_checkpoint_ready() {return h_exists(h_join(lc_checkpoint,"config.json")) && h_exists(h_join(lc_checkpoint,"tokenizer.json")) && h_exists(h_join(lc_checkpoint,"model.safetensors.index.json")) && h_exists(h_join(lc_checkpoint,"model-00001-of-00002.safetensors"));}
fn lc_stop() {if lc_worker {h_stop(lc_worker);lc_worker=0;}lc_ready=0;lc_downloading=0;lc_send_buffer=0;lc_sent=0;return 0;}
fn lc_start() {
    if lc_worker {return 0;}if !lc_demo && !lc_checkpoint_ready() {lc_status="Model not downloaded. Use /download or --checkpoint DIRECTORY.";return 0;}
    let args=h_args(lc_binary,"--worker","1","--checkpoint",lc_checkpoint,"--compiler");h_add(args,lc_compiler);h_add(args,"--backend");h_add(args,lc_backend);h_add(args,"--weights");h_add(args,lc_weights);h_add(args,"--device");h_add(args,lc_device);h_add(args,"--context");let context="auto";if !lc_capacity_auto {context=h_int(lc_capacity);}h_add(args,context);h_add(args,"--demo");h_add(args,h_int(lc_demo));
    lc_worker=h_spawn(args,0,0);lc_ready=0;lc_worker_error=0;lc_stage("Loading model...",0,0);return 0;
}
fn lc_request() {
    let request=j_object();j_set(request,"op",j_string("generate"));let turns=j_array();let i=0;
    while i<j_count(lc_messages)-1 {let m=j_at(lc_messages,i);let role=j_s(m,"role");if h_equal(role,"user") || h_equal(role,"assistant") {j_push(turns,m);}i=i+1;}
    let start=j_count(turns)-1;let bytes=h_len(j_s(j_at(turns,start),"content"));while start>=2 && bytes<65536 {let extra=h_len(j_s(j_at(turns,start-1),"content"))+h_len(j_s(j_at(turns,start-2),"content"));if bytes+extra>65536 {bytes=65536;}else {start=start-2;bytes=bytes+extra;}}
    let selected=j_array();i=start;while i<j_count(turns) {j_push(selected,j_at(turns,i));i=i+1;}
    j_set(request,"turns",selected);j_set(request,"history_offset",j_int(start/2));j_set(request,"thinking",j_int(lc_thinking));j_set(request,"temperature",j_int(lc_temperature));j_set(request,"max_tokens",j_int(lc_maximum));lc_queue(h_cat(j_dump(request),"\n"));lc_stage("Generating...",0,0);return 0;
}
fn lc_finish(reason) {
    lc_busy=0;if lc_reply {j_set(lc_reply,"content",j_string(h_data(lc_reply_buffer)));j_set(lc_reply,"status",j_string(reason));}lc_save();lc_dirty=1;return 0;
}
fn lc_cancel() {
    if lc_busy && lc_ready && lc_worker {let e=j_object();j_set(e,"op",j_string("cancel"));lc_queue(h_cat(j_dump(e),"\n"));lc_status="Stopping...";}
    else if lc_worker && !lc_ready {lc_stop();lc_status="Loading stopped. Send a prompt to retry.";if lc_busy {lc_finish("cancelled");}}
    lc_dirty=1;return 0;
}
fn lc_event(e) {
    let kind=j_s(e,"event");
    if h_equal(kind,"status") {lc_stage(j_s(e,"text"),0,0);}
    else if h_equal(kind,"progress") {lc_stage(j_s(e,"text"),j_n(e,"completed"),j_n(e,"total"));}
    else if h_equal(kind,"ready") {lc_ready=1;lc_capacity=j_n(e,"context_capacity");lc_status="Model ready";let reply="auto";if lc_maximum {reply=h_int(lc_maximum);}lc_stats=h_cat3("Context ",h_int(lc_capacity),h_cat3(" | reply ",reply,h_cat3(" | Resident GPU memory: ",h_int(j_n(e,"resident_bytes")/1048576)," MiB")));if lc_busy {lc_request();}}
    else if h_equal(kind,"token") {if lc_busy {h_text(lc_reply_buffer,j_s(e,"text"));j_set(lc_reply,"content",j_string(h_data(lc_reply_buffer)));lc_stage("Generating...",0,0);}}
    else if h_equal(kind,"context") {lc_stats=h_cat3("Context ",h_int(j_n(e,"prompt_tokens")),h_cat3(" / ",h_int(lc_capacity),h_cat3(" | archived turns: ",h_int(j_n(e,"trimmed_turns")),"")));}
    else if h_equal(kind,"done") {let elapsed=j_n(e,"elapsed_us");let tokens=j_n(e,"tokens");lc_status=h_cat3("Finished: ",j_s(e,"reason"),"");lc_stats=h_cat3(h_int(tokens)," tokens | ",h_cat3(h_int(elapsed/1000)," ms | ",h_cat3(h_int(tokens*1000000/(elapsed+1))," tok/s | first token ",h_cat(h_int(j_n(e,"first_token_us")/1000)," ms"))));lc_finish(j_s(e,"reason"));}
    else if h_equal(kind,"error") {lc_worker_error=1;lc_status=j_s(e,"text");lc_finish("error");}
    else if h_equal(kind,"downloaded") {lc_stop();lc_status="Download complete.";lc_start();}
    lc_dirty=1;return 0;
}
fn lc_pump() {
    if !lc_worker {return 0;}let p=lc_worker;let status=lc_scratch+8192;
    if lc_send_buffer && lc_sent<h_size(lc_send_buffer) {let n=h_size(lc_send_buffer)-lc_sent;if n>4096 {n=4096;}let wrote=syscall(1,load64(p+32),h_data(lc_send_buffer)+lc_sent,n,0,0,0);if wrote>0 {lc_sent=lc_sent+wrote;}}
    if lc_send_buffer && lc_sent==h_size(lc_send_buffer) {lc_send_buffer=0;lc_sent=0;}
    if syscall(61,load64(p),status,1,0,0,0)==load64(p) {let v=load64(status)&65535;let code=(v>>8)&255;if v&127 {code=-(v&127);}store64(p+8,code);}
    let i=0;while i<2 {let fd=load64(p+40+i*8);if fd>=0 {let reading=1;while reading {let n=syscall(0,fd,lc_scratch,8192,0,0,0);if n<=0 {if n==0 || n==-5 {h_close(fd);store64(p+40+i*8,-1);}reading=0;}else {h_append(load64(p+16+i*8),lc_scratch,n);}}}i=i+1;}
    let buffer=load64(p+16);let s=h_data(buffer);let at=0;let start=0;while at<h_size(buffer) {if load8(s+at)==10 {lc_event(j_parse(h_slice(s+start,at-start)));if lc_worker!=p {return 0;}start=at+1;}at=at+1;}
    if start {h_copy(s,s+start,h_size(buffer)-start);store64(buffer+8,h_size(buffer)-start);store8(s+h_size(buffer),0);}
    let error=load64(p+24);if h_size(error) {h_text(lc_log,h_data(error));if h_size(lc_log)>65536 {let last=h_slice(h_data(lc_log)+h_size(lc_log)-32768,32768);lc_log=h_buffer();h_text(lc_log,last);}store64(error+8,0);store8(h_data(error),0);}
    if h_status(p)!=-999 && load64(p+40)<0 {lc_worker=0;lc_ready=0;lc_downloading=0;if !lc_worker_error {lc_status="Worker stopped. /logs shows details; send a prompt to retry.";}if lc_busy {lc_finish("error");}h_stop(p);lc_dirty=1;}return 0;
}
fn lc_number(text,limit) {let n=0;let i=0;while load8(text+i) {let c=load8(text+i);if c<48 || c>57 || i>=6 {return -1;}n=n*10+c-48;i=i+1;}if !i || n>limit {return -1;}return n;}
fn lc_temp(text) {let n=0;let scale=1000;let dot=0;let i=0;while load8(text+i) {let c=load8(text+i);if c==46 && !dot {dot=1;}else if c>=48 && c<=57 {if !dot {n=n*10+(c-48)*1000;}else {scale=scale/10;n=n+(c-48)*scale;}}else {return -1;}if i>6 || n>2000 {return -1;}i=i+1;}if !i {return -1;}return n;}
fn lc_command(text) {
    lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;
    let split=h_find(text," ");let name=text;let arg="";if split>=0 {name=h_slice(text,split);arg=h_trim(text+split+1);}
    if h_equal(name,"/quit") || h_equal(name,"/exit") {lc_running=0;}
    else if h_equal(name,"/help") {lc_menu("Help","/models /model qwen3-1.7b /download\n/backend sass|cuda /device N /weights bf16|f16|f16-tiled\n/thinking on|off /temperature 0..2 /tokens auto|N\n/new /clear /sessions /resume latest|ID /history /logs /quit\n\nEnter sends; Ctrl+J or Alt+Enter inserts a newline. Tab completes commands.\nArrows edit; Up/Down recall prompts; Shift+arrows select.\nClick Thinking to expand/collapse; Ctrl+T toggles the latest block.\nCtrl+A selects all; Ctrl+E moves to end; Ctrl+U clears.\nCtrl+C copies selection or quits; Ctrl+X cuts; Ctrl+V pastes.\nDrag to select and copy on release; right-click pastes in the composer.\nEsc cancels generation. Mouse wheel / PageUp / PageDown scroll.\nConversation history is sent to the model; oldest pairs leave context when full.\nFile tools and other model architectures are not supported by this runner.");}
    else if h_equal(name,"/models") || h_equal(name,"/model") {if h_len(arg) && !h_equal(arg,"qwen3-1.7b") {lc_status="Supported model: qwen3-1.7b";}else {lc_menu("Models",lc_models_text());}}
    else if h_equal(name,"/download") {if lc_busy {lc_status="Stop generation before downloading.";}else if lc_checkpoint_ready() {lc_status="Checkpoint is already downloaded.";}else {lc_stop();lc_worker=h_spawn(h_args(lc_binary,"--download-worker","1","--checkpoint",lc_checkpoint,0),0,0);lc_downloading=1;lc_stage("Downloading pinned Qwen3 checkpoint...",0,0);}}
    else if h_equal(name,"/new") {if lc_busy {lc_stop();lc_finish("cancelled");}lc_new();lc_status="New conversation.";}
    else if h_equal(name,"/clear") {lc_clear_at=j_count(lc_messages);lc_scroll=0;lc_status="Display cleared; conversation retained.";}
    else if h_equal(name,"/sessions") || (h_equal(name,"/resume") && !h_len(arg)) {let ids=lc_session_list();let out=h_buffer();h_text(out,"Saved conversations (newest first):\n");let i=0;while i<h_count(ids) && i<30 {h_text(out,h_cat(h_at(ids,i),"\n"));i=i+1;}if !i {h_text(out,"No saved chats yet.");}h_text(out,"\nUse /resume ID or /resume latest.");lc_menu("Sessions",h_data(out));}
    else if h_equal(name,"/resume") {lc_resume(arg);}
    else if h_equal(name,"/history") {lc_menu("History",h_cat3("Session: ",lc_session,h_cat3("\nSaved chats: ",lc_history,"")));}
    else if h_equal(name,"/logs") {lc_show_log=!lc_show_log;}
    else if h_equal(name,"/thinking") {if h_equal(arg,"on") || h_equal(arg,"off") {lc_thinking=h_equal(arg,"on");lc_status=h_cat("Thinking ",arg);lc_save();}else {lc_status="Use /thinking on or /thinking off.";}}
    else if h_equal(name,"/temperature") {let value=lc_temp(arg);if value<0 {lc_status="Temperature must be 0..2.";}else {lc_temperature=value;lc_status=h_cat("Temperature: ",arg);}}
    else if h_equal(name,"/tokens") {let value=lc_number(arg,4095);if h_equal(arg,"auto") {value=0;}if value<0 || (value==0 && !h_equal(arg,"auto")) {lc_status="Use /tokens auto or a positive count up to 4095.";}else {lc_maximum=value;lc_status=h_cat("Reply token limit: ",arg);}}
    else if h_equal(name,"/backend") || h_equal(name,"/weights") || h_equal(name,"/device") {
        let valid=0;if h_equal(name,"/backend") {valid=h_equal(arg,"sass") || h_equal(arg,"cuda");}else if h_equal(name,"/weights") {valid=h_equal(arg,"bf16") || h_equal(arg,"f16") || h_equal(arg,"f16-tiled");}else {valid=lc_number(arg,15)>=0;}
        if !valid {lc_status="Invalid setting. See /help.";}else if lc_busy {lc_status="Stop generation before changing hardware settings.";}else {if h_equal(name,"/backend") {lc_backend=arg;}else if h_equal(name,"/weights") {lc_weights=arg;}else {lc_device=arg;}lc_stop();lc_start();}
    }
    else {lc_status="Unknown command. Type /help.";}lc_dirty=1;return 0;
}
fn lc_submit() {
    let text=h_data(te_text);if !h_len(h_trim(text)) {return 0;}
    if load8(text)==47 {text=te_submit();lc_command(text);return 0;}
    if lc_busy || lc_downloading {lc_status="An operation is running. Esc stops it.";lc_dirty=1;return 0;}
    if j_count(lc_messages)>=1000 {lc_status="This saved chat is full. Use /new to start another.";return 0;}
    if h_len(text)>32768 {lc_status="Prompt exceeds 32 KiB.";return 0;}
    if !lc_worker {lc_start();}if !lc_worker {return 0;}
    text=te_submit();let message=j_object();j_set(message,"role",j_string("user"));j_set(message,"content",j_string(text));j_push(lc_messages,message);
    lc_reply=j_object();lc_reply_buffer=h_buffer();j_set(lc_reply,"role",j_string("assistant"));j_set(lc_reply,"content",j_string(""));j_set(lc_reply,"status",j_string("pending"));j_push(lc_messages,lc_reply);lc_busy=1;lc_scroll=0;lc_select_scope=0;lc_stats="";lc_save();if lc_ready {lc_request();}lc_dirty=1;return 0;
}
fn lc_document_hits(hits) {
    let out=h_buffer();let i=lc_clear_at;if i==j_count(lc_messages) {h_text(out,"Welcome to Flexscript. /help lists commands; /models shows model readiness.\n\nChats are saved automatically. /new starts a conversation; /resume restores one.\n");}
    while i<j_count(lc_messages) {let message=j_at(lc_messages,i);let role=j_s(message,"role");let title="Info";if h_equal(role,"user") {title="You";}else if h_equal(role,"assistant") {title="Assistant";}
        h_text(out,h_cat(title,"\n"));let content=tu_clean(j_s(message,"content"));let begin=-1;if h_equal(role,"assistant") {begin=h_find(content,"<think>");}
        if begin>=0 {h_append(out,content,begin);let thought=content+begin+7;let end=h_find(thought,"</think>");let length=end;if end<0 {length=h_len(thought);}let expanded=j_get(message,"thinking_expanded");let open=expanded && j_value(expanded);
            let lo=h_size(out);let marker="[+] Thinking";if open {marker="[-] Thinking";}let state="";if end<0 {state=" | unfinished";if lc_busy && lc_reply==message {state=" | in progress";}}h_text(out,h_cat3(marker,state," | click to toggle\n"));
            if hits {let hit=h_take(24);store64(hit,lo);store64(hit+8,h_size(out));store64(hit+16,i);h_add(hits,hit);}
            if open {h_append(out,thought,length);h_text(out,"\n");}if end>=0 {let answer=thought+end+8;while load8(answer)==10 {answer=answer+1;}h_text(out,answer);}}
        else {h_text(out,content);}h_text(out,"\n\n");i=i+1;}
    if lc_show_log {h_text(out,"Activity log\n");h_text(out,tu_clean(h_data(lc_log)));}return h_data(out);
}
fn lc_document() {return lc_document_hits(0);}
fn lc_toggle_thinking(message) {let before=h_count(ts_wrap(lc_document(),tu_cols));let value=j_get(message,"thinking_expanded");let open=value && j_value(value);j_set(message,"thinking_expanded",j_int(!open));lc_scroll=lc_scroll+h_count(ts_wrap(lc_document(),tu_cols))-before;if lc_scroll<0 {lc_scroll=0;}lc_select_scope=0;lc_select_start=0;lc_select_end=0;te_anchor=-1;lc_dirty=1;return 0;}
fn lc_toggle_latest() {let i=j_count(lc_messages);while i {i=i-1;let m=j_at(lc_messages,i);if h_equal(j_s(m,"role"),"assistant") && h_has(j_s(m,"content"),"<think>") {return lc_toggle_thinking(m);}}return 0;}
fn lc_draw() {
    // Lazy buffer storage must outlive the temporary rendering arena.
    h_data(te_text);h_data(lc_log);
    let mark=tu_mark();tu_size();let out=h_buffer();h_text(out,tu_ansi("@[?25l"));
    let title=h_cat3("Flexscript | Qwen3-1.7B | ",lc_backend,h_cat3(" | GPU ",lc_device,h_cat3(" | ",lc_weights,"")));if lc_demo {title=h_cat(title," | DEMO");}
    tu_line(out,1,title,"1;36");lc_activity_tick=net_now();lc_activity(out,lc_activity_tick);
    let editor=h_data(te_text);let erows=ts_wrap(editor,tu_cols);let eh=h_count(erows);if eh>5 {eh=5;}let ch=tu_rows-eh-6;
    if ch<1 {tu_line(out,3,"Resize the terminal to at least 20 x 8.",0);h_print(1,h_data(out));tu_reset(mark);return 0;}
    let doc=lc_document();
    let lo=-1;let hi=-1;if lc_select_scope==1 {lo=lc_select_start;hi=lc_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}}
    tw_text(out,doc,4,ch,lc_scroll,lo,hi,0);let i=0;
    tu_line(out,tu_rows-eh-2,lc_stats,"90");let label="Message";if lc_thinking {label="Message | thinking on";}if lc_scroll {label=h_cat(label," | chat scrolled");}tu_line(out,tu_rows-eh-1,label,"1;32");
    let help="Enter send | Ctrl+J newline | Esc stop | /help | Ctrl+C quit";if load8(editor)==47 {let hints=h_buffer();i=0;while i<h_count(lc_commands) {let command=h_at(lc_commands,i);if h_starts(command,editor) {h_text(hints,h_cat(command,"  "));}i=i+1;}if h_size(hints) {help=h_cat("Tab: ",h_data(hints));}}
    lc_panel_top=0;if lc_panel_text {let bottom=tu_rows-eh-2;lc_panel_top=tw_panel(out,lc_panel_title,lc_panel_text,bottom,bottom-3,lc_panel_scroll);}
    tu_line(out,tu_rows,help,"90");tw_editor(out,tu_rows-eh,eh);h_print(1,h_data(out));tu_reset(mark);lc_dirty=0;return 0;
}
fn lc_copy() {
    let text=0;if te_selected() {text=h_slice(h_data(te_text)+te_low(),te_high()-te_low());}
    else if lc_select_scope==1 {let doc=lc_document();let lo=lc_select_start;let hi=lc_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}if hi>h_len(doc) {hi=h_len(doc);}if hi>lo {text=h_slice(doc+lo,hi-lo);}}
    if !text {return 0;}if tc_copy(text) {lc_status="Copied selection.";}else {lc_status=tc_error;}lc_dirty=1;return 1;
}
fn lc_mouse() {
    let editor=h_data(te_text);let erows=ts_wrap(editor,tu_cols);let eh=h_count(erows);if eh>5 {eh=5;}let ch=tu_rows-eh-6;
    if lc_panel_text && ti_button&64 {let delta=-3;if ti_button&1 {delta=3;}return lc_menu_scroll(delta);}
    if (ti_button&3)==0 && !(ti_button&32) && !ti_release {lc_select_scope=0;lc_select_start=0;lc_select_end=0;te_anchor=-1;lc_dirty=1;}
    if lc_panel_text && lc_panel_top && ti_y>=lc_panel_top && ti_y<=tu_rows-eh-2 {return 0;}
    if ti_button&64 {if ti_button&1 {if lc_scroll>2 {lc_scroll=lc_scroll-3;}else {lc_scroll=0;}}else {lc_scroll=lc_scroll+3;}lc_dirty=1;return 0;}
    if (ti_button&3)==2 && ti_y>=tu_rows-eh && !ti_release {let paste=tc_paste();if paste {te_replace(paste);}else {lc_status=tc_error;}lc_dirty=1;return 0;}
    if (ti_button&3)!=0 {return 0;}
    let dragging=ti_button&32;
    if ti_y>=4 && ti_y<4+ch {let hits=h_vec();let doc=lc_document_hits(hits);let rows=ts_wrap(doc,tu_cols);let top=h_count(rows)-ch-lc_scroll;if top<0 {top=0;}let offset=ts_offset(doc,rows,top+ti_y-4,ti_x-1);
        if !dragging && !ti_release {lc_select_scope=1;lc_select_start=offset;te_anchor=-1;}if lc_select_scope==1 {lc_select_end=offset;}
        if ti_release && lc_select_scope==1 && lc_select_start==lc_select_end {let i=0;while i<h_count(hits) {let hit=h_at(hits,i);if offset>=load64(hit) && offset<load64(hit+8) {return lc_toggle_thinking(j_at(lc_messages,load64(hit+16)));}i=i+1;}}}
    else if ti_y>=tu_rows-eh && ti_y<tu_rows {let crow=0;let i=0;while i<h_count(erows) {if te_cursor>=load64(h_at(erows,i)) {crow=i;}i=i+1;}let top=crow-eh+1;if top<0 {top=0;}let offset=ts_offset(editor,erows,top+ti_y-(tu_rows-eh),ti_x-1);
        if !dragging && !ti_release {lc_select_scope=2;te_anchor=offset;}if lc_select_scope==2 {te_cursor=offset;}}
    if ti_release {if lc_select_scope==1 && lc_select_start==lc_select_end {lc_select_scope=0;}if lc_select_scope==2 && !te_selected() {lc_select_scope=0;te_anchor=-1;}lc_copy();}lc_dirty=1;return 0;
}
fn lc_key() {
    if ti_kind==3 {lc_mouse();return 0;}if ti_kind==1 || ti_kind==4 {if !lc_panel_preview {lc_panel_text=0;lc_panel_top=0;}te_replace(ti_text);lc_preview_update();lc_select_scope=0;lc_dirty=1;return 0;}
    let key=ti_key;let shift=ti_mod&1;let ctrl=ti_mod&4;
    if lc_panel_text {if key==27 {lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;lc_dirty=1;return 0;}
        if key==1001 || key==1008 {let delta=-1;if key==1008 {delta=-10;}return lc_menu_scroll(delta);}
        if key==1002 || key==1009 {let delta=1;if key==1009 {delta=10;}return lc_menu_scroll(delta);}}
    if key==13 && !shift {lc_submit();}else if key==10 || (key==13 && shift) {te_replace("\n");}
    else if key==27 {lc_cancel();}
    else if key==3 {if !lc_copy() {lc_running=0;}}
    else if key==4 {lc_running=0;}
    else if key==1 {te_anchor=0;te_cursor=h_size(te_text);lc_select_scope=2;}
    else if key==5 {te_move(h_size(te_text),0);}
    else if key==20 {lc_toggle_latest();}
    else if key==21 {te_set("");}
    else if key==23 {te_anchor=te_cursor;te_word(1,1);te_replace("");}
    else if key==24 {if te_selected() {lc_copy();te_replace("");}}
    else if key==22 {let text=tc_paste();if text {te_replace(text);}else {lc_status=tc_error;}}
    else if key==127 || key==8 {te_backspace();}
    else if key==1007 {te_delete();}
    else if key==1004 {if ctrl {te_word(1,shift);}else {te_left(shift);}}
    else if key==1003 {if ctrl {te_word(0,shift);}else {te_right(shift);}}
    else if key==1005 {if ctrl {te_move(0,shift);}else {te_line_edge(0,shift);}}else if key==1006 {if ctrl {te_move(h_size(te_text),shift);}else {te_line_edge(1,shift);}}
    else if key==1001 {te_vertical(0,shift,tu_cols);}else if key==1002 {te_vertical(1,shift,tu_cols);}
    else if key==1008 {lc_scroll=lc_scroll+10;}else if key==1009 {lc_scroll=lc_scroll-10;if lc_scroll<0 {lc_scroll=0;}}
    else if key==9 {let text=h_data(te_text);let i=0;let found=0;while i<h_count(lc_commands) && !found {let command=h_at(lc_commands,i);if h_starts(command,text) {te_set(h_cat(command," "));found=1;}i=i+1;}}
    lc_preview_update();lc_dirty=1;return 0;
}
fn lc_download(argc,argv) {
    let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide checkpoint destination");h_mkdir(directory);let manifest=j_parse(h_read("libs/ml/examples/qwen3-1.7b.model.json"));let spec=j_need(manifest,"checkpoint");let files=j_need(spec,"files");let i=0;
    ct_progress("Downloading model files",0,j_count(files));
    while i<j_count(files) {let name=j_value(j_at(files,i));h_assert(!h_has(name,"/") && !h_has(name,".."),"invalid asset name");let path=h_join(directory,name);
        if !h_exists(path) {ct_progress(h_cat("Downloading ",name),i,j_count(files));let partial=h_cat(path,".part");let url=h_cat3("https://huggingface.co/",j_s(spec,"repo"),h_cat3("/resolve/",j_s(spec,"revision"),h_cat("/",name)));
            let args=h_args("curl","--fail","--location","--retry","2","--continue-at");h_add(args,"-");h_add(args,"--output");h_add(args,partial);h_add(args,url);let p=h_run(args);h_assert(h_status(p)==0,h_err(p));h_assert(syscall(82,partial,path,0,0,0,0)==0,"download rename failed");}i=i+1;ct_progress("Downloading model files",i,j_count(files));}
    return ct_send(ct_event("downloaded"));
}
fn lc_main(argc,argv) {
    h_environment(argc,argv);h_timeout=3600000;lc_status="Ready";lc_stats="";lc_binary=h_real(load64(argv));
    if b_option(argc,argv,"--capacity-plan",0) {return cap_plan(argc,argv);}if b_option(argc,argv,"--worker",0) {return ct_worker(argc,argv);}if b_option(argc,argv,"--download-worker",0) {return lc_download(argc,argv);}let read=b_option(argc,argv,"--read-session",0);if read {return lc_read_session(read);}
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--help") {h_print(1,"Usage: llm [--checkpoint DIRECTORY] [--backend sass|cuda] [--device N]\n           [--weights bf16|f16|f16-tiled] [--context auto|32..4096]\n           [--max-tokens auto|N] [--history-dir DIRECTORY] [--resume latest|ID]\n           [--no-warmup 1] [--demo 1]\nCompile: build/flex-llm llm.flex -o build/llm-chat\n");return 0;}i=i+1;}
    lc_compiler=b_option(argc,argv,"--compiler","build/flex-llm");lc_backend=b_option(argc,argv,"--backend","sass");lm_select_backend(lc_backend);lc_weights=b_option(argc,argv,"--weights","f16");h_assert(h_equal(lc_weights,"bf16") || h_equal(lc_weights,"f16") || h_equal(lc_weights,"f16-tiled"),"invalid weight format");
    lc_device=b_option(argc,argv,"--device","0");h_assert(lc_number(lc_device,15)>=0,"device must be 0..15");let context=b_option(argc,argv,"--context","auto");lc_capacity_auto=h_equal(context,"auto");if !lc_capacity_auto {lc_capacity=lw_int(context);}h_assert(lc_capacity>=32 && lc_capacity<=4096,"context must be auto or 32..4096");let maximum=b_option(argc,argv,"--max-tokens","auto");lc_maximum=0;if !h_equal(maximum,"auto") {lc_maximum=lw_int(maximum);h_assert(lc_maximum>0 && lc_maximum<=4095,"max tokens must be auto or 1..4095");}
    let demo=h_getenv("FLEX_LLM_DEMO");if !demo {demo="0";}lc_demo=lw_int(b_option(argc,argv,"--demo",demo));h_assert(lc_demo<=1,"demo must be 0 or 1");
    let checkpoint=h_getenv("QWEN_CHECKPOINT");if !checkpoint {let home=h_getenv("HOME");if home {checkpoint=h_join(home,".cache/puppygrad/models/qwen3-1.7b/70d244cc86ccca08cf5af4e1e306ecf908b1ad5e");}if !checkpoint || !h_exists(checkpoint) {checkpoint="build/llm/models/qwen3-1.7b";}}
    lc_checkpoint=b_option(argc,argv,"--checkpoint",checkpoint);let history=h_getenv("FLEX_LLM_HISTORY");if !history {history="build/llm/sessions";}lc_history=b_option(argc,argv,"--history-dir",history);h_mkdir(lc_history);lc_messages=j_array();lc_log=h_buffer();h_data(lc_log);lc_new();te_init();ti_init();lc_scratch=h_take(8208);
    lc_commands=h_args("/help","/models","/model","/download","/backend","/device");h_add(lc_commands,"/weights");h_add(lc_commands,"/thinking");h_add(lc_commands,"/temperature");h_add(lc_commands,"/tokens");h_add(lc_commands,"/new");h_add(lc_commands,"/sessions");h_add(lc_commands,"/resume");h_add(lc_commands,"/history");h_add(lc_commands,"/logs");h_add(lc_commands,"/clear");h_add(lc_commands,"/quit");
    let resume=b_option(argc,argv,"--resume",0);if resume {lc_resume(resume);}h_assert(tu_open(),"interactive terminal required; use --help for CLI options");
    if !lw_int(b_option(argc,argv,"--no-warmup","0")) {lc_start();}
    while lc_running {lc_pump();let tick=net_now();if lc_dirty {lc_draw();}else if lc_active() && tick-lc_activity_tick>=100 {lc_animate(tick);}let ready=ti_wait(30);if ready==2 {lc_running=0;}
        while ti_next(ready==0) {lc_key();}if ti_overflow {lc_status="Paste exceeds 128 KiB.";ti_overflow=0;lc_dirty=1;}
        let cols=tu_cols;let rows=tu_rows;let mark=tu_mark();tu_size();tu_reset(mark);if cols!=tu_cols || rows!=tu_rows {lc_dirty=1;}
    }
    tu_close();if lc_busy {lc_finish("cancelled");}lc_stop();return 0;
}
