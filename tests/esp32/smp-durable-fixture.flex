// Frozen observations compare real owner/ledger/barrier calls with the peer.
// Commands20/21/22 are explicit generation/floor/secret fault injection only.
global dc_pair=0;
global dc_retry=0;
global dc_owner=0;
global dc_gate=0;
global dc_observed=0;
global dc_checks=0;
global dc_case=0;
global dc_step=0;
global dc_payload=0;
global dc_payload_size=0;
fn dc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn dc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn dc_boot() {
    sd_work=0;sd_entries=0;sd_owner=0;sd_ledger=0;sd_revision=0;sd_revision_floor=0;sd_durable=0;sd_sequence=0;sd_sequence_floor=0;sd_seen_floor=0;sd_busy=0;sd_frozen_revision=0;sd_frozen_sequence=0;sd_error=0;sd_views();
    so_work=0;so_links=0;so_active=0;so_now=0;so_sm_work=0;so_sr_work=0;so_sr_entries=0;so_fault=0;
    sm_work=0;sm_links=0;sm_active=0;sm_token_floor=0;sm_now=0;sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;
    sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=0;
    dc_fill(dc_pair,3344,165);dc_fill(dc_retry,400,165);dc_fill(dc_owner,208,165);dc_fill(dc_gate,592,165);let r=sm_init(dc_pair+8,3328,2);if r {return r;}r=sr_init(dc_retry+8,384,4,1000,7000,60000,0);if r {return r;}r=so_init(dc_owner+8,192);if r {return r;}return sd_init(dc_gate+8,576,0);
}
fn dc_command(cmd,data) {
    let op=load64(cmd);let token=load64(cmd+8);let a=load64(cmd+16);let b=load64(cmd+24);let now=load64(cmd+32);let n=load64(cmd+40);let c=load64(cmd+48);let d=load64(cmd+56);dc_payload=data;dc_payload_size=n;
    if op==1 {if n!=29 {return -22;}return sd_open(token,a,data,data+7,data+22,data+14,now);}if op==2 {return sd_pair(token,now);}if op==18 {return sd_request_security(token,now);}if op==3 {return sd_input(token,data,n,now);}if op==4 {return sd_tick(now);}
    if op==5 {return sd_next_packet(token);}if op==6 {return sd_packet_sent(token,a,now);}if op==7 {return sd_next_event(token);}if op==8 {return sd_event_consumed(token,a,b);}if op==9 {return sd_consent(token,a,b,now);}if op==10 {return sd_close(token,now);}
    if op==11 {return sd_checkpoint(now);}if op==12 {return sd_checkpoint_peek();}if op==13 {return sd_done(a,b,c,now);}if op==14 {return sd_deinit();}if op==15 {return sd_init(dc_gate+8+b,a,c);}if op==16 {return sd_phase2(token,a,b,now);}if op==17 {return sd_failure(token,a,b,c,d,now);}
    if op==19 {if n!=14 {return -22;}return sd_inherit(data,data+7,now);}if op==20 {sd_revision_floor=a;return 0;}if op==21 {sr_floor=a;return 0;}if op==22 {let p=sm_find(token);if !p {return -107;}dc_fill(p+512,1024,a);return 0;}
    if op==24 {if n!=7 {return -22;}let p=sr_find(data);if !p {return -107;}store64(p+32,a);return 0;}
    if op==23 {if a==0 {return sd_snapshot(token,dc_observed,271);}if a==1 {return sd_snapshot(token,sd_work,272);}if a==2 {return sd_input(token,sd_work,7,now);}if a==3 {return sd_open(token+1,0,sd_work,sd_work,sd_work,sd_work,now);}if a==4 {return sd_inherit(sd_work,sd_work,now);}return sd_input(token,0,1,now);}
    return -1000;
}
fn dc_guards() {return dc_value(dc_pair,8,165) && dc_value(dc_pair+3336,8,165) && dc_value(dc_retry,8,165) && dc_value(dc_retry+392,8,165) && dc_value(dc_owner,8,165) && dc_value(dc_owner+200,8,165) && dc_value(dc_gate,8,165) && dc_value(dc_gate+584,8,165);}
fn dc_headers() {if !dc_value(dc_pair+8,256,0) || !dc_value(dc_retry+8,128,0) || !dc_value(dc_owner+8,64,0) {return 0;}let i=0;while i<2 {let p=sm_slot(i);if !load64(p) && !dc_value(p,1536,0) {return 0;}i=i+1;}return 1;}
fn dc_observe(token,result) {
    nb_zero(dc_observed,1216);dc_fill(dc_observed+648,272,165);let status=sd_snapshot(token,dc_observed+648,272);
    store64(dc_observed,result);store64(dc_observed+8,sd_work!=0);store64(dc_observed+16,sd_revision);store64(dc_observed+24,sd_revision_floor);store64(dc_observed+32,sd_durable);store64(dc_observed+40,sd_sequence);store64(dc_observed+48,sd_sequence_floor);store64(dc_observed+56,sd_busy);store64(dc_observed+64,sd_frozen_revision);store64(dc_observed+72,sd_frozen_sequence);store64(dc_observed+80,sd_error);store64(dc_observed+88,sd_checkpoint_buffer!=0);store64(dc_observed+96,sd_checkpoint_bytes);store64(dc_observed+104,sd_checkpoint_revision);store64(dc_observed+112,sd_checkpoint_sequence);store64(dc_observed+120,sd_seen_floor);
    nb_copy(dc_observed+128,dc_gate+8+352,224);nb_copy(dc_observed+352,dc_gate+8+320,32);nb_copy(dc_observed+384,dc_retry+8+128,256);store64(dc_observed+640,status);let p=sm_find(token);if p {store64(dc_observed+920,load64(p+168));nb_copy(dc_observed+928,p+320,72);}
    store64(dc_observed+1000,sm_packet_connection);store64(dc_observed+1008,sm_packet_generation);store64(dc_observed+1016,sm_packet_size);store64(dc_observed+1024,sm_event_kind);store64(dc_observed+1032,sm_event_connection);store64(dc_observed+1040,sm_event_generation);store64(dc_observed+1048,sm_event_status);store64(dc_observed+1056,sr_now);store64(dc_observed+1064,sr_floor);store64(dc_observed+1072,so_now);store64(dc_observed+1080,sm_now);store64(dc_observed+1088,so_active);
    let i=0;while i<2 {nb_copy(dc_observed+1096+i*32,dc_owner+8+64+i*64,32);i=i+1;}store64(dc_observed+1160,dc_guards());store64(dc_observed+1168,dc_headers());let clean=dc_value(dc_gate+8,64,0);if !sd_work {clean=dc_value(dc_gate+8,576,0);}store64(dc_observed+1176,clean);let sum=0;i=0;while i<dc_payload_size {sum=sum+(i+1)*load8(dc_payload+i);i=i+1;}store64(dc_observed+1184,sum);clean=1;if p {clean=dc_value(p+512,1024,0);}store64(dc_observed+1192,clean);store64(dc_observed+1200,so_fault);return 0;
}
fn dc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPDURA1",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}dc_pair=alloc(3344);dc_retry=alloc(400);dc_owner=alloc(208);dc_gate=alloc(592);dc_observed=alloc(1216);let at=16;let index=0;
    while index<count {dc_case=index+1;if dc_boot() {return 3;}if at>size-16 {return 4;}let total=load64(data+at);let commands=load64(data+at+8);if total<16 || total>size-at || commands<1 || commands>65535 {return 5;}let end=at+total;at=at+16;let j=0;
        while j<commands {dc_step=j+1;if at>end-64 {return 6;}let cmd=data+at;let n=load64(cmd+40);if n<0 || n>end-at-64-1216 {return 7;}let payload=cmd+64;let expected=payload+n;let result=dc_command(cmd,payload);dc_observe(load64(cmd+8),result);dc_checks=dc_checks+1;
            if !nb_equal(dc_observed,expected,1216) {let byte=0;while byte<1216 && load8(dc_observed+byte)==load8(expected+byte) {byte=byte+1;}dc_report(dc_case,dc_step,byte,load8(dc_observed+byte),load8(expected+byte));return 8;}at=at+64+n+1216;j=j+1;}
        if at!=end {return 9;}index=index+1;
    }if at!=size {return 10;}return 0;
}
