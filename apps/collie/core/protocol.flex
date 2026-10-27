// Native Responses tool definitions and separate prose/source display streams.
import "events.flex";
global pp_message_fd=-1;
global pp_debug_fd=-1;
global pp_text=0;
global pp_text_size=0;
global pp_text_sent=0;
global pp_code=0;
global pp_code_size=0;
global pp_code_sent=0;
global pp_problem=0;
fn pt_id(value) {if !value || !h_len(value) || h_len(value)>256 {return 0;}let i=0;while load8(value+i) {let c=load8(value+i);if c<33 || c>126 {return 0;}i=i+1;}return 1;}
fn pt_tool() {
    let tool=j_object();j_set(tool,"type",j_string("custom"));j_set(tool,"name",j_string("flexscript"));
    j_set(tool,"description",j_string("Execute one complete Flexscript program in a restricted VM with persistent FlexDB. Input is raw Flexscript source, without tags or Markdown fences. db_* functions are preloaded. Returns stdout, stderr, exit_code and execution state. Host files, network, processes and FFI are unavailable. Wait for the real result before reporting execution outcomes."));return tool;
}
fn pt_call(item) {
    if !h_equal(c_string(item,"type"),"custom_tool_call") || !h_equal(c_string(item,"name"),"flexscript") {return 0;}
    let id=c_string(item,"call_id");let source=c_string(item,"input");let status=c_string(item,"status");
    if !pt_id(id) || !source || h_len(source)>65536 || (status && !h_equal(status,"completed")) {return 0;}
    let result=j_object();j_set(result,"type",j_string("custom_tool_call"));j_set(result,"call_id",j_string(id));j_set(result,"name",j_string("flexscript"));j_set(result,"input",j_string(source));j_set(result,"status",j_string("completed"));
    let item_id=c_string(item,"id");if item_id {if !pt_id(item_id) {return 0;}j_set(result,"id",j_string(item_id));}return result;
}
fn pt_result(item) {
    if !h_equal(c_string(item,"type"),"custom_tool_call_output") {return 0;}let id=c_string(item,"call_id");let output=c_string(item,"output");if !pt_id(id) || !output || h_len(output)>1048576 {return 0;}
    let result=j_object();j_set(result,"type",j_string("custom_tool_call_output"));j_set(result,"call_id",j_string(id));j_set(result,"output",j_string(output));return result;
}
fn pt_summary_parts(item){
    let parts=j_get(item,"summary");let out=j_array();if !parts{return out;}if j_kind(parts)!=3 || j_count(parts)>128{return 0;}let i=0;let bytes=0;
    while i<j_count(parts){let part=j_at(parts,i);let text=c_string(part,"text");if !h_equal(c_string(part,"type"),"summary_text") || !text{return 0;}bytes=bytes+h_len(text);if bytes>65536{return 0;}let p=j_object();j_set(p,"type",j_string("summary_text"));j_set(p,"text",j_string(text));j_push(out,p);i=i+1;}return out;
}
fn pt_reasoning(item) {
    if !h_equal(c_string(item,"type"),"reasoning") {return 0;}let cipher=c_string(item,"encrypted_content");if !cipher || !h_len(cipher) || h_len(cipher)>1048576 {return 0;}
    let summary=pt_summary_parts(item);if !summary{return 0;}let result=j_object();j_set(result,"type",j_string("reasoning"));j_set(result,"encrypted_content",j_string(cipher));j_set(result,"summary",summary);let id=c_string(item,"id");if id {if !pt_id(id) {return 0;}j_set(result,"id",j_string(id));}return result;
}
fn pt_seen(items,id,before) {let i=0;while i<before {let item=j_at(items,i);if h_equal(c_string(item,"type"),"custom_tool_call") && h_equal(c_string(item,"call_id"),id) {return 1;}i=i+1;}return 0;}
fn pp_reset() {
    pp_text=h_take(65537);pp_code=h_take(65537);store8(pp_text,0);store8(pp_code,0);
    pp_text_size=0;pp_code_size=0;pp_text_sent=0;pp_code_sent=0;pp_problem=0;return 0;
}
fn pp_emit() {
    if pp_message_fd>=0 && pp_text_size>pp_text_sent {if ce_enabled {ce_text(pp_message_fd,"message_delta",h_slice(pp_text+pp_text_sent,pp_text_size-pp_text_sent));}else {h_write(pp_message_fd,pp_text+pp_text_sent,pp_text_size-pp_text_sent);}pp_text_sent=pp_text_size;}
    if ce_enabled && pp_message_fd>=0 && pp_code_size>pp_code_sent {ce_text(pp_message_fd,"source_delta",h_slice(pp_code+pp_code_sent,pp_code_size-pp_code_sent));pp_code_sent=pp_code_size;}
    if pp_debug_fd>=0 && pp_code_size>pp_code_sent {if !pp_code_sent {h_print(pp_debug_fd,"Collie: source\n");}h_write(pp_debug_fd,pp_code+pp_code_sent,pp_code_size-pp_code_sent);pp_code_sent=pp_code_size;}return 0;
}
fn pp_feed(text) {
    let n=h_len(text);if n>65536-pp_text_size {pp_problem="Assistant text exceeded 64 KiB.";return 0;}h_copy(pp_text+pp_text_size,text,n);pp_text_size=pp_text_size+n;store8(pp_text+pp_text_size,0);pp_emit();return 1;
}
fn pp_source(text) {
    let n=h_len(text);if n>65536-pp_code_size {pp_problem="Flexscript tool input exceeded 64 KiB.";return 0;}h_copy(pp_code+pp_code_size,text,n);pp_code_size=pp_code_size+n;store8(pp_code+pp_code_size,0);pp_emit();return 1;
}
fn pp_finish() {pp_emit();return !pp_problem;}
