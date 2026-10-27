import "../lib/state.flex";
// Portable vision request policy. ci_load is a platform byte-reader hook; image
// decoding and the validated private snapshot file remain platform operations.
fn ci_base64(data,n){let out=alloc(((n+2)/3)*4+1);let abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";let at=0;let i=0;while i<n{let x=load8(data+i)<<16;if i+1<n{x=x|(load8(data+i+1)<<8);}if i+2<n{x=x|load8(data+i+2);}store8(out+at,load8(abc+((x>>18)&63)));store8(out+at+1,load8(abc+((x>>12)&63)));let a=61;let b=61;if i+1<n{a=load8(abc+((x>>6)&63));}if i+2<n{b=load8(abc+(x&63));}store8(out+at+2,a);store8(out+at+3,b);i=i+3;at=at+4;}store8(out+at,0);return out;}
fn ci_views(item){if !h_equal(cj_text(item,"type"),"custom_tool_call_output"){return 0;}let raw=cj_text(item,"output");if load8(raw)!=123{return 0;}let observation=c_json(raw);let views=cj_get(observation,"views");if views && j_kind(views)==3{return views;}return 0;}
fn ci_tokens(messages,anchor){let n=0;let i=anchor;if i<0{i=0;}while i<j_count(messages){let views=ci_views(j_at(messages,i));if views{let k=0;while k<j_count(views){if h_equal(cj_text(j_at(views,k),"type"),"image"){n=n+4096;}k=k+1;}}i=i+1;}return n;}
fn ci_prepare(request){
    let input=j_need(request,"input");let chosen=j_object();let sent=j_object();let used=0;let budget=(8388608-h_len(j_dump(request))-32768)*3/4;if budget<0{budget=0;}if budget>4194304{budget=4194304;}
    let i=j_count(input);while i{i=i-1;let views=ci_views(j_at(input,i));if views{let k=j_count(views);while k{k=k-1;let view=j_at(views,k);if h_equal(cj_text(view,"type"),"image"){
        let id=j_s(view,"image_id");if !j_get(chosen,id){let size=alloc(8);let bytes=ci_load(id,size);if bytes>0 && load64(size)<=budget-used{let value=j_object();j_set(value,"url",j_string(h_cat("data:image/jpeg;base64,",ci_base64(bytes,load64(size)))));j_set(chosen,id,value);used=used+load64(size);}}
    }}}}
    i=0;while i<j_count(input){let item=j_at(input,i);let views=ci_views(item);if views{let output=j_array();let part=j_object();j_set(part,"type",j_string("input_text"));j_set(part,"text",j_need(item,"output"));j_push(output,part);let k=0;
        while k<j_count(views){let view=j_at(views,k);if h_equal(cj_text(view,"type"),"image"){let id=j_s(view,"image_id");let value=j_get(chosen,id);let part=j_object();
            if value && !j_get(sent,id){j_set(sent,id,j_bool(1));j_set(part,"type",j_string("input_image"));j_set(part,"detail",j_string("auto"));j_set(part,"image_url",j_need(value,"url"));}
            else{let text="Image snapshot omitted from this request (unavailable or beyond the image budget). View the workspace image again if needed.";if j_get(sent,id){text="This exact image snapshot was already included earlier in this request.";}j_set(part,"type",j_string("input_text"));j_set(part,"text",j_string(text));}j_push(output,part);
        }k=k+1;}if j_count(output)>1{j_set(item,"output",output);}
    }i=i+1;}return request;
}
