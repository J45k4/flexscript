// Consumer of the actual commit and recovery owners,not generated bank images.
// Cold boots discard test-only RAM state and retain only NOR bytes/counter.
fn be_store_effect(kind) {
    if kind<=3 {return ct_nor(kind,cs_io_offset,cs_io_buffer,cs_io_size);}
    if kind==5 {ct_check(nb_equal(cs_io_scope,"checkpoint-scope",16) && cs_io_expected==ct_anchor && cs_io_desired==ct_anchor+1,200);ct_anchor=cs_io_desired;}return 0;
}
fn be_store_done(kind,result,now) {let value=0;if kind>=4 {value=ct_anchor;}return cs_io_done(cs_io_token,result,value,now);}
fn be_scenario(cut,delivered) {
    ct_case=cut*2+delivered;ct_cold_reset();cr_work=0;cr_error=0;cr_state=0;cr_clear_io();let pm=ct_allocate(3344);let rm=ct_allocate(400);let om=ct_allocate(208);let gm=ct_allocate(592);let cm=ct_allocate(816);let km=ct_allocate(8472);let mm=ct_allocate(8208);let data=ct_allocate(32);let rb=ct_allocate(400);let kb=ct_allocate(8472);let wb=ct_allocate(768);
    if !pm || !rm || !om || !gm || !cm || !km || !mm || !data || !rb || !kb || !wb {return 1;}pc_fill(pm,3344,165);pc_fill(rm,400,165);pc_fill(om,208,165);pc_fill(gm,592,165);pc_fill(cm,816,165);pc_fill(km,8472,165);pc_fill(mm,8208,165);pc_fill(rb,400,165);pc_fill(kb,8472,165);pc_fill(wb,768,165);nb_zero(data,32);ct_media=mm+8;
    let local=data;let peer=data+8;let id=data+16;let config=data+24;store8(local+1,1);store8(peer+1,2);store8(id+1,1);store8(config,1);store8(config+2,13);store8(config+3,16);store8(config+4,7);store8(config+5,7);store8(config+6,7);
    if sm_init(pm+8,3328,2) || sr_init(rm+8,384,4,1000,7000,60000,0) || so_init(om+8,192) || sd_init(gm+8,576,0) || kv_init(km+8,8456,4096) || ct_empty_store()!=1 {return 2;}
    pc_before(7,0);if cs_init(cm+8,800,"0123456789abcdef","checkpoint-scope") || cs_start(0)!=1 {return 3;}
    let r=1;let count=0;while r>0 && count<20 {let kind=cs_next_io();if kind<1 {return 4;}let result=be_store_effect(kind);r=be_store_done(kind,result,0);count=count+1;}ct_check(r==0 && count==10 && ct_anchor==1 && sd_durable==1 && !sr_floor,201);
    ct_check(sd_open(1,0,local,peer,id,config,1)==0 && sd_pair(1,1)==0 && cs_start(1)==1 && cs_sequence==2 && sd_next_packet(1)==-11,202);
    let step=0;while step<cut {let kind=cs_next_io();if kind<1 {return 5;}let result=be_store_effect(kind);step=step+1;if step<cut || delivered {r=be_store_done(kind,result,1);ct_check(r>=0,203);}ct_check(step==10 && delivered || sd_next_packet(1)==-11,204);}
    if cut==10 && delivered {ct_check(sd_next_packet(1)==7 && sd_durable==2,205);}else {ct_check(sd_next_packet(1)==-11 && sd_durable==1,206);}
    let persistent_anchor=ct_anchor;ct_cold_reset();ct_anchor=persistent_anchor;cr_work=0;cr_error=0;cr_state=0;cr_clear_io();if sr_init(rb+8,384,4,1000,7000,60000,0) || kv_init(kb+8,8456,4096) {return 6;}nb_copy(kb+8,ct_media,8192);
    if cr_init(wb+8,752,"0123456789abcdef","checkpoint-scope") || cr_start(0)!=1 {return 7;}r=1;count=0;let now=0;
    while r>0 && count<5 {let kind=cr_next_io();ct_check((kind==4 || kind==5) && pc_value(rb+8,384,0) && !sr_floor && !so_work && !sd_work,207);if kind==5 {ct_check(cr_io_expected==ct_anchor && cr_io_desired==ct_anchor+1,208);ct_anchor=cr_io_desired;}now=now+10;r=cr_io_done(cr_io_token,0,ct_anchor,now);count=count+1;}
    let expected_sequence=1;if cut>=7 {expected_sequence=2;}ct_check(r==0 && cr_state==4 && cr_sequence==expected_sequence && ct_anchor==expected_sequence && pc_value(wb+8,752,0),209);let sequence=cr_sequence;
    if cut>=7 {let p=sr_find(id);ct_check(sr_floor==1 && p && load64(p+8)==1000 && load64(p+16)==now+1000 && !load64(p+32) && sr_wait(id,now)==1000,210);}else {ct_check(!sr_floor && pc_value(rb+8,384,0) && sr_wait(id,now)==0,211);}
    ct_check(cr_deinit()==0 && pc_value(wb+8,752,0),212);ct_check(sm_init(pm+8,3328,2)==0 && so_init(om+8,192)==0 && sd_init(gm+8,576,sequence)==0,213);ct_check(sd_open(1,0,local,peer,id,config,now)==0,214);
    if cut>=7 {ct_check(sd_pair(1,now)==-11 && sd_next_packet(1)==0 && sr_wait(id,now)==1000,215);}else {ct_check(sd_pair(1,now)==0 && sd_next_packet(1)==-11,216);}
    ct_check(!ct_peer_error && pc_backend_clean() && pc_ps_clean(),217);ct_check(pc_value(pm,8,165) && pc_value(pm+3336,8,165) && pc_value(rm,8,165) && pc_value(rm+392,8,165) && pc_value(om,8,165) && pc_value(om+200,8,165) && pc_value(gm,8,165) && pc_value(gm+584,8,165) && pc_value(cm,8,165) && pc_value(cm+808,8,165) && pc_value(km,8,165) && pc_value(km+8464,8,165) && pc_value(mm,8,165) && pc_value(mm+8200,8,165) && pc_value(rb,8,165) && pc_value(rb+392,8,165) && pc_value(kb,8,165) && pc_value(kb+8464,8,165) && pc_value(wb,8,165) && pc_value(wb+760,8,165),218);
    ct_cold_reset();cr_work=0;cr_error=0;cr_state=0;cr_clear_io();ct_release(wb);ct_release(kb);ct_release(rb);ct_release(data);ct_release(mm);ct_release(km);ct_release(cm);ct_release(gm);ct_release(om);ct_release(rm);ct_release(pm);ct_check(ct_arena_clean(),219);return ct_status;
}
fn be_run() {let cut=0;while cut<=10 {let delivered=0;while delivered<2 {let r=be_scenario(cut,delivered);if r {return r;}delivered=delivered+1;}cut=cut+1;}return ct_status;}
