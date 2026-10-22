import "../lib/state.flex";
// Streaming protocol state belongs to the provider, not to platform TLS code.
import "codex.flex";
fn co_stream_packet(request){
    let stream=cj_get(request,"stream");if !stream{stream=j_object();}let raw=j_s(request,"event_json");if h_equal(raw,"[DONE]"){let out=j_object();j_set(out,"stream",stream);j_set(out,"preview",j_string(cj_text(stream,"text")));j_set(out,"complete",j_bool(0));return out;}let event=c_json(raw);let kind=cj_text(event,"type");let compact=cj_int(request,"compact");
    if !compact && h_equal(kind,"response.output_text.delta"){let text=h_cat(cj_text(stream,"text"),j_s(event,"delta"));if h_len(text)>65536{return c_error("Assistant text exceeds limit.");}j_set(stream,"text",j_string(text));}
    else if !compact && h_equal(kind,"response.output_item.added"){
        let item=j_need(event,"item");if h_equal(cj_text(item,"type"),"custom_tool_call"){
            if !h_equal(cj_text(item,"name"),"flexscript") || h_len(cj_text(stream,"key")){return c_error("Unexpected or multiple tool calls.");}let id=cj_text(item,"id");if !h_len(id){id=cj_text(item,"call_id");}if !pt_id(id){return c_error("Invalid tool stream identity.");}j_set(stream,"key",j_string(id));
        }
    }else if !compact && h_equal(kind,"response.custom_tool_call_input.delta"){
        let id=cj_text(event,"item_id");if !h_len(id){id=cj_text(event,"call_id");}let key=cj_text(stream,"key");if !pt_id(id) || (h_len(key) && !h_equal(key,id)){return c_error("Tool stream identity changed.");}
        let text=h_cat(cj_text(stream,"source"),j_s(event,"delta"));if h_len(text)>65536{return c_error("Tool input exceeds limit.");}j_set(stream,"source",j_string(text));j_set(stream,"key",j_string(id));
    }
    let out=j_object();j_set(out,"stream",stream);j_set(out,"preview",j_string(cj_text(stream,"text")));j_set(out,"complete",j_bool(0));
    if h_equal(kind,"response.completed"){
        co_compact_mode=compact;co_stream_reset();let prose=cj_text(stream,"text");let source=cj_text(stream,"source");let key=cj_text(stream,"key");
        if h_len(prose){co_stream_delta(prose);}if h_len(key){co_source_delta(source,key);}let reply=co_completed(event);if !reply{return c_error(co_problem);}
        if compact{let messages=co_compacted_history(j_need(request,"messages"),reply);reply=j_object();j_set(reply,"messages",messages);}j_set(out,"reply",reply);j_set(out,"complete",j_bool(1));
    }else if h_equal(kind,"response.failed") || h_equal(kind,"response.incomplete") || h_equal(kind,"error"){return c_error("Model response failed or was incomplete.");}
    return out;
}
