// Execute real providers and compare protocol/crypto observations. No device I/O.
global pc_pair=0;
global pc_retry=0;
global pc_owner=0;
global pc_output=0;
global pc_work=0;
global pc_observed=0;
global pc_checks=0;
global pc_case=0;
global pc_step=0;
global pc_payload=0;
global pc_payload_size=0;
fn pc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn pc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn pc_boot() {
    so_work=0;so_links=0;so_active=0;so_now=0;so_sm_work=0;so_sr_work=0;so_sr_entries=0;so_fault=0;
    sm_work=0;sm_links=0;sm_active=0;sm_token_floor=0;sm_now=0;sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;
    sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=0;
    pc_fill(pc_pair,3344,165);pc_fill(pc_retry,400,165);pc_fill(pc_owner,208,165);let r=sm_init(pc_pair+8,3328,2);if r {return r;}r=sr_init(pc_retry+8,384,4,1000,7000,60000,0);if r {return r;}return so_init(pc_owner+8,192);
}
fn pc_command(cmd,data) {
    let op=load64(cmd);let token=load64(cmd+8);let a=load64(cmd+16);let b=load64(cmd+24);let now=load64(cmd+32);let n=load64(cmd+40);let fail=load64(cmd+48);let level=load64(cmd+56);pc_payload=data;pc_payload_size=n;
    pc_fill(pc_output,64,165);pc_fill(pc_work,672,165);pc_fill(pc_work+16,640,90);pc_before(level,fail);
    if op==1 {if n<7 {return -22;}let peer=data;let records=data+7;let out=pc_output+16;let work=pc_work+16;let cap=608;if b==1 {out=peer;}if b==2 {out=records;}if b==3 {work=peer;}if b==4 {cap=607;}if b==5 {out=0;}if b==6 {work=0;}if b==7 {records=0;}if b==8 {peer=0;}if b==9 {out=peer;records=data+71;}return sp_resolve(peer,records,a,out,work,cap);}
    if op==2 {if n<22 {return -22;}let local=data;let peer=data+7;let config=data+14;let records=data+22;let work=pc_work+16;let cap=640;let mode=b&255;if mode==1 {work=so_work;}if mode==2 {local=work;}if mode==3 {records=work;}if mode==4 {cap=639;}return sp_open(token,b>>8,local,peer,records,a,config,work,cap,now);}
    if op==3 {if n!=7 {return -22;}return sp_inherit_identity(data,a,now,pc_work+16,16);}if op==4 {if n!=7 {return -22;}return sr_wait(data,now);}
    if op==5 {return so_pair(token,now);}if op==6 {return so_input(token,data,n,now);}if op==7 {return so_close(token,now);}if op==8 {return so_tick(now);}if op==9 {return so_packet_sent(token,a,now);}if op==10 {return so_request_security(token,now);}if op==15 {return so_consent(token,a,b,now);}
    if op==16 {let p=sm_find(token);if !p {return -107;}pc_fill(p+512,1024,a);return 0;}return -1000;
}
fn pc_scratch() {let i=0;let used=0;while i<640 && load8(pc_work+16+i)==0 {used=used+1;i=i+1;}if used!=0 && used!=16 && used!=608 && used!=640 {return -1;}if !pc_value(pc_work+16+used,640-used,90) {return -1;}return used;}
fn pc_guards() {return pc_value(pc_pair,8,165) && pc_value(pc_pair+3336,8,165) && pc_value(pc_retry,8,165) && pc_value(pc_retry+392,8,165) && pc_value(pc_owner,8,165) && pc_value(pc_owner+200,8,165) && pc_value(pc_output,16,165) && pc_value(pc_output+48,16,165) && pc_value(pc_work,16,165) && pc_value(pc_work+656,16,165);}
fn pc_headers() {if !pc_value(pc_pair+8,256,0) || !pc_value(pc_retry+8,128,0) || !pc_value(pc_owner+8,64,0) {return 0;}let i=0;while i<2 {let p=sm_slot(i);if !load64(p) && !pc_value(p,1536,0) {return 0;}i=i+1;}return 1;}
fn pc_observe(token,result) {
    nb_zero(pc_observed,816);pc_fill(pc_observed+56,256,165);let status=so_snapshot(token,pc_observed+56,256);store64(pc_observed,result);store64(pc_observed+8,pc_calls());store64(pc_observed+16,pc_scratch());store64(pc_observed+24,pc_guards());store64(pc_observed+32,pc_backend_clean());store64(pc_observed+40,pc_ps_clean());store64(pc_observed+48,status);
    nb_copy(pc_observed+312,pc_output+16,32);store64(pc_observed+344,sr_now);store64(pc_observed+352,sr_floor);store64(pc_observed+360,so_now);store64(pc_observed+368,sm_now);store64(pc_observed+376,so_active);nb_copy(pc_observed+384,pc_retry+8+128,256);let i=0;while i<2 {nb_copy(pc_observed+640+i*32,pc_owner+8+64+i*64,32);i=i+1;}
    let p=sm_find(token);let clean=1;if p {store64(pc_observed+704,load64(p+168));nb_copy(pc_observed+712,p+320,72);clean=pc_value(p+512,1024,0);}store64(pc_observed+784,clean);store64(pc_observed+792,pc_headers());store64(pc_observed+800,so_fault);let sum=0;i=0;while i<pc_payload_size {sum=sum+(i+1)*load8(pc_payload+i);i=i+1;}store64(pc_observed+808,sum);return 0;
}
fn pc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPPRIV1",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}pc_pair=alloc(3344);pc_retry=alloc(400);pc_owner=alloc(208);pc_output=alloc(64);pc_work=alloc(672);pc_observed=alloc(816);let index=0;let at=16;
    while index<count {pc_case=index+1;if pc_boot() {return 3;}if at>size-16 {return 4;}let total=load64(data+at);let commands=load64(data+at+8);if total<16 || total>size-at || commands<1 || commands>65535 {return 5;}let end=at+total;at=at+16;let j=0;
        while j<commands {pc_step=j+1;if at>end-64 {return 6;}let cmd=data+at;let n=load64(cmd+40);if n<0 || n>end-at-64-816 {return 7;}let payload=cmd+64;let expected=payload+n;let result=pc_command(cmd,payload);pc_observe(load64(cmd+8),result);pc_checks=pc_checks+1;
            if !nb_equal(pc_observed,expected,816) {let byte=0;while byte<816 && load8(pc_observed+byte)==load8(expected+byte) {byte=byte+1;}pc_report(pc_case,pc_step,byte,load8(pc_observed+byte),load8(expected+byte));return 8;}at=at+64+n+816;j=j+1;}
        if at!=end {return 9;}index=index+1;
    }if at!=size {return 10;}return 0;
}
