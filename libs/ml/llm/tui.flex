// Chat application built on libs/tui; inference lives in a reusable child worker.
import "chat.flex";
import "models.flex";
import "telemetry.flex";
import "../../tui/tui.flex";
global lc_binary=0;
global lc_checkpoint=0;
global lc_model=0;
global lc_checkpoints=0;
global lc_compiler=0;
global lc_backend=0;
global lc_runtime=0;
global lc_runtime_choice=0;
global lc_weights=0;
global lc_device=0;
global lc_capacity=40960;
global lc_capacity_auto=1;
global lc_context_limit=0;
global lc_context_used=-1;
global lc_context_prompt=-1;
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
global lc_selecting=0;
global lc_monitor_drag=0;
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
global lc_models_cursor=0;
global lc_models_navigation=0;
global lc_models_pressed=0;
global lc_models_first0=0;
global lc_models_last0=0;
global lc_models_first1=0;
global lc_models_last1=0;
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
fn lc_animate(tick) {let mark=tu_mark();let out=h_buffer();h_text(out,tu_ansi("@[s@[?25l"));let full=tu_cols;tu_cols=lt_columns();tu_clip=tu_cols!=full;lc_activity(out,tick);tu_cols=full;tu_clip=0;h_text(out,tu_ansi("@[u@[?25h"));h_print(1,h_data(out));tu_reset(mark);lc_activity_tick=tick;return 0;}
fn lc_queue(text) {if !lc_send_buffer {lc_send_buffer=h_buffer();}h_text(lc_send_buffer,text);return 0;}
fn lc_menu(title,text) {lc_panel_title=title;lc_panel_text=tu_clean(text);lc_panel_scroll=0;lc_panel_preview=0;lc_select_scope=0;lc_dirty=1;return 0;}
fn lc_model_id(index) {if index {return "qwen3-4b";}return "qwen3-1.7b";}
fn lc_model_directory(id) {let saved=j_get(lc_checkpoints,id);if saved {return j_value(saved);}return qm_directory(id);}
fn lc_models_panel() {return lc_panel_text && h_equal(lc_panel_title,"Models");}
fn lc_models_text() {
    let out=h_buffer();let i=0;while i<2 {let id=lc_model_id(i);let state="missing; /download to install";if lc_demo || qm_ready(lc_model_directory(id)) {state="downloaded";}
        let prefix="  ";if i==lc_models_cursor {prefix="> ";}h_text(out,h_cat3(prefix,id,h_cat(" | ",state)));if h_equal(id,lc_model) {h_text(out," [active]");}h_text(out,"\n");i=i+1;}
    h_text(out,h_cat3("\nCheckpoint: ",lc_model_directory(lc_model_id(lc_models_cursor)),"\nBoth support /thinking on|off.\n16-bit weights, FP32 KV cache."));return h_data(out);
}
fn lc_models_open() {lc_models_cursor=h_equal(lc_model,"qwen3-4b");lc_models_navigation=0;lc_models_pressed=0;return lc_menu("Models",lc_models_text());}
fn lc_models_move(delta) {
    lc_models_cursor=lc_models_cursor+delta;if lc_models_cursor<0 {lc_models_cursor=0;}if lc_models_cursor>1 {lc_models_cursor=1;}lc_models_navigation=1;lc_panel_text=tu_clean(lc_models_text());lc_panel_scroll=0;
    let mark=tu_mark();let eh=h_count(ts_wrap(h_data(te_text),lt_columns()));if eh>5 {eh=5;}let body=tu_rows-eh-7;let start=0;if lc_models_cursor {start=h_find(lc_panel_text,"\n")+1;}
    let rows=ts_wrap(lc_panel_text,lt_columns());let i=0;while i<h_count(rows) && load64(h_at(rows,i))<start {i=i+1;}if body>0 && i>=body {lc_panel_scroll=i-body+1;}tu_reset(mark);lc_dirty=1;return 0;
}
fn lc_models_draw(out,bottom,max_height) {
    lc_models_first0=0;lc_models_last0=0;lc_models_first1=0;lc_models_last1=0;
    let top=tw_panel(out,lc_panel_title,lc_panel_text,bottom,max_height,lc_panel_scroll);if !top {return 0;}
    let rows=ts_wrap(lc_panel_text,lt_columns());let body=bottom-top-1;let last=h_count(rows)-body;if last<0 {last=0;}let first=lc_panel_scroll;if first>last {first=last;}if first<0 {first=0;}
    let end0=h_find(lc_panel_text,"\n");let end1=end0+1+h_find(lc_panel_text+end0+1,"\n");let i=0;
    while i<body {let row=h_at(rows,first+i);let at=load64(row);let choice=-1;if at<end0 {choice=0;}else if at> end0 && at<end1 {choice=1;}
        if choice>=0 {let screen=top+i+1;if !choice {if !lc_models_first0 {lc_models_first0=screen;}lc_models_last0=screen;}else {if !lc_models_first1 {lc_models_first1=screen;}lc_models_last1=screen;}
            if choice==lc_models_cursor {ts_draw(out,lc_panel_text,row,screen,-1,-1,"1;7");}}i=i+1;}
    tu_line(out,bottom,"Click model | Up/Down choose | Enter select | Esc close","90");return top;
}
fn lc_models_activate() {
    if lc_busy || lc_downloading {lc_status="Stop the operation before changing models.";lc_dirty=1;return 0;}
    let id=lc_model_id(lc_models_cursor);if lc_panel_preview {te_submit();}lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;lc_models_pressed=0;
    if !h_equal(id,lc_model) {lc_save();lc_use_model(id);lc_new();lc_start();}else {lc_status=h_cat("Selected ",qm_title(id));}lc_dirty=1;return 0;
}
fn lc_use_model(id) {
    lc_stop();lc_model=id;let saved=j_get(lc_checkpoints,id);lc_checkpoint=qm_directory(id);if saved {lc_checkpoint=j_value(saved);}
    lc_context_limit=0;lc_context_used=-1;lc_context_prompt=-1;return 0;
}
fn lc_preview_update() {
    let text=h_trim(h_data(te_text));if h_equal(text,"/models") || h_equal(text,"/model") || h_starts(text,"/model ") {if !lc_panel_preview {lc_models_open();lc_panel_preview=1;}}
    else if lc_panel_preview {lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;}return 0;
}
fn lc_menu_scroll(delta) {let mark=tu_mark();let eh=h_count(ts_wrap(h_data(te_text),lt_columns()));if eh>5 {eh=5;}let body=tu_rows-eh-7;let last=h_count(ts_wrap(lc_panel_text,lt_columns()))-body;if last<0 {last=0;}
    lc_panel_scroll=lc_panel_scroll+delta;if lc_panel_scroll>last {lc_panel_scroll=last;}if lc_panel_scroll<0 {lc_panel_scroll=0;}tu_reset(mark);lc_dirty=1;return 0;}
fn lc_save() {
    let data=j_object();j_set(data,"version",j_int(1));j_set(data,"id",j_string(lc_session));j_set(data,"model",j_string(lc_model));j_set(data,"thinking",j_int(lc_thinking));j_set(data,"messages",lc_messages);
    let file=h_join(lc_history,h_cat(lc_session,".json"));let temporary=h_cat(file,".tmp");let text=j_dump(data);let fd=syscall(2,temporary,0x80241,384,0,0,0);
    if fd<0 {lc_status="Could not save this session.";return 0;}let written=h_write(fd,text,h_len(text));let synced=syscall(74,fd,0,0,0,0,0);h_close(fd);
    if written<0 || synced<0 || syscall(82,temporary,file,0,0,0,0)!=0 {syscall(87,temporary,0,0,0,0,0);lc_status="Could not save this session.";}return 0;
}
fn lc_new() {lt_profile_reset();lc_session=h_cat3(h_int(syscall(201,0,0,0,0,0,0)),"-",h_cat3(h_int(syscall(39,0,0,0,0,0,0)),"-",h_int(net_now())));lc_messages=j_array();lc_context_used=0;lc_context_prompt=-1;lc_clear_at=0;lc_scroll=0;lc_select_scope=0;lc_reply=0;lc_stats="";lc_dirty=1;return 0;}
fn lc_valid_id(id) {let i=0;while load8(id+i) {let c=load8(id+i);if !(c>=48 && c<=57) && !(c>=97 && c<=122) && c!=45 {return 0;}i=i+1;}return i>0 && i<=80;}
fn lc_session_list() {
    let files=h_entries(lc_history);let ids=h_vec();let i=0;while i<h_count(files) {let name=h_at(files,i);let n=h_len(name);if n>5 && h_equal(name+n-5,".json") {let id=h_slice(name,n-5);if lc_valid_id(id) {h_add(ids,id);}}i=i+1;}
    i=1;while i<h_count(ids) {let value=h_at(ids,i);let j=i;while j>0 && b_compare(h_at(ids,j-1),value)<0 {store64(ids+8+j*8,h_at(ids,j-1));j=j-1;}store64(ids+8+j*8,value);i=i+1;}return ids;
}
fn lc_read_session(path) {
    let data=j_parse(h_read(path));h_assert(j_n(data,"version")==1 && qm_valid(j_s(data,"model")),"unsupported session version or model");let messages=j_need(data,"messages");h_assert(j_count(messages)<=1024,"too many saved messages");let i=0;let expected=0;
    while i<j_count(messages) {let m=j_at(messages,i);let role=j_s(m,"role");h_assert(h_equal(role,"user") || h_equal(role,"assistant") || h_equal(role,"notice"),"invalid saved role");h_assert(h_len(j_s(m,"content"))<=131072,"saved message too long");let error=j_get(m,"error");if error {h_assert(j_kind(error)==2,"invalid saved error");h_assert(h_len(j_value(error))<=131072,"saved error too long");}if h_equal(role,"user") {h_assert(!expected,"invalid saved turn order");expected=1;}else if h_equal(role,"assistant") {h_assert(expected,"invalid saved turn order");expected=0;}i=i+1;}h_assert(!expected,"incomplete saved turn pair");
    h_print(1,j_dump(data));return 0;
}
fn lc_resume(id) {
    if lc_busy || lc_downloading {lc_status="Stop the operation before resuming a chat.";return 0;}if h_equal(id,"latest") {let ids=lc_session_list();if !h_count(ids) {lc_status="No saved chats yet.";return 0;}id=h_at(ids,0);}
    if !lc_valid_id(id) {lc_status="Invalid session ID.";return 0;}let file=h_join(lc_history,h_cat(id,".json"));if !h_exists(file) {lc_status="Session not found.";return 0;}
    let p=h_run(h_args(lc_binary,"--read-session",file,0,0,0));if h_status(p) {lc_status="Cannot resume this session: invalid or unsupported file.";return 0;}
    let data=j_parse(h_out(p));if !h_equal(lc_model,j_s(data,"model")) {lc_use_model(j_s(data,"model"));}lc_session=id;lc_messages=j_need(data,"messages");lc_context_used=-1;lc_context_prompt=-1;lc_thinking=j_n(data,"thinking");if lc_thinking && !lc_temperature {lc_temperature=600;}lc_clear_at=0;lc_scroll=0;lc_select_scope=0;lc_status="Resumed saved conversation.";lc_stats="";lc_dirty=1;return 0;
}
fn lc_checkpoint_ready() {return qm_ready(lc_checkpoint);}
fn lc_stop() {if lc_worker {h_stop(lc_worker);lc_worker=0;}lt_profile_reset();lc_ready=0;lc_downloading=0;lc_send_buffer=0;lc_sent=0;lt_workers=0;lt_wave_size=0;lt_worker_threads=0;lt_resident_bytes=0;return 0;}
fn lc_start() {
    if lc_worker {return 0;}if !lc_demo && !lc_checkpoint_ready() {lc_status="Model not downloaded. Use /download or --checkpoint DIRECTORY.";return 0;}
    lc_runtime=lc_runtime_choice;
    let args=h_args(lc_binary,"--worker","1","--checkpoint",lc_checkpoint,"--compiler");h_add(args,lc_compiler);h_add(args,"--backend");h_add(args,lc_backend);h_add(args,"--runtime");h_add(args,lc_runtime_choice);h_add(args,"--weights");h_add(args,lc_weights);h_add(args,"--device");h_add(args,lc_device);h_add(args,"--context");let context="auto";if !lc_capacity_auto {context=h_int(lc_capacity);}h_add(args,context);h_add(args,"--demo");h_add(args,h_int(lc_demo));
    lc_context_limit=0;lc_context_used=-1;lc_context_prompt=-1;lc_worker=h_spawn(args,0,0);lc_ready=0;lc_worker_error=0;lc_stage("Loading model...",0,0);return 0;
}
fn lc_request() {
    lt_request(net_now());
    lc_context_used=-1;lc_context_prompt=-1;
    let request=j_object();j_set(request,"op",j_string("generate"));let turns=j_array();let i=0;
    while i<j_count(lc_messages)-1 {let m=j_at(lc_messages,i);let role=j_s(m,"role");if h_equal(role,"user") || h_equal(role,"assistant") {j_push(turns,m);}i=i+1;}
    let start=j_count(turns)-1;let bytes=h_len(j_s(j_at(turns,start),"content"));while start>=2 && bytes<524288 {let extra=h_len(j_s(j_at(turns,start-1),"content"))+h_len(j_s(j_at(turns,start-2),"content"));if bytes+extra>524288 {bytes=524288;}else {start=start-2;bytes=bytes+extra;}}
    let selected=j_array();i=start;while i<j_count(turns) {j_push(selected,j_at(turns,i));i=i+1;}
    j_set(request,"turns",selected);j_set(request,"history_offset",j_int(start/2));j_set(request,"thinking",j_int(lc_thinking));j_set(request,"temperature",j_int(lc_temperature));j_set(request,"max_tokens",j_int(lc_maximum));j_set(request,"profile",j_int(lt_enabled));lc_queue(h_cat(j_dump(request),"\n"));lc_stage("Generating...",0,0);return 0;
}
fn lc_finish(reason) {
    lc_busy=0;if lc_reply {j_set(lc_reply,"content",j_string(h_data(lc_reply_buffer)));j_set(lc_reply,"status",j_string(reason));}lc_save();lc_dirty=1;return 0;
}
fn lc_fail(text) {
    lc_status=text;if lc_busy && lc_reply {j_set(lc_reply,"error",j_string(text));lc_status="Reply failed";lc_scroll=0;lc_finish("error");}lc_dirty=1;return 0;
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
    else if h_equal(kind,"gpu_profile") {lt_profile(j_need(e,"records"));}
    else if h_equal(kind,"ready") {let runtime=j_get(e,"runtime");if runtime {lc_runtime=j_value(runtime);}lt_resident_bytes=j_n(e,"resident_bytes");lt_workers=0;lt_wave_size=0;lt_worker_threads=0;let workers=j_get(e,"resident_workers");let wave=j_get(e,"wave_size");let threads=j_get(e,"threads_per_worker");if workers {lt_workers=j_value(workers);}if wave {lt_wave_size=j_value(wave);}if threads {lt_worker_threads=j_value(threads);}lc_ready=1;lc_capacity=j_n(e,"context_capacity");lc_context_limit=lc_capacity;lc_context_used=0;lc_context_prompt=-1;lc_status="Model ready";let reply="auto";if lc_maximum {reply=h_int(lc_maximum);}lc_stats=h_cat3("Context ",h_int(lc_capacity),h_cat3(" | reply ",reply,h_cat3(" | Resident GPU memory: ",h_int(j_n(e,"resident_bytes")/1048576)," MiB")));if lc_busy {lc_request();}}
    else if h_equal(kind,"token") {if lc_busy {lt_token(net_now());if lc_context_prompt>=0 && j_get(e,"id") {lc_context_used=lc_context_used+1;}h_text(lc_reply_buffer,j_s(e,"text"));j_set(lc_reply,"content",j_string(h_data(lc_reply_buffer)));lc_stage("Generating...",0,0);}}
    else if h_equal(kind,"context") {lc_context_prompt=j_n(e,"prompt_tokens");lc_context_used=lc_context_prompt;lc_stats=h_cat3("Context ",h_int(j_n(e,"prompt_tokens")),h_cat3(" / ",h_int(lc_capacity),h_cat3(" | archived turns: ",h_int(j_n(e,"trimmed_turns")),"")));}
    else if h_equal(kind,"done") {let elapsed=j_n(e,"elapsed_us");let tokens=j_n(e,"tokens");lt_done(tokens,elapsed,j_n(e,"first_token_us"));if lc_context_prompt>=0 {lc_context_used=lc_context_prompt+tokens;}lc_status=h_cat3("Finished: ",j_s(e,"reason"),"");lc_stats=h_cat3(h_int(tokens)," tokens | ",h_cat3(h_int(elapsed/1000)," ms | ",h_cat3(h_int(tokens*1000000/(elapsed+1))," tok/s | first token ",h_cat(h_int(j_n(e,"first_token_us")/1000)," ms"))));lc_finish(j_s(e,"reason"));}
    else if h_equal(kind,"error") {lc_worker_error=1;lc_fail(j_s(e,"text"));}
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
    if h_status(p)!=-999 && load64(p+40)<0 {lc_worker=0;lc_ready=0;lc_downloading=0;lt_profile_reset();lt_workers=0;lt_wave_size=0;lt_worker_threads=0;lt_resident_bytes=0;if !lc_worker_error {lc_fail("Worker stopped. /logs shows details; send a prompt to retry.");}h_stop(p);lc_dirty=1;}return 0;
}
fn lc_number(text,limit) {let n=0;let i=0;while load8(text+i) {let c=load8(text+i);if c<48 || c>57 || i>=6 {return -1;}n=n*10+c-48;i=i+1;}if !i || n>limit {return -1;}return n;}
fn lc_temp(text) {let n=0;let scale=1000;let dot=0;let i=0;while load8(text+i) {let c=load8(text+i);if c==46 && !dot {dot=1;}else if c>=48 && c<=57 {if !dot {n=n*10+(c-48)*1000;}else {scale=scale/10;n=n+(c-48)*scale;}}else {return -1;}if i>6 || n>2000 {return -1;}i=i+1;}if !i {return -1;}return n;}
fn lc_command(text) {
    lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;
    let split=h_find(text," ");let name=text;let arg="";if split>=0 {name=h_slice(text,split);arg=h_trim(text+split+1);}
    if h_equal(name,"/quit") || h_equal(name,"/exit") {lc_running=0;}
    else if h_equal(name,"/help") {lc_menu("Help","/models /model qwen3-1.7b|qwen3-4b /download\n/backend sass|cuda|hip|rdna|rdna-direct /device N /weights bf16|f16|f16-tiled\n/runtime auto|graph|gpu-os /monitor on|off\n/thinking on|off /temperature 0..2 /tokens auto|N\n/new /clear /sessions /resume latest|ID /history /logs /quit\n\nEnter sends; Ctrl+J or Alt+Enter inserts a newline. Tab completes commands.\nArrows edit; Up/Down recall prompts; Shift+arrows select.\nClick Thinking to expand/collapse; Ctrl+T toggles the latest block.\nCtrl+A selects all; Ctrl+E moves to end; Ctrl+U clears.\nCtrl+C copies selection or quits; Ctrl+X cuts; Ctrl+V pastes.\nDrag to select and copy on release; right-click pastes in the composer.\nDrag the monitor divider to resize the right column.\nEsc cancels generation. Mouse wheel / PageUp / PageDown scroll.\nConversation history is sent to the model; oldest pairs leave context when full.\nFile tools and other model architectures are not supported by this runner.");}
    else if h_equal(name,"/models") || h_equal(name,"/model") {
        if !h_len(arg) {lc_models_open();}else if !qm_valid(arg) {lc_status="Supported models: qwen3-1.7b, qwen3-4b";}
        else if lc_busy || lc_downloading {lc_status="Stop the operation before changing models.";}
        else if h_equal(arg,lc_model) {lc_models_open();}
        else {lc_save();lc_use_model(arg);lc_new();lc_status=h_cat("Selected ",qm_title(lc_model));lc_start();}
    }
    else if h_equal(name,"/download") {if lc_busy || lc_downloading {lc_status="Stop the operation before downloading.";}else if lc_checkpoint_ready() {lc_status="Checkpoint is already downloaded.";}else {lc_stop();let args=h_args(lc_binary,"--download-worker","1","--checkpoint",lc_checkpoint,"--model");h_add(args,lc_model);lc_worker=h_spawn(args,0,0);lc_downloading=1;lc_stage("Downloading pinned Qwen3 checkpoint...",0,0);}}
    else if h_equal(name,"/new") {if lc_busy {lc_stop();lc_finish("cancelled");}lc_new();lc_status="New conversation.";}
    else if h_equal(name,"/clear") {lc_clear_at=j_count(lc_messages);lc_scroll=0;lc_status="Display cleared; conversation retained.";}
    else if h_equal(name,"/sessions") || (h_equal(name,"/resume") && !h_len(arg)) {let ids=lc_session_list();let out=h_buffer();h_text(out,"Saved conversations (newest first):\n");let i=0;while i<h_count(ids) && i<30 {h_text(out,h_cat(h_at(ids,i),"\n"));i=i+1;}if !i {h_text(out,"No saved chats yet.");}h_text(out,"\nUse /resume ID or /resume latest.");lc_menu("Sessions",h_data(out));}
    else if h_equal(name,"/resume") {lc_resume(arg);}
    else if h_equal(name,"/history") {lc_menu("History",h_cat3("Session: ",lc_session,h_cat3("\nSaved chats: ",lc_history,"")));}
    else if h_equal(name,"/logs") {lc_show_log=!lc_show_log;}
    else if h_equal(name,"/thinking") {if h_equal(arg,"on") || h_equal(arg,"off") {lc_thinking=h_equal(arg,"on");if lc_thinking && !lc_temperature {lc_temperature=600;}lc_status=h_cat("Thinking ",arg);lc_save();}else {lc_status="Use /thinking on or /thinking off.";}}
    else if h_equal(name,"/temperature") {let value=lc_temp(arg);if value<0 {lc_status="Temperature must be 0..2.";}else {lc_temperature=value;lc_status=h_cat("Temperature: ",arg);}}
    else if h_equal(name,"/monitor") {if h_equal(arg,"on") || h_equal(arg,"off") {lt_enabled=h_equal(arg,"on");lc_status="GPU monitor hidden.";if lt_enabled {lc_status="GPU monitor enabled (110+ columns).";}}else {lc_status="Use /monitor on or /monitor off.";}}
    else if h_equal(name,"/runtime") {
        if !h_equal(arg,"auto") && !h_equal(arg,"graph") && !h_equal(arg,"gpu-os") {lc_status="Use /runtime auto, graph or gpu-os.";}
        else if lc_busy || lc_downloading {lc_status="Stop the operation before changing runtimes.";}
        else if h_equal(arg,"gpu-os") && (!h_equal(lc_backend,"rdna-direct") || !h_equal(lc_weights,"f16")) {lc_status="GPU OS requires /backend rdna-direct and /weights f16.";}
        else {lc_runtime_choice=arg;lc_runtime=arg;lc_stop();lc_start();}
    }
    else if h_equal(name,"/tokens") {let value=lc_number(arg,ll_context_max()-1);if h_equal(arg,"auto") {value=0;}if value<0 || (value==0 && !h_equal(arg,"auto")) {lc_status="Use /tokens auto or a positive count up to 40959.";}else {lc_maximum=value;lc_status=h_cat("Reply token limit: ",arg);}}
    else if h_equal(name,"/backend") || h_equal(name,"/weights") || h_equal(name,"/device") {
        let valid=0;if h_equal(name,"/backend") {valid=h_equal(arg,"sass") || h_equal(arg,"cuda") || h_equal(arg,"hip") || h_equal(arg,"rdna") || h_equal(arg,"rdna-direct");}else if h_equal(name,"/weights") {valid=h_equal(arg,"bf16") || h_equal(arg,"f16") || h_equal(arg,"f16-tiled");}else {valid=lc_number(arg,15)>=0;}
        if !valid {lc_status="Invalid setting. See /help.";}else if lc_busy || lc_downloading {lc_status="Stop the operation before changing hardware settings.";}
        else if h_equal(lc_runtime_choice,"gpu-os") && ((h_equal(name,"/backend") && !h_equal(arg,"rdna-direct")) || (h_equal(name,"/weights") && !h_equal(arg,"f16"))) {lc_status="Switch to /runtime graph before changing GPU OS backend or weights.";}
        else {if h_equal(name,"/backend") {lc_backend=arg;}else if h_equal(name,"/weights") {lc_weights=arg;}else {lc_device=arg;}lc_stop();lc_start();}
    }
    else {lc_status="Unknown command. Type /help.";}lc_dirty=1;return 0;
}
fn lc_submit() {
    let text=h_data(te_text);if !h_len(h_trim(text)) {return 0;}
    if load8(text)==47 {text=te_submit();lc_command(text);return 0;}
    if lc_busy || lc_downloading {lc_status="An operation is running. Esc stops it.";lc_dirty=1;return 0;}
    if j_count(lc_messages)>=1000 {lc_status="This saved chat is full. Use /new to start another.";return 0;}
    if h_len(text)>262144 {lc_status="Prompt exceeds 256 KiB.";return 0;}
    if !lc_worker {lc_start();}if !lc_worker {return 0;}
    text=te_submit();let message=j_object();j_set(message,"role",j_string("user"));j_set(message,"content",j_string(text));j_push(lc_messages,message);
    lc_reply=j_object();lc_reply_buffer=h_buffer();j_set(lc_reply,"role",j_string("assistant"));j_set(lc_reply,"content",j_string(""));j_set(lc_reply,"status",j_string("pending"));j_push(lc_messages,lc_reply);lc_busy=1;lc_scroll=0;lc_select_scope=0;lc_stats="";lc_save();if lc_ready {lc_request();}lc_dirty=1;return 0;
}
fn lc_document_build(hits,errors) {
    let out=h_buffer();let i=lc_clear_at;if i==j_count(lc_messages) {h_text(out,"Welcome to Flexscript. /help lists commands; /models shows model readiness.\n\nChats are saved automatically. /new starts a conversation; /resume restores one.\n");}
    while i<j_count(lc_messages) {let message=j_at(lc_messages,i);let role=j_s(message,"role");let title="Info";if h_equal(role,"user") {title="You";}else if h_equal(role,"assistant") {title="Assistant";}
        h_text(out,h_cat(title,"\n"));let content=tu_clean(j_s(message,"content"));let begin=-1;if h_equal(role,"assistant") {begin=h_find(content,"<think>");}
        if begin>=0 {h_append(out,content,begin);let thought=content+begin+7;let end=h_find(thought,"</think>");let length=end;if end<0 {length=h_len(thought);}let expanded=j_get(message,"thinking_expanded");let open=expanded && j_value(expanded);
            let lo=h_size(out);let marker="[+] Thinking";if open {marker="[-] Thinking";}let state="";if end<0 {state=" | unfinished";if lc_busy && lc_reply==message {state=" | in progress";}}h_text(out,h_cat3(marker,state," | click to toggle\n"));
            if hits {let hit=h_take(24);store64(hit,lo);store64(hit+8,h_size(out));store64(hit+16,i);h_add(hits,hit);}
            if open {h_append(out,thought,length);h_text(out,"\n");}if end>=0 {let answer=thought+end+8;while load8(answer)==10 {answer=answer+1;}h_text(out,answer);}}
        else {h_text(out,content);}
        let error=j_get(message,"error");if error {if h_len(content) {h_text(out,"\n\n");}let lo=h_size(out);h_text(out,tu_clean(j_value(error)));if errors {let range=h_take(16);store64(range,lo);store64(range+8,h_size(out));h_add(errors,range);}}
        h_text(out,"\n\n");i=i+1;}
    if lc_show_log {h_text(out,"Activity log\n");h_text(out,tu_clean(h_data(lc_log)));}return h_data(out);
}
fn lc_document_hits(hits) {return lc_document_build(hits,0);}
fn lc_document() {return lc_document_build(0,0);}
fn lc_draw_messages(out,doc,errors,height,lo,hi) {
    let rows=ts_wrap(doc,lt_columns());let top=h_count(rows)-height-lc_scroll;if top<0 {top=0;}let i=0;
    while i<height {if top+i<h_count(rows) {let row=h_at(rows,top+i);let color=0;let j=0;
            while j<h_count(errors) {let error=h_at(errors,j);if load64(row)<load64(error+8) && load64(row+8)>load64(error) {color="33";}j=j+1;}
            ts_draw(out,doc,row,4+i,lo,hi,color);}else {tu_line(out,4+i,"",0);}i=i+1;}return 0;
}
fn lc_toggle_thinking(message) {let before=h_count(ts_wrap(lc_document(),lt_columns()));let value=j_get(message,"thinking_expanded");let open=value && j_value(value);j_set(message,"thinking_expanded",j_int(!open));lc_scroll=lc_scroll+h_count(ts_wrap(lc_document(),lt_columns()))-before;if lc_scroll<0 {lc_scroll=0;}lc_select_scope=0;lc_select_start=0;lc_select_end=0;te_anchor=-1;lc_dirty=1;return 0;}
fn lc_toggle_latest() {let i=j_count(lc_messages);while i {i=i-1;let m=j_at(lc_messages,i);if h_equal(j_s(m,"role"),"assistant") && h_has(j_s(m,"content"),"<think>") {return lc_toggle_thinking(m);}}return 0;}
fn lc_draw() {
    // Lazy buffer storage must outlive the temporary rendering arena.
    h_data(te_text);h_data(lc_log);
    let mark=tu_mark();tu_size();let full=tu_cols;tu_cols=lt_columns();tu_clip=tu_cols!=full;let out=h_buffer();h_text(out,tu_ansi("@[?25l"));
    let backend=lc_backend;if h_equal(lc_runtime,"gpu-os") {backend=h_cat(backend," | gpu-os");}
    let title=h_cat3("Flexscript | ",qm_title(lc_model),h_cat3(" | ",backend,h_cat3(" | GPU ",lc_device,h_cat3(" | ",lc_weights,""))));if lc_demo {title=h_cat(title," | DEMO");}
    let context="auto";if lc_context_limit {context=h_int(lc_context_limit);if lc_context_used>=0 {context=h_cat3(h_int(lc_context_used),"/",context);}}else if !lc_capacity_auto {context=h_int(lc_capacity);}
    title=h_cat3(h_cat("Context ",context)," | ",title);
    tu_line(out,1,title,"1;36");lc_activity_tick=net_now();lc_activity(out,lc_activity_tick);
    let editor=h_data(te_text);let erows=ts_wrap(editor,tu_cols);let eh=h_count(erows);if eh>5 {eh=5;}let ch=tu_rows-eh-6;
    if ch<1 {tu_line(out,3,"Resize the terminal to at least 20 x 8.",0);tu_cols=full;tu_clip=0;h_print(1,h_data(out));tu_reset(mark);return 0;}
    let errors=h_vec();let doc=lc_document_build(0,errors);
    let lo=-1;let hi=-1;if lc_select_scope==1 {lo=lc_select_start;hi=lc_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}}
    lc_draw_messages(out,doc,errors,ch,lo,hi);let i=0;
    tu_line(out,tu_rows-eh-2,lc_stats,"90");let label="Message";if lc_thinking {label="Message | thinking on";}if lc_scroll {label=h_cat(label," | chat scrolled");}tu_line(out,tu_rows-eh-1,label,"1;32");
    let help="Enter send | Ctrl+J newline | Esc stop | /help | Ctrl+C quit";if load8(editor)==47 {let hints=h_buffer();i=0;while i<h_count(lc_commands) {let command=h_at(lc_commands,i);if h_starts(command,editor) {h_text(hints,h_cat(command,"  "));}i=i+1;}if h_size(hints) {help=h_cat("Tab: ",h_data(hints));}}
    lc_panel_top=0;if lc_panel_text {let bottom=tu_rows-eh-2;if lc_models_panel() {lc_panel_top=lc_models_draw(out,bottom,bottom-3);}else {lc_panel_top=tw_panel(out,lc_panel_title,lc_panel_text,bottom,bottom-3,lc_panel_scroll);}}
    tu_line(out,tu_rows,help,"90");tw_editor(out,tu_rows-eh,eh);h_text(out,tu_ansi("@[s"));tu_cols=full;tu_clip=0;
    let stage="Idle";if lc_busy {stage="Generating";}else if lc_active() {stage="Loading";}if lc_demo {stage="Demo";}
    lt_draw(out,lc_runtime,stage,lc_context_used,lc_context_limit,lc_demo);h_text(out,tu_ansi("@[u"));h_print(1,h_data(out));tu_reset(mark);lc_dirty=0;return 0;
}
fn lc_copy() {
    let text=0;if te_selected() {text=h_slice(h_data(te_text)+te_low(),te_high()-te_low());}
    else if lc_select_scope==1 {let doc=lc_document();let lo=lc_select_start;let hi=lc_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}if hi>h_len(doc) {hi=h_len(doc);}if hi>lo {text=h_slice(doc+lo,hi-lo);}}
    if !text {return 0;}if tc_copy(text) {lc_status="Copied selection.";}else {lc_status=tc_error;}lc_dirty=1;return 1;
}
fn lc_clear_selection() {lc_select_scope=0;lc_select_start=0;lc_select_end=0;lc_selecting=0;te_anchor=-1;lc_dirty=1;return 0;}
fn lc_mouse() {
    // Capture divider gestures before text selection or model-picker clicks.
    if lc_monitor_drag {
        if lt_visible() {lt_resize(ti_x);lc_dirty=1;}
        if ti_release || !lt_visible() {lc_monitor_drag=0;}return 0;
    }
    if lt_visible() && ti_x==tu_cols-lt_width() && (ti_button&3)==0 && !(ti_button&96) && !ti_release {lc_monitor_drag=1;lc_models_pressed=0;return lc_clear_selection();}
    let columns=lt_columns();if ti_x>columns && columns<tu_cols {if (ti_button&32) || lc_selecting {ti_x=columns;}else {if !ti_release {lc_clear_selection();}return 0;}}
    let editor=h_data(te_text);let erows=ts_wrap(editor,columns);let eh=h_count(erows);if eh>5 {eh=5;}let ch=tu_rows-eh-6;
    if lc_panel_text && ti_button&64 {let delta=-3;if ti_button&1 {delta=3;}return lc_menu_scroll(delta);}
    if ti_button&64 {if ti_button&1 {if lc_scroll>2 {lc_scroll=lc_scroll-3;}else {lc_scroll=0;}}else {lc_scroll=lc_scroll+3;}lc_dirty=1;return 0;}
    if lc_models_panel() && lc_panel_top && ti_y>=lc_panel_top && ti_y<=tu_rows-eh-2 {
        if (ti_button&3)==0 {let choice=-1;if lc_models_first0 && ti_y>=lc_models_first0 && ti_y<=lc_models_last0 {choice=0;}else if lc_models_first1 && ti_y>=lc_models_first1 && ti_y<=lc_models_last1 {choice=1;}
            // Keep the panel geometry stable between press and release: the
            // next model's checkpoint path may wrap to a different height.
            if ti_button&32 {lc_models_pressed=-1;}else if choice>=0 {if ti_release {if !lc_models_pressed || lc_models_pressed==choice+1 {lc_models_cursor=choice;lc_clear_selection();return lc_models_activate();}}else {lc_models_pressed=choice+1;}}
            if ti_release {lc_models_pressed=0;}}return lc_clear_selection();
    }
    if (ti_button&3)==2 && ti_y>=tu_rows-eh && !ti_release {let paste=tc_paste();if paste {te_replace(paste);}else {lc_status=tc_error;}return lc_clear_selection();}
    if !(ti_button&32) && !ti_release {lc_clear_selection();}
    if (ti_button&3)!=0 {return 0;}
    // A completed drag leaves a visible selection, not an active gesture.
    // Some clicks arrive as release-only events; they must dismiss that range
    // rather than extending it from the previous drag's anchor.
    if ti_release && !lc_selecting {return lc_clear_selection();}
    if lc_panel_text && lc_panel_top && ti_y>=lc_panel_top && ti_y<=tu_rows-eh-2 {if ti_release {lc_selecting=0;}return 0;}
    let dragging=ti_button&32;
    if dragging && !lc_selecting {return 0;}
    if ti_y>=4 && ti_y<4+ch {let hits=h_vec();let doc=lc_document_hits(hits);let rows=ts_wrap(doc,lt_columns());let top=h_count(rows)-ch-lc_scroll;if top<0 {top=0;}let offset=ts_offset(doc,rows,top+ti_y-4,ti_x-1);
        if !dragging && !ti_release {lc_selecting=1;lc_select_scope=1;lc_select_start=offset;te_anchor=-1;}if lc_select_scope==1 {lc_select_end=offset;}
        if ti_release && lc_select_scope==1 && lc_select_start==lc_select_end {let i=0;while i<h_count(hits) {let hit=h_at(hits,i);if offset>=load64(hit) && offset<load64(hit+8) {lc_selecting=0;return lc_toggle_thinking(j_at(lc_messages,load64(hit+16)));}i=i+1;}}}
    else if ti_y>=tu_rows-eh && ti_y<tu_rows {let crow=0;let i=0;while i<h_count(erows) {if te_cursor>=load64(h_at(erows,i)) {crow=i;}i=i+1;}let top=crow-eh+1;if top<0 {top=0;}let offset=ts_offset(editor,erows,top+ti_y-(tu_rows-eh),ti_x-1);
        if !dragging && !ti_release {lc_selecting=1;lc_select_scope=2;te_anchor=offset;}if lc_select_scope==2 {te_cursor=offset;}}
    if ti_release {lc_selecting=0;if lc_select_scope==1 && lc_select_start==lc_select_end {lc_select_scope=0;}if lc_select_scope==2 && !te_selected() {lc_select_scope=0;te_anchor=-1;}lc_copy();}lc_dirty=1;return 0;
}
fn lc_key() {
    if ti_kind==3 {lc_mouse();return 0;}if ti_kind==1 || ti_kind==4 {if !lc_panel_preview {lc_panel_text=0;lc_panel_top=0;}te_replace(ti_text);lc_preview_update();lc_select_scope=0;lc_dirty=1;return 0;}
    let key=ti_key;let shift=ti_mod&1;let ctrl=ti_mod&4;
    if lc_panel_text {if key==27 {lc_panel_text=0;lc_panel_top=0;lc_panel_preview=0;lc_dirty=1;return 0;}
        if lc_models_panel() {if key==1001 {return lc_models_move(-1);}if key==1002 {return lc_models_move(1);}if key==13 && !shift && (!lc_panel_preview || lc_models_navigation) {return lc_models_activate();}}
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
    else if key==1001 {te_vertical(0,shift,lt_columns());}else if key==1002 {te_vertical(1,shift,lt_columns());}
    else if key==1008 {lc_scroll=lc_scroll+10;}else if key==1009 {lc_scroll=lc_scroll-10;if lc_scroll<0 {lc_scroll=0;}}
    else if key==9 {let text=h_data(te_text);let i=0;let found=0;while i<h_count(lc_commands) && !found {let command=h_at(lc_commands,i);if h_starts(command,text) {te_set(h_cat(command," "));found=1;}i=i+1;}}
    lc_preview_update();lc_dirty=1;return 0;
}
fn lc_download(argc,argv) {
    let directory=b_option(argc,argv,"--checkpoint",0);h_assert(directory,"provide checkpoint destination");h_mkdir(directory);let manifest=qm_manifest(b_option(argc,argv,"--model","qwen3-1.7b"));let spec=j_need(manifest,"checkpoint");let files=j_need(spec,"files");let i=0;
    ct_progress("Downloading model files",0,j_count(files));
    while i<j_count(files) {let name=j_value(j_at(files,i));h_assert(!h_has(name,"/") && !h_has(name,".."),"invalid asset name");let path=h_join(directory,name);
        if !h_exists(path) {ct_progress(h_cat("Downloading ",name),i,j_count(files));let partial=h_cat(path,".part");let url=h_cat3("https://huggingface.co/",j_s(spec,"repo"),h_cat3("/resolve/",j_s(spec,"revision"),h_cat("/",name)));
            let args=h_args("curl","--fail","--location","--retry","2","--continue-at");h_add(args,"-");h_add(args,"--output");h_add(args,partial);h_add(args,url);let p=h_run(args);h_assert(h_status(p)==0,h_err(p));h_assert(syscall(82,partial,path,0,0,0,0)==0,"download rename failed");}i=i+1;ct_progress("Downloading model files",i,j_count(files));}
    return ct_send(ct_event("downloaded"));
}
fn lc_main(argc,argv) {
    h_environment(argc,argv);h_timeout=3600000;lc_status="Ready";lc_stats="";lc_binary=h_real(load64(argv));lc_model="qwen3-1.7b";
    if b_option(argc,argv,"--capacity-plan",0) {return cap_plan(argc,argv);}if b_option(argc,argv,"--worker",0) {return ct_worker(argc,argv);}if b_option(argc,argv,"--download-worker",0) {return lc_download(argc,argv);}let read=b_option(argc,argv,"--read-session",0);if read {return lc_read_session(read);}
    let i=1;while i<argc {if h_equal(load64(argv+i*8),"--help") {h_print(1,"Usage: llm [--model qwen3-1.7b|qwen3-4b] [--checkpoint DIRECTORY] [--backend sass|cuda|hip|rdna|rdna-direct] [--device N]\n           [--runtime auto|graph|gpu-os] [--monitor on|off] [--weights bf16|f16|f16-tiled] [--context auto|32..40960]\n           [--max-tokens auto|N] [--history-dir DIRECTORY] [--resume latest|ID]\n           [--thinking on|off] [--temperature 0..2] [--no-warmup 1] [--demo 1]\nRun: build/flex ./llm.flex [options]\nCompile: build/flex-llm llm.flex -o build/llm-chat\n");return 0;}i=i+1;}
    lc_compiler=b_option(argc,argv,"--compiler",lm_default_compiler());lc_backend=b_option(argc,argv,"--backend",lm_default_backend());lm_select_backend(lc_backend);lc_weights=b_option(argc,argv,"--weights","f16");h_assert(h_equal(lc_weights,"bf16") || h_equal(lc_weights,"f16") || h_equal(lc_weights,"f16-tiled"),"invalid weight format");
    lc_runtime_choice=b_option(argc,argv,"--runtime","auto");lc_runtime=lc_runtime_choice;h_assert(h_equal(lc_runtime,"auto") || h_equal(lc_runtime,"graph") || h_equal(lc_runtime,"gpu-os"),"--runtime must be auto, graph or gpu-os");
    if h_equal(lc_runtime,"gpu-os") {h_assert(h_equal(lc_backend,"rdna-direct") && h_equal(lc_weights,"f16"),"GPU OS requires --backend rdna-direct --weights f16");}
    let monitor=b_option(argc,argv,"--monitor","off");h_assert(h_equal(monitor,"on") || h_equal(monitor,"off"),"--monitor must be on or off");lt_enabled=h_equal(monitor,"on");
    lc_device=b_option(argc,argv,"--device","0");h_assert(lc_number(lc_device,15)>=0,"device must be 0..15");let context=b_option(argc,argv,"--context","auto");lc_capacity_auto=h_equal(context,"auto");if !lc_capacity_auto {lc_capacity=lw_int(context);}h_assert(lc_capacity>=32 && lc_capacity<=ll_context_max(),"context must be auto or 32..40960");let maximum=b_option(argc,argv,"--max-tokens","auto");lc_maximum=0;if !h_equal(maximum,"auto") {lc_maximum=lw_int(maximum);h_assert(lc_maximum>0 && lc_maximum<ll_context_max(),"max tokens must be auto or 1..40959");}
    let demo=h_getenv("FLEX_LLM_DEMO");if !demo {demo="0";}lc_demo=lw_int(b_option(argc,argv,"--demo",demo));h_assert(lc_demo<=1,"demo must be 0 or 1");
    let selected=b_option(argc,argv,"--model",0);if selected {h_assert(qm_valid(selected),"supported models: qwen3-1.7b, qwen3-4b");lc_model=selected;}
    let checkpoint=b_option(argc,argv,"--checkpoint",0);if !checkpoint {checkpoint=h_getenv("QWEN_CHECKPOINT");if checkpoint && selected {let detected=qm_detect(checkpoint);if !detected || !h_equal(selected,detected) {checkpoint=0;}}}
    if checkpoint {let detected=qm_detect(checkpoint);if h_exists(h_join(checkpoint,"config.json")) {h_assert(detected,"checkpoint is not a supported original Qwen3-1.7B or Qwen3-4B model");}if detected {if selected {h_assert(h_equal(selected,detected),"--model does not match --checkpoint");}lc_model=detected;}}else {checkpoint=qm_directory(lc_model);}
    lc_checkpoints=j_object();j_set(lc_checkpoints,lc_model,j_string(checkpoint));lc_checkpoint=checkpoint;
    let thinking=b_option(argc,argv,"--thinking","off");h_assert(h_equal(thinking,"on") || h_equal(thinking,"off"),"thinking must be on or off");lc_thinking=h_equal(thinking,"on");let temperature="0";if lc_thinking {temperature="0.6";}lc_temperature=lc_temp(b_option(argc,argv,"--temperature",temperature));h_assert(lc_temperature>=0,"temperature must be 0..2");
    lt_init(lc_device,lc_backend);
    let history=h_getenv("FLEX_LLM_HISTORY");if !history {history="build/llm/sessions";}lc_history=b_option(argc,argv,"--history-dir",history);h_mkdir(lc_history);lc_messages=j_array();lc_log=h_buffer();h_data(lc_log);lc_new();te_init();ti_init();lc_scratch=h_take(8208);
    lc_commands=h_args("/help","/models","/model","/download","/backend","/device");h_add(lc_commands,"/runtime");h_add(lc_commands,"/monitor");h_add(lc_commands,"/weights");h_add(lc_commands,"/thinking");h_add(lc_commands,"/temperature");h_add(lc_commands,"/tokens");h_add(lc_commands,"/new");h_add(lc_commands,"/sessions");h_add(lc_commands,"/resume");h_add(lc_commands,"/history");h_add(lc_commands,"/logs");h_add(lc_commands,"/clear");h_add(lc_commands,"/quit");
    let resume=b_option(argc,argv,"--resume",0);if resume {lc_resume(resume);}h_assert(tu_open(),"interactive terminal required; use --help for CLI options");
    if !lw_int(b_option(argc,argv,"--no-warmup","0")) {lc_start();}
    while lc_running {lc_pump();let tick=net_now();if !h_equal(lt_device,lc_device) || !h_equal(lt_backend,lc_backend) {lt_init(lc_device,lc_backend);}
        if lt_tick(tick,lc_busy) {lc_dirty=1;}if lc_dirty {lc_draw();}else if lc_active() && tick-lc_activity_tick>=100 {lc_animate(tick);}let ready=ti_wait(30);if ready==2 {lc_running=0;}
        while ti_next(ready==0) {lc_key();}if ti_overflow {lc_status="Paste exceeds 128 KiB.";ti_overflow=0;lc_dirty=1;}
        let cols=tu_cols;let rows=tu_rows;let mark=tu_mark();tu_size();tu_reset(mark);if cols!=tu_cols || rows!=tu_rows {lc_dirty=1;}
    }
    tu_close();if lc_busy {lc_finish("cancelled");}lc_stop();return 0;
}
