import "../core/cli.flex";
import "../../../scripts/lib/harness.flex";
import "workspace.flex";

global ct_collie=0;
global ct_vm_enabled=0;

fn ct_message(text) {let part=j_object();j_set(part,"type",j_string("output_text"));j_set(part,"text",j_string(text));let content=j_array();j_push(content,part);let item=j_object();j_set(item,"type",j_string("message"));j_set(item,"role",j_string("assistant"));j_set(item,"content",content);return item;}
fn ct_call(source,id) {let call=j_object();j_set(call,"type",j_string("custom_tool_call"));j_set(call,"name",j_string("flexscript"));j_set(call,"call_id",j_string(id));j_set(call,"id",j_string("ctc_test"));j_set(call,"status",j_string("completed"));j_set(call,"input",j_string(source));return call;}
fn ct_event(output) {let response=j_object();j_set(response,"status",j_string("completed"));j_set(response,"output",output);let event=j_object();j_set(event,"type",j_string("response.completed"));j_set(event,"response",response);return event;}
fn ct_reply(text) {let output=j_array();j_push(output,ct_message(text));return ct_event(output);}
fn ct_tool_reply(source) {let output=j_array();j_push(output,ct_call(source,"call_test"));return ct_event(output);}
fn ct_replay(source) {let item=j_object();let output=j_array();j_push(output,ct_call(source,"call_replay"));j_set(item,"output",output);return item;}
fn ct_source_delta(text) {let event=j_object();j_set(event,"type",j_string("response.custom_tool_call_input.delta"));j_set(event,"item_id",j_string("ctc_test"));j_set(event,"delta",j_string(text));return h_cat3("data: ",j_dump(event),"\n\n");}

fn ct_delta(text) {
    let event=j_object();j_set(event,"type",j_string("response.output_text.delta"));
    j_set(event,"delta",j_string(text));return h_cat3("data: ",j_dump(event),"\n\n");
}
fn ct_stream(text,chunked) {
    co_problem=0;http_buffer=text;http_start=0;http_end=h_len(text);
    co_chunked=chunked;co_remaining=h_len(text);if chunked {co_remaining=0;}
    co_chunk_crlf=0;co_body_size=0;co_body_eof=0;
    co_line=h_take(8193);return co_receive();
}
fn ct_hex(n) {
    let p=h_take(32);let i=31;store8(p+i,0);let more=1;
    while more {i=i-1;store8(p+i,load8("0123456789abcdef"+n%16));n=n/16;if !n {more=0;}}
    return p+i;
}
fn ct_auth() {
    let file=h_join(t_work,"auth.json");
    let fixture="{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"fixture-access\",\"account_id\":\"fixture-account\",\"refresh_token\":\"private-refresh\"}}";
    h_save(file,fixture);let before=h_sha(file);let headers=co_auth(file);
    t_assert(headers && h_equal(j_s(headers,"access"),"fixture-access"),"ChatGPT access token");
    t_assert(h_equal(j_s(headers,"account"),"fixture-account"),"account header");
    t_assert(h_equal(before,h_sha(file)),"auth file must stay unchanged");
    h_save(file,"{\"tokens\":{\"access_token\":\"access\",\"account_id\":\"account\"}}");
    t_assert(co_auth(file),"legacy cache without auth_mode");
    h_save(file,"{\"auth_mode\":null,\"tokens\":{\"access_token\":\"access\",\"account_id\":\"account\"}}");
    t_assert(co_auth(file),"nullable auth_mode");
    h_save(file,"{\"auth_mode\":\"apikey\",\"OPENAI_API_KEY\":\"private-key\"}");
    t_assert(!co_auth(file) && !h_has(co_problem,"private-key"),"API keys rejected without disclosure");
    h_save(file,"{\"tokens\":{\"access_token\":\"bad\\nheader\",\"account_id\":\"account\"}}");
    t_assert(!co_auth(file),"credential header injection rejected");
    t_assert(!co_auth(h_join(t_work,"missing-auth.json")),"missing auth rejected");
    let saved=h_env;h_setenv("CODEX_HOME",t_work);
    t_assert(h_equal(co_auth_path(),file),"CODEX_HOME auth path");h_env=saved;
    t_assert(h_has(co_http_status(401),"refresh") && h_has(co_http_status(429),"limit"),"auth and rate-limit errors");
}
fn ct_request() {
    let messages=j_array();collie_message(messages,"user","a task");collie_message(messages,"assistant","fn main(){return 0;}");
    let request=co_request("fixture-model",messages);
    t_assert(j_count(j_need(request,"tools"))==1 && h_equal(j_s(j_at(j_need(request,"tools"),0),"name"),"flexscript") && h_equal(j_s(j_at(j_need(request,"tools"),0),"type"),"custom") && h_equal(j_s(request,"tool_choice"),"auto") && !j_n(request,"parallel_tool_calls"),"exactly one native Flexscript tool with sequential calls");
    t_assert(!j_n(request,"store") && j_n(request,"stream"),"streaming without server storage");
    let input=j_need(request,"input");
    t_assert(h_equal(j_s(j_at(j_need(j_at(input,1),"content"),0),"type"),"output_text"),"assistant history content type");
    t_assert(!h_has(j_dump(request),"fixture-access") && !h_has(j_dump(request),"private-refresh"),"request contains no credentials");
    let parsed=c_json("{\"float\":1.25e-3,\"int\":42,\"large\":99999999999999999999999999,\"text\":\"1.25\"}");
    t_assert(j_kind(j_need(parsed,"float"))==6 && j_n(parsed,"int")==42 && j_kind(j_need(parsed,"large"))==6,"JSON numeric metadata");
    t_assert(h_equal(j_s(parsed,"text"),"1.25"),"JSON numeric parser preserves strings");
    t_assert(h_equal(j_dump(parsed),"{\"float\":1.25e-3,\"int\":42,\"large\":99999999999999999999999999,\"text\":\"1.25\"}"),"raw fractional and large numeric metadata serializes exactly without treating numeric text as an array");
    let valid=h_args("0","-0","1.25e-3","-12.5E+9","9223372036854775808","-0.0");let n=0;while n<h_count(valid){let raw=h_at(valid,n);t_assert(j_raw_number(raw)&&h_equal(j_dump(j_node(6,raw)),raw),"exact JSON number writer");n=n+1;}
    let invalid=h_args("","-","01","1.",".5","1e+");h_add(invalid,"NaN");h_add(invalid,"Infinity");h_add(invalid,"1,\"injected\":true");h_add(invalid," 1");n=0;while n<h_count(invalid){t_assert(!j_raw_number(h_at(invalid,n)),"raw numeric metadata rejects invalid or compound JSON");n=n+1;}
}
fn ct_sse() {
    let source="fn main(){return 42;}";let event=ct_tool_reply(source);let text=h_cat3(": keepalive\r\n\r\ndata: ",j_dump(event),"\r\n\r\n");let reply=ct_stream(text,0);
    t_assert(reply && h_equal(j_s(reply,"source"),source) && pt_call(j_get(reply,"tool_call")),"completed native tool source");
    text=h_replace(text,"\"status\":\"completed\"","\"status\":\"completed\",\"duration\":1.25e-3");t_assert(h_equal(j_s(ct_stream(text,0),"source"),source),"SSE fractional metadata");
    let split=21;let chunks=h_cat3(ct_hex(split),"\r\n",h_slice(text,split));chunks=h_cat3(chunks,"\r\n",h_cat3(ct_hex(h_len(text)-split),"\r\n",text+split));chunks=h_cat(chunks,"\r\n0\r\n\r\n");
    t_assert(h_equal(j_s(ct_stream(chunks,1),"source"),source),"chunked SSE across event lines");
    t_assert(!ct_stream(ct_source_delta(source),0) && h_has(co_problem,"before response.completed"),"tool input delta never authorizes execution");
    t_assert(!ct_stream("data: {\"type\":\"response.incomplete\"}\n\n",0),"incomplete response rejected");
    let response=j_need(event,"response");j_set(response,"status",j_string("incomplete"));co_problem=0;co_stream_reset();t_assert(!co_completed(event) && co_problem,"incomplete completion rejected");
    let output=j_array();let call=ct_call(source,"call_test");j_set(call,"name",j_string("shell"));j_push(output,call);t_assert(!ct_stream(h_cat3("data: ",j_dump(ct_event(output)),"\n\n"),0),"unregistered tool rejected");
    j_set(call,"name",j_string("flexscript"));j_set(call,"call_id",j_string(""));t_assert(!ct_stream(h_cat3("data: ",j_dump(ct_event(output)),"\n\n"),0),"missing call ID rejected");
    j_set(call,"call_id",j_string("call_test"));j_set(call,"status",j_string("in_progress"));t_assert(!ct_stream(h_cat3("data: ",j_dump(ct_event(output)),"\n\n"),0),"unfinished tool item rejected");
    j_set(call,"status",j_string("completed"));j_push(output,ct_call(source,"call_second"));t_assert(!ct_stream(h_cat3("data: ",j_dump(ct_event(output)),"\n\n"),0),"multiple calls rejected before execution");
    source=h_cat3("// ",h_repeat("\"",40000),"\nfn main(){return 42;}");reply=ct_stream(h_cat3("data: ",j_dump(ct_tool_reply(source)),"\n\n"),0);t_assert(reply && h_equal(j_s(reply,"source"),source),"JSON transport escaping preserves raw tool code");
    source="fn main(){return 42;}";text=h_cat(ct_delta("Checking.\n"),ct_source_delta("fn main(){"));text=h_cat(text,ct_source_delta("return 42;}"));output=j_array();j_push(output,ct_message("Checking.\n"));j_push(output,ct_call(source,"call_test"));text=h_cat(text,h_cat3("data: ",j_dump(ct_event(output)),"\n\n"));reply=ct_stream(text,0);
    t_assert(reply && h_equal(j_s(reply,"source"),source) && h_equal(j_s(reply,"message"),"Checking.\n") && pp_code_size==h_len(source),"prose and source streams stay separate without duplicate completion");
    text=h_cat(ct_source_delta("fn main(){return 0;}"),h_cat3("data: ",j_dump(ct_tool_reply(source)),"\n\n"));t_assert(!ct_stream(text,0) && h_has(co_problem,"differed"),"completed code must match previewed tool input");
    text=h_replace(ct_source_delta(source),"ctc_test","ctc_other");text=h_cat(text,h_cat3("data: ",j_dump(ct_tool_reply(source)),"\n\n"));t_assert(!ct_stream(text,0) && h_has(co_problem,"ID differed"),"tool stream item identity is verified");
    text=h_cat(ct_source_delta("fn main(){"),h_replace(ct_source_delta("return 42;}"),"ctc_test","ctc_other"));t_assert(!ct_stream(text,0),"different tool streams cannot be mixed");
    t_assert(!ct_stream(ct_source_delta(h_repeat("x",65537)),0) && h_has(co_problem,"64 KiB"),"streamed tool input cap");
    t_assert(!ct_stream(ct_delta(h_repeat("x",65537)),0) && h_has(co_problem,"64 KiB"),"streamed assistant text cap");
    let literal="<FLEXSCRIPT>fn main(){return 42;}</FLEXSCRIPT> fina?";reply=ct_stream(h_cat3("data: ",j_dump(ct_reply(literal)),"\n\n"),0);t_assert(reply && !c_flag(reply,"has_code") && h_equal(j_s(reply,"message"),literal),"tags in ordinary assistant text never execute");
    output=j_array();j_push(output,ct_call(source,"call_test"));j_push(output,ct_message("A separate assistant message."));reply=ct_stream(h_cat3("data: ",j_dump(ct_event(output)),"\n\n"),0);t_assert(reply && c_flag(reply,"has_code") && h_equal(j_s(reply,"message"),"A separate assistant message."),"native message boundaries need no end tag rule");
    event=ct_reply("Measured reply.");response=j_need(event,"response");let usage=j_object();j_set(usage,"input_tokens",j_int(100));j_set(usage,"output_tokens",j_int(23));j_set(usage,"total_tokens",j_int(999));j_set(response,"usage",usage);reply=ct_stream(h_cat3("data: ",j_dump(event),"\n\n"),0);t_assert(reply && co_last_usage && j_n(co_last_usage,"total_tokens")==999,"reported total usage retained");
    reply=ct_stream(h_cat3("data: ",j_dump(ct_reply("No usage.")),"\n\n"),0);t_assert(reply && !co_last_usage,"missing usage does not reuse previous count");
    j_set(usage,"input_tokens",j_int(-1));t_assert(!co_usage(usage),"negative token count ignored");j_set(usage,"input_tokens",j_string("100"));t_assert(!co_usage(usage),"noninteger token count ignored");
}

fn ct_stream_fixture(message_mode) {
    let pipes=h_take(8);h_assert(syscall(293,pipes,0x80800,0,0,0,0)==0,"fixture pipe");let read_fd=load64(pipes)&0xffffffff;let write_fd=load64(pipes)>>32;let pid=syscall(57,0,0,0,0,0,0);h_assert(pid>=0,"fixture fork");
    if !pid {syscall(157,1,9,0,0,0,0);h_close(read_fd);let prefix="fn main(){";let suffix="return 42;}";if message_mode {prefix="Hello ";suffix="there!\n";}let first=ct_source_delta(prefix);if message_mode {first=ct_delta(prefix);}h_write(write_fd,first,h_len(first));h_sleep(500);
        let last=ct_source_delta(suffix);let event=ct_tool_reply(h_cat(prefix,suffix));if message_mode {last=ct_delta(suffix);event=ct_reply(h_cat(prefix,suffix));}let rest=h_cat(last,h_cat3("data: ",j_dump(event),"\n\n"));h_write(write_fd,rest,h_len(rest));h_close(write_fd);syscall(60,0,0,0,0,0,0);}
    h_close(write_fd);http_session=h_zero(h_take(32),32);store64(http_session+16,read_fd);store64(http_session+24,net_now()+3000);http_buffer=h_take(8192);http_start=0;http_end=0;co_line=h_take(8193);co_chunked=0;co_remaining=-1;co_chunk_crlf=0;co_body_size=0;co_body_eof=0;co_problem=0;co_stream_fd=2;if message_mode {co_message_fd=2;co_stream_fd=-1;}
    let reply=co_receive();h_close(read_fd);let status=h_take(8);syscall(61,pid,status,0,0,0,0);h_assert(reply,"fixture stream failed");let source=j_s(reply,"source");if message_mode {source=j_s(reply,"message");}let result=j_object();j_set(result,"source",j_string(source));h_print(1,j_dump(result));return 0;
}

fn ct_stream_forwarding() {
    let child=h_spawn(h_args("/proc/self/exe","--stream-fixture-parent",0,0,0,0),"",0);
    let deadline=net_now()+2000;
    while !h_has(h_err(child),"fn main(){") && net_now()<deadline {h_pump(child,5);}
    let visible=h_has(h_err(child),"fn main(){");
    let before_completion=visible && h_status(child)==-999 && h_size(load64(child+16))==0;
    if !visible {h_stop(child);}
    t_assert(before_completion,"source is forwarded before the response completes");
    h_wait(child);h_check(child,0,0);let reply=c_json(h_out(child));
    t_assert(h_equal(j_s(reply,"source"),"fn main(){return 42;}"),"stream preserves completed worker JSON");
    t_assert(h_equal(h_err(child),"Collie: source\nfn main(){return 42;}\n"),"displayed source is emitted exactly once");
}
fn ct_message_forwarding() {
    let child=h_spawn(h_args("/proc/self/exe","--message-fixture-parent",0,0,0,0),"",0);
    let deadline=net_now()+2000;
    while !h_has(h_err(child),"Hello ") && net_now()<deadline {h_pump(child,5);}
    let live=h_has(h_err(child),"Hello ") && h_status(child)==-999 && h_size(load64(child+16))==0;
    if !live {h_stop(child);}
    t_assert(live,"user prose streams before response completion");
    h_wait(child);h_check(child,0,0);
    t_assert(h_equal(h_err(child),"Hello there!\n"),"user prose streams exactly once without source labels");
}
fn ct_protocol() {
    let messages=j_array();collie_message(messages,"user","task");let call=ct_call("fn main(){return 0;}","call_pair");j_push(messages,call);t_assert(!co_history_valid(messages),"unfinished tool call cannot be saved or sent");
    let result=j_object();j_set(result,"type",j_string("custom_tool_call_output"));j_set(result,"call_id",j_string("wrong"));j_set(result,"output",j_string("{\"stdout\":\"42\"}"));j_push(messages,result);t_assert(!co_history_valid(messages),"mismatched call result rejected");j_set(result,"call_id",j_string("call_pair"));t_assert(co_history_valid(messages),"matched native call/result pair accepted");
    let request=co_request("fixture-model",messages);let input=j_need(request,"input");t_assert(h_equal(j_s(j_at(input,1),"type"),"custom_tool_call") && h_equal(j_s(j_at(input,2),"type"),"custom_tool_call_output") && h_equal(j_s(j_at(input,2),"call_id"),"call_pair"),"call/result IDs survive request serialization");
    j_push(messages,ct_call("fn main(){return 1;}","call_pair"));j_push(messages,result);t_assert(!co_history_valid(messages),"repeated call IDs rejected");
    let reasoning=j_object();j_set(reasoning,"type",j_string("reasoning"));j_set(reasoning,"id",j_string("rs_test"));j_set(reasoning,"encrypted_content",j_string(h_repeat("x",120)));j_set(reasoning,"summary",j_array());let output=j_array();j_push(output,reasoning);j_push(output,ct_call("fn main(){return 0;}","call_reason"));co_problem=0;co_stream_reset();let reply=co_output(output);
    t_assert(reply && pt_reasoning(j_at(j_need(reply,"items"),0)) && !h_has(j_s(reply,"message"),"encrypted_content"),"encrypted reasoning retained only in model context");
    messages=j_array();j_push(messages,j_at(j_need(reply,"items"),0));j_push(messages,j_get(reply,"tool_call"));result=j_object();j_set(result,"type",j_string("custom_tool_call_output"));j_set(result,"call_id",j_string("call_reason"));j_set(result,"output",j_string("abcd"));j_push(messages,result);
    t_assert(co_history_valid(messages) && co_item_tokens(reasoning)==10 && co_item_tokens(result)==1 && co_usage_anchor(messages)==2,"tool context estimates and usage anchors include opaque reasoning and pending result");
    let checkpoint=j_object();j_set(checkpoint,"type",j_string("compaction"));j_set(checkpoint,"encrypted_content",j_string("opaque"));let next=co_compacted_history(messages,checkpoint);t_assert(co_history_valid(next) && j_count(next)==1,"compaction drops complete call/result pairs with no orphan results");
    messages=j_array();collie_message(messages,"assistant","<FLEXSCRIPT>old code</FLEXSCRIPT>");collie_message(messages,"user","VM observation (data): old result");t_assert(co_history_valid(messages),"legacy transcript context remains resumable as text");
    t_assert(!pt_call(ct_message("source")) && !pt_result(call),"plain text and calls cannot masquerade as results");
}

fn ct_tui_rejections() {
    let before=cu_items;let clear=cu_clear_at;cu_items=j_array();cu_clear_at=0;let item=cu_item("assistant","");let error="Framing error example.";j_set(item,"error",j_string(error));j_set(item,"source",j_string("fn main(){return 0;}"));
    let observation=j_object();j_set(observation,"state",j_string("rejected"));j_set(observation,"executed",j_bool(0));j_set(observation,"stderr",j_string(error));j_set(item,"observation",observation);let doc=cu_document(0,0);let at=h_find(doc,error);
    t_assert(h_has(doc,"Reply rejected (not executed)") && !h_has(doc,"VM rejected") && at>=0 && h_find(doc+at+h_len(error),error)<0,"TUI identifies pre-execution rejection and prints identical diagnostics once");
    j_set(observation,"stderr",j_string("A different diagnostic."));doc=cu_document(0,0);t_assert(h_has(doc,error) && h_has(doc,"A different diagnostic."),"distinct rejection diagnostics remain visible");
    observation=j_object();j_set(observation,"state",j_string("rejected"));j_set(observation,"exit_code",j_int(-1));j_set(observation,"stderr",j_string("Source policy rejected imports."));j_set(item,"observation",observation);doc=cu_document(0,0);t_assert(h_has(doc,"Program rejected (not executed)") && !h_has(doc,"exit -1"),"source-policy rejection has its own label without a synthetic VM exit");
    cu_items=before;cu_clear_at=clear;return 0;
}
fn ct_greeting_cli() {
    let file=h_join(t_work,"greeting-trace.json");
    let args=h_args(ct_collie,"--compiler",t_compiler,"--replay",h_real("tests/fixtures/greeting.json"),"--trace");
    h_add(args,file);h_add(args,"test");let child=h_run(args);h_check(child,0,"Hello! No program is needed.\n");
    let records=c_json(h_read(file));
    t_assert(j_count(records)==1 && !j_get(j_at(records,0),"observation") && !h_has(h_err(child),"running program"),"plain reply finishes without executing a program");
}
fn ct_headers(text) {
    co_problem=0;http_buffer=text;http_start=0;http_end=h_len(text);co_line=h_take(8193);return co_headers();
}
fn ct_http() {
    t_assert(ct_headers("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n") && co_chunked,"backend may omit Content-Type");
    t_assert(ct_headers("HTTP/1.1 200 OK\r\nContent-Type: Text/Event-Stream; charset=utf-8\r\nContent-Length: 123\r\n\r\n") && co_remaining==123,"HTTP type casing and content length");
    t_assert(!ct_headers("HTTP/1.1 307 Redirect\r\n\r\n") && h_has(co_problem,"307"),"never follow redirects with credentials");
    t_assert(!ct_headers("HTTP/1.1 401 Unauthorized\r\n\r\n") && h_has(co_problem,"refresh"),"HTTP unauthorized response");
    t_assert(!ct_headers("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 12\r\n\r\n"),"ambiguous HTTP framing rejected");
    t_assert(!ct_headers("HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n"),"duplicate body length rejected");
    t_assert(!ct_headers("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n"),"unexpected content type rejected");
    t_assert(!ct_headers("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n"),"unsupported compression rejected");
    t_assert(!ct_headers("HTTP/1.1 200 OK\r\n Bad-Header: value\r\n\r\n"),"folded header rejected");
}
fn ct_policy() {
    t_assert(cp_validate("import \"/etc/passwd\";fn main(){return 42;}"),"imports rejected");
    t_assert(cp_validate("extend \"plugin.flex\";fn main(){return 42;}"),"extensions rejected");
    t_assert(cp_validate("```flex\nfn main(){return 42;}\n```"),"Markdown fences rejected");
    t_assert(!cp_validate("// import extend ```\nfn main(){let s=\"import \\\" extend ```\";return 42;}"),"quoted/comment text allowed");
    t_assert(cp_validate(h_repeat(" ",65537)),"oversized source rejected");
    let b=h_buffer();let raw=h_take(8);store8(raw,0);store8(raw+1,255);store8(raw+2,65);h_append(b,raw,3);
    t_assert(h_equal(cp_text(b),"\\0�A"),"binary output is safe JSON text");
}
fn ct_compaction() {
    let model=j_object();j_set(model,"context_window",j_int(272000));j_set(model,"max_context_window",j_int(872000));let config=j_object();let limits=co_model_limits(model,config);
    t_assert(j_n(limits,"usable_context_window")==258400 && j_n(limits,"auto_compact_token_limit")==244800,"Codex default usable and compaction windows");
    let defaults=j_object();j_set(defaults,"model",j_string("gpt-6.1-sol"));j_set(defaults,"auth_file",j_string(h_join(t_work,"auth.json")));
    h_save(h_join(t_work,"models_cache.json"),"{\"models\":[{\"slug\":\"gpt-6.1-sol\",\"context_window\":500000,\"max_context_window\":872000}]}");
    let actual=co_model_info(defaults);t_assert(j_n(actual,"context_window")==272000 && j_n(actual,"auto_compact_token_limit")==244800,"shared cache cannot enlarge bundled default");
    j_set(defaults,"model_context_window",j_int(500000));actual=co_model_info(defaults);t_assert(j_n(actual,"usable_context_window")==475000 && j_n(actual,"auto_compact_token_limit")==450000,"expanded window requires explicit opt-in");
    let old_usage=cx_usage;let old_anchor=cx_anchor;let boundary=j_array();cx_anchor=0;cx_usage=j_object();j_set(cx_usage,"total_tokens",j_int(244799));
    t_assert(!collie_needs_compaction(boundary,limits),"no compaction immediately below Codex default limit");
    j_set(cx_usage,"total_tokens",j_int(244800));t_assert(collie_needs_compaction(boundary,limits),"compaction at exact Codex default limit");
    j_set(cx_usage,"total_tokens",j_int(258400));t_assert(collie_needs_compaction(boundary,limits),"compaction above default limit");
    j_set(limits,"usable_context_window",j_int(200000));j_set(cx_usage,"total_tokens",j_int(200000));t_assert(collie_needs_compaction(boundary,limits),"usable context cap independently triggers compaction");
    limits=co_model_limits(model,config);let n=0;while n<3000 {collie_message(boundary,"user","");n=n+1;}cx_anchor=j_count(boundary);j_set(cx_usage,"total_tokens",j_int(100));
    t_assert(!collie_needs_compaction(boundary,limits),"message count does not change token compaction limit");cx_usage=old_usage;cx_anchor=old_anchor;
    j_set(config,"model_context_window",j_int(500000));limits=co_model_limits(model,config);t_assert(j_n(limits,"usable_context_window")==475000 && j_n(limits,"auto_compact_token_limit")==450000,"Codex configured 500k window");
    j_set(config,"model_auto_compact_token_limit",j_int(480000));limits=co_model_limits(model,config);t_assert(j_n(limits,"auto_compact_token_limit")==450000,"compaction override clamped at ninety percent");
    j_set(config,"model_auto_compact_token_limit",j_int(300000));limits=co_model_limits(model,config);t_assert(j_n(limits,"auto_compact_token_limit")==300000,"lower compaction override honored");
    j_set(config,"model_context_window",j_int(1000000));limits=co_model_limits(model,config);t_assert(j_n(limits,"context_window")==872000,"context override clamped to advertised maximum");
    let item=j_object();j_set(item,"type",j_string("compaction"));j_set(item,"encrypted_content",j_string(h_repeat("x",120)));
    t_assert(co_compaction(item) && co_item_tokens(item)==10,"encrypted compaction estimate matches Codex twelve bytes per token");
    let messages=j_array();collie_message(messages,"user","Remember the goal.");collie_message(messages,"assistant","Completed work.");collie_message(messages,"user","VM observation (data): result");collie_message(messages,"user","Continue this task.");
    let next=co_compacted_history(messages,item);t_assert(j_count(next)==3 && co_compaction(j_at(next,2)),"compact history retains user goals and checkpoint");
    t_assert(h_equal(j_s(j_at(next,0),"content"),"Remember the goal.") && !h_has(j_dump(next),"VM observation"),"VM observations summarized without retaining synthetic user messages");
    let request=co_compact_request("fixture-model",next);let input=j_need(request,"input");t_assert(co_compaction(j_at(input,2)) && h_equal(j_s(j_at(input,3),"type"),"compaction_trigger"),"checkpoint passthrough and V2 compaction trigger");
    t_assert(j_count(j_need(request,"tools"))==1 && !j_n(request,"store"),"compaction keeps the same tool definition without executing it");
    let usage=j_object();j_set(usage,"input_tokens",j_int(100));j_set(usage,"output_tokens",j_int(20));usage=co_usage(usage);
    let anchor=j_count(messages);collie_message(messages,"user","abcd");let measured=co_context_usage(messages,usage,anchor);t_assert(j_n(measured,"total_tokens")==121 && c_flag(measured,"estimated"),"pending messages add estimates to latest server usage");
    let output=j_array();j_push(output,item);let event=ct_reply("");let response=j_need(event,"response");j_set(response,"output",output);co_compact_mode=1;
    t_assert(co_compaction(ct_stream(h_cat3("data: ",j_dump(event),"\n\n"),0)),"completed SSE compaction accepted");
    t_assert(!ct_stream("data: {\"type\":\"response.output_item.done\"}\n\n",0),"interrupted compaction never installs a checkpoint");
    j_push(output,item);t_assert(!ct_stream(h_cat3("data: ",j_dump(event),"\n\n"),0),"multiple compaction checkpoints rejected");
    j_set(response,"output",j_array());t_assert(!ct_stream(h_cat3("data: ",j_dump(event),"\n\n"),0),"empty compaction response rejected");
    j_set(item,"encrypted_content",j_string(""));t_assert(!co_compaction(item),"empty encrypted checkpoint rejected");
    co_compact_mode=0;co_context_exceeded=0;let body="{\"error\":{\"code\":\"context_length_exceeded\"}}";
    let headers=h_cat3("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: ",h_int(h_len(body)),h_cat("\r\n\r\n",body));
    t_assert(!ct_headers(headers) && co_context_exceeded,"HTTP context-length error enables compaction recovery");co_context_exceeded=0;
}
fn ct_config() {let config=j_object();j_set(config,"compiler",j_string(t_compiler));return config;}
fn ct_vm_error(source,message) {
    let result=cp_execute(ct_config(),source);
    t_assert(h_equal(c_string(result,"state"),"error") && h_has(j_s(result,"stderr"),message),h_cat("expected VM failure: ",message));
}
fn ct_trace_cli() {
    let replay=h_real("tests/fixtures/repair.json");let variant=0;
    while variant<4 {
        let file=h_join(t_work,"collie-trace.json");
        if variant==3 {file=h_join(t_work,"explicit-trace.json");}
        h_save(file,"stale trace");
        let args=h_args(ct_collie,"--compiler",t_compiler,"--model","gpt-6.1-sol","--replay");h_add(args,replay);
        if variant==0 {h_add(args,"test");h_add(args,"--trace");}
        else if variant==1 {h_add(args,"--trace");h_add(args,"test");}
        else if variant==2 {h_add(args,"--trace");h_add(args,"--max-steps");h_add(args,"4");h_add(args,"test");}
        else {h_add(args,h_cat("--trace=",file));h_add(args,"test");}
        let child=h_wait(h_spawn(args,"",t_work));h_check(child,0,"42\n");
        let records=c_json(h_read(file));
        t_assert(j_count(records)==4 && h_equal(j_s(j_at(records,2),"source"),j_s(j_at(j_need(j_at(c_json(h_read(replay)),2),"output"),0),"input")),"trace CLI preserves generated tool input");
        t_assert(h_has(h_err(child),h_cat("trace saved to ",file)),"trace CLI reports its output file");
        variant=variant+1;
    }
}
fn ct_stream_cli() {
    let replay=h_real("tests/fixtures/repair.json");let trace=h_join(t_work,"stream-trace.json");
    let args=h_args(ct_collie,"--compiler",t_compiler,"--replay",replay,"--stream");
    h_add(args,"test");h_add(args,h_cat("--trace=",trace));
    let child=h_run(args);h_check(child,0,"42\n");
    t_assert(h_has(h_err(child),"fn main() { return missing_function(); }") && h_has(h_err(child),"Collie: running program 3"),"stream mode displays code during repair");
    t_assert(h_has(h_err(child),"Collie: VM error (exit 1)") && h_has(h_err(child),"error: undefined function"),"compiler diagnostics are displayed alongside streamed source");
    let records=c_json(h_read(trace));
    t_assert(j_count(records)==4 && h_equal(j_s(j_need(j_at(records,2),"observation"),"state"),"done") && !h_len(j_s(j_at(records,3),"source")),"stream mode preserves traces and final prose");
}
fn ct_protocol_cli() {
    let trace=h_join(t_work,"tool-repair-trace.json");let args=h_args(ct_collie,"--compiler",t_compiler,"--replay",h_real("tests/fixtures/protocol-repair.json"),"--trace");h_add(args,trace);h_add(args,"task");let child=h_run(args);h_check(child,0,"The answer is 42.\n");let records=c_json(h_read(trace));
    t_assert(j_count(records)==4 && !j_n(j_need(j_at(records,0),"observation"),"executed") && !j_n(j_need(j_at(records,1),"observation"),"executed"),"empty and disallowed tool programs never execute");
    t_assert(h_equal(j_s(j_need(j_at(records,2),"observation"),"stdout"),"42\n") && !j_get(j_at(records,3),"observation"),"tool repair observes real stdout and finishes with prose");
    let file=h_join(t_work,"literal-tag-replies.json");let replies=j_array();j_push(replies,j_string("<FLEXSCRIPT>fn main(){return 42;}</FLEXSCRIPT> fina?"));h_save(file,j_dump(replies));args=h_args(ct_collie,"--compiler",t_compiler,"--replay",file,"task");child=h_run(args);h_check(child,0,"<FLEXSCRIPT>fn main(){return 42;}</FLEXSCRIPT> fina?");t_assert(!h_has(h_err(child),"running program"),"old tags in assistant text never authorize execution");
}

fn ct_diagnostics_cli() {
    let file=h_join(t_work,"diagnostic-replies.json");let replies=j_array();j_push(replies,ct_replay("import \"/etc/passwd\";fn main(){return 0;}"));j_push(replies,ct_replay("fn main(){let zero=0;return 1/zero;}"));j_push(replies,j_string("Handled.\n"));h_save(file,j_dump(replies));
    let args=h_args(ct_collie,"--compiler",t_compiler,"--replay",file,"task");let child=h_run(args);h_check(child,0,"Handled.\n");t_assert(h_has(h_err(child),"Collie: program rejected\nImports and compiler extensions are unavailable"),"tool source-policy errors remain visible");t_assert(h_has(h_err(child),"Collie: VM error (exit 70)") && h_has(h_err(child),"integer division trap"),"tool execution errors remain visible");
}

fn ct_vm() {
    let observed=cp_execute(ct_config(),"fn main(){let s=\"42\\n\";syscall(1,1,s,3,0,0,0);return 42;}");
    t_assert(h_equal(j_s(observed,"state"),"done") && h_equal(j_s(observed,"stdout"),"42\n") && j_n(observed,"exit_code")==42,"real VM output and completion");
    ct_vm_error("fn main(){syscall(2,\"/home/teppo/.codex/auth.json\",0,0,0,0,0);return 42;}","host capability denied");
    ct_vm_error("fn main(){syscall(41,2,1,0,0,0,0);return 42;}","host capability denied");
    ct_vm_error("fn main(){syscall(57,0,0,0,0,0,0);return 42;}","host capability denied");
    ct_vm_error("fn main(){syscall(0,0,alloc(8),8,0,0,0);return 42;}","host capability denied");
    let fd_probe=cp_execute(ct_config(),"fn main(){if syscall(1,3,\"bypass\",6,0,0,0)==-9{return 42;}return 1;}");
    t_assert(h_equal(j_s(fd_probe,"state"),"done") && !h_len(j_s(fd_probe,"stdout")),"user message descriptor is unavailable to guest code");
    ct_vm_error("fn main(){ffi_open(\"libc.so.6\");return 42;}","host capability denied");
    ct_vm_error("fn main(){while 1 {}return 42;}","instruction budget exhausted");
    ct_vm_error("fn main(){return load64(-1);}","out of bounds");
    ct_vm_error("fn main(){let z=0;return 1/z;}","integer division trap");
    observed=cp_execute(ct_config(),"fn main(){let b=alloc(4096);let i=0;while i<300{syscall(1,1,b,4096,0,0,0);i=i+1;}return 42;}");
    t_assert(h_equal(j_s(observed,"state"),"error") && j_n(observed,"output_truncated") && h_has(j_s(observed,"stderr"),"output limit"),"output budget and bounded observations");
    let captured=cp_capture(h_args("sleep","10",0,0,0,0),100);
    t_assert(h_status(load64(captured))==-9 && h_has(load64(captured+8),"watchdog"),"outer watchdog reaps its child");
    let trace=h_join(t_work,"trace.json");h_save(trace,"was public");
    let args=h_args(ct_collie,"--compiler",t_compiler,"--replay",h_real("tests/fixtures/repair.json"),"--trace");
    h_add(args,trace);h_add(args,"--auth-file");h_add(args,"/definitely/not/available/auth.json");h_add(args,"Print 42");
    h_check(h_run(args),0,"42\n");let records=c_json(h_read(trace));
    t_assert(j_count(records)==4 && h_equal(j_s(j_need(j_at(records,0),"observation"),"state"),"error")
        && h_equal(j_s(j_need(j_at(records,1),"observation"),"state"),"continue")
        && h_equal(j_s(j_need(j_at(records,2),"observation"),"state"),"done") && !j_get(j_at(records,3),"observation"),"native CLI repairs compiler errors and completes with prose");
    let stat=h_take(144);h_assert(syscall(4,trace,stat,0,0,0,0)==0,"trace stat");
    t_assert((load64(stat+24)&511)==384,"trace permissions are 0600 even on overwrite");
    args=h_args(ct_collie,"--compiler",t_compiler,"--replay",h_real("tests/fixtures/repair.json"),"--max-steps");
    h_add(args,"1");h_add(args,"Print 42");let child=h_run(args);
    t_assert(h_status(child)==2 && h_has(h_err(child),"limit reached"),"turn exhaustion exits unsuccessfully");
    ct_trace_cli();
    ct_stream_cli();
    ct_protocol_cli();
    ct_diagnostics_cli();
    h_check(h_run(h_args(ct_collie,"--help",0,0,0,0)),0,0);t_checks=t_checks+1;
    let saved=h_env;h_setenv("PATH",t_work);
    child=h_run(h_args(ct_collie,"--compiler",t_compiler,"--replay",h_real("tests/fixtures/repair.json"),"task"));h_env=saved;
    t_assert(h_status(child)!=0 && h_has(h_err(child),"Bubblewrap"),"isolation absence fails closed");
}
fn suite(compiler) {
    t_init(compiler);
    h_setenv("XDG_STATE_HOME",h_join(t_work,"state"));
    ct_auth();ct_request();ct_sse();ct_http();ct_policy();ct_compaction();ct_protocol();ct_tui_rejections();ct_stream_forwarding();ct_message_forwarding();ct_greeting_cli();ct_workspace_codec();
    if ct_vm_enabled {ct_vm();ct_workspace_vm(compiler);}
    t_done();return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    if argc==2 && h_equal(load64(argv+8),"--stream-fixture") {return ct_stream_fixture(0);}
    if argc==2 && h_equal(load64(argv+8),"--message-fixture") {return ct_stream_fixture(1);}
    if argc==2 && h_equal(load64(argv+8),"--stream-fixture-parent") {
        let child=h_spawn(h_args("/proc/self/exe","--stream-fixture",0,0,0,0),"",0);
        collie_wait_stream(child);h_print(1,h_out(child));return h_status(child);
    }
    if argc==2 && h_equal(load64(argv+8),"--message-fixture-parent") {
        let child=h_spawn(h_args("/proc/self/exe","--message-fixture",0,0,0,0),"",0);
        collie_wait_stream(child);h_print(1,h_out(child));return h_status(child);
    }
    h_assert(argc>=3,"test-collie <compiler> <collie> [--vm]");
    ct_collie=h_real(load64(argv+16));ct_vm_enabled=argc==4 && h_equal(load64(argv+24),"--vm");
    return suite(load64(argv+8));
}
