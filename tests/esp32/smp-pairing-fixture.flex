// Test command/observation ABI. Expected bytes come from an independent Python
// protocol peer. Test-only epoch/secret injection is explicit in commands15/16.
global mc_memory=0;
global mc_snapshot=0;
global mc_observed=0;
global mc_checks=0;
global mc_case=0;
global mc_step=0;
global mc_free_clean=1;
fn mc_equal(a,b,n) {let i=0;while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn mc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn mc_check(ok) {mc_checks=mc_checks+1;if !ok {mc_report(mc_case,mc_step,mc_checks);}return ok;}
fn mc_free_wiped() {if !sm_work {return mc_value(mc_memory+16,6400,0);}let i=0;while i<sm_links {let p=sm_slot(i);if !load64(p) && !mc_value(p,1536,0) {return 0;}i=i+1;}return 1;}
fn mc_boot() {
    if sm_work {let i=0;while i<sm_links {let token=load64(sm_slot(i));if token {sm_close(token);}i=i+1;}sm_deinit();}
    // Independent cases model separate cold host instances. Within each case,
    // deinit/reinit uses the public API and must retain its connection floor.
    sm_token_floor=0;let i=0;while i<6432 {store8(mc_memory+i,165);i=i+1;}mc_free_clean=1;return sm_init(mc_memory+16,6400,4);
}
fn mc_command(cmd,payload) {
    let op=load64(cmd);let token=load64(cmd+8);let a=load64(cmd+16);let b=load64(cmd+24);let now=load64(cmd+32);let n=load64(cmd+40);
    if op==1 {if n!=22 {return -1000;}return sm_open(token,a,payload,payload+7,payload+14,now);}
    if op==2 {return sm_pair(token,now);}if op==3 {return sm_input(token,payload,n,now);}if op==4 {return sm_tick(now);}
    if op==5 {return sm_next_packet(token);}if op==6 {return sm_packet_sent(token,a,now);}if op==7 {return sm_next_event(token);}
    if op==8 {return sm_event_consumed(token,a,b);}if op==9 {return sm_consent(token,a,b,now);}
    if op==10 {let r=sm_close(token);mc_free_clean=mc_free_wiped();return r;}if op==11 {let r=sm_deinit();mc_free_clean=mc_free_wiped();return r;}
    if op==12 {let r=sm_init(mc_memory+16+b,a,token);mc_free_clean=mc_free_wiped();return r;}
    if op==13 {if a==0 {return sm_snapshot(token,mc_snapshot,223);}if a==1 {return sm_snapshot(token,0,224);}return sm_snapshot(token,sm_work,224);}
    if op==14 {return sm_input(token,sm_work+a,b,now);}
    if op==15 {let p=sm_find(token);if !p {return -107;}store64(p+192,a);return 0;}
    if op==16 {let p=sm_find(token);if !p {return -107;}let i=0;while i<1024 {store8(p+512+i,a);i=i+1;}return 0;}
    if op==17 {if n!=7 {return -1000;}return sm_method(load8(payload),load8(payload+1),load8(payload+2),load8(payload+3),load8(payload+4),load8(payload+5),load8(payload+6));}
    if op==18 {return sm_request_security(token,now);}
    return -1000;
}
fn mc_observe(token,result) {
    nb_zero(mc_observed,432);store64(mc_observed,result);store64(mc_observed+8,sm_now);store64(mc_observed+16,sm_active);store64(mc_observed+24,sm_token_floor);
    let i=0;while i<224 {store8(mc_snapshot+i,165);i=i+1;}let r=sm_snapshot(token,mc_snapshot,224);store64(mc_observed+32,r);nb_copy(mc_observed+40,mc_snapshot,224);
    let p=sm_find(token);if p {store64(mc_observed+264,load64(p+168));nb_copy(mc_observed+272,p+320,72);}
    store64(mc_observed+344,sm_packet_connection);store64(mc_observed+352,sm_packet_generation);store64(mc_observed+360,sm_event_kind);store64(mc_observed+368,sm_event_connection);store64(mc_observed+376,sm_event_generation);store64(mc_observed+384,sm_event_status);store64(mc_observed+392,sm_packet_size);
    let clean=1;if p {clean=mc_value(p+512,1024,0);}store64(mc_observed+400,clean);store64(mc_observed+408,mc_free_clean);store64(mc_observed+416,mc_value(mc_memory,16,165) && mc_value(mc_memory+6416,16,165));return 0;
}
fn mc_run(data,size) {
    if size<16 || !mc_equal(data,"SMPPAIR1",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}
    mc_memory=alloc(6432);mc_snapshot=alloc(224);mc_observed=alloc(432);let at=16;let index=0;
    while index<count {mc_case=index+1;if at>size-16 {return 3;}let total=load64(data+at);let commands=load64(data+at+8);if total<16 || total>size-at || commands<1 || commands>65535 {return 4;}let end=at+total;at=at+16;if mc_boot() {return 5;}let j=0;
        while j<commands {mc_step=j+1;if at>end-64 {return 6;}let cmd=data+at;let n=load64(cmd+40);if n<0 || n>end-at-64-432 {return 7;}let payload=cmd+64;let expected=payload+n;let result=mc_command(cmd,payload);mc_observe(load64(cmd+8),result);
            if !mc_check(mc_equal(mc_observed,expected,432)) {let byte=0;while byte<432 && load8(mc_observed+byte)==load8(expected+byte) {byte=byte+1;}mc_difference(byte,load8(mc_observed+byte),load8(expected+byte));return 8;}at=at+64+n+432;j=j+1;}
        if at!=end || !mc_check(mc_free_wiped()) {return 9;}index=index+1;
    }if at!=size {return 10;}return 0;
}
