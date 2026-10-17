global ct_checks=0;
global ct_status=0;
global ct_case=0;
global ct_media=0;
global ct_anchor=0;
global ct_media_ops=0;
global ct_advances=0;
global ct_loads=0;
global ct_peer_error=0;
global ct_operations=7;
fn pc_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn pc_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn ct_check(ok,code) {ct_checks=ct_checks+1;if !ok && !ct_status {ct_status=code;ct_diagnostic(ct_case,code);}return 0;}
// Independent NOR peer:sector erase;program can only clear bits;read copies
// actual persistent bytes. The anchor is an explicit trusted-boundary test peer.
fn ct_nor(kind,offset,buffer,n) {
    if offset<0 || n<1 || offset>8192-n {ct_peer_error=1;return -22;}
    if kind==1 {if offset&4095 || n!=4096 {ct_peer_error=2;return -22;}pc_fill(ct_media+offset,n,255);return n;}
    if kind==2 {let i=0;while i<n {let old=load8(ct_media+offset+i);let value=load8(buffer+i);if (old&value)!=value {ct_peer_error=3;return -5;}store8(ct_media+offset+i,old&value);i=i+1;}return n;}
    if kind==3 {nb_copy(buffer,ct_media+offset,n);return n;}ct_peer_error=4;return -22;
}
fn ct_empty_store() {
    pc_fill(kv_bank_buffer(0),8192,255);pc_fill(ct_media,8192,255);let r=kv_mount();if r!=-61 || kv_create() || kv_commit()!=1 {return -1;}
    let limit=0;while kv_next_io() {limit=limit+1;if limit>20 {return -2;}r=ct_nor(kv_io_kind,kv_io_offset,kv_io_buffer,kv_io_size);if kv_io_done(r)<0 {return -3;}}return kv_generation==1 && kv_active==0;
}
// Each fault scenario represents a separate boot. Test-only reset is followed
// by fresh owned workspaces. Production exposes no reset of a faulted owner.
fn ct_cold_reset() {
    sm_work=0;sm_active=0;sm_token_floor=0;sr_work=0;sr_floor=0;so_work=0;so_active=0;sd_work=0;sd_error=0;sd_busy=0;sd_revision_floor=0;sd_sequence_floor=0;
    cs_work=0;cs_state=0;cs_error=0;cs_clear_io();kv_work=0;kv_busy=0;ct_anchor=0;ct_media_ops=0;ct_advances=0;ct_loads=0;ct_peer_error=0;return 0;
}
fn ct_step(mode,now) {
    let kind=cs_next_io();if kind<=0 {return kind;}let token=cs_io_token;let offset=cs_io_offset;let p=cs_io_buffer;let n=cs_io_size;let scope=cs_io_scope;
    let expected_scope=0;if kind>=4 {expected_scope=cs_work+80;}ct_check(scope==expected_scope && (!scope || nb_equal(scope,"checkpoint-scope",16)) && cs_next_io()==kind && cs_io_token==token && cs_io_offset==offset && cs_io_buffer==p && cs_io_size==n && cs_io_scope==scope,100);
    ct_check(cs_io_done(token+1,0,0,now)==-116 && cs_io_token==token,101);
    let invalid_result=n;let invalid_value=1;if kind>=4 {invalid_result=1;invalid_value=0;}ct_check(cs_io_done(token,invalid_result,invalid_value,now)==-22 && cs_io_token==token,102);
    let wanted_packet=-11;if sd_durable>=2 {wanted_packet=7;}ct_check(cs_start(now)==-16 && cs_deinit()==-16 && sd_busy && sd_durable<cs_revision && sd_next_packet(1)==wanted_packet,103);
    if kind<=3 {
        ct_media_ops=ct_media_ops+1;let r=ct_nor(kind,offset,p,n);
        if mode>=1 && mode<=7 && ct_media_ops==mode {r=-5;}
        if mode==8 && ct_media_ops==3 {r=n-1;}
        if mode==9 && kind==3 && ct_media_ops==4 {store8(p+40,load8(p+40)^1);}
        if mode==10 && ct_media_ops==7 {let old=kv_get("smp.retry",9);if old {return -99;}store8(kv_value+kv_value_size-1,load8(kv_value+kv_value_size-1)^1);}
        if mode==11 && ct_media_ops==7 {pc_before(7,1);}
        return cs_io_done(token,r,0,now);
    }
    if kind==4 {
        ct_loads=ct_loads+1;let r=0;let v=ct_anchor;if mode==12 && ct_loads==1 {r=-5;}if mode==13 && ct_loads==1 {v=7;}if mode==16 && ct_loads==2 {r=-5;}if mode==17 && ct_loads==2 {v=0;}
        return cs_io_done(token,r,v,now);
    }
    ct_check(kind==5 && cs_state==3 && ct_media_ops==ct_operations*cs_sequence && kv_verified==32+kv_used && kv_generation==cs_sequence+1 && ct_anchor==cs_sequence-1,104);
    ct_check(cs_io_expected==ct_anchor && cs_io_desired==ct_anchor+1 && sd_busy && sd_durable<cs_revision && sd_next_packet(1)==wanted_packet,105);
    ct_advances=ct_advances+1;if ct_anchor!=cs_io_expected {return cs_io_done(token,-116,ct_anchor,now);}ct_anchor=cs_io_desired;
    if mode==14 {return cs_io_done(token,-5,ct_anchor,now);}if mode==15 {return cs_io_done(token,0,0,now);}return cs_io_done(token,0,ct_anchor,now);
}
fn ct_scenario(mode) {
    ct_case=mode;ct_cold_reset();let entries=4;let links=2;ct_operations=7;if mode==21 {entries=32;links=4;ct_operations=11;}let ps=sm_size(links);let rs=sr_size(entries);let os=so_size(links);let gs=sd_size(entries);let csize=cs_size(entries);let previous_floor=cs_floor;
    let pm=ct_allocate(ps+16);let rm=ct_allocate(rs+16);let om=ct_allocate(os+16);let gm=ct_allocate(gs+16);let cm=ct_allocate(csize+16);let km=ct_allocate(8472);let mm=ct_allocate(8208);let data=ct_allocate(32);
    if !pm || !rm || !om || !gm || !cm || !km || !mm || !data {return 1;}pc_fill(pm,ps+16,165);pc_fill(rm,rs+16,165);pc_fill(om,os+16,165);pc_fill(gm,gs+16,165);pc_fill(cm,csize+16,165);pc_fill(km,8472,165);pc_fill(mm,8208,165);nb_zero(data,32);ct_media=mm+8;
    let local=data;let peer=data+8;let id=data+16;let config=data+24;store8(local+1,1);store8(peer+1,2);store8(id+1,1);store8(config,1);store8(config+2,13);store8(config+3,16);store8(config+4,7);store8(config+5,7);store8(config+6,7);
    if sm_init(pm+8,ps,links) || sr_init(rm+8,rs,entries,1000,7000,60000,0) || so_init(om+8,os) || sd_init(gm+8,gs,0) || kv_init(km+8,8456,4096) || ct_empty_store()!=1 {return 2;}
    pc_before(7,0);ct_check(cs_size(0)==-22 && cs_size(33)==-22 && cs_size(4)==800 && cs_size(32)==3040,3);
    ct_check(cs_init(cm+8,csize-1,"0123456789abcdef","checkpoint-scope")==-22 && pc_value(cm,csize+16,165),4);
    ct_check(cs_init(km+8,8456,"0123456789abcdef","checkpoint-scope")==-22 && !cs_work,5);
    ct_check(cs_init(cm+8,csize,cm+64,"checkpoint-scope")==-22 && pc_value(cm,csize+16,165),6);
    ct_check(cs_init(cm+8,csize,"0123456789abcdef","checkpoint-scope")==0 && nb_equal(cm+72,"0123456789abcdef",16) && cs_floor==previous_floor,7);
    ct_check(sd_open(1,0,local,peer,id,config,0)==0 && sd_pair(1,0)==0 && sd_revision==2,8);
    if mode==18 {pc_before(7,1);ct_check(cs_start(0)==-32 && !ct_media_ops && kv_generation==1 && !kv_dirty && !cs_state && sd_error==-32 && !sd_busy,9);}else {
        ct_check(cs_start(0)==1 && cs_state==1 && sd_busy && cs_sequence==1 && cs_revision==2,10);
        if mode==20 {store8(id+1,2);ct_check(sd_open(2,0,local,peer,id,config,0)==0 && sd_pair(2,0)==0 && sd_revision==3 && sd_next_packet(2)==-11,23);}
        ct_check(cs_io_done(cs_floor,0,0,0)==-116 && sd_next_packet(1)==-11,11);
        if mode==22 {ct_check(cs_next_io()==4 && cs_io_done(cs_io_token,0,0,10)==1,27);ct_loads=1;ct_check(cs_next_io()==1,28);let token=cs_io_token;ct_check(cs_io_done(token,4096,0,9)==-22 && cs_io_token==token && kv_phase==1,29);if ct_status {return ct_status;}}
        let r=1;let limit=0;while r>0 && limit<30 {limit=limit+1;let now=0;if mode==22 {now=10;}if mode==19 && cs_state==4 {now=30000;}r=ct_step(mode,now);if ct_status {return ct_status;}}
        if mode==0 || mode>=19 {
            ct_check(r==0 && !cs_error && !cs_state && !cs_io_token && ct_anchor==1 && ct_advances==1 && ct_loads==2 && ct_media_ops==ct_operations,12);
            ct_check(!sd_busy && sd_sequence==1 && sd_durable==2 && pc_value(cs_frame(),csize-128,0),13);
            if mode==19 {ct_check(sd_next_packet(1)==-110 && sd_revision==3 && sd_durable==2,15);}else {ct_check(sd_next_packet(1)==7,14);}
            if mode==20 {
                ct_check(sd_next_packet(2)==-11 && cs_start(0)==1 && cs_sequence==2 && cs_revision==3,24);r=1;limit=0;
                while r>0 && limit<30 {limit=limit+1;r=ct_step(mode,0);if ct_status {return ct_status;}}
                ct_check(r==0 && sd_next_packet(1)==7 && sd_next_packet(2)==7 && sd_durable==3 && ct_anchor==2 && ct_advances==2 && ct_loads==4 && ct_media_ops==14,25);
            }
            if mode!=19 {let now=0;if mode==22 {now=10;}ct_check(cs_start(now)==0,26);}ct_check(cs_deinit()==0 && pc_value(cm+8,csize,0),16);
        }else {
            let error=-5;if mode==10 {error=-74;}if mode==11 {error=-32;}if mode==13 || mode==15 || mode==17 {error=-116;}
            ct_check(r==error && cs_error==error && sd_error==error && !sd_busy && !sd_durable && !cs_io_token && !cs_state && !kv_busy,17);
            ct_check(cs_next_io()==error && cs_start(0)==error && cs_deinit()==error && sd_next_packet(1)==error && pc_value(cs_frame(),csize-128,0),18);
            let wanted=0;if mode>=14 {wanted=1;}ct_check(ct_advances==wanted && ct_anchor==wanted,19);
        }
    }
    ct_check(!ct_peer_error && pc_backend_clean() && pc_ps_clean(),20);
    ct_check(pc_value(pm,8,165) && pc_value(pm+ps+8,8,165) && pc_value(rm,8,165) && pc_value(rm+rs+8,8,165) && pc_value(om,8,165) && pc_value(om+os+8,8,165) && pc_value(gm,8,165) && pc_value(gm+gs+8,8,165) && pc_value(cm,8,165) && pc_value(cm+csize+8,8,165) && pc_value(km,8,165) && pc_value(km+8464,8,165) && pc_value(mm,8,165) && pc_value(mm+8200,8,165),21);
    // Faults have no in-flight provider;discard this simulated host lifetime.
    ct_cold_reset();ct_release(data);ct_release(mm);ct_release(km);ct_release(cm);ct_release(gm);ct_release(om);ct_release(rm);ct_release(pm);ct_check(ct_arena_clean(),22);return ct_status;
}
fn ct_run() {let mode=0;while mode<23 {let r=ct_scenario(mode);if r {return r;}mode=mode+1;}return ct_status;}
