global dm_checks=0;
global dm_status=0;
fn dm_check(ok,code) {dm_checks=dm_checks+1;if !ok && !dm_status {dm_status=code;}return 0;}
fn dm_fill(p,n,value) {let i=0;while i<n {store8(p+i,value);i=i+1;}return 0;}
fn dm_value(p,n,value) {let i=0;while i<n {if load8(p+i)!=value {return 0;}i=i+1;}return 1;}
fn dm_sum(p,n) {let sum=0;let i=0;while i<n {sum=sum+(i+1)*load8(p+i);i=i+1;}return sum;}
fn dm_run() {
    let pm=dm_allocate(6416);let rm=dm_allocate(2192);let om=dm_allocate(336);let gm=dm_allocate(3728);let out=dm_allocate(288);let data=dm_allocate(32);if !pm || !rm || !om || !gm || !out || !data {return 1;}
    dm_fill(pm,6416,165);dm_fill(rm,2192,165);dm_fill(om,336,165);dm_fill(gm,3728,165);dm_fill(out,288,165);nb_zero(data,32);let local=data;let peer=data+8;let key=data+16;let config=data+24;store8(local+1,1);store8(peer+1,2);store8(config,1);store8(config+2,13);store8(config+3,16);store8(config+4,7);store8(config+5,7);store8(config+6,7);
    if sm_init(pm+8,6400,4) || sr_init(rm+8,2176,32,1000,7000,60000,0) || so_init(om+8,320) {return 2;}
    let i=5;while i<=32 {store8(key+1,i);dm_check(sr_begin(key,0)==i-4,100+i);dm_check(sr_finish(i-4,1,0)==0,200+i);i=i+1;}
    dm_check(sd_size(0)==-22 && sd_size(33)==-22 && sd_size(32)==3712,3);dm_check(sd_init(gm+8,3711,0)==-22 && dm_value(gm,3728,165),4);dm_check(sd_init(gm+9,3712,0)==-22 && dm_value(gm,3728,165),5);if sd_init(gm+8,3712,0) {return 6;}
    i=1;while i<=4 {store8(key+1,i);dm_check(sd_open(i,0,local,peer,key,config,0)==0,300+i);dm_check(sd_pair(i,0)==0,400+i);dm_check(sd_next_packet(i)==-11,500+i);i=i+1;}
    dm_check(sr_floor==32 && so_active==4 && sd_revision==5,7);dm_check(sd_checkpoint(0)==1 && sd_checkpoint_peek()==1344,8);let frozen=sd_checkpoint_buffer;let sum=dm_sum(frozen,1344);dm_check(sd_checkpoint_revision==5 && sd_checkpoint_sequence==1 && load64(frozen+48)==32,9);
    let p=sm_find(2);dm_fill(p+512,1024,90);store8(data,5);store8(data+1,8);dm_check(sd_input(2,data,2,10)==1,10);dm_check(dm_value(p+512,1024,0) && sd_revision==6,11);dm_check(sd_checkpoint_peek()==1344 && dm_sum(frozen,1344)==sum && sd_checkpoint_revision==5,12);
    dm_check(sd_done(1,5,0,11)==0,13);dm_check(sd_next_packet(1)==7 && sd_next_packet(3)==7 && sd_next_packet(4)==7,14);dm_check(sd_next_event(2)==-11,15);dm_check(sd_next_packet(3)==7 && sm_packet_connection==3,16);
    dm_check(sd_close(1,12)==0 && sd_revision==7 && sm_packet_connection==3,17);dm_check(sd_checkpoint(12)==1 && sd_checkpoint_peek()==1344 && sd_checkpoint_revision==7,18);dm_check(sd_done(2,7,0,13)==0,19);dm_check(sd_next_event(2)==1 && sm_event_kind==3 && sm_event_connection==2,20);dm_check(sd_next_packet(3)==7,21);
    dm_check(sd_close(3,14)==0 && sd_revision==8,22);dm_check(sd_close(4,15)==0 && sd_revision==9,23);dm_check(sd_close(2,15)==0 && so_active==0 && sd_revision==9,24);dm_check(sd_checkpoint(15)==1 && sd_checkpoint_peek()==1344,25);sum=dm_sum(sd_checkpoint_buffer,1344);dm_check(sd_deinit()==-16 && dm_sum(sd_checkpoint_buffer,1344)==sum,26);
    nb_zero(local,7);nb_zero(peer,7);store8(local+1,1);store8(peer+1,2);store8(key+1,33);dm_check(sd_open(5,0,local,peer,key,config,15)==0 && sd_pair(5,15)==-105,27);dm_check(sd_close(5,15)==0 && sd_revision==9,28);dm_check(sd_done(3,9,0,16)==0 && sd_deinit()==0 && dm_value(gm+8,3712,0),29);
    dm_check(sd_init(gm+8,3712,2)==-116 && dm_value(gm+8,3712,0),30);dm_check(sd_init(gm+8,3712,3)==0 && sd_revision==10,31);dm_check(sd_checkpoint(16)==1 && sd_checkpoint_peek()==1344,32);sum=dm_sum(sd_checkpoint_buffer,1344);dm_check(sd_done(3,9,0,16)==-116 && dm_sum(sd_checkpoint_buffer,1344)==sum,33);dm_check(sd_done(4,10,0,17)==0 && sd_deinit()==0 && dm_value(gm+8,3712,0),34);
    dm_check(so_deinit()==0 && sm_deinit()==0 && sr_deinit(700000)==0,35);dm_check(dm_value(pm+8,6400,0) && dm_value(rm+8,2176,0) && dm_value(om+8,320,0),36);
    dm_check(dm_value(pm,8,165) && dm_value(pm+6408,8,165) && dm_value(rm,8,165) && dm_value(rm+2184,8,165) && dm_value(om,8,165) && dm_value(om+328,8,165) && dm_value(gm,8,165) && dm_value(gm+3720,8,165) && dm_value(out,288,165),37);
    dm_release(data);dm_release(out);dm_release(gm);dm_release(om);dm_release(rm);dm_release(pm);dm_check(dm_arena_clean(),38);return dm_status;
}
