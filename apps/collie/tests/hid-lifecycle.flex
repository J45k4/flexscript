// Real-device fixture policy. The host supplies actual SDK/radio/UI events.
// Compiling this file does not run hardware operations; Android calls hl_step.
import "../guest/runtime.flex";
import "../guest/workers.flex";
import "../guest/hardware.flex";
import "../guest/hardware-access.flex";
import "../guest/haptics.flex";

fn hl_eq(map,key,text){let value=device_field(map,key);return db_kind(value)==2&&worker_equal(db_word(value),text);}
fn hl_error(code){return worker_equal(db_word(db_at(device_error(),0)),code);}
fn hl_cap(){let rows=hardware_capabilities();let i=0;while i<db_count(rows){let row=db_at(rows,i);if hl_eq(row,"id","bluetooth_hid_device"){return row;}i=i+1;}return db_null();}
fn hl_descriptor(){
    let d=alloc(32);
    store64(d,0x8501a10109ff0006);store64(d+8,0x087500ff26001501);
    store64(d+16,0x090281010901fe96);store64(d+24,0xc002b10309029102);
    return db_blob(d,32);
}
fn hl_open(){return hid_open("Collie lifecycle","Vendor report test","Collie",0,hl_descriptor(),db_list(),db_list(),25000);}
fn hl_registered(h){let i=0;while i<30{let e=device_wait(h,500);if hl_eq(e,"event","registered"){return 1;}if hl_eq(e,"event","error"){return 0;}i=i+1;}return 0;}
fn hl_idle(){let watch=bt_watch();if !watch{return 0;}let i=0;while i<20{if !db_word(device_field(hl_cap(),"registration_busy")){return device_close(db_word(watch));}device_wait(db_word(watch),250);i=i+1;}device_close(db_word(watch));return 0;}
fn hl_connect(outgoing){
    let old=state_get("lifecycle_device");if db_kind(old)==2{device_close(db_word(old));}
    let device=bt_device(db_word(state_get("lifecycle_address")));if !device{return 1;}state_set("lifecycle_device",device);
    let h=hl_open();if !h||!hl_registered(db_word(h)){return 2;}state_set("lifecycle_hid",h);
    let token=state_get("lifecycle_token");if db_kind(token)==2{if hid_reply(db_word(h),db_word(token),db_blob("old",3)){return 3;}if !hl_error("stale_request"){return 4;}}
    if outgoing{let peer=hid_connect(db_word(h),db_word(device));if !peer{return 5;}state_set("lifecycle_peer",peer);}return 0;
}
fn hl_capture(){
    let h=db_word(state_get("lifecycle_hid"));let i=0;
    while i<20{let e=device_wait(h,250);if hl_eq(e,"event","request"){
        if !hl_eq(e,"kind","get_report")||db_word(device_field(e,"report_id"))!=1||db_word(device_field(e,"report_type"))!=3{return 10;}
        let peers=hid_peers(h,0,8);if db_word(device_field(peers,"total"))!=1{return 11;}
        let live=db_at(device_field(peers,"peers"),0);if !hl_eq(live,"id",db_word(device_field(e,"peer")))||db_word(device_field(live,"state"))!=2||db_word(device_field(hid_requests(h,0,8),"total"))!=1{return 11;}
        state_set("lifecycle_peer",device_field(e,"peer"));
        state_set("lifecycle_token",device_field(e,"token"));return 0;
    }if hl_eq(e,"event","error"){return 12;}i=i+1;}return 13;
}
fn hl_radio_retired(){
    let h=db_word(state_get("lifecycle_hid"));let i=0;let found=0;
    while i<20&&!found{let e=device_wait(h,250);if hl_eq(e,"event","error"){
        let code=device_field(e,"code");if !worker_equal(db_word(code),"bluetooth_disabled")&&!worker_equal(db_word(code),"service_disconnected")&&!worker_equal(db_word(code),"unregistered"){return 20;}
        db_io(0,1,db_word(code),db_bytes(code));found=1;
    }i=i+1;}if !found{return 21;}
    let info=device_info(h);if !hl_eq(info,"state","error")||db_word(device_field(info,"pending_requests"))||db_word(device_field(info,"peers"))||!db_word(device_field(info,"teardown_confirmed")){return 22;}
    if hid_reply(h,db_word(state_get("lifecycle_token")),db_blob("late",4))||!hl_error("not_ready"){return 23;}
    if hl_open()||!hl_error("bluetooth_disabled"){return 24;}
    return !device_close(h);
}
fn hl_gone(){
    let h=db_word(state_get("lifecycle_hid"));if device_info(h)||!hl_error("stale_handle"){return 30;}
    if hid_reply(h,db_word(state_get("lifecycle_token")),db_blob("late",4))||!hl_error("stale_handle"){return 31;}return 0;
}
fn hl_fresh(){
    let h=db_word(state_get("lifecycle_hid"));let n=hl_capture();if n{return n;}
    if !hid_reply(h,db_word(state_get("lifecycle_token")),db_blob("safe",4)){return 40;}
    let i=0;while i<4{let e=device_wait(h,250);if hl_eq(e,"event","error"){return 41;}i=i+1;}
    return !hl_eq(device_info(h),"state","registered");
}
fn hl_step(mode){
    if mode==1{return hl_connect(1);}if mode==8{return hl_connect(0);}if mode==2{return hl_capture();}if mode==3{return hl_radio_retired();}
    if mode==4{let n=hl_gone();if n{return n;}if hl_open()||!hl_error("permission_denied"){return 32;}return 0;}
    if mode==5{let n=hl_gone();if n{return n;}let c=hl_cap();if !db_word(device_field(c,"runtime_permission_required"))||db_word(device_field(c,"available")){return 33;}return 0;}
    if mode==6{return hl_fresh();}
    if mode==7{if !device_close(db_word(state_get("lifecycle_hid")))||!hl_idle(){return 42;}return device_close(db_word(state_get("lifecycle_device")))-1;}
    return 99;
}
fn main(){return 0;}
