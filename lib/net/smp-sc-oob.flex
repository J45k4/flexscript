// SC OOB tickets precede the target connection andsurvive feature resets.
// Ticket256:id,state,expiry,token,role,in/out witnesses,connection cutoff,
// local address64,peer identity72,private80,public112,r176,c192,peer r208,c224.
global sc_oob_work=0;
global sc_oob_tickets=0;
global sc_oob_gate=0;
global sc_oob_floor=0;
global sc_oob_witness_floor=0;
fn sc_oob_size(tickets) {if tickets<1 || tickets>4 {return -22;}return 1024+256*tickets;}
fn sc_ob_slot(i) {return sc_oob_work+128+i*256;}
fn sc_ob_stage() {return sc_oob_work+128+sc_oob_tickets*256;}
fn sc_ob_crypto() {return sc_ob_stage()+384;}
fn sc_ob_erase() {if sc_oob_work && sc_oob_tickets>=1 && sc_oob_tickets<=4 {nb_zero(sc_oob_work,sc_oob_size(sc_oob_tickets));}return 0;}
fn sc_ob_fault(r) {sc_ob_erase();return sc_fault(r);}
fn sc_ob_ready() {let r=sc_ready();if r {sc_ob_erase();return r;}if !sc_oob_work {return -19;}if sd_work!=sc_oob_gate || sd_sensitive_work!=sc_oob_work || sd_sensitive_bytes!=sc_oob_size(sc_oob_tickets) {return sc_ob_fault(-116);}return 0;}
fn sc_ob_find(id) {if id<=0 || !sc_oob_work {return 0;}let i=0;while i<sc_oob_tickets {let p=sc_ob_slot(i);if load64(p)==id {return p;}i=i+1;}return 0;}
fn sc_ob_retire(token) {let q=sc_ob_connection(token);if q {nb_zero(q,256);}return 0;}
fn sc_ob_connection(token) {if token<=0 || !sc_oob_work {return 0;}let i=0;while i<sc_oob_tickets {let p=sc_ob_slot(i);if load64(p) && load64(p+24)==token {return p;}i=i+1;}return 0;}
fn sc_ob_recheck(p,id) {let r=sc_ob_ready();if r {return r;}if load64(p)!=id {return sc_ob_fault(-116);}if so_now>=load64(p+16) {nb_zero(p,256);nb_zero(sc_ob_stage(),896);return -110;}return 0;}
fn sc_ob_tick(now) {
 if !sc_oob_work {return 0;}let r=sc_ob_ready();if r {return r;}let i=0;
 while i<sc_oob_tickets {let q=sc_ob_slot(i);if load64(q) {let token=load64(q+24);let p=sm_find(token);if token && (!p || load64(p+8)==4 || load64(p+8)==5) {nb_zero(q,256);}else if now>=load64(q+16) {nb_zero(q,256);if p {let owner=so_find(token);if owner && load64(owner+8) {r=sc_abort(p,2,-110,1,now);if sd_error {return sd_error;}}else {r=sm_fail(p,2,0);if r<0 {return r;}}}}}i=i+1;}return 0;
}
fn sc_oob_init(work,capacity,tickets) {
 let r=sc_ready();if r {return r;}if sc_oob_work || so_active {return -16;}let n=sc_oob_size(tickets);if n<0 || capacity<n || work&7 || !sd_external(work,capacity) {return -22;}r=smp_sc_ready(work,capacity);if r {return r;}r=smp_sc_oob_available();if r {return r;}r=sd_sensitive_register(work,n);if r {return r;}sc_oob_work=work;sc_oob_tickets=tickets;sc_oob_gate=sd_work;return 0;
}
fn sc_oob_deinit() {if !sc_oob_work {return 0;}let r=sc_ob_ready();if r {return r;}if so_active {return -16;}r=sd_sensitive_release(sc_oob_work);if r {return r;}sc_oob_work=0;sc_oob_tickets=0;sc_oob_gate=0;return 0;}
fn sc_oob_new(local,identity,expires,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}if expires<=now || expires>9223372036854745807 || !sd_external(local,7) || !sd_external(identity,7) || load8(local)>1 || load8(identity)>1 || !sr_key(identity) {return -22;}if sc_oob_floor==9223372036854775807 {return -75;}r=smp_sc_ready(local,7);if r {return r;}r=smp_sc_ready(identity,7);if r {return r;}
 let i=0;while i<sc_oob_tickets && load64(sc_ob_slot(i)) {i=i+1;}if i==sc_oob_tickets {return -105;}let p=sc_ob_slot(i);nb_zero(p,256);sc_oob_floor=sc_oob_floor+1;let id=sc_oob_floor;store64(p,id);store64(p+8,1);store64(p+16,expires);store64(p+56,sm_token_floor);nb_copy(p+64,local,7);nb_copy(p+72,identity,7);
 sc_busy=1;r=p256_keypair(p+80,sc_ob_crypto(),512);sc_busy=0;let safe=sc_ob_recheck(p,id);if safe {return safe;}if r {nb_zero(p,256);return r;}if sc_debug(p+112) {nb_zero(p,256);return -129;}store64(p+56,sm_token_floor);return id;
}
fn sc_oob_generate(id,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}let p=sc_ob_find(id);if !p || load64(p+8)!=1 {return -116;}let stage=sc_ob_stage();sc_busy=1;r=smp_sc_random(stage+256,16,sc_ob_crypto(),512);if !r {r=smp_f4(p+112,p+112,stage+256,0,stage+272,sc_ob_crypto(),512);}sc_busy=0;let safe=sc_ob_recheck(p,id);if safe {return safe;}
 if r {nb_zero(stage,896);if !sc_transient(r) {nb_zero(p,256);}return r;}nb_copy(p+176,stage+256,32);store64(p+8,2);store64(p+56,sm_token_floor);nb_zero(stage,896);return 0;
}
fn sc_oob_export(id,out,capacity,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}if capacity<32 || !sd_external(out,32) {return -22;}r=smp_sc_ready(out,32);if r {return r;}let p=sc_ob_find(id);if !p || load64(p+8)!=2 {return -116;}nb_copy(out,p+176,32);return 0;
}
fn sc_ob_attest(id,operation,record,evidence,size,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}if size<1 || size>96 || !sd_external(evidence,size) || (operation==1 && !sd_external(record,32)) {return -22;}let p=sc_ob_find(id);if !p || load64(p+8)!=2 || (operation==1 && load64(p+40)) || (operation==2 && load64(p+48)) {return -116;}
 r=smp_sc_ready(evidence,size);if r {return r;}if operation==1 {r=smp_sc_ready(record,32);if r {return r;}}let stage=sc_ob_stage();nb_zero(stage,896);if operation==2 {record=p+176;}let expires=load64(p+16);
 store64(stage,id);store64(stage+8,operation);store64(stage+16,stage+80);store64(stage+24,stage+88);store64(stage+32,stage+256);store64(stage+40,stage+288);store64(stage+48,size);store64(stage+56,now);store64(stage+64,expires);nb_copy(stage+80,p+64,7);nb_copy(stage+88,p+72,7);nb_copy(stage+128,stage,128);nb_copy(stage+256,record,32);nb_copy(stage+288,evidence,size);
 sc_busy=1;r=smp_sc_oob_attest(stage);sc_busy=0;let safe=sc_ob_recheck(p,id);if safe {return safe;}
 let immutable=nb_equal(stage,stage+128,128) && nb_equal(stage+256,record,32) && nb_equal(stage+288,evidence,size) && nb_equal(stage+80,p+64,7) && nb_equal(stage+88,p+72,7) && load64(p+8)==2 && load64(p+16)==expires;
 if !immutable {nb_zero(stage,896);nb_zero(p,256);return -116;}if r<=0 {nb_zero(stage,896);if !r {nb_zero(p,256);return -13;}if !sc_transient(r) {nb_zero(p,256);}return r;}if r<=sc_oob_witness_floor {nb_zero(stage,896);nb_zero(p,256);return -116;}sc_oob_witness_floor=r;
 if operation==1 {nb_copy(p+208,stage+256,32);store64(p+40,r);}else {store64(p+48,r);}store64(p+56,sm_token_floor);nb_zero(stage,896);return 0;
}
fn sc_oob_receive(id,record,evidence,size,now) {return sc_ob_attest(id,1,record,evidence,size,now);}
fn sc_oob_sent(id,evidence,size,now) {return sc_ob_attest(id,2,0,evidence,size,now);}
fn sc_oob_bind(id,token,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}let q=sc_ob_find(id);let p=sm_find(token);let owner=so_find(token);if !q || load64(q+8)!=2 || !p || !owner || load64(p+8)!=1 || load64(owner+8) || token<=load64(q+56) || sc_ob_connection(token) {return -116;}
 if !nb_equal(q+64,p+240,7) || !nb_equal(q+72,owner+16,7) || (load8(p+257)!=0)!=(load64(q+40)!=0) || (!load64(q+40) && !load64(q+48)) {return -13;}store64(q+8,3);store64(q+24,token);store64(q+32,load64(p+16));return 0;
}
fn sc_oob_drop(id,now) {
 let r=sc_tick(now);if r {return r;}r=sc_ob_ready();if r {return r;}let q=sc_ob_find(id);if !q {return -116;}let token=load64(q+24);let p=sm_find(token);nb_zero(q,256);if !p {return 0;}let owner=so_find(token);if owner && load64(owner+8) {r=sc_abort(p,2,-13,1,now);if r==-13 {return 0;}return r;}return 0;
}
fn sc_ob_features(token,now) {
 let p=sm_find(token);if !p {return -107;}let q=sc_ob_connection(token);let method=load64(p+88);if !q && method!=3 {return 0;}if method!=3 {return sc_abort(p,3,0,1,now);}let r=sc_ob_ready();if r {if r==-19 {return sc_abort(p,2,0,1,now);}return r;}
 if !q || load64(q+8)!=3 || load64(q+32)!=load64(p+16) || (load8(p+257)!=0)!=(load64(q+40)!=0) || (load8(p+266) && !load64(q+48)) {return sc_abort(p,2,0,1,now);}return 0;
}
fn sc_ob_begin(p,generation,lease,now) {
 let r=sc_ob_features(load64(p),now);if r {return r;}let q=sc_ob_connection(load64(p));if !q || load64(q+8)!=3 {return -116;}nb_zero(p+512,1024);store64(p+512,1);store64(p+520,lease);store64(p+528,generation);store64(p+560,load64(q));nb_copy(p+576,q+80,96);
 let flags=0;if load8(p+257) {nb_copy(p+976,q+208,16);nb_copy(p+992,q+224,16);flags=flags|1;}if load8(p+266) {nb_copy(p+960,q+176,16);flags=flags|2;}store64(p+1008,flags);store64(p+1016,load64(q+16));nb_zero(q+80,176);store64(q+8,4);
 if !load64(p+16) {return sc_queue(p,12,p+608,64,3,now);}store64(p+512,3);return 0;
}
fn sc_ob_peer(p,packet,now) {
 let token=load64(p);let gen=load64(p+528);let lease=load64(p+520);let peer=packet+1;if sc_debug(peer) || smp_equal(peer,p+608,32) {return sc_abort(p,10,0,1,now);}let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}
 let bad=0;nb_copy(p+672,peer,64);sc_busy=1;r=p256_validate(p+672,p+1024,512);if !r {r=p256_shared(p+576,p+672,p+736,p+1024,512);}if !r && (load64(p+1008)&1) {r=smp_f4(p+672,p+672,p+976,0,p+912,p+1024,512);if !r && !smp_equal(p+912,p+992,16) {bad=1;}}if !r && !bad {r=smp_sc_random(p+768,16,p+1024,512);}sc_busy=0;let safe=sc_recheck(p,token,gen,lease);if safe {return safe;}nb_zero(p+912,16);if bad {return sc_abort(p,4,0,1,now);}
 if r {if sc_transient(r) {nb_zero(p+672,144);return -11;}if r==-2 {return sc_abort(p,11,0,1,now);}return sc_abort(p,8,r,1,now);}nb_zero(p+576,32);if load64(p+16) {r=sc_queue(p,12,p+608,64,19,now);}else {r=sc_queue(p,4,p+768,16,18,now);}if r {return r;}return 1;
}
fn sc_ob_random(p,packet,now) {
 let state=load64(p+512);let role=load64(p+16);if (role && state!=19) || (!role && state!=18) {return sc_abort(p,8,0,1,now);}nb_copy(p+784,packet+1,16);let r=sc_derive(p);if r {if sc_transient(r) {nb_zero(p+784,16);return -11;}if load64(p+8)!=3 || !load64(p+512) {return r;}return sc_abort(p,8,r,1,now);}if role {r=sc_queue(p,4,p+768,16,8,now);}else {r=sc_queue(p,13,p+848,16,9,now);}if r {return r;}return 1;
}
