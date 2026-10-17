// Independent binary peer observations; test-only command7 simulates cold
// power loss, command9 forces generation exhaustion, command11 corrupts storage.
global rc_memory=0;
global rc_codec=0;
global rc_observed=0;
global rc_checks=0;
global rc_case=0;
global rc_step=0;
fn rc_fill(p,size,value) {let i=0;while i<size {store8(p+i,value);i=i+1;}return 0;}
fn rc_same(p,size,value) {let i=0;while i<size {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn rc_cold(floor) {sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=floor;rc_fill(rc_memory,416,165);return 0;}
fn rc_command(cmd,data) {
    let op=load64(cmd);let a=load64(cmd+8);let b=load64(cmd+16);let c=load64(cmd+24);let d=load64(cmd+32);let now=load64(cmd+40);let size=load64(cmd+48);
    if op==1 {return sr_init(rc_memory+16,384,a,b,c,d,now);}
    if op==7 {let floor=0;if size==4 && nb_equal(data,"keep",4) {floor=sr_floor;}rc_cold(floor);return sr_init(rc_memory+16,384,a,b,c,d,now);}
    if op==9 {sr_floor=a;return 0;}if op==11 {if a<0 || a>=224 {return -1000;}store8(rc_codec+16+a,b);return 0;}
    if op==2 || op==3 {if size!=7 {return -22;}if op==2 {return sr_wait(data,now);}return sr_begin(data,now);}
    if op==4 {return sr_finish(a,b,now);}if op==5 {return sr_export(rc_codec+16,a,now);}
    if op==6 {let input=rc_codec+16;if size {input=data;}return sr_import(input,a,now);}
    if op==8 {return sr_deinit(now);}
    if op==13 {if size!=14 {return -22;}return sr_inherit(data,data+7,now);}
    if op==10 {if a==0 {return sr_wait(sr_work,now);}if a==1 {return sr_begin(sr_work,now);}if a==2 {return sr_export(sr_work,224,now);}if a==3 {return sr_import(sr_work,224,now);}if a==4 {return sr_wait(0,now);}return sr_begin(0,now);}
    return -1000;
}
fn rc_observe(result) {
    nb_zero(rc_observed,688);store64(rc_observed,result);store64(rc_observed+8,sr_work!=0);store64(rc_observed+16,sr_entries);store64(rc_observed+24,sr_min);store64(rc_observed+32,sr_max);store64(rc_observed+40,sr_decay);store64(rc_observed+48,sr_now);store64(rc_observed+56,sr_floor);
    nb_copy(rc_observed+72,rc_memory+16,384);nb_copy(rc_observed+456,rc_codec+16,224);store64(rc_observed+680,rc_same(rc_memory,16,165) && rc_same(rc_memory+400,16,165) && rc_same(rc_codec,16,165) && rc_same(rc_codec+240,16,165));return 0;
}
fn rc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPRETR1",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}rc_memory=alloc(416);rc_codec=alloc(256);rc_observed=alloc(688);let index=0;let at=16;
    while index<count {rc_case=index+1;rc_cold(0);rc_fill(rc_codec,256,165);if at>size-16 {return 3;}let total=load64(data+at);let commands=load64(data+at+8);if total<16 || total>size-at || commands<1 || commands>65535 {return 4;}let end=at+total;at=at+16;let j=0;
        while j<commands {rc_step=j+1;if at>end-64 {return 5;}let cmd=data+at;let n=load64(cmd+48);if n<0 || n>end-at-64-688 {return 6;}let payload=cmd+64;let expected=payload+n;let result=rc_command(cmd,payload);rc_observe(result);rc_checks=rc_checks+1;
            if !nb_equal(rc_observed,expected,688) {let byte=0;while byte<688 && load8(rc_observed+byte)==load8(expected+byte) {byte=byte+1;}rc_report(rc_case,rc_step,byte,load8(rc_observed+byte),load8(expected+byte));return 8;}at=at+64+n+688;j=j+1;}
        if at!=end {return 9;}index=index+1;
    }if at!=size {return 10;}return 0;
}
