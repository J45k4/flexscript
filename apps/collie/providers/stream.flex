import "../lib/state.flex";
// Streaming protocol state belongs to the provider, not to platform TLS code.
import "codex.flex";
fn co_summary_update(stream,id,index,text,append){
    if !pt_id(id) || index<0 || index>127{return c_error("Invalid summary stream identity.");}
    let parts=cj_array(stream,"summaries");let i=0;let part=0;let bytes=0;
    while i<j_count(parts){let p=j_at(parts,i);bytes=bytes+h_len(cj_text(p,"text"));if h_equal(cj_text(p,"item_id"),id) && cj_int(p,"summary_index")==index{part=p;}i=i+1;}
    let old=cj_text(part,"text");if append{text=h_cat(old,text);}if bytes-h_len(old)+h_len(text)>65536{return c_error("Reasoning summaries exceed 64 KiB.");}
    if !part{if j_count(parts)>=128{return c_error("Too many reasoning summaries.");}part=j_object();j_set(part,"item_id",j_string(id));j_set(part,"summary_index",j_int(index));j_push(parts,part);}j_set(part,"text",j_string(text));return 0;
}
fn co_summary_item(stream,item){let parts=pt_summary_parts(item);if !parts{return c_error("Invalid reasoning summary.");}let i=0;while i<j_count(parts){let error=co_summary_update(stream,cj_text(item,"id"),i,cj_text(j_at(parts,i),"text"),0);if error{return error;}i=i+1;}return 0;}
fn co_stream_display(stream,feedback){let view=j_object();let text=cj_text(stream,"text");let prose=text;let answer="";if feedback{prose="";answer=text;}j_set(view,"text",j_string(prose));j_set(view,"feedback",j_string(answer));j_set(view,"source",j_string(cj_text(stream,"source")));j_set(view,"summaries",cj_array(stream,"summaries"));return view;}
fn co_stream_packet(request){
    let stream=cj_get(request,"stream");if !stream{stream=j_object();}let raw=j_s(request,"event_json");if h_equal(raw,"[DONE]"){let out=j_object();j_set(out,"stream",stream);j_set(out,"display",co_stream_display(stream,cj_int(request,"feedback")));j_set(out,"preview",j_string(cj_text(stream,"text")));j_set(out,"complete",j_bool(0));return out;}let event=c_json(raw);let kind=cj_text(event,"type");let compact=cj_int(request,"compact");
    if !compact && (h_equal(kind,"response.reasoning_summary_text.delta") || h_equal(kind,"response.reasoning_summary_text.done") || h_equal(kind,"response.reasoning_summary_part.added") || h_equal(kind,"response.reasoning_summary_part.done")){
        let index=cj_get(event,"summary_index");if !index || j_kind(index)!=1{return c_error("Invalid summary part index.");}let append=h_equal(kind,"response.reasoning_summary_text.delta");let key="text";if append{key="delta";}let value=cj_get(event,key);
        if h_equal(kind,"response.reasoning_summary_part.added") || h_equal(kind,"response.reasoning_summary_part.done"){let part=cj_get(event,"part");if !h_equal(cj_text(part,"type"),"summary_text"){return c_error("Invalid summary part.");}value=cj_get(part,"text");}
        if !value || j_kind(value)!=2{return c_error("Invalid summary text.");}let error=co_summary_update(stream,cj_text(event,"item_id"),j_value(index),j_value(value),append);if error{return error;}
    }else if !compact && h_equal(kind,"response.output_text.delta"){let text=h_cat(cj_text(stream,"text"),j_s(event,"delta"));if h_len(text)>65536{return c_error("Assistant text exceeds limit.");}j_set(stream,"text",j_string(text));}
    else if !compact && h_equal(kind,"response.output_item.added"){
        let item=j_need(event,"item");if h_equal(cj_text(item,"type"),"custom_tool_call"){
            if !h_equal(cj_text(item,"name"),"flexscript") || h_len(cj_text(stream,"key")){return c_error("Unexpected or multiple tool calls.");}let id=cj_text(item,"id");if !h_len(id){id=cj_text(item,"call_id");}if !pt_id(id){return c_error("Invalid tool stream identity.");}j_set(stream,"key",j_string(id));
        }else if h_equal(cj_text(item,"type"),"reasoning"){let error=co_summary_item(stream,item);if error{return error;}}
    }else if !compact && h_equal(kind,"response.output_item.done"){
        let item=j_need(event,"item");if h_equal(cj_text(item,"type"),"reasoning"){let error=co_summary_item(stream,item);if error{return error;}}
    }else if !compact && h_equal(kind,"response.custom_tool_call_input.delta"){
        let id=cj_text(event,"item_id");if !h_len(id){id=cj_text(event,"call_id");}let key=cj_text(stream,"key");if !pt_id(id) || (h_len(key) && !h_equal(key,id)){return c_error("Tool stream identity changed.");}
        let text=h_cat(cj_text(stream,"source"),j_s(event,"delta"));if h_len(text)>65536{return c_error("Tool input exceeds limit.");}j_set(stream,"source",j_string(text));j_set(stream,"key",j_string(id));
    }
    let out=j_object();j_set(out,"stream",stream);j_set(out,"display",co_stream_display(stream,cj_int(request,"feedback")));j_set(out,"preview",j_string(cj_text(stream,"text")));j_set(out,"complete",j_bool(0));
    if h_equal(kind,"response.completed"){
        co_compact_mode=compact;co_stream_reset();let prose=cj_text(stream,"text");let source=cj_text(stream,"source");let key=cj_text(stream,"key");
        if h_len(prose){co_stream_delta(prose);}if h_len(key){co_source_delta(source,key);}let reply=co_completed(event);if !reply{return c_error(co_problem);}
        if compact{let messages=co_compacted_history(j_need(request,"messages"),reply);reply=j_object();j_set(reply,"messages",messages);}else{let parts=cj_get(reply,"summaries");if !parts || !j_count(parts){j_set(reply,"summaries",cj_array(stream,"summaries"));}}j_set(out,"reply",reply);j_set(out,"complete",j_bool(1));
    }else if h_equal(kind,"response.failed") || h_equal(kind,"response.incomplete") || h_equal(kind,"error"){return c_error("Model response failed or was incomplete.");}
    return out;
}
