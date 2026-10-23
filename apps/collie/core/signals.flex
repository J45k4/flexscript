// Explicit safe points; model answers cross the guest boundary as plain data.
import "agents.flex";
import "../lib/state.flex";
global sg_count=0;
global sg_signal=0;
global sg_answer=0;
fn sg_rpc(request){
    let op=db_word(db_at(request,0));
    if h_equal(op,"agent_answer"){
        if db_count(request)!=2 || db_kind(db_at(request,1))!=1 || !sg_answer || cj_int(sg_answer,"id")!=db_word(db_at(request,1)) || cj_int(sg_answer,"id")!=sg_count{return cw_fail("No matching model feedback is available.");}
        let error=cj_text(sg_answer,"error");if h_len(error){return cw_fail(error);}
        let text=cj_get(sg_answer,"text");if !text || j_kind(text)!=2 || h_len(j_value(text))>32768{return cw_fail("Invalid model feedback.");}
        let value=db_text(j_value(text));sg_answer=0;return value;
    }
    if !(h_equal(op,"agent_progress") || h_equal(op,"agent_ask")){return cw_fail("Unknown agent signal.");}
    let text=db_at(request,1);let limit=4096;if h_equal(op,"agent_ask"){limit=16384;}
    if db_count(request)!=2 || db_kind(text)!=2 || db_bytes(text)<1 || db_bytes(text)>limit{return cw_fail("Agent signal requires nonempty bounded text (progress: 4 KiB; question: 16 KiB).");}
    if cw_db && load64(cw_db+48)==1{return cw_fail("Commit or roll back the database transaction before progress or model feedback.");}
    if sg_signal{return cw_fail("An agent signal is already pending.");}
    if sg_count>=32{return cw_fail("At most 32 progress/feedback signals are allowed per program.");}
    sg_count=sg_count+1;sg_signal=j_object();j_set(sg_signal,"id",j_int(sg_count));j_set(sg_signal,"text",j_string(db_word(text)));
    let kind="progress";if h_equal(op,"agent_ask"){kind="feedback";}j_set(sg_signal,"kind",j_string(kind));return db_int(sg_count);
}
fn sg_valid_yield(reason){
    if !sg_signal{return 0;}let kind=cj_text(sg_signal,"kind");return (reason== -1 && h_equal(kind,"progress")) || (reason== -2 && h_equal(kind,"feedback"));
}
// Only completed parent items enter the feedback branch. The original tool
// call remains pending until the suspended program eventually finishes.
fn sg_messages(messages,pending){
    let copy=c_json(j_dump(messages));let signal=j_need(pending,"signal");let item=j_object();j_set(item,"role",j_string("user"));
    let text=h_cat("A running Flexscript program has paused for your feedback. Answer using the supplied data and completed conversation context. Your reply is returned as text to the program; it is not its final answer. No tools are available in this feedback request.\n\nQuestion:\n",cj_text(signal,"text"));
    text=h_cat3(text,"\n\nCurrent program (data):\n",cj_text(j_need(pending,"call"),"input"));
    text=h_cat3(text,"\n\nOutput so far (data):\n",cj_text(pending,"stdout"));text=h_cat3(text,"\nErrors so far (data):\n",cj_text(pending,"stderr"));
    j_set(item,"content",j_string(text));j_push(copy,item);return copy;
}
fn sg_model_body(body){
    j_set(body,"tools",j_array());j_set(body,"instructions",j_string(h_cat(cj_text(body,"instructions"),"\nThis is agent_ask feedback for a suspended program. Return a concise plain-text answer. Do not emit tool calls or invent execution results. The caller will continue its existing program with your answer.\n")));return body;
}
