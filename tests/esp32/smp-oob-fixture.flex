global tc_ob_pool=0;
global tc_ob_raw=0;
global tc_ob_id=0;
global tc_ob_role=0;
global tc_ob_flags=0;
global tc_ob_expiry=0;
global tc_ob_result=1;
global tc_ob_operation=0;
global tc_ob_bad=0;
global tc_ob_row=0;
fn tc_ob_fill(p,n,v) {let i=0;while i<n {store8(p+i,v);i=i+1;}return 0;}
fn tc_ob_guards() {let i=0;while i<16 {if load8(tc_ob_raw+i)!=165 || load8(tc_ob_pool+2048+i)!=165 {return 0;}i=i+1;}if sd_sensitive_work==tc_ob_pool {i=sd_sensitive_bytes;while i<2048 {if load8(tc_ob_pool+i)!=165 {return 0;}i=i+1;}}return 1;}
fn tc_ob_cb(request) {
 let local=tc_io;let peer=tc_io+8;if tc_ob_role {local=tc_io+8;peer=tc_io;}let size=load64(request+48);let record=tc_io+64;if tc_ob_operation==1 {record=tc_ob_row+64;}
 if !sc_busy || sc_tick(0)!=-16 || tc_ob_configure(1)!=-16 || load64(request)!=tc_ob_id || load64(request+8)!=tc_ob_operation || !nb_equal(load64(request+16),local,7) || !nb_equal(load64(request+24),peer,7) || !nb_equal(load64(request+32),record,32) || size!=8 || load64(load64(request+40))!=0x31464f4f5250424f || load64(request+56)!=0 || load64(request+64)!=tc_ob_expiry || load64(request+72)!=0x1122334455667788 {tc_ob_bad=1;return -5;}
 if tc_mode==600 {return 0;}if tc_mode==601 {return -5;}if tc_mode==602 {store64(request+8,99);}if tc_mode==603 {store8(load64(request+32),load8(load64(request+32))^1);}if tc_mode==604 {store8(load64(request+40),0);}if tc_mode==605 {store64(request+72,0);}if tc_mode==606 {sd_fault(-5);}if tc_mode==607 {sd_tick(tc_ob_expiry);}if tc_mode==609 {store64(request+32,0);}if tc_mode>=620 && tc_mode<=635 {tc_ob_change_ps();}return tc_ob_result;
}
fn tc_ob_connect(kind) {
 let local=tc_io;let peer=tc_io+8;if tc_ob_role {local=tc_io+8;peer=tc_io;}let identity=peer;if kind==1 {store8(local+1,load8(local+1)^128);}if kind==2 {nb_copy(tc_io+48,peer,7);store8(tc_io+49,load8(tc_io+49)^128);identity=tc_io+48;}if kind==3 {store8(tc_io+17,load8(tc_io+17)^1);}return sc_open(1,tc_ob_role,local,peer,identity,tc_io+16,0);
}
fn tc_ob_open() {let r=tc_ob_connect(0);if r {return r;}r=sc_oob_bind(tc_ob_id,1,0);if r {return r;}return tc_ob_negotiate();}
fn tc_ob_negotiate() { let r=0;if !tc_ob_role {r=sc_pair(1,0);if r {return r;}r=tc_flush();if r {return r;}r=sc_packet_sent(1,load64(sm_find(1)+200),0);if r {return r;}}
 store8(tc_io+32,2-tc_ob_role);nb_copy(tc_io+33,tc_io+16,6);store8(tc_io+34,(tc_ob_flags&2)!=0);r=sc_input(1,tc_io+32,7,0);if r!=1 {return -100;}let p=sm_find(1);if load64(p+8)!=3 {return 1;}r=tc_flush();if r {return r;}tc_generation=load64(p+192);tc_lease=load64(so_find(1)+8);if tc_ob_role {r=sc_packet_sent(1,load64(p+200),0);if r {return r;}}return sc_event_consumed(1,tc_generation,1);
}
fn tc_ob_command(row) {
 let op=load64(row);let arg=load64(row+8);if op==39 {return sc_oob_init(tc_ob_pool,2048,arg);}if op==40 {tc_ob_expiry=arg;let local=tc_io;let peer=tc_io+8;if tc_ob_role {local=tc_io+8;peer=tc_io;}let r=sc_oob_new(local,peer,arg,0);if r>0 {tc_ob_id=r;}return r;}
 if op==41 {return sc_oob_generate(tc_ob_id,0);}if op==42 {let r=sc_oob_export(tc_ob_id,tc_io+64,32,0);if r {return r;}if !nb_equal(tc_io+64,row+64,32) {return -1002;}return 0;}if op==43 {tc_ob_operation=2;return sc_oob_sent(tc_ob_id,row+64,8,0);}if op==44 {tc_ob_operation=1;return sc_oob_receive(tc_ob_id,row+64,row+96,8,0);}if op==45 {return tc_ob_open();}if op==46 {return sc_oob_drop(tc_ob_id,0);}if op==47 {return sc_oob_deinit();}if op==48 {return sc_oob_bind(tc_ob_id,arg,0);}if op==49 {return sc_oob_generate(tc_ob_id+arg,0);}if op==50 {return tc_ob_connect(arg);}if op==51 {return tc_ob_negotiate();}if op==52 {tc_ob_flags=arg;return 0;}if op==53 {return tc_ob_configure(arg);}if op==54 {if arg==4 {return tc_ob_init_alias();}let p=tc_ob_pool;let cap=2048;if !arg {p=0;}if arg==1 {p=p+1;}if arg==2 {cap=2047;}if arg==3 {p=sm_work;}return sc_oob_init(p,cap,4);}return -1000;
}
