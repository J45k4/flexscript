// Portable card callback state machine. Android owns routing and durable files;
// this code owns byte paging, staged replies and the callback capability boundary.
import "hardware.flex";
global card_active=0;
global card_input=0;
global card_input_bytes=0;
global card_saved=0;
global card_output=0;
global card_output_bytes=0;
global card_output_written=0;
global card_committed=0;
fn card_begin(input,state){
    if j_kind(input)!=3 || j_count(input)<1 || j_count(input)>3{return 0;}
    card_input=alloc(65544);card_input_bytes=0;let i=0;
    while i<j_count(input){let part=hw_value(j_at(input,i),0);if db_kind(part)!=3 || db_bytes(part)<1 || db_bytes(part)>65544-card_input_bytes{return 0;}h_copy(card_input+card_input_bytes,db_word(part),db_bytes(part));card_input_bytes=card_input_bytes+db_bytes(part);i=i+1;}
    if card_input_bytes<4{return 0;}card_saved=hw_value(state,0);let state_bytes=db_encode(card_saved);if !card_saved || !state_bytes || state_bytes>65504{return 0;}
    card_output=0;card_output_bytes=0;card_output_written=0;card_committed=0;card_active=1;return 1;
}
fn card_fail(code,message){let r=db_list();db_add(r,hw_error(code,message));db_add(r,db_null());return db_encode(r);}
fn card_ok(value){let r=db_list();db_add(r,db_null());db_add(r,value);return db_encode(r);}
fn card_dispatch(request){
    if db_kind(request)!=5 || db_kind(db_at(request,0))!=2{return card_fail("invalid_argument","Expected a typed card callback request.");}
    let op=db_word(db_at(request,0));let count=db_count(request);
    if card_committed{return card_fail("already_committed","The callback already committed its reply; return0 now.");}
    if h_equal(op,"card_state") && count==1{return card_ok(card_saved);}
    if h_equal(op,"card_command") && count==3{
        let offset=db_at(request,1);let limit=db_at(request,2);
        if db_kind(offset)!=1 || db_kind(limit)!=1 || db_word(offset)<0 || db_word(offset)>card_input_bytes || db_word(limit)<1 || db_word(limit)>32768{return card_fail("invalid_argument","Command offset is0..size and limit is1..32768.");}
        let at=db_word(offset);let n=card_input_bytes-at;if n>db_word(limit){n=db_word(limit);}
        let page=db_list();db_add(page,db_blob(card_input+at,n));db_add(page,db_int(card_input_bytes));let next=at+n;if next==card_input_bytes{next=-1;}db_add(page,db_int(next));return card_ok(page);
    }
    if h_equal(op,"card_reply_begin") && count==2{
        let total=db_at(request,1);if db_kind(total)!=1 || db_word(total)<2 || db_word(total)>65538{return card_fail("invalid_argument","An APDU reply contains2..65538 bytes, including status bytes.");}
        if card_output{return card_fail("busy","A reply is already staged; continue at its current offset.");}
        card_output_bytes=db_word(total);card_output=alloc(card_output_bytes);return card_ok(db_int(card_output_bytes));
    }
    if h_equal(op,"card_reply_write") && count==3{
        if !card_output{return card_fail("not_ready","Begin the reply before writing bytes.");}
        let at=db_at(request,1);let data=db_at(request,2);
        if db_kind(at)!=1 || db_word(at)!=card_output_written || db_kind(data)!=3 || db_bytes(data)<1 || db_bytes(data)>card_output_bytes-card_output_written{return card_fail("invalid_argument","Append a nonempty blob at the exact next offset without exceeding the reply size.");}
        h_copy(card_output+card_output_written,db_word(data),db_bytes(data));card_output_written=card_output_written+db_bytes(data);return card_ok(db_int(db_bytes(data)));
    }
    if h_equal(op,"card_commit") && count==2{
        if !card_output || card_output_written!=card_output_bytes{return card_fail("not_ready","Write the entire reply before committing.");}
        let state=db_at(request,1);let bytes=db_encode(state);if !state || !bytes || bytes>65504{return card_fail("size_limit","Saved callback state must fit one64KiB typed reply frame including its envelope.");}
        card_saved=state;card_committed=1;return card_ok(db_int(1));
    }
    return card_fail("callback_restricted","Card callbacks can only read their command/state and stage one reply/state. Host files, database, network, workers and hardware calls are unavailable.");
}
fn card_result(){
    let result=j_object();j_set(result,"committed",j_bool(card_committed));
    if card_committed{
        let parts=j_array();let i=0;while i<card_output_bytes{let n=card_output_bytes-i;if n>32768{n=32768;}j_push(parts,hw_json(db_blob(card_output+i,n),0));i=i+n;}
        j_set(result,"response",parts);j_set(result,"saved_state",hw_json(card_saved,0));
    }return result;
}
