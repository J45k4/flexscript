import "smp-oob-fixture.flex";
// Independent peer wire transcripts. Key observations below are test-only.
global tc_pair=0;
global tc_retry=0;
global tc_owner=0;
global tc_gate=0;
global tc_io=0;
global tc_generation=0;
global tc_lease=0;
global tc_case=0;
global tc_step=0;
global tc_checks=0;
global tc_mode=0;
global tc_last_ack=0;
fn tc_lifetime() {if tc_mode==400 {sd_fault(-5);}if tc_mode==401 {sd_tick(30000);}if tc_mode==402 {sc_fault(-5);}return 0;}
fn tc_zero(p,n) {let i=0;while i<n {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn tc_check(test,field,actual,expected) {tc_checks=tc_checks+1;if !test {tc_report(field,actual,expected);return 8;}return 0;}
fn tc_hex(out,hex,n) {let i=0;while i<n {store8(out+i,(nb_hex(load8(hex+i*2))<<4)|nb_hex(load8(hex+i*2+1)));i=i+1;}return 0;}
fn tc_flush() {let r=sd_checkpoint(so_now);if r<0 {return r;}if r {return sd_done(sd_frozen_sequence,sd_frozen_revision,0,so_now);}return 0;}
fn tc_boot(role,numeric) {
 tc_ob_id=0;tc_ob_role=role;tc_ob_flags=numeric-10;tc_ob_bad=0;sc_oob_work=0;sc_oob_tickets=0;sc_oob_gate=0;sc_oob_floor=0;sc_oob_witness_floor=0;sd_sensitive_work=0;sd_sensitive_bytes=0;if tc_ob_raw {tc_ob_fill(tc_ob_raw,2080,165);}tc_last_ack=0;sc_gate=0;sc_engine=0;sc_links=0;sc_owner=0;sc_ledger=0;sc_error=0;sc_busy=0;
 sd_work=0;sd_engine=0;sd_link_count=0;sd_entries=0;sd_owner=0;sd_ledger=0;sd_revision=0;sd_revision_floor=0;sd_durable=0;sd_sequence=0;sd_sequence_floor=0;sd_seen_floor=0;sd_busy=0;sd_frozen_revision=0;sd_frozen_sequence=0;sd_error=0;sd_views();
 so_work=0;so_links=0;so_active=0;so_now=0;so_sm_work=0;so_sr_work=0;so_sr_entries=0;so_fault=0;
 sm_work=0;sm_links=0;sm_active=0;sm_token_floor=0;sm_now=0;sm_packet=0;sm_packet_size=0;sm_packet_connection=0;sm_packet_generation=0;sm_event_kind=0;sm_event_connection=0;sm_event_generation=0;sm_event_status=0;
 sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;sr_floor=0;
 let configured=tc_ob_configure(1);if configured {return configured;}let r=sm_init(tc_pair,3328,2);if r {return r;}r=sr_init(tc_retry,384,4,1000,7000,60000,0);if r {return r;}r=so_init(tc_owner,192);if r {return r;}r=sd_init(tc_gate,576,0);if r {return r;}r=sc_init();if r {return r;}
 nb_zero(tc_io,128);tc_hex(tc_io,"00010203040506",7);tc_hex(tc_io+8,"010a0b0c0d0ec0",7);tc_hex(tc_io+16,"0300091000000706",8);if numeric==1 {store8(tc_io+16,1);store8(tc_io+18,13);store8(tc_io+23,7);}if numeric>=2 && numeric<6 {let io=2;if numeric&1 {io=0;}store8(tc_io+16,io);let auth=13;if numeric>=4 {auth=29;}store8(tc_io+18,auth);store8(tc_io+23,7);}let local=tc_io;let peer=tc_io+8;if role {local=tc_io+8;peer=tc_io;}
 if numeric>=10 {store8(tc_io+16,3);store8(tc_io+17,tc_ob_flags&1);store8(tc_io+18,13);store8(tc_io+23,15);return 0;}
 r=sc_open(1,role,local,peer,tc_io,tc_io+16,0);if r {return r;}if !role {r=sc_pair(1,0);if r {return r;}r=tc_flush();if r {return r;}r=sc_packet_sent(1,load64(sm_find(1)+200),0);if r {return r;}}
 store8(tc_io+32,2-role);nb_copy(tc_io+33,tc_io+16,6);if numeric>=2 && numeric<6 {let io=0;if numeric&1 {io=2;}store8(tc_io+33,io);}r=sc_input(1,tc_io+32,7,0);if r!=1 {return -100;}r=tc_flush();if r {return r;}let p=sm_find(1);tc_generation=load64(p+192);tc_lease=load64(so_find(1)+8);
 if role {r=sc_packet_sent(1,load64(p+200),0);if r {return r;}}r=sc_event_consumed(1,tc_generation,1);if r {return r;}return 0;
}
fn tc_secondary() {
 nb_copy(tc_io+48,tc_io,7);store8(tc_io+54,load8(tc_io+54)^128);let r=sc_open(2,1,tc_io+8,tc_io,tc_io+48,tc_io+16,0);if r {return r;}store8(tc_io+32,1);nb_copy(tc_io+33,tc_io+16,6);r=sc_input(2,tc_io+32,7,0);if r!=1 {return -100;}r=tc_flush();if r {return r;}let p=sm_find(2);let gen=load64(p+192);r=sc_packet_sent(2,load64(p+200),0);if r {return r;}r=sc_event_consumed(2,gen,1);if r {return r;}return sc_begin(2,gen,load64(so_find(2)+8),0);
}
fn tc_command(row) {
 let op=load64(row);let arg=load64(row+8);if op>=39 {return tc_ob_command(row);}if op==1 {return sc_begin(1,tc_generation,tc_lease,0);}if op==2 {return sc_input(1,row+64,load64(row+24),0);}if op==3 {let gen=load64(sm_find(1)+200)+arg;if arg==-2 {gen=tc_last_ack;}let r=sc_packet_sent(1,gen,0);if !r {tc_last_ack=gen;}return r;}if op==4 {let accept=arg;if arg>=500 {accept=1;}return sc_confirm(1,tc_generation,tc_lease,accept,0);}if op==5 {return sc_tick(arg);}if op==6 {let i=0;while i<1024 {store8(sm_slot(1)+512+i,165);i=i+1;}return sd_fault(-5);}if op==7 {return sc_close(1,0);}if op==8 {return tc_flush();}if op==9 {return tc_secondary();}if op==10 {let gen=tc_generation;let lease=tc_lease;if arg {lease=lease+1;}else {gen=gen+1;}return sc_confirm(1,gen,lease,1,0);}if op==12 {return 0;}if op==20 {return sc_passkey_generate(1,tc_generation,tc_lease,0);}if op==21 {return sc_passkey_enter(1,tc_generation,tc_lease,arg,0);}if op==22 {return sc_passkey_start(1,tc_generation,tc_lease,0);}if op==23 {return sc_passkey_cancel(1,tc_generation,tc_lease,0);}if op==24 {return sc_keypress(1,tc_generation,tc_lease,arg,0);}if op==26 {return load64(sm_find(1)+976);}if op==28 {return sc_input(1,row+64,load64(row+24),arg);}if op==29 {return load64(sm_find(1)+152);}if op==30 {let r=sc_keypress_peer(1,tc_generation,tc_lease,tc_io+64,24,arg);if r!=1 {return r;}if !nb_equal(tc_io+64,row+64,24) {return -1001;}return 0;}if op==31 {if arg {return sc_passkey_enter(1,tc_generation,tc_lease+1,0,0);}return sc_passkey_enter(1,tc_generation+1,tc_lease,0,0);}return -1000;
}
fn tc_run(data,size) {
 if size<16 || load64(data)!=0x315343504d53 {return 2;}if !tc_pair {tc_pair=alloc(3328);tc_retry=alloc(384);tc_owner=alloc(192);tc_gate=alloc(576);tc_io=alloc(128);tc_ob_raw=alloc(2080);tc_ob_pool=tc_ob_raw+16;}let cases=load64(data+8);let at=16;tc_case=0;
 while tc_case<cases {if at>size-32 {return 3;}let header=data+at;let r=tc_boot(load64(header),load64(header+8));if r {tc_report(0,r,0);return 4;}let rows=load64(header+16);at=at+32;tc_step=0;
 while tc_step<rows {if at>size-280 {return 5;}let row=data+at;tc_before(row);let actual=tc_command(row);if tc_ob_bad {tc_report(20,tc_ob_bad,0);return 8;}if !tc_ob_guards() {tc_report(19,0,1);return 8;}if !tc_ob_ps_clean() {tc_report(21,0,1);return 8;}r=tc_check(actual==load64(row+16),1,actual,load64(row+16));if r {return r;}let p=sm_find(1);let flags=load64(row+56);
 // Check a fault's cleanup before any SC poll could itself wipe the slots.
 if flags&2 {r=tc_check(tc_zero(sm_slot(0)+512,1024) && tc_zero(sm_slot(1)+512,1024),2,0,1);if r {return r;}}
 if p {r=tc_check(!load64(p+224),3,load64(p+224),0);if r {return r;}}
 if load64(row+40)>=0 {r=tc_check(load64(p+512)==load64(row+40),4,load64(p+512),load64(row+40));if r {return r;}}
 if load64(row+32)>=0 {let n=sc_next_packet(1);r=tc_check(n==load64(row+32),5,n,load64(row+32));if r {return r;}if n>0 {r=tc_check(nb_equal(sm_packet,row+192,n),6,0,1);if r {return r;}}}
 if load64(row+48)>=0 {let v=0;if flags&16 {r=sc_passkey_prompt(1,tc_generation,tc_lease,tc_io+64,40,0);v=load64(tc_io+96);}else {r=sc_prompt(1,tc_generation,tc_lease,tc_io+64,32,0);v=load64(tc_io+88);}let c=tc_check(r==1 && v==load64(row+48),7,v,load64(row+48));if c {return c;}}
 if flags&1 {r=tc_check(nb_equal(p+832,row+264,16) && tc_zero(p+576,256) && tc_zero(p+848,688),8,0,1);if r {return r;}}
 if flags&4 {r=tc_check(tc_zero(p+512,1024),9,0,1);if r {return r;}}
 if flags&32 {r=tc_check(tc_zero(tc_ob_pool,sd_sensitive_bytes),11,0,1);if r {return r;}}
 if flags&128 {let at=0;let clean=1;while at<2048 {if load8(tc_ob_pool+at)!=165 {clean=0;}at=at+1;}r=tc_check(clean,13,0,1);if r {return r;}}
 if flags&64 {r=tc_check(sc_ob_find(tc_ob_id) && load64(sc_ob_find(tc_ob_id)+8)==4 && tc_zero(sc_ob_find(tc_ob_id)+80,176),12,0,1);if r {return r;}}
 if flags&8 {let other=sm_find(2);r=tc_check(other && load64(other+512)==3 && nb_equal(other+576,row+64,96),10,0,1);if r {return r;}}
 at=at+280;tc_step=tc_step+1;}tc_case=tc_case+1;}if at!=size {return 6;}return 0;
}
