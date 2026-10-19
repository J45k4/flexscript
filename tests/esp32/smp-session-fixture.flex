// Actual calls/byte observations compared with composed independent peers.
// Only commands15/16/19 deliberately inject epoch/secret/ledger corruption.
global oc_pair=0;
global oc_retry=0;
global oc_owner=0;
global oc_observed=0;
global oc_checks=0;
global oc_case=0;
global oc_step=0;
fn oc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn oc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn oc_boot() {
    // Independent cases start cold. Reinit inside a case uses public ownership
    // APIs and must retain both connection and attempt-generation floors.
    so_work=0;so_links=0;so_active=0;so_now=0;so_sm_work=0;so_sr_work=0;so_sr_entries=0;so_fault=0;
    sm_work=0;sm_links=0;sm_active=0;sm_token_floor=0;sm_now=0;sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;
    sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=0;
    oc_fill(oc_pair,6416,165);oc_fill(oc_retry,400,165);oc_fill(oc_owner,336,165);
    let r=sm_init(oc_pair+8,6400,4);if r {return r;}r=sr_init(oc_retry+8,384,4,1000,7000,60000,0);if r {return r;}return so_init(oc_owner+8,320);
}
fn oc_command(cmd,data) {
    let op=load64(cmd);let token=load64(cmd+8);let a=load64(cmd+16);let b=load64(cmd+24);let now=load64(cmd+32);let size=load64(cmd+40);let c=load64(cmd+48);let d=load64(cmd+56);
    if op==1 {if size!=29 {return -22;}return so_open(token,a,data,data+7,data+22,data+14,now);}
    if op==2 {return so_pair(token,now);}if op==18 {return so_request_security(token,now);}if op==3 {return so_input(token,data,size,now);}if op==4 {return so_tick(now);}
    if op==5 {return so_next_packet(token);}if op==6 {return so_packet_sent(token,a,now);}if op==7 {return so_next_event(token);}if op==8 {return so_event_consumed(token,a,b);}if op==9 {return so_consent(token,a,b,now);}
    if op==10 {return so_close(token,now);}if op==11 {return so_deinit();}if op==12 {return so_init(oc_owner+8+b,a);}if op==13 {return so_phase2(token,a,b,now);}if op==14 {return so_failure(token,a,b,c,d,now);}
    if op==15 {let p=sm_find(token);if !p {return -107;}store64(p+192,a);return 0;}
    if op==16 {let p=sm_find(token);if !p {return -107;}oc_fill(p+512,1024,a);return 0;}
    if op==17 {if size!=7 {return -22;}return sr_wait(data,now);}
    if op==19 {if size!=7 {return -22;}let p=sr_find(data);if !p {return -107;}store64(p+32,a);return 0;}
    if op==20 {if a==0 {return so_snapshot(token,oc_observed,255);}if a==1 {return so_snapshot(token,0,256);}if a==2 {return so_snapshot(token,so_work,256);}if a==3 {return so_snapshot(token,sr_work,256);}return so_snapshot(token,sm_work,256);}
    if op==21 {if size!=29 {return -22;}let local=data;let peer=data+7;let identity=data+22;let config=data+14;if a==0 {local=sm_work;}if a==1 {peer=sr_work;}if a==2 {identity=so_work;}if a==3 {config=sm_work;}return so_open(token,1,local,peer,identity,config,now);}
    if op==22 {let input=so_work;if a==1 {input=sm_work;}if a==2 {input=sr_work;}return so_input(token,input,1,now);}
    return -1000;
}
fn oc_headers() {if !oc_value(oc_pair+8,256,0) || !oc_value(oc_retry+8,128,0) || !oc_value(oc_owner+8,64,0) {return 0;}let i=0;while i<4 {if !oc_value(oc_owner+8+64+i*64+32,32,0) {return 0;}let p=oc_pair+8+256+i*1536;if !load64(p) && !oc_value(p,1536,0) {return 0;}i=i+1;}return 1;}
fn oc_observe(token,result) {
    nb_zero(oc_observed,896);oc_fill(oc_observed+96,256,165);let status=so_snapshot(token,oc_observed+96,256);
    store64(oc_observed,result);store64(oc_observed+8,so_work!=0);store64(oc_observed+16,so_active);store64(oc_observed+24,so_links);store64(oc_observed+32,so_now);store64(oc_observed+40,so_fault);store64(oc_observed+48,sm_now);store64(oc_observed+56,sm_active);store64(oc_observed+64,sm_token_floor);store64(oc_observed+72,sr_now);store64(oc_observed+80,sr_floor);store64(oc_observed+88,status);
    let p=sm_find(token);if p {store64(oc_observed+352,load64(p+168));nb_copy(oc_observed+360,p+320,72);}store64(oc_observed+432,sm_packet_connection);store64(oc_observed+440,sm_packet_generation);store64(oc_observed+448,sm_packet_size);store64(oc_observed+456,sm_event_kind);store64(oc_observed+464,sm_event_connection);store64(oc_observed+472,sm_event_generation);store64(oc_observed+480,sm_event_status);
    nb_copy(oc_observed+488,oc_retry+8+128,256);let i=0;while i<4 {nb_copy(oc_observed+744+i*32,oc_owner+8+64+i*64,32);i=i+1;}
    let clean=1;if p {clean=oc_value(p+512,1024,0);}store64(oc_observed+872,clean);store64(oc_observed+880,oc_headers());store64(oc_observed+888,oc_value(oc_pair,8,165) && oc_value(oc_pair+6408,8,165) && oc_value(oc_retry,8,165) && oc_value(oc_retry+392,8,165) && oc_value(oc_owner,8,165) && oc_value(oc_owner+328,8,165));return 0;
}
fn oc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPOWNR1",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}oc_pair=alloc(6416);oc_retry=alloc(400);oc_owner=alloc(336);oc_observed=alloc(896);let index=0;let at=16;
    while index<count {oc_case=index+1;if oc_boot() {return 3;}if at>size-16 {return 4;}let total=load64(data+at);let commands=load64(data+at+8);if total<16 || total>size-at || commands<1 || commands>65535 {return 5;}let end=at+total;at=at+16;let j=0;
        while j<commands {oc_step=j+1;if at>end-64 {return 6;}let cmd=data+at;let n=load64(cmd+40);if n<0 || n>end-at-64-896 {return 7;}let payload=cmd+64;let expected=payload+n;let result=oc_command(cmd,payload);oc_observe(load64(cmd+8),result);oc_checks=oc_checks+1;
            if !nb_equal(oc_observed,expected,896) {let byte=0;while byte<896 && load8(oc_observed+byte)==load8(expected+byte) {byte=byte+1;}oc_report(oc_case,oc_step,byte,load8(oc_observed+byte),load8(expected+byte));return 8;}at=at+64+n+896;j=j+1;}
        if at!=end {return 9;}index=index+1;
    }if at!=size {return 10;}return 0;
}
