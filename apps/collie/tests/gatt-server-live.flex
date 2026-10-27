// Original local GATT server VM logic and assertions.

fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}
fn eq(map,key,text){let v=device_field(map,key);return db_kind(v)==2 && worker_equal(db_word(v),text);}
fn row_id(s,parent,uuid,nth){let at=0;let n=0;while at>=0{let page=ble_server_items(s,parent,at,16);if !page{return 0;}let rows=device_field(page,"items");let i=0;while i<db_count(rows){let row=db_at(rows,i);if eq(row,"uuid",uuid){if n==nth{return db_word(device_field(row,"id"));}n=n+1;}i=i+1;}at=db_word(device_field(page,"next"));}return 0;}
fn peer_row(s,id){let at=0;while at>=0{let page=ble_server_peers(s,at,16);let rows=device_field(page,"peers");let i=0;while i<db_count(rows){let row=db_at(rows,i);if eq(row,"id",id){return row;}i=i+1;}at=db_word(device_field(page,"next"));}return db_null();}
fn answer(s,e,status,offset,bytes){if !db_word(device_field(e,"response_needed")){return 1;}return db_word(ble_server_respond(s,db_word(device_field(e,"token")),status,offset,bytes));}

fn gatt_server_live_setup(fixture_service,fixture_characteristic,fixture_descriptor,fixture_slow,fixture_control){
 let s=ble_server_open(3000);if !s{return 1;}state_set("server",s);let other=ble_server_open(3000);if !other{return 2;}state_set("other",other);
 let ds=db_list();ble_define_descriptor(ds,fixture_descriptor,17);ble_define_descriptor(ds,"00002902-0000-1000-8000-00805f9b34fb",17);
 let invalid=db_list();ble_define_characteristic(invalid,fixture_characteristic,256,1,db_list());if ble_server_add(db_word(s),fixture_service,0,invalid){return 9;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument") || db_word(device_field(device_info(db_word(s)),"attributes")){return 10;}
 let chars=db_list();ble_define_characteristic(chars,fixture_characteristic,62,17,ds);ble_define_characteristic(chars,fixture_characteristic,2,1,db_list());ble_define_characteristic(chars,fixture_slow,2,1,db_list());ble_define_characteristic(chars,fixture_control,10,17,db_list());
 let service=ble_server_add(db_word(s),fixture_service,0,chars);if !service{return 3;}state_set("service",service);let i=0;let active=0;while i<10 && !active{let e=device_wait(db_word(s),1000);if db_kind(e)==5 && eq(e,"event","service_added"){if db_word(device_field(e,"status"))!=0{return 4;}active=1;}i=i+1;}if !active{return 5;}
 let first=row_id(db_word(s),db_word(service),fixture_characteristic,0);let second=row_id(db_word(s),db_word(service),fixture_characteristic,1);if !first || !second || worker_equal(first,second){return 6;}state_set("first",db_text(first));state_set("second",db_text(second));state_set("descriptor",db_text(row_id(db_word(s),first,fixture_descriptor,0)));state_set("cccd",db_text(row_id(db_word(s),first,"00002902-0000-1000-8000-00805f9b34fb",0)));state_set("slow",db_text(row_id(db_word(s),db_word(service),fixture_slow,0)));state_set("control",db_text(row_id(db_word(s),db_word(service),fixture_control,0)));
 if ble_server_items(db_word(other),first,0,16){return 7;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_attribute"){return 8;}
 let bytes=alloc(512);i=0;while i<512{store8(bytes+i,i%256);i=i+1;}state_set("value",db_blob(bytes,512));let b=alloc(4);store8(b,0);store8(b+1,255);store8(b+2,129);store8(b+3,90);state_set("descriptor_value",db_blob(b,4));return 0;
 }
fn gatt_server_live_alive(){let s=db_word(state_get("server"));if !eq(device_info(s),"state","open"){return 1;}let rows=device_field(ble_server_items(s,"",0,16),"items");if db_count(rows)!=1 || !db_word(device_field(db_at(rows,0),"active")){return 2;}return 0;}
fn gatt_server_live_advertise(fixture_service){let h=ble_advertise(fixture_service,db_blob("",0),-1,db_blob("",0),1,2,2,0);if !h{return 1;}state_set("advertisement",h);let i=0;while i<10{let e=device_wait(db_word(h),1000);if db_kind(e)==5 && eq(e,"event","started"){return 0;}i=i+1;}return 2;}
fn gatt_server_live_finish(){let s=db_word(state_get("server"));if db_word(state_get("batches"))<2 || !db_word(state_get("status_validated")){return 8;}if !db_word(state_get("pending_observed")) || !db_word(state_get("expiration_seen")) || !db_word(state_get("replay_rejected")) || !db_word(state_get("no_response_seen")){return 1;}if db_word(device_field(ble_server_requests(s,0,16),"total")){return 2;}let i=0;while i<20 && db_word(device_field(ble_server_peers(s,0,16),"total")){device_wait(s,500);i=i+1;}if db_word(device_field(ble_server_peers(s,0,16),"total")){return 3;}let old=db_word(state_get("first"));if !ble_server_remove(s,db_word(state_get("service"))){return 4;}if ble_server_items(s,old,0,16){return 5;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_attribute"){return 6;}if !device_close(db_word(state_get("advertisement"))){return 7;}return device_close(s)-1;}

fn handle(s,e){
 let kind=db_word(device_field(e,"kind"));let peer=db_word(device_field(e,"peer"));state_set("peer",db_text(peer));let token=device_field(e,"token");let empty=db_blob("",0);
 if worker_equal(kind,"execute"){let staged=state_get("prepared");if db_word(device_field(e,"execute")) && db_kind(staged)==3{state_set("value",staged);}state_set("prepared",db_null());return answer(s,e,0,0,empty);}
 let attribute=db_word(device_field(e,"attribute"));let off=db_word(device_field(e,"offset"));let first=db_word(state_get("first"));
 if worker_equal(kind,"read"){
  if worker_equal(attribute,db_word(state_get("slow"))){state_set("expired_token",token);let pending=ble_server_requests(s,0,16);if db_word(device_field(pending,"total"))<1{return 0;}state_set("pending_observed",db_int(1));return 1;}
  if !db_word(state_get("token_isolation")){let other=db_word(state_get("other"));if ble_server_respond(other,db_word(token),0,0,empty){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_request"){return 0;}if !device_close(other){return 0;}state_set("token_isolation",db_int(1));}
  let value=db_null();if worker_equal(attribute,first){value=state_get("value");}else{if worker_equal(attribute,db_word(state_get("second"))){value=db_blob("second",6);}else{if worker_equal(attribute,db_word(state_get("descriptor"))){value=state_get("descriptor_value");}else{if worker_equal(attribute,db_word(state_get("cccd"))){let b=alloc(2);store8(b,db_word(state_get("subscription")));store8(b+1,0);value=db_blob(b,2);}else{if worker_equal(attribute,db_word(state_get("control"))){let b=alloc(1);store8(b,db_word(state_get("sent")));value=db_blob(b,1);}}}}}
  if db_kind(value)!=3{return answer(s,e,6,0,empty);}let n=db_bytes(value);if off<0 || off>n{return answer(s,e,7,0,empty);}n=n-off;let row=peer_row(s,peer);let limit=db_word(device_field(row,"mtu"))-1;if n>limit{n=limit;}if !db_word(state_get("status_validated")){if ble_server_respond(s,db_word(token),256,0,empty){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"invalid_argument"){return 0;}state_set("status_validated",db_int(1));}let ok=answer(s,e,0,off,db_blob(db_word(value)+off,n));if !ok{return 0;}
  if !db_word(state_get("replay_rejected")){if ble_server_respond(s,db_word(token),0,0,empty){return 0;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_request"){return 0;}state_set("replay_rejected",db_int(1));}return 1;
 }
 let value=device_field(e,"value");let prepared=db_word(device_field(e,"prepared"));
 if worker_equal(attribute,first){
  if off<0 || off+db_bytes(value)>512{return answer(s,e,13,0,empty);}
  if prepared{let old=state_get("prepared");if db_kind(old)!=3{old=state_get("value");}let b=alloc(512);let i=0;while i<512{store8(b+i,load8(db_word(old)+i));i=i+1;}i=0;while i<db_bytes(value){store8(b+off+i,load8(db_word(value)+i));i=i+1;}state_set("prepared",db_blob(b,512));return answer(s,e,0,off,value);}
  if off!=0{return answer(s,e,7,0,empty);}state_set("value",value);if !db_word(device_field(e,"response_needed")){if db_kind(token)!=0{return 0;}state_set("no_response_seen",db_int(1));}
  if db_word(state_get("subscription")){state_set("send",value);}return answer(s,e,0,0,empty);
 }
 if worker_equal(attribute,db_word(state_get("descriptor"))){if prepared || off!=0{return answer(s,e,6,0,empty);}state_set("descriptor_value",value);return answer(s,e,0,0,empty);}
 if worker_equal(attribute,db_word(state_get("cccd"))){if off || db_bytes(value)!=2 || load8(db_word(value))>3 || load8(db_word(value)+1){return answer(s,e,13,0,empty);}state_set("subscription",db_int(load8(db_word(value))));if !load8(db_word(value)){state_set("send",db_null());}return answer(s,e,0,0,empty);}
 if worker_equal(attribute,db_word(state_get("control"))){if db_bytes(value)==4 && load8(db_word(value))==83 && load8(db_word(value)+1)==84 && load8(db_word(value)+2)==79 && load8(db_word(value)+3)==80{state_set("stop",db_int(1));return answer(s,e,0,0,empty);}}
 return answer(s,e,3,0,empty);
}
fn gatt_server_live_loop(){state_set("batches",db_int(db_word(state_get("batches"))+1));let s=db_word(state_get("server"));let loops=0;while loops<8{
 let e=device_wait(s,500);if db_kind(e)==5{
  if eq(e,"event","request"){if !handle(s,e){return 1;}}
  if eq(e,"event","error"){let m=device_field(e,"message");db_io(0,2,db_word(m),db_bytes(m));return 2;}
  if eq(e,"event","notification_sent"){if db_word(device_field(e,"status"))!=0{return 3;}state_set("sent",db_int(db_word(state_get("sent"))+1));}
  if eq(e,"event","request_expired"){let token=db_word(device_field(e,"token"));if ble_server_respond(s,token,0,0,db_blob("",0)){return 4;}if !worker_equal(db_word(db_at(device_error(),0)),"stale_request"){return 5;}state_set("expiration_seen",db_int(1));}
 }
 let queued=state_get("send");let peer=state_get("peer");if db_kind(queued)==3 && db_kind(peer)==2{let row=peer_row(s,db_word(peer));if db_kind(row)==5 && eq(row,"pending_operation",""){let id=db_word(state_get("next_notify"));let confirm=db_word(state_get("subscription"))&2;if confirm{confirm=1;}if !ble_server_notify(s,db_word(peer),db_word(state_get("first")),queued,confirm,id){return 6;}state_set("next_notify",db_int(id+1));state_set("send",db_null());}}
 if db_word(state_get("stop")) && db_word(state_get("next_notify"))==db_word(state_get("sent")){return 0;}loops=loops+1;
}return 0;}
