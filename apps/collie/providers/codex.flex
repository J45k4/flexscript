import "../lib/json.flex";
import "../lib/state.flex";
import "../../../lib/http.flex";
import "instructions.flex";
import "../core/protocol.flex";
import "usage.flex";
import "context.flex";

global co_problem=0;
global co_chunked=0;
global co_remaining=-1;
global co_chunk_crlf=0;
global co_body_size=0;
global co_body_eof=0;
global co_line=0;
// Display goes to stderr; the worker's stdout remains a completed JSON reply.
global co_stream_fd=-1;
global co_stream_bytes=0;
global co_stream_size=0;
global co_stream_started=0;
global co_message_fd=-1;
global co_last_usage=0;
global co_compact_mode=0;
global co_context_exceeded=0;
global co_tool_key=0;

fn co_stream_reset() {
    co_last_usage=0;co_stream_size=0;co_stream_started=0;pp_message_fd=co_message_fd;pp_debug_fd=co_stream_fd;pp_reset();co_stream_bytes=pp_text;
    co_tool_key=h_take(257);store8(co_tool_key,0);return 0;
}

fn co_stream_delta(text) {if !pp_feed(text) {co_problem=pp_problem;return 0;}co_stream_size=pp_text_size;return 1;}
fn co_source_delta(text,key) {
    if !pt_id(key) {co_problem="Tool input delta is missing a valid item ID.";return 0;}
    if h_len(co_tool_key) && !h_equal(co_tool_key,key) {co_problem="Multiple or mismatched tool input streams; no program was executed.";return 0;}
    if !h_len(co_tool_key) {h_copy(co_tool_key,key,h_len(key)+1);}if !pp_source(text) {co_problem=pp_problem;return 0;}return 1;
}
fn co_tool_added(item) {
    if !h_equal(c_string(item,"type"),"custom_tool_call") {return 1;}if !h_equal(c_string(item,"name"),"flexscript") {co_problem="Only the flexscript tool is available; no program was executed.";return 0;}
    let key=c_string(item,"id");if !key {key=c_string(item,"call_id");}let input=c_string(item,"input");if !input {input="";}return co_source_delta(input,key);
}

fn co_stream_finish() {
    if co_stream_fd>=0 && pp_code_sent && load8(pp_code+pp_code_sent-1)!=10 {
        h_print(co_stream_fd,"\n");
    }
    return 0;
}

fn co_auth_path() {
    let home=h_getenv("CODEX_HOME");
    if !home || !h_len(home) {
        home=h_getenv("HOME");h_assert(home,"HOME or CODEX_HOME is required");
        home=h_join(home,".codex");
    }
    return h_join(home,"auth.json");
}
fn co_header_valid(text) {
    if !text || !h_len(text) || h_len(text)>32768 {return 0;}
    let i=0;while load8(text+i) {
        let c=load8(text+i);if c<33 || c>126 {return 0;}i=i+1;
    }
    return 1;
}
fn co_auth(path) {
    co_problem=0;let text=c_read(path,65536);
    if !text {co_problem="Cannot read Codex auth.json. Run codex login with ChatGPT or select --auth-file.";return 0;}
    return co_auth_tokens(c_json(text));
}
fn co_auth_tokens(data) {
    co_problem=0;
    if j_kind(data)!=4 {co_problem="Invalid Codex authentication cache.";return 0;}
    let mode=j_get(data,"auth_mode");
    if mode && j_kind(mode)!=0 && (j_kind(mode)!=2 || !h_equal(j_value(mode),"chatgpt")) {
        co_problem="Collie requires ChatGPT login tokens in auth.json.";return 0;
    }
    let tokens=j_get(data,"tokens");
    let access=c_string(tokens,"access_token");let account=c_string(tokens,"account_id");
    if !co_header_valid(access) || !co_header_valid(account) {
        co_problem="auth.json is missing valid ChatGPT access token/account ID fields.";return 0;
    }
    // Credentials are only returned to the HTTPS transport in this worker.
    // Never include this object in model input, observations or trace records.
    let headers=j_object();j_set(headers,"access",j_string(access));j_set(headers,"account",j_string(account));
    return headers;
}
fn co_request(model,messages) {
    h_assert(co_history_valid(messages),"invalid tool-call history");let request=j_object();j_set(request,"model",j_string(model));j_set(request,"instructions",j_string(co_instructions()));let input=j_array();
    let i=0;while i<j_count(messages) {let message=j_at(messages,i);let item=co_compaction(message);if !item {item=pt_call(message);}if !item {item=pt_result(message);}if !item {item=pt_reasoning(message);}
        if item {j_push(input,item);}else {let role=j_s(message,"role");let part=j_object();let kind="input_text";if h_equal(role,"assistant") {kind="output_text";}j_set(part,"type",j_string(kind));j_set(part,"text",j_string(j_s(message,"content")));let content=j_array();j_push(content,part);item=j_object();j_set(item,"role",j_string(role));j_set(item,"content",content);j_push(input,item);}i=i+1;
    }
    let tools=j_array();j_push(tools,pt_tool());j_set(request,"input",input);j_set(request,"tools",tools);j_set(request,"tool_choice",j_string("auto"));j_set(request,"parallel_tool_calls",j_bool(0));let include=j_array();j_push(include,j_string("reasoning.encrypted_content"));j_set(request,"include",include);
    let reasoning=j_object();j_set(reasoning,"summary",j_string("auto"));j_set(request,"reasoning",reasoning);j_set(request,"store",j_bool(0));j_set(request,"stream",j_bool(1));return request;
}

// Platform HTTPS adapters execute this descriptor; backend identity, auth
// headers and timeouts are provider policy shared with the conversation core.
fn co_transport(auth){
    let out=j_object();j_set(out,"url",j_string("https://chatgpt.com/backend-api/codex/responses"));j_set(out,"method",j_string("POST"));
    let headers=j_object();j_set(headers,"Authorization",j_string(h_cat("Bearer ",j_s(auth,"access"))));j_set(headers,"ChatGPT-Account-ID",j_need(auth,"account"));j_set(headers,"originator",j_string("collie"));j_set(headers,"User-Agent",j_string("collie/0.1"));j_set(headers,"Content-Type",j_string("application/json"));j_set(headers,"Accept",j_string("text/event-stream"));j_set(headers,"Accept-Encoding",j_string("identity"));j_set(out,"headers",headers);
    j_set(out,"connect_timeout_ms",j_int(30000));j_set(out,"read_timeout_ms",j_int(120000));return out;
}
fn co_http_status(status) {
    if status==401 {return "ChatGPT login rejected. Let Codex refresh auth.json or run codex login.";}
    if status==429 {return "Codex usage limit reached; retry later.";}
    return h_cat3("Codex backend returned HTTP ",h_int(status),".");
}
// This transport never follows redirects or sends credentials to a configurable
// origin. Tests use this low-level connection function with fabricated headers.
fn co_open(host,service,path,auth,body,timeout) {
    co_problem=0;http_session=tls_connect(host,service,timeout);
    if !http_session {co_problem="Codex TLS connection failed (certificate verification required).";return 0;}
    http_buffer=h_take(8192);http_start=0;http_end=0;co_line=h_take(8193);
    let head=h_buffer();h_text(head,h_cat3("POST ",path," HTTP/1.1\r\nHost: "));
    h_text(head,host);h_text(head,"\r\nUser-Agent: collie/0.1\r\noriginator: collie\r\nAccept: text/event-stream\r\nAccept-Encoding: identity\r\nContent-Type: application/json\r\nConnection: close\r\nAuthorization: Bearer ");
    h_text(head,j_s(auth,"access"));h_text(head,"\r\nChatGPT-Account-ID: ");h_text(head,j_s(auth,"account"));
    h_text(head,h_cat3("\r\nContent-Length: ",h_int(h_len(body)),"\r\n\r\n"));
    if !http_write(http_session,h_data(head),h_size(head)) || !http_write(http_session,body,h_len(body)) {
        co_problem="Cannot send Codex request.";return 0;
    }
    return co_headers();
}
fn co_headers() {
    let n=http_line(co_line,8192);
    if n<12 || !(h_starts(co_line,"HTTP/1.1 ") || h_starts(co_line,"HTTP/1.0 "))
        || !c_json_digit(load8(co_line+9)) || !c_json_digit(load8(co_line+10)) || !c_json_digit(load8(co_line+11)) {
        co_problem="Invalid HTTP status from Codex.";return 0;
    }
    let status=(load8(co_line+9)-48)*100+(load8(co_line+10)-48)*10+load8(co_line+11)-48;
    let header_bytes=n+2;let more=1;let event_stream=0;let has_content_type=0;co_chunked=0;co_remaining=-1;
    while more {
        n=http_line(co_line,8192);header_bytes=header_bytes+n+2;
        if n<0 || header_bytes>65536 {co_problem="Invalid or oversized HTTP headers.";return 0;}
        if !n {more=0;}
        else {
            let k=0;while k<n && load8(co_line+k)!=58 {
                let c=load8(co_line+k);
                if !((c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)||c==45) {
                    co_problem="Malformed HTTP header name.";return 0;
                }
                k=k+1;
            }
            if !k || k==n {co_problem="Malformed HTTP header.";return 0;}
            let value=http_header(co_line,"content-length");
            if value {
                if co_remaining>=0 {co_problem="Duplicate Content-Length.";return 0;}
                co_remaining=http_decimal(value,8388608);
                if co_remaining<0 {co_problem="Invalid HTTP body length.";return 0;}
            }
            value=http_header(co_line,"transfer-encoding");
            if value {
                if co_chunked || !http_case_equal(value,"chunked") {co_problem="Unsupported HTTP transfer encoding.";return 0;}
                co_chunked=1;
            }
            value=http_header(co_line,"content-encoding");
            if value && !http_case_equal(value,"identity") {co_problem="Unsupported HTTP content encoding.";return 0;}
            value=http_header(co_line,"content-type");
            if value {
                if has_content_type {co_problem="Duplicate HTTP content type.";return 0;}
                has_content_type=1;
                if h_len(value)>=17 && http_case_equal(h_slice(value,17),"text/event-stream") {
                    let next=load8(value+17);if !next || next==59 || next==32 || next==9 {event_stream=1;}
                }
            }
        }
    }
    // The Codex backend can omit Content-Type on its HTTP/1.1 stream. In that
    // case the strictly parsed SSE events still have to reach response.completed.
    if status==200 && has_content_type && !event_stream {co_problem="Unexpected HTTP content type from Codex.";return 0;}
    if co_chunked && co_remaining>=0 {co_problem="Ambiguous HTTP body framing from Codex.";return 0;}
    if co_chunked {co_remaining=0;}
    co_chunk_crlf=0;co_body_size=0;co_body_eof=0;
    if status!=200 {
        if status==400 && co_remaining<=65536 {let body=h_buffer();let reading=1;while reading && h_size(body)<65536 {let byte=co_body_byte();if byte<0 {reading=0;}else {let p=h_take(1);store8(p,byte);h_append(body,p,1);}}
            let text=h_data(body);if h_len(text) && load8(text)==123 {let parsed=c_json(text);if j_kind(parsed)==4 {let error=j_get(parsed,"error");if h_equal(c_string(error,"code"),"context_length_exceeded") {co_context_exceeded=1;}}}}
        co_problem=co_http_status(status);if co_context_exceeded {co_problem="Model context length exceeded.";}return 0;
    }
    return 1;
}
fn co_body_byte() {
    if co_body_eof || co_problem {return -1;}
    if co_chunked && !co_remaining {
        if co_chunk_crlf && (http_byte()!=13 || http_byte()!=10) {co_problem="Invalid chunk framing.";return -1;}
        let n=http_line(co_line,8192);let i=0;let size=0;
        while i<n && load8(co_line+i)!=59 {
            let value=http_hex(load8(co_line+i));
            if value<0 || size>(8388608-value)/16 {co_problem="Invalid HTTP chunk size.";return -1;}
            size=size*16+value;i=i+1;
        }
        if n<=0 || !i || size>8388608-co_body_size {co_problem="Invalid or oversized HTTP chunk.";return -1;}
        if !size {co_body_eof=1;return -1;}
        co_remaining=size;co_chunk_crlf=1;
    }
    if !co_chunked && !co_remaining {co_body_eof=1;return -1;}
    let byte=http_byte();
    if byte<0 {
        if co_remaining>0 {co_problem="Truncated HTTP body.";}
        co_body_eof=1;return -1;
    }
    co_body_size=co_body_size+1;
    if co_body_size>8388608 {co_problem="Model stream exceeded its size limit.";return -1;}
    if co_remaining>0 {co_remaining=co_remaining-1;}
    return byte;
}
fn co_sse_line() {
    let line=h_buffer();let more=1;
    while more {
        let byte=co_body_byte();
        if byte<0 || byte==0 {return 0;}
        if byte==10 {more=0;}
        else {let p=h_take(1);store8(p,byte);h_append(line,p,1);}
    }
    let size=h_size(line);
    if size && load8(h_data(line)+size-1)==13 {store8(h_data(line)+size-1,0);}
    return h_data(line);
}
fn co_output(output) {
    if !output || j_kind(output)!=3 || j_count(output)>128 {co_problem="Invalid model output items.";return 0;}
    let message=h_buffer();let items=j_array();let summaries=j_array();let summary_bytes=0;let call=0;let i=0;
    while i<j_count(output) {
        let item=j_at(output,i);let type=c_string(item,"type");
        if h_equal(type,"reasoning") {
            let parts=pt_summary_parts(item);if !parts{co_problem="Invalid reasoning summary.";return 0;}let k=0;
            while k<j_count(parts){let text=j_s(j_at(parts,k),"text");summary_bytes=summary_bytes+h_len(text);if summary_bytes>65536 || j_count(summaries)>=128{co_problem="Reasoning summaries exceed limit.";return 0;}if h_len(text){let part=j_object();j_set(part,"item_id",j_string(cj_text(item,"id")));j_set(part,"summary_index",j_int(k));j_set(part,"text",j_string(text));j_push(summaries,part);}k=k+1;}
            let reasoning=pt_reasoning(item);if reasoning {j_push(items,reasoning);}
        }
        else if h_equal(type,"custom_tool_call") {
            if call {co_problem="Multiple tool calls in one response are unsupported; no program was executed.";return 0;}call=pt_call(item);if !call {co_problem="Invalid flexscript tool call (name, ID, status or 64 KiB source limit); no program was executed.";return 0;}j_push(items,call);
        }else if h_equal(type,"message") && h_equal(c_string(item,"role"),"assistant") {
            let parts=j_get(item,"content");if !parts || j_kind(parts)!=3 {co_problem="Invalid assistant text content.";return 0;}let content=h_buffer();let k=0;
            while k<j_count(parts) {let part=j_at(parts,k);let text=0;if h_equal(c_string(part,"type"),"output_text") {text=c_string(part,"text");}else if h_equal(c_string(part,"type"),"refusal") {text=c_string(part,"refusal");}
                if !text || h_size(message)+h_size(content)+h_len(text)>65536 {co_problem="Invalid or oversized assistant text.";return 0;}h_text(content,text);k=k+1;}
            h_text(message,h_data(content));let m=j_object();j_set(m,"role",j_string("assistant"));j_set(m,"content",j_string(h_data(content)));j_push(items,m);
        }else {co_problem="Unexpected model output; only assistant text and the flexscript tool are supported.";return 0;}i=i+1;
    }
    let text=h_data(message);if !call && !h_len(h_trim(text)) {co_problem="Model returned no text or flexscript tool call.";return 0;}
    if pp_text_size && !h_equal(pp_text,text) {co_problem="Completed assistant text differed from streamed text.";return 0;}if !pp_text_size && h_len(text) {co_stream_delta(text);}
    let source="";if call {source=j_s(call,"input");let id=c_string(call,"id");if h_len(co_tool_key) && !h_equal(co_tool_key,id) && !h_equal(co_tool_key,j_s(call,"call_id")) {co_problem="Completed tool call ID differed from its streamed input; no program was executed.";return 0;}
        if pp_code_size && !h_equal(pp_code,source) {co_problem="Completed tool source differed from streamed input; no program was executed.";return 0;}if !pp_code_size && h_len(source) {pp_source(source);}
    }else if pp_code_size || h_len(co_tool_key) {co_problem="Streamed tool input was missing from the completed response.";return 0;}
    if pp_problem {co_problem=pp_problem;return 0;}
    let reply=j_object();j_set(reply,"summaries",summaries);j_set(reply,"text",j_string(text));j_set(reply,"message",j_string(text));j_set(reply,"source",j_string(source));j_set(reply,"has_code",j_bool(call!=0));j_set(reply,"message_streamed",j_bool(pp_text_sent>0));j_set(reply,"items",items);if call {j_set(reply,"tool_call",call);}return reply;
}
fn co_completed(event) {
    let kind=c_string(event,"type");
    if h_equal(kind,"error") || h_equal(kind,"response.failed") || h_equal(kind,"response.incomplete") {
        let error=j_get(event,"error");let response=j_get(event,"response");if response && j_kind(response)==4 {error=j_get(response,"error");}let code=c_string(error,"code");if h_equal(code,"context_length_exceeded") || h_equal(c_string(event,"code"),"context_length_exceeded") {co_context_exceeded=1;}
        co_problem="Model response failed or was incomplete.";return 0;
    }
    if !h_equal(kind,"response.completed") {return 0;}co_last_usage=0;let response=j_get(event,"response");if !h_equal(c_string(response,"status"),"completed") {co_problem="Model did not complete its response.";return 0;}
    let output=j_get(response,"output");if !output || j_kind(output)!=3 {co_problem="Missing model output.";return 0;}
    if co_compact_mode {let item=0;let count=0;let i=0;while i<j_count(output) {let current=j_at(output,i);let compact=co_compaction(current);if compact {item=compact;count=count+1;}else {let type=c_string(current,"type");if !h_equal(type,"reasoning") && !h_equal(type,"message") {co_problem="Unexpected item in compaction response.";return 0;}}i=i+1;}if count!=1 {co_problem="Compaction must return exactly one encrypted checkpoint.";return 0;}co_last_usage=co_usage(j_get(response,"usage"));return item;}
    let reply=co_output(output);if reply {co_last_usage=co_usage(j_get(response,"usage"));if co_last_usage {j_set(reply,"usage",co_last_usage);}}return reply;
}

fn co_receive() {
    co_stream_reset();
    while !co_problem {
        let mark=h_mark();let event=h_buffer();let more=1;
        while more && !co_problem {let line=co_sse_line();if !line {if !co_problem {co_problem="Model stream ended before response.completed.";}more=0;}else if !h_len(line) {if h_size(event) {more=0;}}else if h_starts(line,"data:") {let data=line+5;if load8(data)==32 {data=data+1;}if h_size(event) {h_text(event,"\n");}h_text(event,data);}}
        if !co_problem {
            let parsed=c_json(h_data(event));if j_kind(parsed)!=4 {co_problem="Invalid model stream event.";}
            else {
                let kind=c_string(parsed,"type");
                if !co_compact_mode && h_equal(kind,"response.output_text.delta") {let delta=c_string(parsed,"delta");if !delta {co_problem="Invalid assistant text delta.";}else {co_stream_delta(delta);}}
                else if !co_compact_mode && h_equal(kind,"response.custom_tool_call_input.delta") {let delta=c_string(parsed,"delta");let key=c_string(parsed,"item_id");if !key {key=c_string(parsed,"call_id");}if !delta {co_problem="Invalid tool input delta.";}else {co_source_delta(delta,key);}}
                else if !co_compact_mode && h_equal(kind,"response.output_item.added") {let item=j_get(parsed,"item");if item {co_tool_added(item);}}
                else {let reply=co_completed(parsed);if reply {pp_finish();co_stream_finish();return reply;}}
            }
        }
        h_reset(mark);
    }
    co_stream_finish();return 0;
}

fn co_new_call_id() {let p=h_take(8);h_assert(syscall(318,p,8,0,0,0,0)==8,"tool call ID generation failed");return h_cat("call_replay_",h_hex(p,8));}
fn co_generate(config,messages,step) {
    co_problem=0;co_compact_mode=0;co_context_exceeded=0;co_stream_fd=-1;if c_flag(config,"stream") {co_stream_fd=2;}let reply=0;let replay=j_s(config,"replay");
    if h_len(replay) {
        let text=c_read(replay,4194304);if !text {return c_error("Cannot read bounded replay file.");}let replies=c_json(text);if j_kind(replies)!=3 || step>=j_count(replies) {return c_error("Replay needs enough response items.");}let entry=j_at(replies,step);let output=0;
        co_stream_reset();
        if j_kind(entry)==2 {output=j_array();let item=j_object();j_set(item,"type",j_string("message"));j_set(item,"role",j_string("assistant"));let content=j_array();let part=j_object();j_set(part,"type",j_string("output_text"));j_set(part,"text",entry);j_push(content,part);j_set(item,"content",content);j_push(output,item);}
        else if j_kind(entry)==4 {output=j_get(entry,"output");}
        if output && j_kind(output)==3 {let i=0;while i<j_count(output) {let item=j_at(output,i);if h_equal(c_string(item,"type"),"custom_tool_call") {let id=co_new_call_id();j_set(item,"call_id",j_string(id));j_set(item,"id",j_string(h_cat("ctc_",id)));}i=i+1;}reply=co_output(output);if reply && j_kind(entry)==4 {let usage=co_usage(j_get(entry,"usage"));if usage {j_set(reply,"usage",usage);}}}
        else {co_problem="Replay entries must be prose strings or Responses output objects.";}co_stream_finish();
    }else {
        let auth=co_auth(j_s(config,"auth_file"));if !auth {return c_error(co_problem);}let body=j_dump(co_request(j_s(config,"model"),messages));let ok=co_open("chatgpt.com","443","/backend-api/codex/responses",auth,body,150000);if ok {reply=co_receive();}if http_session {tls_close(http_session);http_session=0;}
    }
    if !reply {let error=c_error(co_problem);if co_context_exceeded {j_set(error,"context_exceeded",j_bool(1));}return error;}
    let call=j_get(reply,"tool_call");if call && pt_seen(messages,j_s(call,"call_id"),j_count(messages)) {return c_error("Repeated tool call ID; no program was executed.");}return reply;
}

fn co_compact(config,messages) {
    co_problem=0;co_compact_mode=1;co_context_exceeded=0;co_stream_fd=-1;co_message_fd=-1;
    if h_len(j_s(config,"replay")) {return c_error("Offline source replay has no compaction response.");}
    let auth=co_auth(j_s(config,"auth_file"));if !auth {return c_error(co_problem);}
    let request=co_compact_request(j_s(config,"model"),messages);
    let ok=co_open("chatgpt.com","443","/backend-api/codex/responses",auth,j_dump(request),150000);let item=0;if ok {item=co_receive();}
    if http_session {tls_close(http_session);http_session=0;}
    if !item {return c_error(co_problem);}let result=j_object();j_set(result,"item",item);if co_last_usage {j_set(result,"usage",co_last_usage);}return result;
}
fn co_compact_request(model,messages) {let request=co_request(model,messages);let trigger=j_object();j_set(trigger,"type",j_string("compaction_trigger"));j_push(j_need(request,"input"),trigger);return request;}
