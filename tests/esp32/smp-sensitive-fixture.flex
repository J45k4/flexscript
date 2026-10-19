import "smp-durable-fixture.flex";
// The boot helper below is a test-only cold-RAM reset. Production callers
// retain registered memory until an explicit,quiescent successful release.
global sk_raw=0;
global sk_io=0;
global sk_checks=0;
fn sk_check(ok,point) {sk_checks=sk_checks+1;if !ok {sk_report(point);return 8;}return 0;}
fn sk_boot() {sd_sensitive_work=0;sd_sensitive_bytes=0;dc_fill(sk_raw,65568,165);dc_fill(sk_io,128,204);return dc_boot();}
fn sk_flush() {let r=sd_checkpoint(0);if r<0 {return r;}if r {return sd_done(sd_frozen_sequence,sd_frozen_revision,0,0);}return 0;}
fn sk_open() {nb_zero(sk_io,32);store8(sk_io+1,1);store8(sk_io+9,2);store8(sk_io+16,3);store8(sk_io+18,9);store8(sk_io+19,16);store8(sk_io+22,7);store8(sk_io+23,6);return sd_open(1,0,sk_io,sk_io+8,sk_io+8,sk_io+16,0);}
fn sk_guards() {return dc_value(sk_raw,16,165) && dc_value(sk_raw+65552,16,165);}
fn sk_run() {
 dc_pair=sk_allocate(3344);dc_retry=sk_allocate(400);dc_owner=sk_allocate(208);dc_gate=sk_allocate(592);sk_raw=sk_allocate(65568);sk_io=sk_allocate(128);if !dc_pair || !dc_retry || !dc_owner || !dc_gate || !sk_raw || !sk_io {return 2;}let area=sk_raw+16;
 let r=sk_check(sd_sensitive_register(area,256)==-19 && sd_sensitive_release(area)==-19,1);if r {return r;}r=sk_boot();if r {return r;}
 let i=0;while i<12 {let p=area;let n=256;if i==0 {p=0;}if i==1 {p=area+1;}if i==2 {n=0;}if i==3 {n=7;}if i==4 {n=-1;}if i==5 {n=65537;}if i==6 {p=9223372036854775800;n=16;}if i==7 {p=sm_work;}if i==8 {p=sr_work;}if i==9 {p=so_work;n=64;}if i==10 {p=sd_work;}if i==11 {p=sm_work-8;n=16;}
  r=sk_check(sd_sensitive_register(p,n)==-22 && !sd_sensitive_work && dc_value(area,65536,165) && sk_guards(),10+i);if r {return r;}i=i+1;}
 r=sk_check(sd_sensitive_register(area,65536)==0 && sd_sensitive_work==area && sd_sensitive_bytes==65536 && dc_value(area,65536,0) && sk_guards(),30);if r {return r;}
 dc_fill(area,65536,90);r=sk_check(sd_sensitive_register(area,8)==-16 && dc_value(area,65536,90),31);if r {return r;}
 r=sk_check(!sd_external(area,1) && !sd_external(area+65535,1) && !sd_external(area-8,16) && !sd_external(area+65528,16) && sd_external(area-8,8) && sd_external(area+65536,8),32);if r {return r;}
 r=sk_check(sd_input(1,area,7,0)==-107 && sd_open(1,0,area,sk_io,sk_io,sk_io,0)==-22 && !so_active && dc_value(area,65536,90),33);if r {return r;}
 r=sk_check(sd_sensitive_release(area+8)==-116 && dc_value(area,65536,90),34);if r {return r;}
 r=sk_check(sk_flush()==0 && sd_deinit()==-16 && sd_work && dc_value(area,65536,90),35);if r {return r;}
 r=sk_check(sk_open()==0 && sd_sensitive_release(area)==-16 && dc_value(area,65536,90),36);if r {return r;}
 r=sk_check(sd_input(1,area,7,0)==-22 && sd_snapshot(1,area,272)==-22 && dc_value(area,65536,90),37);if r {return r;}
 r=sk_check(sd_close(1,0)==0 && sd_sensitive_release(area)==0 && !sd_sensitive_work && !sd_sensitive_bytes && dc_value(area,65536,0) && sk_guards() && sd_external(area,65536),38);if r {return r;}
 r=sk_check(sd_deinit()==0,39);if r {return r;}
 r=sk_boot();if r {return r;}r=sk_check(sd_checkpoint(0)==1 && sd_sensitive_register(area,65536)==-16 && dc_value(area,65536,165),40);if r {return r;}r=sk_check(sd_done(sd_frozen_sequence,sd_frozen_revision,0,0)==0 && sd_sensitive_register(area,65536)==0,41);if r {return r;}
 r=sk_check(sk_open()==0 && sd_pair(1,0)==0 && sd_checkpoint(0)==1 && sd_sensitive_release(area)==-16,42);if r {return r;}
 r=sk_boot();if r {return r;}r=sk_check(sk_open()==0 && sd_sensitive_register(area,65536)==-16 && dc_value(area,65536,165) && sd_close(1,0)==0,43);if r {return r;}
 r=sk_check(sd_sensitive_register(area,8)==0 && dc_value(area,8,0) && dc_value(area+8,65528,165) && sk_guards(),44);if r {return r;}
 r=sk_check(sd_checkpoint(0)==1 && sd_sensitive_release(area)==-16 && sd_done(sd_frozen_sequence,sd_frozen_revision,0,0)==0 && sd_sensitive_release(area)==0,45);if r {return r;}
 // Inspect every byte immediately after the fault,without another owner poll.
 i=0;while i<5 {r=sk_boot();if r {return r;}r=sk_check(sd_sensitive_register(area,65536)==0,50+i*4);if r {return r;}dc_fill(area,65536,90);let engine=sm_work;dc_fill(engine+256+512,1024,90);dc_fill(engine+256+1536+512,1024,90);
  let fault=-5;if i==0 {r=sd_fault(-5);}if i==1 {r=sd_checkpoint(0);if r!=1 {return 3;}r=sd_done(sd_frozen_sequence,sd_frozen_revision,-5,0);}if i==2 {so_work=so_work+8;fault=-116;r=sd_ready();}if i==3 {sm_work=sk_io;fault=-116;r=sd_ready();}if i==4 {sm_links=4;fault=-116;r=sd_ready();}
  r=sk_check(r==fault && sd_error==fault && dc_value(area,65536,0) && dc_value(engine+256+512,1024,0) && dc_value(engine+256+1536+512,1024,0) && sk_guards(),51+i*4);if r {return r;}
  r=sk_check(sd_sensitive_release(area)==fault && sd_sensitive_work==area && sd_sensitive_bytes==65536 && dc_value(area,65536,0),52+i*4);if r {return r;}
  if i==3 {r=sk_check(dc_value(sk_io,128,204),53+i*4);if r {return r;}}i=i+1;}
 return 0;
}
