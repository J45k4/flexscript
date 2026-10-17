global rb_checks=0;
global rb_status=0;
fn rb_assert(ok,code) {rb_checks=rb_checks+1;if !ok && !rb_status {rb_status=code;}return 0;}
fn rb_zero(p,n) {let i=0;while i<n {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn rb_pattern(p,n) {let i=0;while i<n {if load8(p+i)!=165 {return 0;}i=i+1;}return 1;}
fn rb_run() {
    let memory=alloc(2208);let blob=alloc(1376);let id=alloc(8);let i=0;while i<2208 {store8(memory+i,165);i=i+1;}i=0;while i<1376 {store8(blob+i,165);i=i+1;}nb_zero(id,8);
    rb_assert(sr_size(0)==-22 && sr_size(33)==-22 && sr_size(1)==192 && sr_size(32)==2176,1);
    rb_assert(sr_init(memory+16,2175,32,1000,7000,60000,0)==-22,2);rb_assert(rb_pattern(memory,2208),3);
    rb_assert(sr_init(memory+17,2176,32,1000,7000,60000,0)==-22,4);rb_assert(rb_pattern(memory,2208),5);
    rb_assert(sr_init(memory+16,2176,32,1000,7000,60000,0)==0,6);rb_assert(sr_checkpoint_size()==1344,7);
    i=0;while i<32 {store8(id+1,i+1);rb_assert(sr_begin(id,0)==i+1,100+i);rb_assert(sr_begin(id,0)==-16,200+i);rb_assert(sr_finish(i+1,1,0)==0,300+i);rb_assert(sr_wait(id,0)==1000,400+i);i=i+1;}
    store8(id+1,99);rb_assert(sr_begin(id,0)==-105,8);store8(id+1,32);rb_assert(sr_begin(id,999)==-11,9);rb_assert(sr_wait(id,999)==1,10);rb_assert(sr_begin(id,1000)==33,11);
    rb_assert(sr_export(blob+16,1344,1000)==1344,12);rb_assert(load64(blob+16+48)==32,13);rb_assert(load64(blob+16+64+31*40+32)==1,14);rb_assert(sr_deinit(1000)==-16,15);
    // Deliberate simulated cold boot: a checkpoint remains in external storage.
    sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=0;
    rb_assert(sr_init(memory+16,2176,32,1000,7000,60000,0)==0,16);rb_assert(sr_import(blob+16,1344,0)==0,17);rb_assert(sr_floor==33,18);
    rb_assert(sr_wait(id,0)==2000,19);rb_assert(sr_finish(33,0,0)==-116,20);store8(id+1,1);rb_assert(sr_wait(id,0)==0,21);store8(id+1,99);rb_assert(sr_begin(id,0)==-105,22);
    rb_assert(sr_export(blob+16,1344,0)==1344,23);rb_assert(load64(blob+16+64+31*40+32)==0,24);rb_assert(sr_deinit(600000)==0,25);rb_assert(rb_zero(memory+16,2176),26);rb_assert(sr_floor==33,27);
    rb_assert(sr_init(memory+16,2176,32,1,1,1,0)==0,28);rb_assert(sr_begin(id,0)==34,29);rb_assert(sr_finish(34,0,0)==0,30);rb_assert(sr_deinit(0)==0,31);rb_assert(sr_floor==34 && rb_zero(memory+16,2176),32);
    rb_assert(rb_pattern(memory,16) && rb_pattern(memory+2192,16) && rb_pattern(blob,16) && rb_pattern(blob+1360,16),33);
    // Full32-entry tagged history transitions, without extra heap allocation.
    nb_zero(blob+16,8);store8(blob+16,2);let bucket=blob+16;
    rb_assert(sr_init(memory+16,2176,32,1000,7000,60000,0)==0,34);rb_assert(sr_begin(bucket,0)==35,35);rb_assert(sr_finish(35,1,0)==0,36);
    i=1;while i<=31 {store8(id+1,i);rb_assert(sr_begin(id,0)==35+i,1000+i);if i<31 {rb_assert(sr_finish(35+i,1,0)==0,1100+i);}i=i+1;}
    store8(id+1,99);rb_assert(sr_inherit(bucket,id,0)==-105,37);rb_assert(sr_finish(66,0,0)==0,38);rb_assert(sr_inherit(bucket,id,0)==0,39);rb_assert(sr_wait(bucket,0)==1000 && sr_wait(id,0)==1000,40);rb_assert(sr_floor==66,41);
    rb_assert(sr_begin(id,1000)==67,42);rb_assert(sr_inherit(bucket,id,1000)==-16,43);rb_assert(sr_finish(67,1,1000)==0,44);rb_assert(sr_inherit(id,bucket,1000)==0,45);rb_assert(sr_wait(bucket,1000)==2000 && sr_wait(id,1000)==2000,46);rb_assert(sr_floor==67,47);
    rb_assert(sr_export(blob+16,1344,1000)==1344,48);rb_assert(load64(blob+16+48)==32 && load8(blob+16+64)==2,49);rb_assert(sr_deinit(600000)==0,50);
    sr_floor=0;rb_assert(sr_init(memory+16,2176,32,1000,7000,60000,0)==0,51);rb_assert(sr_import(blob+16,1344,0)==0,52);rb_assert(sr_floor==67,53);
    // The checkpoint occupies blob now; use its first record's external key.
    bucket=blob+16+64;rb_assert(sr_wait(bucket,0)==2000 && sr_wait(id,0)==2000,54);rb_assert(sr_deinit(600000)==0,55);rb_assert(rb_zero(memory+16,2176),56);
    rb_assert(rb_pattern(memory,16) && rb_pattern(memory+2192,16) && rb_pattern(blob,16) && rb_pattern(blob+1360,16),57);return rb_status;
}
