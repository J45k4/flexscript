// Codex-compatible text history and encrypted compaction checkpoints.
// Reference: openai/codex 89461ea, compact_remote_v2.rs and history.rs.
import "instructions.flex";
import "usage.flex";
import "../core/protocol.flex";

fn co_compaction(item) {
    let kind=c_string(item,"type");if !kind || !(h_equal(kind,"compaction") || h_equal(kind,"compaction_summary")) {return 0;}
    let cipher=c_string(item,"encrypted_content");if !cipher || !h_len(cipher) || h_len(cipher)>1048576 {return 0;}
    let result=j_object();j_set(result,"type",j_string("compaction"));j_set(result,"encrypted_content",j_string(cipher));
    let id=c_string(item,"id");if id && h_len(id)<=256 {j_set(result,"id",j_string(id));}return result;
}
fn co_history_valid(items) {
    if !items || j_kind(items)!=3 || j_count(items)>4095 {return 0;}
    let pending=0;let i=0;while i<j_count(items) {let m=j_at(items,i);let type=c_string(m,"type");
        if type {
            if co_compaction(m) {if pending {return 0;}}
            else if h_equal(type,"custom_tool_call") {let call=pt_call(m);if !call || pending {return 0;}pending=j_s(call,"call_id");if pt_seen(items,pending,i) {return 0;}}
            else if h_equal(type,"custom_tool_call_output") {let result=pt_result(m);if !result || !pending || !h_equal(j_s(result,"call_id"),pending) {return 0;}pending=0;}
            else if !pt_reasoning(m) {return 0;}
        }else {let role=c_string(m,"role");let text=c_string(m,"content");if !role || !(h_equal(role,"user") || h_equal(role,"assistant")) || !text || h_len(text)>131200 || (pending && h_equal(role,"user")) {return 0;}}
        i=i+1;}return !pending;
}
fn co_item_tokens(item) {
    let cipher=c_string(item,"encrypted_content");if cipher && co_compaction(item) {return (h_len(cipher)+11)/12;}
    if pt_reasoning(item) {let n=(h_len(cipher)+11)/12;let parts=j_get(item,"summary");let i=0;while parts && i<j_count(parts){n=n+(h_len(j_s(j_at(parts,i),"text"))+3)/4;i=i+1;}return n;}
    let call=pt_call(item);if call {return (h_len(j_s(call,"input"))+3)/4;}
    let result=pt_result(item);if result {return (h_len(j_s(result,"output"))+3)/4;}
    let text=c_string(item,"content");return (h_len(text)+3)/4;
}
fn co_usage_anchor(messages) {
    let i=j_count(messages);while i {i=i-1;let m=j_at(messages,i);let role=c_string(m,"role");if co_compaction(m) || pt_call(m) || pt_reasoning(m) || (role && h_equal(role,"assistant")) {return i+1;}}return 0;
}
fn co_context_usage(messages,usage,anchor) {
    let total=co_count(usage,"total_tokens");let estimated=0;let i=anchor;
    if total<0 || anchor<0 || anchor>j_count(messages) {total=(h_len(co_instructions())+3)/4;i=0;estimated=1;}
    if usage && c_flag(usage,"estimated") {estimated=1;}
    while i<j_count(messages) {total=total+co_item_tokens(j_at(messages,i));estimated=1;i=i+1;}
    if !estimated {return usage;}
    let result=j_object();j_set(result,"input_tokens",j_int(0));j_set(result,"output_tokens",j_int(0));j_set(result,"total_tokens",j_int(total));j_set(result,"estimated",j_bool(1));return result;
}
fn co_utf8_prefix(text,limit) {let n=h_len(text);if n<=limit {return text;}while limit>0 && (load8(text+limit)&192)==128 {limit=limit-1;}return h_slice(text,limit);}
fn co_compacted_history(messages,item) {
    // Codex retains newest genuine user requests within 64k estimated tokens,
    // followed by the encrypted summary. VM observations are covered by it.
    let retained=h_vec();let remaining=64000;let i=j_count(messages);
    while i && remaining>0 && h_count(retained)<4000 {i=i-1;let m=j_at(messages,i);let role=c_string(m,"role");let text=c_string(m,"content");
        if role && h_equal(role,"user") && text && !c_flag(m,"observation") && !h_starts(text,"VM observation (data): ") {
            let tokens=(h_len(text)+3)/4;if tokens<1 {tokens=1;}
            let copy=j_object();j_set(copy,"role",j_string("user"));
            if tokens<=remaining {j_set(copy,"content",j_string(text));remaining=remaining-tokens;}
            else {let prefix=co_utf8_prefix(text,remaining*4);j_set(copy,"content",j_string(prefix));remaining=0;}
            h_add(retained,copy);
        }
    }
    let result=j_array();i=h_count(retained);while i {i=i-1;j_push(result,h_at(retained,i));}j_push(result,item);return result;
}
