// Actual restricted VM program for the native incoming-RFCOMM fixture.
fn ri_fail(n){let message=db_error();db_io(0,2,message,db_len(message));return n;}
fn ri_word(seed){let p=alloc(32800);let x=seed;let i=0;while i<32800{x=x*6364136223846793005+1442695040888963407;store64(p+i,x);i=i+8;}store64(p,seed);return p;}
fn ri_listener(){return db_word(state_get("ri-listener"));}
fn ri_stream(){return db_word(state_get("ri-stream"));}
fn ri_setup(name,uuid,secure){
    if !bt_request_enable(){return ri_fail(1);}let h=bt_rfcomm_listen(name,uuid,secure);if !h{return ri_fail(2);}
    state_set("ri-listener",h);state_set("ri-service-name",db_text(name));state_set("ri-service-uuid",db_text(uuid));state_set("ri-secure",db_int(secure));return 0;
}
fn ri_empty_accept(){
    if bt_rfcomm_accept(ri_listener(),100){return ri_fail(1);}if !worker_equal(db_word(db_at(device_error(),0)),"timeout"){return ri_fail(2);}
    if !device_info(ri_listener()){return ri_fail(3);}return 0;
}
fn ri_accept(){
    let child=bt_rfcomm_accept(ri_listener(),8000);if !child{return ri_fail(1);}state_set("ri-stream",child);
    let info=device_info(db_word(child));if !info||!db_word(device_field(info,"connected"))||db_word(device_field(info,"connection_type"))!=1{return ri_fail(2);}
    let address=device_field(info,"address");state_set("ri-peer-address",address);db_io(0,1,db_word(address),db_bytes(address));return 0;
}
fn ri_close_listener(){
    if !device_close(ri_listener()){return ri_fail(1);}if device_info(ri_listener()){return ri_fail(2);}
    let again=bt_rfcomm_listen(db_word(state_get("ri-service-name")),db_word(state_get("ri-service-uuid")),db_word(state_get("ri-secure")));if !again{return ri_fail(3);}
    if !device_close(db_word(again)){return ri_fail(4);}if !db_word(device_field(device_info(ri_stream()),"connected")){return ri_fail(5);}return 0;
}
fn ri_exchange(seed){
    let expected=ri_word(seed);let reply=ri_word(seed^1515870810);let at=0;
    while at<32791{let want=32791-at;if want>32768{want=32768;}let bytes=device_read(ri_stream(),want,8000);if !bytes||db_kind(bytes)!=3||db_bytes(bytes)<1||db_bytes(bytes)>want{return ri_fail(1);}let i=0;while i<db_bytes(bytes){if load8(db_word(bytes)+i)!=load8(expected+at+i){return ri_fail(2);}i=i+1;}at=at+db_bytes(bytes);}
    if db_word(device_write(ri_stream(),db_blob(reply,32768)))!=32768||db_word(device_write(ri_stream(),db_blob(reply+32768,23)))!=23{return ri_fail(3);}
    state_set("ri-verified-bytes",db_int(at));return 0;
}
fn ri_close_stream(){if !device_close(ri_stream()){return ri_fail(1);}if device_info(ri_stream()){return ri_fail(2);}return 0;}
fn ri_bonds(name){
    let at=0;let count=0;while at>=0{let page=bt_bonded(at,16);if !page{return ri_fail(1);}let rows=device_field(page,"devices");let i=0;while i<db_count(rows){let row=db_at(rows,i);let address=device_field(row,"address");if db_bytes(address)!=17{return ri_fail(2);}if !load8(name)||worker_equal(db_word(device_field(row,"name")),name){db_io(0,1,db_word(address),17);db_io(0,1,"\n",1);}i=i+1;count=count+1;if count>1024{return ri_fail(3);}}at=db_word(device_field(page,"next"));}return 0;
}
fn ri_unpaired(address){let d=bt_device(address);if !d{return ri_fail(1);}let info=device_info(db_word(d));if !info||db_word(device_field(info,"bond_state"))!=10{return ri_fail(2);}return device_close(db_word(d))-1;}
