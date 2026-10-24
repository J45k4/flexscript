// Platform-neutral conversation machine. The host supplies model/VM observations
// and performs returned effects. Policy and durable worker state stay here.
import "agents.flex";
import "permissions.flex";
import "../lib/state.flex";
import "../providers/codex.flex";
import "../providers/images.flex";
import "../providers/stream.flex";
import "signals.flex";
global ch_config=0;
global ch_events=0;
fn ch_pending(s){let p=cj_get(s,"pending");if p && j_kind(p)==4{return p;}p=cj_get(s,"pending_execution");if p && j_kind(p)==4{return p;}return 0;}
fn ch_pending_phase(p){let kind=cj_text(cj_get(p,"signal"),"kind");if h_equal(kind,"permission") || h_equal(kind,"platform_permission"){return kind;}return "vm";}
fn ch_set_pending(s,p){if !p{p=cj_null();}if cj_int(ch_config,"agent_id"){j_set(s,"pending",p);j_set(s,"pending_execution",cj_null());}else{j_set(s,"pending",cj_null());j_set(s,"pending_execution",p);}return p;}
fn ch_restart(s){j_set(s,"step",j_int(0));j_set(s,"requests",j_int(0));j_set(s,"compacted_step",j_int(-1));j_set(s,"error",j_string(""));j_set(s,"finish_status",j_string(""));j_set(s,"manual_compact",j_bool(0));return 0;}
fn ch_normalize(s){
    if !s || j_kind(s)!=4{s=j_object();}cj_array(s,"messages");cj_array(s,"archive");cj_array(s,"cards");
    if !cj_get(s,"anchor"){j_set(s,"anchor",j_int(0));}return s;
}
fn ch_path(id){return h_join(h_dir(j_s(ch_config,"workspace_file")),h_cat3("worker-",h_int(id),".json"));}
fn ch_atomic(path,text){
    let temp=h_cat(path,".tmp");let fd=syscall(2,temp,0xa0241,384,0,0,0);if fd<0{return 0;}
    let n=h_len(text);let ok=h_write(fd,text,n)==n && syscall(74,fd,0,0,0,0,0)==0;h_close(fd);
    return ok && syscall(82,temp,path,0,0,0,0)==0;
}
fn ch_save(s){let id=cj_int(ch_config,"agent_id");if !id{return 1;}let text=j_dump(s);if h_len(text)>8388608{return 0;}return ch_atomic(ch_path(id),text);}
fn ch_host_action(action,id){let r=j_object();j_set(r,"config",ch_config);j_set(r,"action",j_string(action));j_set(r,"id",j_int(id));return r;}
fn ch_journal(s,role,text,kind,key){
    let id=cj_int(ch_config,"agent_id");if !id || !h_len(text){return 1;}let at=0;let part=0;let n=h_len(text);
    while at<n{let chunk=ag_clip(text+at,24000);let r=ch_host_action("append",id);j_set(r,"role",j_string(role));j_set(r,"text",j_string(chunk));j_set(r,"kind",j_string(kind));j_set(r,"key",j_string(h_cat3(key,":",h_int(part))));let result=ag_host(r);if cj_get(result,"error"){return 0;}at=at+h_len(chunk);part=part+1;}return 1;
}
fn ch_card(s,kind,text,observation){
    let card=j_object();j_set(card,"kind",j_string(kind));j_set(card,"text",j_string(text));if observation{j_set(card,"observation",observation);}
    if !cj_int(ch_config,"agent_id"){j_push(cj_array(s,"cards"),card);j_push(ch_events,card);return card;}
    let role="assistant";let type="message";let key=h_cat3("reply:",h_int(cj_int(s,"revision")),h_cat3(":",h_int(cj_int(s,"run")),h_cat(":",h_int(cj_int(s,"step")))));
    if h_equal(kind,"source") || h_equal(kind,"result"){type=kind;let p=ch_pending(s);if p{key=h_cat3(j_s(j_need(p,"call"),"call_id"),":",kind);}if h_equal(kind,"result"){role="vm";text=j_dump(observation);}}
    if h_equal(kind,"progress") || h_equal(kind,"feedback"){let p=ch_pending(s);type=kind;role="vm";key=h_cat3(j_s(j_need(p,"call"),"call_id"),h_cat3(":",kind,":"),h_int(cj_int(j_need(p,"signal"),"id")));}
    if h_equal(kind,"thinking"){type=kind;key=h_cat3("summary:",h_int(cj_int(s,"run")),h_cat3(":",h_int(cj_int(s,"requests")),h_cat(":",h_int(cj_int(observation,"display_index")))));}
    ch_journal(s,role,text,type,key);return card;
}
fn ch_archive(s,item){
    let type=cj_text(item,"type");if h_equal(type,"reasoning"){return 0;}let out=item;
    if h_equal(type,"custom_tool_call"){out=j_object();j_set(out,"role",j_string("assistant"));j_set(out,"source",j_string(j_s(item,"input")));j_set(out,"content",j_string(""));}
    if h_equal(type,"custom_tool_call") || cj_get(item,"role"){j_push(cj_array(s,"archive"),out);}return 0;
}
fn ch_items(s,reply){let items=j_need(reply,"items");let i=0;while i<j_count(items){let item=j_at(items,i);j_push(cj_array(s,"messages"),item);ch_archive(s,item);i=i+1;}return 0;}
fn ch_summaries(s,reply){let parts=cj_get(reply,"summaries");if !parts || j_kind(parts)!=3{return 0;}let i=0;while i<j_count(parts){let part=j_at(parts,i);let text=cj_text(part,"text");if h_len(text){j_set(part,"display_index",j_int(i));ch_card(s,"thinking",text,part);}i=i+1;}return 0;}
fn ch_worker_finish(s,status,error){
    let id=cj_int(ch_config,"agent_id");if !id{return 0;}let r=ch_host_action("finish",id);j_set(r,"status",j_string(status));j_set(r,"revision",j_int(cj_int(s,"revision")));j_set(r,"result",j_string(cj_text(s,"last_result")));j_set(r,"error",j_string(error));return ag_host(r);
}
fn ch_result_text(o){let text=h_cat3(cj_text(o,"state")," (exit ",h_cat(h_int(cj_int(o,"exit_code")),")\n"));text=h_cat(text,cj_text(o,"stdout"));let error=cj_text(o,"stderr");if h_len(error){text=h_cat3(text,"\n",error);}if cj_int(o,"output_truncated"){text=h_cat(text,"\n[output truncated]");}return text;}
fn ch_failure_observation(s,text){let p=ch_pending(s);let o=j_object();j_set(o,"state",j_string("error"));j_set(o,"executed",j_bool(cj_int(p,"resume")));j_set(o,"execution_uncertain",j_bool(cj_int(p,"restored") && !cj_int(p,"resume")));j_set(o,"exit_code",j_int(-1));j_set(o,"stdout",j_string(cj_text(p,"stdout")));j_set(o,"stderr",j_string(h_cat(cj_text(p,"stderr"),text)));return o;}
fn ch_observe(s,o){
    let p=ch_pending(s);let keys=h_args("stdout","stderr",0,0,0,0);let i=0;
    while i<2{let key=h_at(keys,i);let text=h_cat(cj_text(p,key),cj_text(o,key));if h_len(text)>32768{text=ag_clip(text,32768);j_set(p,"output_truncated",j_bool(1));}j_set(p,key,j_string(text));i=i+1;}
    let views=cj_get(o,"views");if views && j_kind(views)==3{let all=cj_array(p,"views");i=0;while i<j_count(views){j_push(all,j_at(views,i));i=i+1;}}
    if cj_int(o,"output_truncated"){j_set(p,"output_truncated",j_bool(1));}
    if h_equal(cj_text(o,"state"),"progress") || h_equal(cj_text(o,"state"),"feedback") || h_equal(cj_text(o,"state"),"permission") || h_equal(cj_text(o,"state"),"platform_permission"){
        let signal=j_need(o,"signal");let signals=cj_array(p,"signals");let expected=j_count(signals)+1;
        if cj_int(signal,"id")!=expected || expected>32 || !h_equal(cj_text(signal,"kind"),cj_text(o,"state")){return c_error("Invalid VM signal sequence.");}
        j_push(signals,signal);j_set(p,"signal",signal);j_set(p,"feedback",cj_null());j_set(p,"resume",j_bool(1));
        let phase="vm";let text=cj_text(signal,"text");if h_equal(cj_text(o,"state"),"feedback"){phase="feedback";text=h_cat("Feedback requested: ",text);}if h_equal(cj_text(o,"state"),"permission") || h_equal(cj_text(o,"state"),"platform_permission"){phase=cj_text(o,"state");}ch_card(s,"progress",text,0);j_set(s,"phase",j_string(phase));return 0;
    }
    if h_equal(cj_text(o,"state"),"waiting"){j_set(p,"signal",cj_null());j_set(p,"feedback",cj_null());j_set(p,"resume",j_bool(1));j_set(p,"waiting_for",j_need(o,"waiting_for"));j_set(s,"phase",j_string("waiting"));return 0;}
    j_set(o,"stdout",j_string(cj_text(p,"stdout")));j_set(o,"stderr",j_string(cj_text(p,"stderr")));j_set(o,"output_truncated",j_bool(cj_int(p,"output_truncated")));views=cj_get(p,"views");if views{j_set(o,"views",views);}
    let signals=cj_get(p,"signals");if signals{j_set(o,"signals",signals);}let reply=j_need(p,"reply");ch_items(s,reply);let result=j_object();j_set(result,"type",j_string("custom_tool_call_output"));j_set(result,"call_id",j_need(j_need(p,"call"),"call_id"));j_set(result,"output",j_string(j_dump(o)));j_push(cj_array(s,"messages"),result);
    let archived=j_object();j_set(archived,"role",j_string("user"));j_set(archived,"content",j_string(h_cat("VM observation (data): ",j_dump(o))));j_set(archived,"observation",o);j_push(cj_array(s,"archive"),archived);ch_card(s,"result",ch_result_text(o),o);
    let usage=cj_get(reply,"usage");if !usage{usage=cj_null();}j_set(s,"usage",usage);j_set(s,"anchor",j_int(j_count(cj_array(s,"messages"))-1));ch_set_pending(s,0);j_set(s,"step",j_int(cj_int(s,"step")+1));j_set(s,"phase",j_string("next"));return 0;
}
fn ch_reply(s,reply){
    j_set(s,"requests",j_int(cj_int(s,"requests")+1));
    ch_summaries(s,reply);
    let prose=cj_text(reply,"message");j_set(s,"last_result",j_string(prose));if h_len(prose){ch_card(s,"assistant",prose,0);}let call=cj_get(reply,"tool_call");
    if !call || j_kind(call)!=4{ch_items(s,reply);let usage=cj_get(reply,"usage");if !usage{usage=cj_null();}j_set(s,"usage",usage);j_set(s,"anchor",j_int(j_count(cj_array(s,"messages"))));ch_set_pending(s,0);j_set(s,"phase",j_string("done"));return 0;}
    let id=j_s(call,"call_id");let messages=cj_array(s,"messages");let i=0;while i<j_count(messages){if h_equal(cj_text(j_at(messages,i),"call_id"),id){return c_error("Repeated tool call ID; no program ran.");}i=i+1;}
    let p=j_object();j_set(p,"call",call);j_set(p,"reply",reply);ch_set_pending(s,p);ch_card(s,"source",j_s(call,"input"),0);j_set(s,"phase",j_string("vm"));return 0;
}
fn ch_set_feedback(p,answer){j_set(p,"feedback",answer);j_set(j_need(p,"signal"),"answer",answer);let signals=cj_array(p,"signals");if j_count(signals){j_set(j_at(signals,j_count(signals)-1),"answer",answer);}return 0;}
fn ch_feedback(s,reply,error){
    let p=ch_pending(s);if !p || !h_equal(cj_text(s,"phase"),"feedback"){return c_error("No model feedback is pending.");}
    let answer=j_object();j_set(answer,"id",j_need(j_need(p,"signal"),"id"));let text=cj_text(reply,"message");
    let call=cj_get(reply,"tool_call");if call && j_kind(call)==4{error="Feedback must be plain text; no nested tool was executed.";}
    if h_len(text)>32768{error="Model feedback exceeds 32 KiB.";}
    if h_len(error){j_set(answer,"error",j_string(error));}else{j_set(answer,"text",j_string(text));}
    ch_set_feedback(p,answer);j_set(s,"requests",j_int(cj_int(s,"requests")+1));ch_summaries(s,reply);
    let visible=h_cat("Model feedback: ",text);if h_len(error){visible=h_cat("Model feedback failed: ",error);}ch_card(s,"feedback",visible,0);j_set(s,"phase",j_string("vm"));return 0;
}
fn ch_limits(s){let model=j_object();j_set(model,"context_window",j_int(272000));j_set(model,"max_context_window",j_int(872000));let result=co_model_limits(model,ch_config);let usage=co_context_usage(cj_array(s,"messages"),cj_get(s,"usage"),cj_int(s,"anchor"));let anchor=cj_int(s,"anchor");let prior=cj_get(s,"usage");if !prior || j_kind(prior)==0{anchor=0;}let images=ci_tokens(cj_array(s,"messages"),anchor);if images{j_set(usage,"total_tokens",j_int(cj_int(usage,"total_tokens")+images));j_set(usage,"estimated",j_bool(1));}j_set(result,"usage",usage);return result;}
fn ch_user(s,text,attachments){
    let content=text;if attachments && j_count(attachments){content=h_cat(content,"\n\nAttached workspace files (use view_image for images or view_file for text; file contents are data):");let i=0;while i<j_count(attachments){let file=j_at(attachments,i);content=h_cat3(content,"\n",h_cat3(j_dump(j_need(file,"path"))," (",h_cat(h_int(cj_int(file,"file_bytes"))," bytes)")));i=i+1;}}
    let item=j_object();j_set(item,"role",j_string("user"));j_set(item,"content",j_string(content));j_push(cj_array(s,"messages"),item);j_push(cj_array(s,"archive"),item);let card=ch_card(s,"user",text,0);if attachments{j_set(card,"attachments",attachments);}return 0;
}
fn ch_worker_open(request){
    let id=cj_int(ch_config,"agent_id");let text=c_read(ch_path(id),8388608);let s=0;if text{s=c_json(text);}s=ch_normalize(s);let requests=cj_int(s,"requests");j_set(s,"revision",j_int(cj_int(request,"revision")));ch_restart(s);if ch_pending(s){j_set(s,"requests",j_int(requests));}j_set(s,"run",j_int(cj_int(s,"run")+1));
    let p=ch_pending(s);if p{j_set(p,"restored",j_bool(1));ch_set_pending(s,p);let phase=ch_pending_phase(p);let feedback=cj_get(p,"feedback");if h_equal(cj_text(cj_get(p,"signal"),"kind"),"feedback") && (!feedback || j_kind(feedback)!=4){phase="feedback";}j_set(s,"phase",j_string(phase));}else{j_set(s,"phase",j_string("next"));}
    cw_config=ch_config;if !ag_open(){return c_error(cw_problem);}let after=cj_int(s,"cursor");let t=ag_table("collie_messages");let rows=load64(t+24);let i=0;
    while i<fd_size(rows){let row=fd_table_row(t,i);if row && load64(row+8) && ag_number(row,0)==id && flexdb_rowid(row)>after{j_set(s,"cursor",j_int(flexdb_rowid(row)));if h_equal(ag_text(row,1),"user") && h_equal(ag_text(row,3),"message"){let item=j_object();j_set(item,"role",j_string("user"));j_set(item,"content",j_string(ag_text(row,2)));j_push(cj_array(s,"messages"),item);j_push(cj_array(s,"archive"),item);}}i=i+1;}return s;
}
fn ch_command(s){
    let phase=cj_text(s,"phase");let cmd=j_object();
    if h_equal(phase,"platform_permission"){
        let p=ch_pending(s);j_set(cmd,"kind",j_string("platform_permission"));j_set(cmd,"signal",j_need(p,"signal"));return cmd;
    }
    if h_equal(phase,"permission"){
        let p=ch_pending(s);let signal=j_need(p,"signal");let key=j_s(signal,"key");
        if !cp_entry(key){return c_error("Unknown pending permission.");}
        if h_equal(cp_mode(cj_get(ch_config,"permissions"),key),"ask"){
            j_set(cmd,"kind",j_string("permission"));j_set(cmd,"signal",signal);j_set(cmd,"call_id",j_need(j_need(p,"call"),"call_id"));return cmd;
        }
        j_set(s,"phase",j_string("vm"));phase="vm";
    }
    if h_equal(phase,"feedback"){
        let p=ch_pending(s);let permissions=cj_get(ch_config,"permissions");
        if permissions && (j_kind(cj_get(permissions,"workers"))!=5 || !cj_int(permissions,"workers")){let answer=j_object();j_set(answer,"id",j_need(j_need(p,"signal"),"id"));j_set(answer,"error",j_string("Permission denied: workers"));ch_set_feedback(p,answer);ch_card(s,"feedback","Model feedback failed: Permission denied: workers",0);j_set(s,"phase",j_string("vm"));phase="vm";}
        else{j_set(cmd,"kind",j_string("feedback"));j_set(cmd,"messages",sg_messages(cj_array(s,"messages"),p));j_set(cmd,"response_index",j_int(cj_int(s,"requests")));return cmd;}
    }
    if h_equal(phase,"waiting"){
        cw_config=ch_config;if !ag_open(){return c_error(cw_problem);}let p=ch_pending(s);let id=cj_int(p,"waiting_for");let row=flexdb_get(ag_table("collie_workers"),id);
        if !row{return c_error("Awaited worker no longer exists.");}if ag_terminal(ag_text(row,2)){j_set(s,"phase",j_string("vm"));phase="vm";}else{j_set(cmd,"kind",j_string("wait"));j_set(cmd,"milliseconds",j_int(300));j_set(cmd,"waiting_for",j_int(id));return cmd;}
    }
    if h_equal(phase,"vm"){
        let p=ch_pending(s);if cj_int(p,"restored") && !cj_int(p,"resume"){return c_error("Interrupted program has no safe checkpoint. Side effects may already have happened; no program was replayed.");}
        let call=j_need(p,"call");let r=j_object();j_set(r,"source",j_need(call,"input"));j_set(r,"call_id",j_need(call,"call_id"));j_set(r,"resume",j_int(cj_int(p,"resume")));let feedback=cj_get(p,"feedback");if feedback && j_kind(feedback)==4{j_set(r,"feedback",feedback);}j_set(cmd,"kind",j_string("vm"));j_set(cmd,"request",r);return cmd;
    }
    if h_equal(phase,"next"){
        if cj_int(s,"step")>=16{j_set(s,"phase",j_string("failed"));j_set(s,"error",j_string("Stopped after 16 programs. Send a message to continue."));j_set(s,"finish_status",j_string("paused"));phase="failed";}
        else{let compact=0;if !cj_int(s,"fixture") && cj_int(s,"compacted_step")!=cj_int(s,"step"){let limits=ch_limits(s);compact=cj_int(j_need(limits,"usage"),"total_tokens")>=cj_int(limits,"auto_compact_token_limit");}if compact{phase="compact";}else{phase="model";}j_set(s,"phase",j_string(phase));}
    }
    if h_equal(phase,"model") || h_equal(phase,"compact"){j_set(cmd,"kind",j_string("model"));j_set(cmd,"compact",j_bool(h_equal(phase,"compact")));j_set(cmd,"engine_op",j_int(1));if h_equal(phase,"compact"){j_set(cmd,"engine_op",j_int(4));}j_set(cmd,"step",j_int(cj_int(s,"step")));j_set(cmd,"response_index",j_int(cj_int(s,"requests")));return cmd;}
    j_set(cmd,"kind",j_string("done"));if h_equal(phase,"failed"){j_set(cmd,"error",j_string(cj_text(s,"error")));}return cmd;
}
fn ch_host(request){
    ch_config=j_need(request,"config");ch_events=j_array();let action=cj_text(request,"action");
    if h_equal(action,"permissions"){return cp_permissions(cj_get(request,"saved"));}
    if h_equal(action,"stream"){return co_stream_packet(request);}
    if h_equal(action,"transport_error"){let out=j_object();j_set(out,"message",j_string(co_http_status(cj_int(request,"status"))));return out;}
    if h_equal(action,"authenticate"){let auth=co_auth_tokens(j_need(request,"auth"));if !auth{return c_error(co_problem);}return co_transport(auth);}
    let s=ch_normalize(cj_get(request,"state"));let failed=0;
    if h_equal(action,"open_worker"){s=ch_worker_open(request);if h_len(cj_text(s,"error")){return s;}}
    if h_equal(action,"begin"){ch_restart(s);ch_user(s,j_s(request,"text"),cj_get(request,"attachments"));j_set(s,"phase",j_string("next"));}
    if h_equal(action,"resume"){let requests=cj_int(s,"requests");ch_restart(s);let p=ch_pending(s);if p{j_set(s,"requests",j_int(requests));j_set(p,"restored",j_bool(1));ch_set_pending(s,p);let phase=ch_pending_phase(p);let feedback=cj_get(p,"feedback");if h_equal(cj_text(cj_get(p,"signal"),"kind"),"feedback") && (!feedback || j_kind(feedback)!=4){phase="feedback";}j_set(s,"phase",j_string(phase));}else{j_set(s,"phase",j_string("next"));}}
    if h_equal(action,"compact"){j_set(s,"manual_compact",j_bool(1));j_set(s,"phase",j_string("compact"));}
    j_set(s,"fixture",j_bool(cj_int(request,"fixture")));
    if h_equal(action,"reply"){failed=ch_reply(s,j_need(request,"reply"));}
    if h_equal(action,"observation"){failed=ch_observe(s,j_need(request,"observation"));}
    if h_equal(action,"platform_completed"){if !h_equal(cj_text(s,"phase"),"platform_permission"){return c_error("No Android consent is pending.");}j_set(s,"phase",j_string("vm"));}
    if h_equal(action,"feedback"){failed=ch_feedback(s,j_need(request,"reply"),"");}
    if h_equal(action,"compacted"){let reply=j_need(request,"reply");j_set(s,"messages",j_need(reply,"messages"));j_set(s,"usage",cj_null());j_set(s,"anchor",j_int(0));j_set(s,"compacted_step",j_int(cj_int(s,"step")));let phase="next";if cj_int(s,"manual_compact"){phase="done";}j_set(s,"manual_compact",j_bool(0));j_set(s,"phase",j_string(phase));ch_card(s,"info","Context compacted. FlexDB and workspace files are unchanged.",0);}
    if h_equal(action,"failure"){
        let text=j_s(request,"error");if h_equal(cj_text(s,"phase"),"feedback") && !cj_int(request,"cancelled"){failed=ch_feedback(s,0,text);}
        else if h_equal(cj_text(s,"phase"),"vm") || h_equal(cj_text(s,"phase"),"waiting") || h_equal(cj_text(s,"phase"),"feedback") || h_equal(cj_text(s,"phase"),"permission") || h_equal(cj_text(s,"phase"),"platform_permission"){
            let o=ch_failure_observation(s,text);let p=ch_pending(s);j_set(p,"stdout",j_string(""));j_set(p,"stderr",j_string(""));ch_observe(s,o);
            if cj_int(request,"cancelled"){j_set(s,"phase",j_string("done"));}
        }else{j_set(s,"phase",j_string("failed"));j_set(s,"error",j_string(text));ch_card(s,"error",text,0);}
    }
    if h_equal(action,"failure") && cj_int(request,"cancelled") && cj_int(ch_config,"agent_id"){j_set(s,"phase",j_string("failed"));j_set(s,"finish_status",j_string("paused"));}
    if failed && cj_get(failed,"error"){return failed;}let command=ch_command(s);
    if cj_get(command,"error") && !h_equal(cj_text(command,"kind"),"done"){
        // An unsafe restored execution is paired with an explicit observation;
        // the model can inspect uncertainty without replaying the program.
        if ch_pending(s){let text=cj_text(command,"error");let o=ch_failure_observation(s,text);let p=ch_pending(s);j_set(p,"stdout",j_string(""));j_set(p,"stderr",j_string(""));ch_observe(s,o);command=ch_command(s);}else{return command;}
    }
    if !ch_save(s){return c_error("Cannot save worker context.");}
    if h_equal(cj_text(command,"kind"),"done"){
        let status="done";if h_equal(cj_text(s,"phase"),"failed"){status=cj_text(s,"finish_status");if !h_len(status){status="failed";}}ch_worker_finish(s,status,cj_text(s,"error"));
    }
    let out=j_object();j_set(out,"state",s);j_set(out,"command",command);j_set(out,"cards",ch_events);return out;
}
