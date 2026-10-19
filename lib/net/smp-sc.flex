import "smp-durable.flex";
import "smp-crypto.flex";
import "smp-p256.flex";
import "smp-sc-passkey.flex";
import "smp-sc-oob.flex";
// Serialized offline SC phase2 owner. All active host calls use this facade.
// SC JW/NC/passkey/OOB;legacy andcontroller key handoff remain separate.
// Slot512:state,lease,sessionGeneration,nextState,userAccepted,prompt,flags,value.
// Private576,local public608,peer672,DHKey736,local nonce768,peer784,confirm800,
// MacKey816,LTK832,local/peer DH checks848/864,commit896,verify912,g2result928,
// zero R944;512-byte crypto scratch1024. No allocation or transport trust here.
// States:1 preparing,2 queued TX,3 waitPublic,4 waitConfirm,5 waitNa,6 waitNb,
// 7 numeric decision,8 waitEa,9 waitEb,10 cryptoComplete,11 queueCommit internal.
global sc_gate=0;
global sc_engine=0;
global sc_links=0;
global sc_owner=0;
global sc_ledger=0;
global sc_error=0;
global sc_busy=0;
fn sc_fault(status) {
    sc_error=status;sc_ob_erase();if sc_engine && sc_links>=1 && sc_links<=4 {let i=0;while i<sc_links {nb_zero(sc_engine+256+i*1536+512,1024);i=i+1;}}if sd_work==sc_gate {sd_fault(status);}return status;
}
fn sc_ready() {if !sc_gate {return -19;}if sc_error {return sc_error;}if sc_busy {return -16;}if sd_work!=sc_gate || sm_work!=sc_engine || sm_links!=sc_links || so_work!=sc_owner || sr_work!=sc_ledger {return sc_fault(-116);}let r=sd_ready();if r {return sc_fault(r);}return 0;}
fn sc_init() {
    if sc_gate {return -16;}let r=sd_ready();if r {return r;}if so_active {return -16;}
    r=smp_sc_ready(sm_work,sm_size(sm_links));if r {return r;}r=smp_sc_ready(so_work,so_size(so_links));if r {return r;}r=smp_sc_ready(sr_work,sr_size(sr_entries));if r {return r;}r=smp_sc_ready(sd_work,sd_size(sd_entries));if r {return r;}
    sc_gate=sd_work;sc_engine=sm_work;sc_links=sm_links;sc_owner=so_work;sc_ledger=sr_work;sc_error=0;sc_busy=0;return 0;
}
fn sc_deinit() {if !sc_gate {return 0;}let r=sc_ready();if r {return r;}if so_active || sc_oob_work {return -16;}sc_gate=0;sc_engine=0;sc_links=0;sc_owner=0;sc_ledger=0;sc_error=0;return 0;}
fn sc_tick(now) {let r=sc_ready();if r {return r;}r=sd_tick(now);if r {return r;}return sc_ob_tick(now);}
fn sc_open(token,role,local,peer,key,config,now) {let r=sc_tick(now);if r {return r;}return sd_open(token,role,local,peer,key,config,now);}
fn sc_pair(token,now) {let r=sc_tick(now);if r {return r;}let p=sm_find(token);if p && load8(p+257) && !sc_ob_connection(token) {return -19;}return sd_pair(token,now);}
fn sc_request_security(token,now) {let r=sc_tick(now);if r {return r;}return sd_request_security(token,now);}
fn sc_consent(token,generation,accepted,now) {let r=sc_tick(now);if r {return r;}return sd_consent(token,generation,accepted,now);}
fn sc_close(token,now) {let r=sc_tick(now);if r {return r;}r=sd_close(token,now);if !r {sc_ob_retire(token);}return r;}
fn sc_next_packet(token) {let r=sc_ready();if r {return r;}return sd_next_packet(token);}
fn sc_next_event(token) {let r=sc_ready();if r {return r;}return sd_next_event(token);}
fn sc_event_consumed(token,generation,kind) {let r=sc_ready();if r {return r;}return sd_event_consumed(token,generation,kind);}
fn sc_bound(token,generation,lease,now,durable) {
    let r=sc_tick(now);if r {return r;}let p=sm_find(token);let q=so_find(token);if !p || !q {return -107;}if load64(p+8)==5 {return -110;}
    if load64(p+8)!=3 || !load64(p+512) || generation<=0 || lease<=0 || load64(p+528)!=generation || load64(p+520)!=lease || load64(q+8)!=lease {return -116;}if load64(p+192)<generation {return sc_fault(-116);}if durable {return sd_allowed(token);}return 0;
}
// Revalidate after every external crypto/entropy boundary before committing
// keys ornew protocol effects. A callback/fault may have ended the lifetime.
fn sc_recheck(p,token,generation,lease) {
    let r=sc_ready();if r {nb_zero(p+512,1024);return r;}let q=so_find(token);if load64(p)!=token || !q {return sc_fault(-116);}if load64(p+8)==5 {nb_zero(p+512,1024);return -110;}
    if load64(p+8)!=3 || !load64(p+512) || load64(p+528)!=generation || load64(p+520)!=lease || load64(q+8)!=lease {nb_zero(p+512,1024);return -116;}if load64(p+88)==3 && so_now>=load64(p+1016) {return sc_abort(p,2,-110,1,so_now);}return 0;
}
fn sc_exhaust(p,now) {sm_clear_attempt(p);store64(p+8,4);store64(p+144,-75);store64(p+184,4);store64(p+400,-75);let r=so_cleanup(now);if r {return sc_fault(r);}r=sd_sync();if r {return sc_fault(r);}return -75;}
fn sc_abort(p,reason,status,reply,now) {
    sc_ob_retire(load64(p));
    if load64(p+192)==9223372036854775807 {return sc_exhaust(p,now);}let token=load64(p);let q=so_find(token);if !q {return sc_fault(-116);}let lease=load64(q+8);let r=sd_failure(token,load64(p+192),lease,reason,0,now);if r<0 {return r;}
    if reply {store8(p+392,5);store8(p+393,reason);sm_queue(p,p+392,2,0);nb_zero(p+392,2);}store64(p+400,status);if status<0 {return status;}return 1;
}
fn sc_queue(p,code,data,size,next,now) {
    let safe=sc_recheck(p,load64(p),load64(p+528),load64(p+520));if safe {return safe;}if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return sc_exhaust(p,now);}let r=sm_epoch(p);if r {return r;}store8(p+392,code);nb_copy(p+393,data,size);sm_queue(p,p+392,size+1,1);nb_zero(p+392,72);store64(p+512,2);store64(p+536,next);return 0;
}
fn sc_debug(public) {let hex="20b003d2f297be2c5e2c83a7e9f9a5b9eff49111acf4fddbcc0301480e359de6";let diff=0;let i=0;while i<32 {let at=(31-i)*2;let b=(nb_hex(load8(hex+at))<<4)|nb_hex(load8(hex+at+1));diff=diff|(load8(public+i)^b);i=i+1;}return diff==0;}
fn sc_transient(r) {return r==-11 || r==-16;}
fn sc_peer_clear(p) {nb_zero(p+672,144);nb_zero(p+816,144);return 0;}
fn sc_derive(p) {
    let token=load64(p);let generation=load64(p+528);let lease=load64(p+520);let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {return r;}let n1=p+768;let n2=p+784;let a1=p+240;let a2=p+248;let ownio=p+273;let peerio=p+281;
    if load64(p+16) {n1=p+784;n2=p+768;a1=p+248;a2=p+240;ownio=p+281;peerio=p+273;}nb_zero(p+944,16);if load64(p+88)==1 {store64(p+944,load64(p+960));}sc_busy=1;
    r=smp_f5(p+736,n1,n2,a1,a2,p+816,p+1024,512);
    let localr=p+944;let peerr=p+944;if load64(p+88)==3 {localr=p+976;peerr=p+960;}
    if !r {r=smp_f6(p+816,p+768,p+784,localr,ownio,p+240,p+248,p+848,p+1024,512);}
    if !r {r=smp_f6(p+816,p+784,p+768,peerr,peerio,p+248,p+240,p+864,p+1024,512);}sc_busy=0;let safe=sc_recheck(p,token,generation,lease);if safe {return safe;}nb_zero(p+944,16);if r {nb_zero(p+816,64);}return r;
}
fn sc_finish(p,now) {
    if load64(p+88)==2 && !load64(p+544) {return sc_abort(p,8,-116,1,now);}nb_zero(p+576,256);nb_zero(p+848,688);store64(p+512,10);store64(p+536,0);store64(p+552,0);store64(p+568,0);return 0;
}
fn sc_begin(token,generation,lease,now) {
    let r=sc_ready();if r {return r;}r=sd_phase2(token,generation,lease,now);if r {return r;}let p=sm_find(token);if load64(p+512) {return -16;}if load64(p+184) {return -11;}if !load64(p+80) || (load64(p+88)<0 || load64(p+88)>3) {return -95;}if load64(p+192)>9223372036854775679 {return -75;}if load64(p+88)==3 {return sc_ob_begin(p,generation,lease,now);}
    r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {return r;}nb_zero(p+512,1024);store64(p+512,1);store64(p+520,lease);store64(p+528,generation);sc_busy=1;r=p256_keypair(p+576,p+1024,512);sc_busy=0;let safe=sc_recheck(p,token,generation,lease);if safe {return safe;}
    if r {if sc_transient(r) {nb_zero(p+512,1024);return r;}return sc_abort(p,8,r,1,now);}if sc_debug(p+608) {return sc_abort(p,10,-129,1,now);}
    if !load64(p+16) {return sc_queue(p,12,p+608,64,3,now);}store64(p+512,3);return 0;
}
fn sc_peer(p,packet,now) {
    if load64(p+88)==3 {return sc_ob_peer(p,packet,now);}
    let token=load64(p);let generation=load64(p+528);let lease=load64(p+520);let peer=packet+1;if sc_debug(peer) || smp_equal(peer,p+608,32) {return sc_abort(p,10,0,1,now);}let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}
    nb_copy(p+672,peer,64);sc_busy=1;r=p256_validate(p+672,p+1024,512);if !r {r=p256_shared(p+576,p+672,p+736,p+1024,512);}if !r && load64(p+88)!=1 {r=smp_sc_random(p+768,16,p+1024,512);}if !r && load64(p+16) && load64(p+88)!=1 {r=smp_f4(p+608,p+672,p+768,0,p+896,p+1024,512);}sc_busy=0;let safe=sc_recheck(p,token,generation,lease);if safe {return safe;}
    if r {if sc_transient(r) {sc_peer_clear(p);return -11;}if r==-2 {return sc_abort(p,11,0,1,now);}return sc_abort(p,8,r,1,now);}nb_zero(p+576,32);
    if load64(p+88)==1 {store64(p+984,load64(p+128));if load64(p+16) {r=sc_queue(p,12,p+608,64,12,now);if r {return r;}}else {store64(p+512,12);}return 1;}
    if load64(p+16) {r=sc_queue(p,12,p+608,64,11,now);if r {return r;}}else {store64(p+512,4);}return 1;
}
fn sc_random(p,packet,now) {
    let token=load64(p);let generation=load64(p+528);let lease=load64(p+520);let role=load64(p+16);let r=smp_sc_ready(sc_engine,sm_size(sc_links));if r {if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}nb_copy(p+784,packet+1,16);sc_busy=1;
    if !role {r=smp_f4(p+672,p+608,p+784,0,p+912,p+1024,512);if !r && !smp_equal(p+912,p+800,16) {sc_busy=0;return sc_abort(p,4,0,1,now);}}
    if !r && load64(p+88)==2 {let u=p+608;let v=p+672;let x=p+768;let y=p+784;if role {u=p+672;v=p+608;x=p+784;y=p+768;}r=smp_g2(u,v,x,y,p+928,p+1024,512);}sc_busy=0;let safe=sc_recheck(p,token,generation,lease);if safe {return safe;}
    if r {nb_zero(p+784,16);nb_zero(p+912,32);if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}
    if load64(p+88)==2 {let value=load8(p+928)|(load8(p+929)<<8)|(load8(p+930)<<16)|(load8(p+931)<<24);store64(p+568,value%1000000);store64(p+552,1);}else {r=sc_derive(p);if r {nb_zero(p+784,16);if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}}
    nb_zero(p+800,16);nb_zero(p+912,32);if role {let next=8;if load64(p+88)==2 {next=7;}r=sc_queue(p,4,p+768,16,next,now);if r {return r;}}
    else {if load64(p+88)==2 {store64(p+512,7);}else {r=sc_queue(p,13,p+848,16,9,now);if r {return r;}}}return 1;
}
fn sc_input(token,packet,size,now) {
    let r=sc_tick(now);if r {return r;}r=sd_input(token,packet,size,now);if r!=2 {let sweep=sc_ob_tick(now);if sweep {return sweep;}let feature=sm_find(token);if r==1 && size==7 && (load8(packet)==1 || load8(packet)==2) && feature && (load64(feature+8)==3 || load64(feature+8)==6) {let checked=sc_ob_features(token,now);if checked {return checked;}}return r;}let p=sm_find(token);let state=load64(p+512);if !state {return -11;}let q=so_find(token);r=sc_bound(token,load64(p+528),load64(q+8),now,1);if r {return r;}let code=load8(packet);if code==14 {if load64(p+88)==1 {return sc_pk_keypress(p,packet,now);}return 0;}
    if load64(p+88)==3 && code==4 {return sc_ob_random(p,packet,now);}
    if load64(p+88)==1 && code==3 {return sc_pk_confirm(p,packet,now);}if load64(p+88)==1 && code==4 {return sc_pk_random(p,packet,now);}
    if state==3 && code==12 {return sc_peer(p,packet,now);}if state==4 && code==3 && !load64(p+16) {nb_copy(p+800,packet+1,16);r=sc_queue(p,4,p+768,16,6,now);if r {return r;}return 1;}
    if (state==5 && load64(p+16) || state==6 && !load64(p+16)) && code==4 {return sc_random(p,packet,now);}
    if state==7 && load64(p+16) && code==13 {return -11;}
    if (state==8 && load64(p+16) || state==9 && !load64(p+16)) && code==13 {if !smp_equal(p+864,packet+1,16) {return sc_abort(p,11,0,1,now);}if load64(p+16) {r=sc_queue(p,13,p+848,16,10,now);if r {return r;}}else {r=sc_finish(p,now);if r {return r;}}return 1;}
    return sc_abort(p,8,0,1,now);
}
fn sc_packet_sent(token,generation,now) {
    let r=sc_tick(now);if r {return r;}r=sd_packet_sent(token,generation,now);if r {return r;}let p=sm_find(token);if load64(p+512)!=2 {return 0;}let next=load64(p+536);
    if next==11 {return sc_queue(p,3,p+896,16,5,now);}if next==10 {return sc_finish(p,now);}if next==17 {nb_zero(p+768,48);nb_zero(p+896,16);store64(p+976,load64(p+976)+1);store64(p+512,13);store64(p+536,0);return 0;}if next<3 || next>19 {return sc_abort(p,8,-116,1,now);}store64(p+512,next);store64(p+536,0);return 0;
}
fn sc_confirm(token,generation,lease,accepted,now) {
    if accepted!=0 && accepted!=1 {return -22;}let r=sc_bound(token,generation,lease,now,accepted);if r {return r;}let p=sm_find(token);if !load64(p+552) || load64(p+88)!=2 {return -116;}if !accepted {r=sc_abort(p,12,-13,1,now);if r==-13 {return 0;}return r;}
    if load64(p+168) {return -11;}if load64(p+512)!=7 {return -116;}r=sc_derive(p);if r {if sc_transient(r) {return -11;}return sc_abort(p,8,r,1,now);}store64(p+544,1);store64(p+552,0);
    if !load64(p+16) {return sc_queue(p,13,p+848,16,9,now);}store64(p+512,8);return 0;
}
fn sc_prompt(token,generation,lease,out,capacity,now) {
    let r=sc_bound(token,generation,lease,now,1);if r {return r;}if capacity<32 || !sd_external(out,32) {return -22;}let p=sm_find(token);if !load64(p+552) {return 0;}store64(out,token);store64(out+8,generation);store64(out+16,lease);store64(out+24,load64(p+568));return 1;
}
// Copied metadata only. No key or controller trust is published by this API.
fn sc_snapshot(token,out,capacity,now) {
    let r=sc_ready();if r {return r;}if capacity<80 || !sd_external(out,80) {return -22;}r=sc_tick(now);if r {return r;}let p=sm_find(token);if !p || !so_find(token) {return -107;}if load64(p+8)==5 {return -110;}r=sd_allowed(token);if r {return r;}nb_zero(out,80);store64(out,load64(p+512));store64(out+8,load64(p+528));store64(out+16,load64(p+520));store64(out+24,load64(p+552));store64(out+32,load64(p+568));store64(out+40,load64(p+544));store64(out+48,load64(p+136));store64(out+56,load64(p+224));store64(out+64,load64(p+400));store64(out+72,load64(p+200));return 0;
}
