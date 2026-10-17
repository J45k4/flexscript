global pc_checks=0;
global pc_case=0;
fn pc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn pc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn br_expect(ok,field,actual,expected) {pc_checks=pc_checks+1;if !ok {pc_report(pc_case,0,field,actual,expected);return 1;}return 0;}
fn br_cold(floor) {sr_work=0;sr_floor=floor;sm_work=0;sm_active=0;so_work=0;sd_work=0;cs_work=0;kv_work=0;kv_busy=0;cr_work=0;cr_error=0;cr_state=0;cr_clear_io();return 0;}
fn br_case(row) {
    let mode=load64(row);let entries=load64(row+16);let initial_floor=load64(row+32);let status=load64(row+40);let expected=row+8368;let bytes=sr_size(entries);let ws=cr_size(entries);let rm=br_allocate(bytes+16);let km=br_allocate(8472);let wm=br_allocate(ws+16);if !rm || !km || !wm {return 7;}
    br_cold(initial_floor);pc_fill(rm,bytes+16,165);pc_fill(km,8472,165);pc_fill(wm,ws+16,165);if sr_init(rm+8,bytes,entries,1000,7000,60000,0) || kv_init(km+8,8456,4096) {return 7;}nb_copy(km+8,row+176,8192);let key=row+144;let scope=key+16;let floor=cr_floor;
    if br_expect(cr_size(0)==-22 && cr_size(33)==-22 && cr_size(1)==512 && cr_size(32)==2992,1,0,1) {return 8;}
    if br_expect(cr_init(wm+8,ws-1,key,scope)==-22 && pc_value(wm,ws+16,165),2,0,1) {return 8;}
    if br_expect(cr_init(km+8,8456,key,scope)==-22 && !cr_work,3,0,1) {return 8;}
    if br_expect(cr_init(wm+8,ws,wm+64,scope)==-22 && pc_value(wm,ws+16,165),4,0,1) {return 8;}
    if br_expect(cr_init(wm+8,ws,key,scope)==0 && cr_floor==floor,5,0,1) {return 8;}
    if br_expect(cr_deinit()==0 && pc_value(wm+8,ws,0),26,0,1) {return 8;}pc_fill(wm+8,ws,165);if br_expect(cr_init(wm+8,ws,key,scope)==0 && cr_floor==floor,27,0,1) {return 8;}
    if br_expect(cr_next_io()==0 && cr_start(0)==1,6,0,1) {return 8;}pc_before(pc_case&15,load64(row+8));
    let anchor=load64(row+24);let loads=0;let advances=0;let result=1;let loops=0;
    while result>0 && loops<5 {
        let kind=cr_next_io();let token=cr_io_token;let now=(loops+1)*10;loops=loops+1;
        if br_expect((kind==4 || kind==5) && token>floor && nb_equal(cr_io_scope,scope,16),7,kind,4) {return 8;}
        if br_expect(cr_next_io()==kind && cr_io_token==token && nb_equal(cr_io_scope,scope,16),8,0,1) {return 8;}
        if br_expect(cr_io_done(token+1,0,0,now)==-116 && cr_io_token==token,9,0,1) {return 8;}
        if br_expect(cr_io_done(token,1,0,now)==-22 && cr_io_token==token && cr_deinit()==-16,10,0,1) {return 8;}
        if br_expect(pc_value(sr_work,bytes,0) && sr_now==0 && sr_floor==initial_floor && !so_work && !sd_work && !cs_work,11,sr_floor,initial_floor) {return 8;}
        if mode==9 && loops==2 {if br_expect(cr_io_done(token,0,anchor,9)==-22 && cr_io_token==token,12,0,1) {return 8;}}
        let r=0;let value=anchor;
        if kind==4 {loads=loads+1;if loads==1 {if mode==1 {r=-5;}if mode==2 {value=-1;}if mode==3 {value=9223372036854775807;}}else {if mode==7 {r=-5;}if mode==8 {value=anchor-1;}}}
        else {
            if br_expect(cr_io_expected==anchor && cr_io_desired==anchor+1,13,cr_io_expected,anchor) {return 8;}
            advances=advances+1;if mode==4 {r=-5;}else {anchor=cr_io_desired;value=anchor;if mode==5 {r=-5;}if mode==6 {value=anchor-1;}}
        }
        if cr_state==3 {if mode==10 {so_work=8;}if mode==11 {kv_generation=kv_generation+1;}if mode==14 {pc_fill(cr_payload(),64+40*entries,90);}}
        result=cr_io_done(token,r,value,now);if mode==10 {so_work=0;}
        if br_expect(pc_backend_clean() && pc_ps_clean(),14,0,1) {return 8;}
    }
    if br_expect(result==status,15,result,status) {return 8;}
    if br_expect(anchor==load64(row+64) && loads==load64(row+72) && advances==load64(row+80),16,anchor,load64(row+64)) {return 8;}
    if br_expect(pc_calls()==load64(row+104),17,pc_calls(),load64(row+104)) {return 8;}
    if br_expect(sr_now==load64(row+88) && sr_floor==load64(row+96),18,sr_now,load64(row+88)) {return 8;}
    if !nb_equal(sr_work,expected,bytes) {let i=0;while i<bytes && load8(sr_work+i)==load8(expected+i) {i=i+1;}pc_report(pc_case,0,1000+i,load8(sr_work+i),load8(expected+i));return 8;}pc_checks=pc_checks+1;
    if status==0 {
        if br_expect(cr_state==4 && cr_sequence==load64(row+48) && cr_revision==load64(row+56) && !cr_error && !cr_io_token && cr_next_io()==0 && pc_value(wm+8,ws,0),19,cr_sequence,load64(row+48)) {return 8;}
        if br_expect(cr_io_done(cr_floor,0,anchor,50)==-116 && cr_deinit()==0 && pc_value(wm+8,ws,0),20,0,1) {return 8;}
    }else {
        if br_expect(cr_error==status && !cr_state && !cr_sequence && !cr_revision && !cr_io_token && pc_value(wm+8,ws,0),21,cr_error,status) {return 8;}
        if br_expect(cr_next_io()==status && cr_start(50)==status && cr_deinit()==status,22,0,1) {return 8;}
    }
    if br_expect(pc_value(rm,8,165) && pc_value(rm+bytes+8,8,165) && pc_value(km,8,165) && pc_value(km+8464,8,165) && pc_value(wm,8,165) && pc_value(wm+ws+8,8,165),23,0,1) {return 8;}
    let sum=0;let i=0;while i<8224 {sum=sum+(i+1)*load8(row+144+i);i=i+1;}if br_expect(sum==load64(row+120),24,sum,load64(row+120)) {return 8;}
    br_cold(0);br_release(wm);br_release(km);br_release(rm);if br_expect(br_arena_clean(),25,0,1) {return 8;}return 0;
}
fn pc_run(data,size) {
    if size<16 || !nb_equal(data,"SMPREC01",8) {return 1;}let count=load64(data+8);if count<1 || count>65535 {return 2;}let at=16;let i=0;
    while i<count {if at>size-144 {return 3;}let row=data+at;let entries=load64(row+16);let bytes=sr_size(entries);if bytes<0 || load64(row+112)!=bytes || load64(row+128)!=8192 || at>size-8368-bytes {return 4;}pc_case=load64(row+136)+1;let r=br_case(row);if r {return r;}at=at+8368+bytes;i=i+1;}if at!=size {return 5;}return 0;
}
