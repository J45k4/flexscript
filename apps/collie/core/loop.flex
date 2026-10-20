import "../adapters/linux.flex";
import "../providers/codex.flex";

global cx_usage=0;
global cx_anchor=0;
global cx_compactions=0;
global cx_archive=0;

fn collie_message(messages,role,text) {
    let message=j_object();
    j_set(message,"role",j_string(role));
    j_set(message,"content",j_string(text));
    j_push(messages,message);
    return 0;
}
fn collie_context(messages) {
    if ce_enabled {let data=j_object();j_set(data,"bytes",j_int(h_len(j_dump(messages))));j_set(data,"messages",j_int(j_count(messages)));j_set(data,"usage",co_context_usage(messages,cx_usage,cx_anchor));ce_data("context",data);}return 0;
}
fn collie_checkpoint(messages,pending) {let data=j_object();j_set(data,"messages",messages);j_set(data,"usage",co_context_usage(messages,cx_usage,cx_anchor));j_set(data,"pending_prompt",j_bool(pending));j_set(data,"compactions",j_int(cx_compactions));ce_data("checkpoint",data);return 0;}

fn collie_wait_stream(child) {
    let shown=0;
    while h_status(child)==-999 || load64(child+40)>=0 || load64(child+48)>=0 {
        h_pump(child,10);
        let buffer=load64(child+24);let size=h_size(buffer);
        if size>shown {h_write(2,h_data(buffer)+shown,size-shown);shown=size;}
        if net_now()-load64(child+80)>h_timeout {
            h_stop(child);h_die("model worker timed out");
        }
    }
    h_close(load64(child+32));store64(child+32,-1);return child;
}

fn collie_adapter(config,operation,request) {
    let args=h_args("/proc/self/exe","--adapter",operation,0,0,0);
    // The adapter applies its own network/process deadlines. This watchdog also
    // bounds an adapter failure. Requests contain paths, never credential values.
    h_timeout=195000;
    h_output_limit=4194304;
    let message_fd=-1;let inherited=h_inherit_fd;
    if h_equal(operation,"model") {
        // Preserve a duplicate of the user's stdout across the worker exec.
        // Worker stdout still carries JSON; this separate fd carries only prose.
        message_fd=syscall(72,1,0,3,0,0,0);h_assert(message_fd>=3,"cannot open user message channel");
        j_set(request,"message_fd",j_int(message_fd));h_inherit_fd=message_fd;
    }
    let before=h_child_memory;h_child_memory=1073741824;
    let streaming=c_flag(config,"stream") && h_equal(operation,"model");
    let child=h_spawn(args,j_dump(request),0);h_child_memory=before;h_inherit_fd=inherited;
    if message_fd>=0 {h_close(message_fd);}
    if streaming {collie_wait_stream(child);}else {h_wait(child);}
    if h_status(child)!=0 {
        if h_equal(operation,"model_info") {return co_model_limits(j_object(),config);}
        if !streaming {h_print(2,h_err(child));}
        h_die("host adapter failed");
    }
    return j_parse(h_out(child));
}

fn collie_trace(config,trace) {
    let file=j_s(config,"trace_file");if !h_len(file) {return 0;}
    let fd=syscall(2,file,0x80241,384,0,0,0);h_assert(fd>=0,"cannot create trace file");
    h_assert(syscall(91,fd,384,0,0,0,0)==0,"cannot protect trace file");
    let text=j_dump(trace);h_assert(h_write(fd,text,h_len(text))==h_len(text),"cannot write trace");h_close(fd);
    h_print(2,h_cat3("Collie: trace saved to ",file,"\n"));return 0;
}

fn collie_diagnostics(observation,protocol_error) {
    if protocol_error {
        h_print(2,h_cat3("Collie: reply rejected: ",protocol_error,"\n"));return 0;
    }
    let state=j_s(observation,"state");let label="VM ";
    if h_equal(state,"rejected") {label="program ";}
    let status=h_cat3("Collie: ",label,state);
    if h_equal(state,"error") {status=h_cat3(status," (exit ",h_cat(h_int(j_n(observation,"exit_code")),")"));}
    h_print(2,h_cat(status,"\n"));
    let details=c_string(observation,"stderr");
    if details && h_len(details) {
        h_print(2,details);if load8(details+h_len(details)-1)!=10 {h_print(2,"\n");}
    }
    return 0;
}

fn collie_complete(messages,trace,status) {
    if ce_enabled {let e=ce_event("done");j_set(e,"messages",messages);j_set(e,"trace",trace);j_set(e,"status",j_int(status));j_set(e,"usage",co_context_usage(messages,cx_usage,cx_anchor));j_set(e,"compactions",j_int(cx_compactions));ce_write(1,e);}
    return status;
}

fn collie_needs_compaction(messages,info) {
    let usage=co_context_usage(messages,cx_usage,cx_anchor);let limit=co_count(info,"auto_compact_token_limit");let used=co_count(usage,"total_tokens");
    let full=co_count(info,"usable_context_window");
    return (limit>=0 && used>=limit) || (full>=0 && used>=full);
}
fn collie_compact(config,messages,trace,pending,automatic) {
    h_print(2,"Collie: compacting conversation\n");ce_note("status","Compacting conversation...");
    let request=j_object();j_set(request,"config",config);j_set(request,"messages",messages);let result=collie_adapter(config,"compact",request);
    let error=c_string(result,"error");if error {return result;}
    let item=co_compaction(j_get(result,"item"));if !item {return c_error("Compaction returned an invalid encrypted checkpoint.");}
    let next=co_compacted_history(messages,item);let before=co_count(co_context_usage(messages,cx_usage,cx_anchor),"total_tokens");let usage=co_context_usage(next,0,0);let after=co_count(usage,"total_tokens");
    if automatic && after>=before {return c_error("Compaction did not reduce context; original history was kept.");}
    cx_compactions=cx_compactions+1;cx_usage=usage;cx_anchor=j_count(next);
    let record=j_object();j_set(record,"event",j_string("compaction"));j_set(record,"text",j_string(""));j_set(record,"message",j_string(""));j_set(record,"source",j_string(""));j_set(record,"checkpoint",item);j_set(record,"before_tokens",j_int(before));j_set(record,"after_tokens",j_int(after));let spent=j_get(result,"usage");if spent {j_set(record,"usage",spent);}j_push(trace,record);collie_trace(config,trace);
    collie_checkpoint(next,pending);collie_context(next);ce_note("compacted","Conversation compacted.");h_print(2,"Collie: conversation compacted\n");
    let done=j_object();j_set(done,"messages",next);return done;
}

fn collie_loop(config) {
    let messages=j_get(config,"messages");if !messages {messages=j_array();}
    h_assert(co_history_valid(messages),"invalid conversation history");
    // Requests must not serialize a duplicate of the old window inside config.
    j_set(config,"messages",j_array());cx_usage=co_usage(j_get(config,"usage"));cx_anchor=co_usage_anchor(messages);if cx_usage {cx_anchor=j_count(messages);}
    cx_compactions=co_count(config,"compactions");if cx_compactions<0 {cx_compactions=0;}
    let info=j_get(config,"model_info");if !info {let request=j_object();j_set(request,"config",config);info=collie_adapter(config,"model_info",request);}
    let trace=j_array();
    if c_flag(config,"compact_only") {
        if j_count(messages) {let result=collie_compact(config,messages,trace,0,0);let error=c_string(result,"error");if error {ce_note("error",h_cat("Compaction failed: ",error));return collie_complete(messages,trace,1);}messages=j_need(result,"messages");}
        return collie_complete(messages,trace,0);
    }
    cw_prepare(config);cx_archive=cw_archive_load(config);
    if !ce_enabled {h_print(2,h_cat3("Collie: workspace ",j_s(config,"workspace_file"),"\n"));}
    collie_message(messages,"user",j_s(config,"prompt"));
    collie_message(cx_archive,"user",j_s(config,"prompt"));cw_archive_save(config,cx_archive);
    let step=0;let compacted_step=-1;
    while step<j_n(config,"max_steps") {
        collie_context(messages);
        if collie_needs_compaction(messages,info) && compacted_step!=step {
            let result=collie_compact(config,messages,trace,1,1);let error=c_string(result,"error");if error {h_print(2,h_cat3("Collie: compaction failed: ",error,"\n"));ce_note("error",h_cat("Compaction failed: ",error));return collie_complete(messages,trace,1);}messages=j_need(result,"messages");compacted_step=step;
        }
        if h_len(j_dump(messages))>8388608 || j_count(messages)>4095 {
            h_print(2,"Collie: conversation byte limit reached\n");
            ce_note("error","Conversation byte limit reached.");return collie_complete(messages,trace,2);
        }
        let request=j_object();
        j_set(request,"config",config);
        j_set(request,"messages",messages);
        j_set(request,"step",j_int(step));
        h_print(2,h_cat3("Collie: generating reply ",h_int(step+1),"\n"));
        ce_note("reply_start",h_cat("Generating reply ",h_int(step+1)));
        let reply=collie_adapter(config,"model",request);
        let error=j_get(reply,"error");
        if error && c_flag(reply,"context_exceeded") && compacted_step!=step {
            let result=collie_compact(config,messages,trace,1,1);let compact_error=c_string(result,"error");
            if !compact_error {messages=j_need(result,"messages");compacted_step=step;j_set(request,"messages",messages);reply=collie_adapter(config,"model",request);error=j_get(reply,"error");}
            else {reply=c_error(h_cat("Compaction failed: ",compact_error));error=j_get(reply,"error");}
        }
        if error {
            h_print(2,h_cat3("Collie: ",j_value(error),"\n"));
            ce_note("error",j_value(error));return collie_complete(messages,trace,1);
        }
        let text=j_s(reply,"text");let source=j_s(reply,"source");let message=j_s(reply,"message");
        let output=j_need(reply,"items");let oi=0;while oi<j_count(output) {j_push(messages,j_at(output,oi));oi=oi+1;}
        let reported=co_usage(j_get(reply,"usage"));if reported {cx_usage=reported;cx_anchor=j_count(messages);}
        collie_context(messages);
        if !ce_enabled && !c_flag(reply,"message_streamed") {h_print(1,message);}
        ce_data("reply",reply);
        // Keep terminal progress on its own line without changing piped prose.
        if h_len(message) && load8(message+h_len(message)-1)!=10 {h_print(2,"\n");}
        let record=j_object();
        j_set(record,"text",j_string(text));j_set(record,"message",j_string(message));j_set(record,"source",j_string(source));
        j_set(record,"role",j_string("assistant"));j_set(record,"content",j_string(message));j_push(cx_archive,record);cw_archive_save(config,cx_archive);
        let usage=j_get(reply,"usage");if usage {j_set(record,"usage",usage);}
        j_push(trace,record);
        let call=j_get(reply,"tool_call");let observation=0;let host_error=0;
        if !call {
            collie_trace(config,trace);h_print(2,"Collie: done\n");return collie_complete(messages,trace,0);
        }else {
            j_set(record,"tool_call",call);
            h_print(2,h_cat3("Collie: running program ",h_int(step+1),"\n"));
            ce_note("status",h_cat("Running program ",h_int(step+1)));
            let execution=j_object();j_set(execution,"config",config);j_set(execution,"source",j_string(source));
            j_set(execution,"history",cx_archive);
            observation=collie_adapter(config,"run",execution);host_error=c_string(observation,"error");
            if host_error {
                observation=j_object();j_set(observation,"state",j_string("error"));j_set(observation,"executed",j_bool(0));j_set(observation,"phase",j_string("host"));j_set(observation,"exit_code",j_int(-1));j_set(observation,"stdout",j_string(""));j_set(observation,"stderr",j_string(host_error));
            }
        }
        j_set(record,"observation",observation);collie_trace(config,trace);
        cw_archive_save(config,cx_archive);
        collie_diagnostics(observation,0);
        ce_data("observation",observation);
        let result=j_object();j_set(result,"type",j_string("custom_tool_call_output"));j_set(result,"call_id",j_need(call,"call_id"));j_set(result,"output",j_string(j_dump(observation)));j_push(messages,result);
        collie_checkpoint(messages,1);
        collie_context(messages);
        if host_error {ce_note("error",host_error);return collie_complete(messages,trace,1);}
        step=step+1;
    }
    h_print(2,"Collie: reply limit reached without completion\n");
    ce_note("error","Reply limit reached without completion.");return collie_complete(messages,trace,2);
}
