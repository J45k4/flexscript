// Native conversational UI, using the same terminal/editor widgets as llm.flex.
// Model and guest execution live in a child; only framed display events enter here.
import "loop.flex";
import "../../../libs/tui/tui.flex";

global cu_config=0;
global cu_binary=0;
global cu_context=0;
global cu_items=0;
global cu_reply=0;
global cu_prose=0;
global cu_source=0;
global cu_worker=0;
global cu_scratch=0;
global cu_complete=0;
global cu_status=0;
global cu_error=0;
global cu_log=0;
global cu_history=0;
global cu_session=0;
global cu_prompt=0;
global cu_scroll=0;
global cu_clear_at=0;
global cu_dirty=1;
global cu_running=1;
global cu_tick=0;
global cu_stage_at=0;
global cu_show_code=0;
global cu_commands=0;
global cu_panel=0;
global cu_title=0;
global cu_panel_scroll=0;
global cu_scope=0;
global cu_select_start=0;
global cu_select_end=0;
global cu_selecting=0;
global cu_bytes=2;
global cu_message_count=0;
global cu_last_usage=0;
global cu_window=0;
global cu_compactions=0;
global cu_manual=0;
global cu_pending_recorded=0;
global cu_before_usage=0;
global cu_before_anchor=0;
global cu_workspace_override=0;

fn cu_measure() {cu_bytes=h_len(j_dump(cu_context));cu_message_count=j_count(cu_context);return 0;}
fn cu_model_info() {
    // A missing/corrupt optional cache must not close a terminal in raw mode.
    let info=co_model_limits(j_object(),cu_config);let request=j_object();j_set(request,"config",cu_config);
    let child=h_wait(h_spawn(h_args(cu_binary,"--adapter","model_info",0,0,0),j_dump(request),0));
    if !h_status(child) {info=c_json(h_out(child));}cu_window=co_count(info,"usable_context_window");j_set(cu_config,"model_info",info);return 0;
}
fn cu_context_label() {
    let text="?";if cu_last_usage {text=h_int(j_n(cu_last_usage,"total_tokens"));if c_flag(cu_last_usage,"estimated") {text=h_cat("~",text);}}if cu_window>0 {text=h_cat3(text,"/",h_int(cu_window));}
    text=h_cat3("Context ",text," tok");if cu_last_usage {let label=" (last)";if c_flag(cu_last_usage,"estimated") {label=" (est)";}text=h_cat(text,label);}return text;
}
fn cu_limit_number(text) {
    // Invalid interactive input must not abort the terminal host.
    let n=0;let i=0;if !h_len(text) || h_len(text)>10 {return 0;}
    while load8(text+i) {let c=load8(text+i);if c<48 || c>57 {return 0;}n=n*10+c-48;if n>1000000000 {return 0;}i=i+1;}return n;
}
fn cu_context_menu() {
    let info=j_need(cu_config,"model_info");let out=h_buffer();
    h_text(out,h_cat("Model: ",j_s(cu_config,"model")));
    h_text(out,h_cat("\nContext window: ",h_int(j_n(info,"context_window"))));
    h_text(out,h_cat("\nUsable tokens: ",h_int(cu_window)));
    h_text(out,h_cat("\nAuto-compact tokens: ",h_int(j_n(info,"auto_compact_token_limit"))));
    h_text(out,h_cat("\nMaximum window: ",h_int(j_n(info,"max_context_window"))));
    h_text(out,"\n\n/context N sets the context window.\n/compact N sets the compaction threshold.\n/compact default restores the automatic threshold.\n/context default restores both model defaults.\n\nValues above the model limits are capped.\nChanges apply to the next model request.\n/compact compacts the conversation now.");
    return cu_menu("Context limits",h_data(out));
}
fn cu_limits_command(arg,compact) {
    if !h_len(arg) {if compact {return cu_compact();}return cu_context_menu();}
    if cu_worker {return cu_stage("Esc stops the current turn before changing context limits.");}
    let key="model_context_window";if compact {key="model_auto_compact_token_limit";}
    if h_equal(arg,"default") {j_set(cu_config,key,j_node(0,0));if !compact {j_set(cu_config,"model_auto_compact_token_limit",j_node(0,0));}}
    else {
        let n=cu_limit_number(arg);if !n {let name="/context";if compact {name="/compact";}return cu_stage(h_cat3("Use ",name,h_cat3(" N or ",name," default (N: 1..1000000000).")));}j_set(cu_config,key,j_int(n));
    }
    cu_model_info();cu_save();cu_stage("Context limits updated.");return cu_context_menu();
}

fn cu_stage(text) {cu_status=text;cu_stage_at=net_now();cu_dirty=1;return 0;}
fn cu_item(role,text) {let m=j_object();j_set(m,"role",j_string(role));j_set(m,"content",j_string(text));j_push(cu_items,m);return m;}
fn cu_workspace() {
    let path=cu_workspace_override;if !path || !h_len(path) {path=h_join(h_join(cu_history,"workspaces"),h_cat(cu_session,".flexdb"));}
    j_set(cu_config,"workspace_file",j_string(path));j_set(cu_config,"history_file",j_string(h_join(cu_history,h_cat(cu_session,".json"))));return 0;
}
fn cu_new() {
    cu_context=j_array();cu_items=j_array();cu_reply=0;cu_error=0;cu_clear_at=0;cu_scroll=0;cu_scope=0;
    cu_last_usage=0;cu_compactions=0;cu_pending_recorded=0;cu_manual=0;cu_measure();cu_model_info();
    cu_session=h_cat3(h_int(syscall(201,0,0,0,0,0,0)),"-",h_cat3(h_int(syscall(39,0,0,0,0,0,0)),"-",h_int(net_now())));
    cu_workspace();
    return cu_stage("Ready. /help lists commands.");
}
fn cu_valid_id(id) {
    let i=0;while load8(id+i) {let c=load8(id+i);if !(c>=48 && c<=57) && c!=45 {return 0;}i=i+1;}return i>0 && i<=80;
}
fn cu_compare(a,b) {let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)-load8(b+i);}
fn cu_sessions() {
    let files=h_entries(cu_history);let ids=h_vec();let i=0;
    while i<h_count(files) {let name=h_at(files,i);let n=h_len(name);if n>5 && h_equal(name+n-5,".json") {let id=h_slice(name,n-5);if cu_valid_id(id) {h_add(ids,id);}}i=i+1;}
    i=1;while i<h_count(ids) {let value=h_at(ids,i);let j=i;while j>0 && cu_compare(h_at(ids,j-1),value)<0 {store64(ids+8+j*8,h_at(ids,j-1));j=j-1;}store64(ids+8+j*8,value);i=i+1;}return ids;
}
fn cu_save() {
    cu_measure();
    if !j_count(cu_items) {return 0;}
    let data=j_object();j_set(data,"version",j_int(1));j_set(data,"model",j_need(cu_config,"model"));j_set(data,"messages",cu_context);j_set(data,"items",cu_items);
    if cu_last_usage {j_set(data,"usage",cu_last_usage);}
    j_set(data,"compactions",j_int(cu_compactions));
    let limits=j_object();let keys=h_args("model_context_window","model_auto_compact_token_limit",0,0,0,0);let i=0;while i<2 {let key=h_at(keys,i);if co_count(cu_config,key)>0 {j_set(limits,key,j_need(cu_config,key));}i=i+1;}j_set(data,"limits",limits);
    let text=j_dump(data);if h_len(text)>16777216 {return cu_stage("Session exceeds 16 MiB; use /new. This turn was not saved.");}
    let file=h_join(cu_history,h_cat(cu_session,".json"));let temp=h_cat(file,".tmp");let fd=syscall(2,temp,0xa0241,384,0,0,0);
    if fd<0 {return cu_stage("Could not save this session.");}
    let protected=syscall(91,fd,384,0,0,0,0);let n=h_write(fd,text,h_len(text));let synced=syscall(74,fd,0,0,0,0,0);h_close(fd);
    if protected<0 || n!=h_len(text) || synced<0 || syscall(82,temp,file,0,0,0,0)!=0 {syscall(87,temp,0,0,0,0,0);cu_stage("Could not save this session.");}return 0;
}
// Parse untrusted saved data in a worker so malformed JSON cannot strand raw mode.
fn cu_read_session(file) {
    let text=c_read(file,16777216);h_assert(text,"cannot read bounded session");let data=c_json(text);
    h_assert(j_kind(data)==4 && j_n(data,"version")==1,"unsupported session");
    h_assert(h_len(j_s(data,"model"))<=256,"invalid saved model");
    let usage=j_get(data,"usage");if usage {let checked=co_usage(usage);h_assert(checked,"invalid saved usage");j_set(data,"usage",checked);}
    let messages=j_need(data,"messages");let items=j_need(data,"items");h_assert(co_history_valid(messages) && j_kind(items)==3 && j_count(items)<=4095,"session item limit or invalid context");
    let count=j_get(data,"compactions");if count {h_assert(co_count(data,"compactions")>=0,"invalid compaction count");}
    let limits=j_get(data,"limits");if limits {h_assert(j_kind(limits)==4,"invalid saved context limits");let keys=h_args("model_context_window","model_auto_compact_token_limit",0,0,0,0);let k=0;while k<2 {let key=h_at(keys,k);if j_get(limits,key) {h_assert(co_count(limits,key)>0,"invalid saved context limit");}k=k+1;}}
    let i=0;
    i=0;while i<j_count(items) {let m=j_at(items,i);let role=j_s(m,"role");h_assert(h_equal(role,"user") || h_equal(role,"assistant"),"invalid display role");h_assert(h_len(j_s(m,"content"))<=65536,"invalid display message");
        let source=j_get(m,"source");if source {h_assert(j_kind(source)==2 && h_len(j_value(source))<=65536,"invalid saved code");}
        let error=j_get(m,"error");if error {h_assert(j_kind(error)==2 && h_len(j_value(error))<=131200,"invalid saved error");}
        let expanded=j_get(m,"expanded");if expanded {h_assert(j_kind(expanded)==5,"invalid saved expansion");}
        let observation=j_get(m,"observation");if observation {h_assert(j_kind(observation)==4,"invalid observation");h_assert(h_len(j_s(observation,"state"))<=32,"invalid state");let keys=h_args("stdout","stderr",0,0,0,0);let k=0;while k<2 {let value=j_get(observation,h_at(keys,k));if value {h_assert(j_kind(value)==2 && h_len(j_value(value))<=131200,"invalid output");}k=k+1;}}
        i=i+1;}
    h_print(1,j_dump(data));return 0;
}
fn cu_resume(id) {
    if cu_worker {return cu_stage("Esc stops the current turn before resuming.");}
    if h_equal(id,"latest") {let ids=cu_sessions();if !h_count(ids) {return cu_stage("No saved conversations yet.");}id=h_at(ids,0);}
    if !cu_valid_id(id) {return cu_stage("Invalid session ID.");}
    let file=h_join(cu_history,h_cat(id,".json"));if !h_exists(file) {return cu_stage("Session not found.");}
    cu_save();let before=h_output_limit;h_output_limit=33554432;let child=h_run(h_args(cu_binary,"--read-session",file,0,0,0));h_output_limit=before;if h_status(child) {return cu_stage("Cannot resume: invalid or unsupported session.");}
    let data=c_json(h_out(child));cu_session=id;cu_context=j_need(data,"messages");cu_items=j_need(data,"items");j_set(cu_config,"model",j_need(data,"model"));
    cu_workspace();
    let limits=j_get(data,"limits");if limits {let keys=h_args("model_context_window","model_auto_compact_token_limit",0,0,0,0);let i=0;while i<2 {let key=h_at(keys,i);let value=j_get(limits,key);if !value {value=j_node(0,0);}j_set(cu_config,key,value);i=i+1;}}
    cu_last_usage=j_get(data,"usage");cu_measure();cu_model_info();
    cu_compactions=co_count(data,"compactions");if cu_compactions<0 {cu_compactions=0;}
    cu_clear_at=0;cu_scroll=0;cu_scope=0;cu_reply=0;return cu_stage("Resumed saved conversation.");
}
fn cu_cancel() {
    if !cu_worker {return 0;}h_stop(cu_worker);cu_worker=0;if cu_complete {cu_complete=0;cu_save();return 0;}
    if cu_manual {cu_stage("Compaction stopped.");cu_save();return 0;}
    if !cu_reply {cu_reply=cu_item("assistant","");}
    j_set(cu_reply,"error",j_string("Turn cancelled. Any in-flight execution may be incomplete."));
    let anchor=j_count(cu_context);if !cu_pending_recorded {cu_last_usage=cu_before_usage;anchor=cu_before_anchor;collie_message(cu_context,"user",cu_prompt);}collie_message(cu_context,"assistant","Turn cancelled. Any in-flight execution may be incomplete.");cu_last_usage=co_context_usage(cu_context,cu_last_usage,anchor);
    cu_stage("Turn cancelled.");cu_save();return 0;
}
fn cu_turn_config() {
    let config=c_json(j_dump(cu_config));j_set(config,"messages",c_json(j_dump(cu_context)));j_set(config,"usage",j_node(0,0));if cu_last_usage {j_set(config,"usage",cu_last_usage);}j_set(config,"compactions",j_int(cu_compactions));j_set(config,"events",j_bool(1));j_set(config,"stream",j_bool(0));return config;
}
fn cu_compact() {
    if cu_worker {return cu_stage("Esc stops the current turn before compacting.");}if !j_count(cu_context) {return cu_stage("No conversation to compact.");}
    cu_manual=1;cu_pending_recorded=0;cu_reply=0;cu_complete=0;cu_prompt="";let config=cu_turn_config();j_set(config,"compact_only",j_bool(1));j_set(config,"prompt",j_string(""));
    cu_worker=h_spawn(h_args(cu_binary,"--turn-worker",0,0,0,0),j_dump(config),0);return cu_stage("Compacting conversation...");
}
fn cu_submit() {
    let text=h_data(te_text);if !h_len(h_trim(text)) {return 0;}
    if load8(text)==47 {return cu_command(te_submit());}
    if cu_worker {return cu_stage("A turn is running. Esc stops it; your draft is kept.");}
    if h_len(text)>16384 {return cu_stage("Prompt exceeds 16 KiB.");}
    if j_count(cu_items)>4000 || h_len(j_dump(cu_items))>7340032 {return cu_stage("Local transcript is full. Use /new.");}
    cu_manual=0;cu_pending_recorded=0;cu_before_usage=cu_last_usage;cu_before_anchor=j_count(cu_context);
    text=te_submit();cu_prompt=text;cu_item("user",text);cu_reply=0;cu_complete=0;cu_error=0;cu_scroll=0;cu_scope=0;
    let config=cu_turn_config();j_set(config,"prompt",j_string(text));
    // h_spawn inherits the terminal's blocked signal mask. The turn entry point
    // restores it before launching adapters; parent-death SIGKILL covers exits.
    cu_worker=h_spawn(h_args(cu_binary,"--turn-worker",0,0,0,0),j_dump(config),0);
    return cu_stage("Generating reply 1");
}
fn cu_observation_label(observation) {
    let state=j_s(observation,"state");if h_equal(state,"rejected") {let executed=j_get(observation,"executed");if executed && !j_value(executed) && !h_equal(c_string(observation,"phase"),"source") {return "Reply rejected (not executed)";}return "Program rejected (not executed)";}return h_cat("VM ",state);
}
fn cu_event(e) {
    let kind=j_s(e,"event");
    if h_equal(kind,"reply_start") {cu_reply=cu_item("assistant","");cu_prose=h_buffer();h_data(cu_prose);cu_source=h_buffer();h_data(cu_source);j_set(cu_reply,"expanded",j_bool(cu_show_code));cu_stage(j_s(e,"text"));}
    else if h_equal(kind,"message_delta") && cu_reply {h_text(cu_prose,j_s(e,"text"));j_set(cu_reply,"content",j_string(h_data(cu_prose)));}
    else if h_equal(kind,"source_delta") && cu_reply {h_text(cu_source,j_s(e,"text"));j_set(cu_reply,"source",j_string(h_data(cu_source)));}
    else if h_equal(kind,"reply") && cu_reply {let reply=j_need(e,"data");j_set(cu_reply,"content",j_need(reply,"message"));j_set(cu_reply,"source",j_need(reply,"source"));let error=j_get(reply,"protocol_error");if error {j_set(cu_reply,"error",error);}let usage=co_usage(j_get(reply,"usage"));if usage {cu_last_usage=usage;}}
    else if h_equal(kind,"context") {let data=j_need(e,"data");cu_bytes=j_n(data,"bytes");cu_message_count=j_n(data,"messages");let usage=co_usage(j_get(data,"usage"));if usage {cu_last_usage=usage;}}
    else if h_equal(kind,"checkpoint") {let data=j_need(e,"data");cu_context=j_need(data,"messages");cu_last_usage=co_usage(j_get(data,"usage"));cu_pending_recorded=c_flag(data,"pending_prompt");cu_compactions=j_n(data,"compactions");cu_before_usage=cu_last_usage;cu_before_anchor=j_count(cu_context);}
    else if h_equal(kind,"compacted") {cu_stage(j_s(e,"text"));}
    else if h_equal(kind,"observation") && cu_reply {j_set(cu_reply,"observation",j_need(e,"data"));cu_stage(cu_observation_label(j_need(e,"data")));}
    else if h_equal(kind,"status") {cu_stage(j_s(e,"text"));}
    else if h_equal(kind,"error") {cu_error=1;if !cu_reply {cu_reply=cu_item("assistant","");}j_set(cu_reply,"error",j_need(e,"text"));cu_stage("Turn failed.");}
    else if h_equal(kind,"done") {cu_context=j_need(e,"messages");cu_last_usage=co_usage(j_get(e,"usage"));cu_compactions=j_n(e,"compactions");cu_complete=1;if !j_n(e,"status") {let text="Done.";if cu_manual {text="Conversation compacted.";}cu_stage(text);}else {cu_stage("Turn failed.");}}
    cu_dirty=1;return 0;
}
fn cu_pump() {
    if !cu_worker {return 0;}let p=cu_worker;let scratch=cu_scratch;let status=scratch+8192;
    if syscall(61,load64(p),status,1,0,0,0)==load64(p) {let v=load64(status)&65535;let code=(v>>8)&255;if v&127 {code=-(v&127);}store64(p+8,code);}
    let input=load64(p+32);if input>=0 {let left=load64(p+64)-load64(p+72);if left>4096 {left=4096;}let n=syscall(1,input,load64(p+56)+load64(p+72),left,0,0,0);if n>0 {store64(p+72,load64(p+72)+n);}if load64(p+72)==load64(p+64) || (n<0 && n!=-11 && n!=-4) {h_close(input);store64(p+32,-1);}}
    let i=0;while i<2 {let fd=load64(p+40+i*8);if fd>=0 {let reading=1;while reading {let n=syscall(0,fd,scratch,8192,0,0,0);if n>0 {let buffer=load64(p+16+i*8);if h_size(buffer)+n>33554432 {cu_cancel();return cu_stage("Worker output exceeded its limit.");}h_append(buffer,scratch,n);}else {if n==0 || n==-5 {h_close(fd);store64(p+40+i*8,-1);}reading=0;}}}i=i+1;}
    let buffer=load64(p+16);let s=h_data(buffer);let at=0;let start=0;
    while at<h_size(buffer) {if load8(s+at)==10 {cu_event(c_json(h_slice(s+start,at-start)));start=at+1;}at=at+1;}
    if start {h_copy(s,s+start,h_size(buffer)-start);store64(buffer+8,h_size(buffer)-start);store8(s+h_size(buffer),0);}
    let errors=load64(p+24);if h_size(errors) {h_text(cu_log,h_data(errors));if h_size(cu_log)>65536 {let tail=h_slice(h_data(cu_log)+h_size(cu_log)-32768,32768);cu_log=h_buffer();h_text(cu_log,tail);}store64(errors+8,0);store8(h_data(errors),0);}
    if h_status(p)!=-999 && load64(p+40)<0 && load64(p+48)<0 {
        h_close(load64(p+32));store64(p+32,-1);cu_worker=0;
        if !cu_complete {if !cu_reply {cu_reply=cu_item("assistant","");}let details=h_data(cu_log);if h_len(details)>4096 {details=details+h_len(details)-4096;}j_set(cu_reply,"error",j_string(h_cat("Worker failed before completing the turn.\n",details)));cu_stage("Turn failed.");
            if !cu_manual {let anchor=j_count(cu_context);if !cu_pending_recorded {cu_last_usage=cu_before_usage;anchor=cu_before_anchor;collie_message(cu_context,"user",cu_prompt);}collie_message(cu_context,"assistant","Turn failed before completing. Any in-flight execution may be incomplete.");cu_last_usage=co_context_usage(cu_context,cu_last_usage,anchor);}}
        cu_save();cu_dirty=1;
    }
    if cu_worker && net_now()-load64(p+80)>6400000 {cu_cancel();cu_stage("Turn timed out.");}return 0;
}

fn cu_menu(title,text) {cu_title=title;cu_panel=tu_clean(text);cu_panel_scroll=0;cu_scope=0;cu_dirty=1;return 0;}
fn cu_command(text) {
    cu_panel=0;let split=h_find(text," ");let name=text;let arg="";if split>=0 {name=h_slice(text,split);arg=h_trim(text+split+1);}
    if h_equal(name,"/quit") || h_equal(name,"/exit") {cu_running=0;}
    else if h_equal(name,"/help") {cu_menu("Collie help","/new /clear /sessions /resume latest|ID /history\n/model MODEL /code [on|off] /logs /help /quit\n\nEnter sends; Ctrl+J or Alt+Enter inserts a newline.\nArrows edit; Up/Down recall prompts; Shift+arrows select.\nCtrl+A selects all; Ctrl+E moves to end; Ctrl+U clears.\nCtrl+C copies selection or quits; Ctrl+X cuts; Ctrl+V pastes.\nDrag to select and copy; right-click pastes in the composer.\nClick a Flexscript heading or Ctrl+T to expand code and VM output.\nEsc stops the current turn. PageUp/PageDown and wheel scroll.\nTab completes commands. Bracketed paste never submits automatically.\n\nUser prose, generated code and actual VM observations are separate.\nErrors remain visible when code is collapsed.\nSessions are saved locally with mode 0600. /new resets model context.");}
    else if h_equal(name,"/new") {cu_cancel();cu_save();cu_new();}
    else if h_equal(name,"/clear") {cu_clear_at=j_count(cu_items);cu_scroll=0;cu_stage("Display cleared; conversation retained.");}
    else if h_equal(name,"/logs") {cu_menu("Activity log",h_data(cu_log));}
    else if h_equal(name,"/history") {cu_menu("Conversation",h_cat3("Session: ",cu_session,h_cat("\nSaved in: ",cu_history)));}
    else if h_equal(name,"/sessions") || (h_equal(name,"/resume") && !h_len(arg)) {let ids=cu_sessions();let out=h_buffer();h_text(out,"Saved conversations (newest first):\n");let i=0;while i<h_count(ids) && i<50 {h_text(out,h_cat(h_at(ids,i),"\n"));i=i+1;}if !i {h_text(out,"No saved conversations yet.\n");}h_text(out,"\n/resume latest or /resume ID");cu_menu("Sessions",h_data(out));}
    else if h_equal(name,"/resume") {cu_resume(arg);}
    else if h_equal(name,"/compact") {cu_limits_command(arg,1);}
    else if h_equal(name,"/context") {cu_limits_command(arg,0);}
    else if h_equal(name,"/model") {if !h_len(arg) {cu_menu("Model",h_cat("Current model: ",j_s(cu_config,"model")));}else if cu_worker {cu_stage("Esc stops the current turn before changing models.");}else if h_len(arg)>256 {cu_stage("Model ID is too long.");}else {cu_save();j_set(cu_config,"model",j_string(arg));cu_new();cu_stage(h_cat("Selected model: ",arg));}}
    else if h_equal(name,"/code") {if !h_len(arg) {arg="on";}if h_equal(arg,"on") || h_equal(arg,"off") {cu_show_code=h_equal(arg,"on");let i=0;while i<j_count(cu_items) {j_set(j_at(cu_items,i),"expanded",j_bool(cu_show_code));i=i+1;}cu_scope=0;cu_stage(h_cat("Code display: ",arg));}else {cu_stage("Use /code, /code on or /code off.");}}
    else {cu_stage("Unknown command. Type /help.");}
    if h_equal(name,"/help") {cu_panel=h_cat(cu_panel,"\n\n/context shows limits; /context N changes the window.\n/compact N changes the threshold; /compact default resets it.\n/context default resets both limits.\n/compact compacts model context now; it also runs automatically near the limit.\nThe visible transcript stays intact. Estimates use a ~ prefix.\n");}
    if h_equal(name,"/history") {let info=j_need(cu_config,"model_info");cu_panel=h_cat3(cu_panel,"\nWorkspace: ",j_s(cu_config,"workspace_file"));cu_panel=h_cat3(cu_panel,"\nUsable tokens: ",h_cat3(h_int(cu_window),"\nAuto-compact tokens: ",h_cat3(h_int(j_n(info,"auto_compact_token_limit")),"\nCompactions: ",h_int(cu_compactions))));}
    cu_dirty=1;return 0;
}
fn cu_document(hits,errors) {
    let out=h_buffer();let i=cu_clear_at;if i==j_count(cu_items) {h_text(out,"Welcome to Collie. Type a task or /help.\n\nPrograms execute inside the restricted Flexscript VM.\nChats are saved locally; /sessions and /resume restore them.\n");}
    while i<j_count(cu_items) {let m=j_at(cu_items,i);let title="Assistant";if h_equal(j_s(m,"role"),"user") {title="You";}h_text(out,h_cat(title,"\n"));h_text(out,tu_clean(j_s(m,"content")));
        let source=c_string(m,"source");let observation=j_get(m,"observation");
        if source && h_len(source) {h_text(out,"\n");let begin=h_size(out);let marker="[+] Flexscript";if c_flag(m,"expanded") {marker="[-] Flexscript";}h_text(out,h_cat(marker," | click to toggle\n"));if hits {let hit=h_take(24);store64(hit,begin);store64(hit+8,h_size(out));store64(hit+16,i);h_add(hits,hit);}if c_flag(m,"expanded") {h_text(out,tu_clean(source));h_text(out,"\n");}}
        if observation {h_text(out,tu_clean(cu_observation_label(observation)));let exit=j_get(observation,"exit_code");if exit && j_kind(exit)==1 && !h_equal(j_s(observation,"state"),"rejected") {h_text(out,h_cat3(" (exit ",h_int(j_value(exit)),")"));}h_text(out,"\n");let stdout=c_string(observation,"stdout");if c_flag(m,"expanded") && stdout && h_len(stdout) {h_text(out,"VM stdout:\n");h_text(out,tu_clean(stdout));h_text(out,"\n");}}
        let error=c_string(m,"error");let details=0;if observation {details=c_string(observation,"stderr");}
        if error && details && h_equal(error,details) {details=0;}
        if (error && h_len(error)) || (details && h_len(details)) {h_text(out,"\n");let begin=h_size(out);if error && h_len(error) {h_text(out,tu_clean(error));h_text(out,"\n");}if details && h_len(details) {h_text(out,tu_clean(details));h_text(out,"\n");}if errors {let range=h_take(16);store64(range,begin);store64(range+8,h_size(out));h_add(errors,range);}}
        h_text(out,"\n\n");i=i+1;}return h_data(out);
}
fn cu_editor_height() {let n=h_count(ts_wrap(h_data(te_text),tu_cols));if n>5 {n=5;}return n;}
fn cu_scroll_by(delta) {let mark=tu_mark();let height=tu_rows-cu_editor_height()-6;let last=h_count(ts_wrap(cu_document(0,0),tu_cols))-height;if last<0 {last=0;}cu_scroll=cu_scroll+delta;if cu_scroll<0 {cu_scroll=0;}if cu_scroll>last {cu_scroll=last;}tu_reset(mark);cu_dirty=1;return 0;}
fn cu_panel_by(delta) {let mark=tu_mark();let body=tu_rows-cu_editor_height()-7;let last=h_count(ts_wrap(cu_panel,tu_cols))-body;if last<0 {last=0;}cu_panel_scroll=cu_panel_scroll+delta;if cu_panel_scroll<0 {cu_panel_scroll=0;}if cu_panel_scroll>last {cu_panel_scroll=last;}tu_reset(mark);cu_dirty=1;return 0;}
fn cu_draw() {
    h_data(te_text);h_data(cu_log);let mark=tu_mark();tu_size();let out=h_buffer();h_text(out,tu_ansi("@[?25l"));
    let title=h_cat3(cu_context_label()," | Collie | ",tu_clean(j_s(cu_config,"model")));if h_len(j_s(cu_config,"replay")) {title=h_cat(title," | REPLAY");}tu_line(out,1,title,"1;36");
    cu_tick=net_now();let stage=tu_clean(cu_status);if cu_worker {stage=h_cat3(h_slice("|/-\\"+(cu_tick/100)%4,1)," ",h_cat3(stage," | ",h_cat(h_int((cu_tick-cu_stage_at)/1000),"s | Esc stop")));}tu_line(out,2,stage,"33");
    if cu_worker {tw_progress(out,3,0,0,cu_tick);}else {tu_line(out,3,h_repeat("-",tu_cols),"90");}
    let eh=cu_editor_height();let height=tu_rows-eh-6;if height<1 {tu_line(out,3,"Resize to at least 20 x 8.",0);h_print(1,h_data(out));tu_reset(mark);cu_dirty=0;return 0;}
    let errors=h_vec();let doc=cu_document(0,errors);let rows=ts_wrap(doc,tu_cols);let last=h_count(rows)-height;if last<0 {last=0;}if cu_scroll>last {cu_scroll=last;}let top=last-cu_scroll;
    let lo=-1;let hi=-1;if cu_scope==1 {lo=cu_select_start;hi=cu_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}}
    let i=0;while i<height {if top+i<h_count(rows) {let row=h_at(rows,top+i);let color=0;let j=0;while j<h_count(errors) {let e=h_at(errors,j);if load64(row)<load64(e+8) && load64(row+8)>load64(e) {color="33";}j=j+1;}ts_draw(out,doc,row,4+i,lo,hi,color);}else {tu_line(out,4+i,"",0);}i=i+1;}
    let context=h_cat3("Context ",h_int(cu_bytes),h_cat3(" B/8 MiB | ",h_int(cu_message_count),h_cat3(" messages | ",h_int(cu_compactions)," compactions")));
    tu_line(out,tu_rows-eh-2,h_cat3(context," | ",cu_session),"90");let label="Message";if cu_scroll {label=h_cat(label," | scrolled");}tu_line(out,tu_rows-eh-1,label,"1;32");
    if cu_panel {let bottom=tu_rows-eh-2;tw_panel(out,cu_title,cu_panel,bottom,bottom-3,cu_panel_scroll);}
    let help="Enter send | Ctrl+J newline | Esc stop | Ctrl+T code | /help";let draft=h_data(te_text);if load8(draft)==47 {let hints=h_buffer();i=0;while i<h_count(cu_commands) {let cmd=h_at(cu_commands,i);if h_starts(cmd,draft) {h_text(hints,h_cat(cmd,"  "));}i=i+1;}if h_size(hints) {help=h_cat("Tab: ",h_data(hints));}}
    tu_line(out,tu_rows,help,"90");tw_editor(out,tu_rows-eh,eh);h_print(1,h_data(out));tu_reset(mark);cu_dirty=0;return 0;
}
fn cu_selection_clear() {cu_scope=0;cu_selecting=0;te_anchor=-1;cu_dirty=1;return 0;}
fn cu_copy() {
    let text=0;if te_selected() {text=h_slice(h_data(te_text)+te_low(),te_high()-te_low());}else if cu_scope==1 {let doc=cu_document(0,0);let lo=cu_select_start;let hi=cu_select_end;if lo>hi {let t=lo;lo=hi;hi=t;}if hi>h_len(doc) {hi=h_len(doc);}if hi>lo {text=h_slice(doc+lo,hi-lo);}}
    if !text {return 0;}if tc_copy(text) {cu_stage("Copied selection.");}else {cu_stage(tc_error);}return 1;
}
fn cu_toggle(index) {let m=j_at(cu_items,index);j_set(m,"expanded",j_bool(!c_flag(m,"expanded")));cu_selection_clear();cu_scroll=0;cu_dirty=1;return 0;}
fn cu_toggle_latest() {let i=j_count(cu_items);while i {i=i-1;let source=c_string(j_at(cu_items,i),"source");if source && h_len(source) {return cu_toggle(i);}}return 0;}
fn cu_mouse() {
    if ti_button&64 {let delta=3;if ti_button&1 {delta=-3;}if cu_panel {return cu_panel_by(-delta);}return cu_scroll_by(delta);}
    let editor=h_data(te_text);let eh=cu_editor_height();let height=tu_rows-eh-6;
    if (ti_button&3)==2 && ti_y>=tu_rows-eh && !ti_release {let text=tc_paste();if text {te_replace(text);}else {cu_stage(tc_error);}return cu_selection_clear();}
    if (ti_button&3)!=0 {return 0;}if ti_release && !cu_selecting {return cu_selection_clear();}
    let dragging=ti_button&32;if dragging && !cu_selecting {return 0;}if !dragging && !ti_release {cu_selection_clear();}
    if cu_panel {return 0;}
    if ti_y>=4 && ti_y<4+height {let hits=h_vec();let doc=cu_document(hits,0);let rows=ts_wrap(doc,tu_cols);let top=h_count(rows)-height-cu_scroll;if top<0 {top=0;}let offset=ts_offset(doc,rows,top+ti_y-4,ti_x-1);
        if !dragging && !ti_release {cu_selecting=1;cu_scope=1;cu_select_start=offset;}if cu_scope==1 {cu_select_end=offset;}
        if ti_release && cu_scope==1 && cu_select_start==cu_select_end {let i=0;while i<h_count(hits) {let hit=h_at(hits,i);if offset>=load64(hit) && offset<load64(hit+8) {return cu_toggle(load64(hit+16));}i=i+1;}}}
    else if ti_y>=tu_rows-eh && ti_y<tu_rows {let rows=ts_wrap(editor,tu_cols);let crow=0;let i=0;while i<h_count(rows) {if te_cursor>=load64(h_at(rows,i)) {crow=i;}i=i+1;}let top=crow-eh+1;if top<0 {top=0;}let offset=ts_offset(editor,rows,top+ti_y-(tu_rows-eh),ti_x-1);
        if !dragging && !ti_release {cu_selecting=1;cu_scope=2;te_anchor=offset;}if cu_scope==2 {te_cursor=offset;}}
    if ti_release {cu_selecting=0;if cu_scope==1 && cu_select_start==cu_select_end {cu_scope=0;}if cu_scope==2 && !te_selected() {cu_scope=0;te_anchor=-1;}cu_copy();}cu_dirty=1;return 0;
}
fn cu_key() {
    if ti_kind==3 {cu_mouse();return 0;}if ti_kind==1 || ti_kind==4 {cu_panel=0;te_replace(ti_text);cu_scope=0;cu_dirty=1;return 0;}
    let key=ti_key;let shift=ti_mod&1;let ctrl=ti_mod&4;
    if cu_panel {if key==27 {cu_panel=0;cu_dirty=1;return 0;}if key==1001 || key==1008 {return cu_panel_by(-10);}if key==1002 || key==1009 {return cu_panel_by(10);}}
    if key==13 && !shift {cu_submit();}else if key==10 || (key==13 && shift) {te_replace("\n");}
    else if key==27 {cu_cancel();}else if key==3 {if !cu_copy() {cu_running=0;}}else if key==4 {cu_running=0;}
    else if key==1 {te_anchor=0;te_cursor=h_size(te_text);cu_scope=2;}else if key==5 {te_move(h_size(te_text),0);}
    else if key==20 {cu_toggle_latest();}else if key==21 {te_set("");}else if key==23 {te_anchor=te_cursor;te_word(1,1);te_replace("");}
    else if key==24 {if te_selected() {cu_copy();te_replace("");}}else if key==22 {let text=tc_paste();if text {te_replace(text);}else {cu_stage(tc_error);}}
    else if key==127 || key==8 {te_backspace();}else if key==1007 {te_delete();}
    else if key==1004 {if ctrl {te_word(1,shift);}else {te_left(shift);}}else if key==1003 {if ctrl {te_word(0,shift);}else {te_right(shift);}}
    else if key==1005 {if ctrl {te_move(0,shift);}else {te_line_edge(0,shift);}}else if key==1006 {if ctrl {te_move(h_size(te_text),shift);}else {te_line_edge(1,shift);}}
    else if key==1001 {te_vertical(0,shift,tu_cols);}else if key==1002 {te_vertical(1,shift,tu_cols);}
    else if key==1008 {cu_scroll_by(10);}else if key==1009 {cu_scroll_by(-10);}
    else if key==9 {let text=h_data(te_text);let i=0;let found=0;while i<h_count(cu_commands) && !found {let cmd=h_at(cu_commands,i);if h_starts(cmd,text) {te_set(h_cat(cmd," "));found=1;}i=i+1;}}
    cu_dirty=1;return 0;
}
fn collie_tui(config) {
    let terminal=h_take(64);h_assert(syscall(16,0,0x5401,terminal,0,0,0)==0 && syscall(16,1,0x5401,terminal,0,0,0)==0,"interactive terminal required; pass a quoted task for plain output");
    cu_config=config;cu_workspace_override=c_string(config,"workspace_file");cu_binary=h_real("/proc/self/exe");cu_show_code=c_flag(config,"stream");cu_log=h_buffer();h_data(cu_log);cu_scratch=h_take(8208);
    cu_history=j_s(config,"history_dir");if !h_len(cu_history) {let base=h_getenv("XDG_STATE_HOME");if !base || !h_len(base) {let home=h_getenv("HOME");h_assert(home,"HOME or --history-dir is required");base=h_join(home,".local/state");}cu_history=h_join(base,"collie/sessions");}
    let existing=h_exists(cu_history);h_mkdir(cu_history);cu_history=h_real(cu_history);if !existing {syscall(90,cu_history,448,0,0,0,0);}cu_new();te_init();ti_init();
    cu_commands=h_args("/help","/new","/clear","/sessions","/resume","/history");h_add(cu_commands,"/compact");h_add(cu_commands,"/context");h_add(cu_commands,"/model");h_add(cu_commands,"/code");h_add(cu_commands,"/logs");h_add(cu_commands,"/quit");
    let resume=j_s(config,"resume");if h_len(resume) {cu_resume(resume);}h_assert(tu_open(),"interactive terminal required; pass a quoted task for plain output");
    let prompt=j_s(config,"prompt");if h_len(prompt) {te_set(prompt);cu_submit();}
    while cu_running {cu_pump();let tick=net_now();if cu_dirty || (cu_worker && tick-cu_tick>=100) {cu_draw();}let ready=ti_wait(30);if ready==2 {cu_running=0;}
        while ti_next(ready==0) {cu_key();}if ti_overflow {cu_stage("Paste exceeds 128 KiB.");ti_overflow=0;}
        let cols=tu_cols;let rows=tu_rows;let mark=tu_mark();tu_size();tu_reset(mark);if cols!=tu_cols || rows!=tu_rows {cu_dirty=1;}}
    tu_close();cu_cancel();cu_save();return 0;
}
