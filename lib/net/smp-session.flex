import "smp-pairing.flex";
import "smp-retry.flex";
// Serialized pairing owner. Initialize the two engines first, then use only
// these entrypoints while attached. No radio, P256, trust promotion or storage.
// Storage64+64*links; record:connection,lease,admission key7,last denial.
// The caller supplies a canonical identity or tagged unresolved bucket separately
// from the actual connection addresses retained in the cryptographic transcript.
global so_work=0;
global so_links=0;
global so_active=0;
global so_now=0;
global so_sm_work=0;
global so_sr_work=0;
global so_sr_entries=0;
global so_fault=0;
fn so_size(links) {if links<1 || links>4 {return -22;}return 64+64*links;}
fn so_overlap(p,n,q,size) {return p<q+size && q<p+n;}
fn so_external(p,n) {return sm_range(p,n) && !so_overlap(p,n,so_work,so_size(so_links)) && !so_overlap(p,n,sm_work,sm_size(sm_links)) && !so_overlap(p,n,sr_work,sr_size(sr_entries));}
fn so_slot(i) {return so_work+64+i*64;}
fn so_find(token) {let i=0;while i<so_links {let p=so_slot(i);if load64(p)==token && token>0 {return p;}i=i+1;}return 0;}
fn so_ready() {
    if !so_work {return -19;}if so_fault {return so_fault;}if sm_work!=so_sm_work || sr_work!=so_sr_work || sm_links!=so_links || sr_entries!=so_sr_entries || sm_active!=so_active {so_fault=-116;return so_fault;}
    let i=0;while i<so_links {let q=so_slot(i);let token=load64(q);if token {let p=sm_find(token);if !p {so_fault=-116;return so_fault;}let lease=load64(q+8);
        if lease {let r=sr_find(q+16);if !r || load64(r+32)!=lease {so_fault=-116;return so_fault;}}
        else {let state=load64(p+8);if state==2 || state==3 || state==6 || state==7 || state==8 {so_fault=-116;return so_fault;}}}i=i+1;}return 0;
}
fn so_clock(now) {return now>=so_now && now>=sm_now && now<=9223372036854745807 && sr_clock(now);}
fn so_init(work,capacity) {
    if so_work {return -16;}if !sm_work || !sr_work {return -19;}let size=so_size(sm_links);if sm_active {return -16;}
    if size<0 || capacity<size || !sm_range(work,capacity) || work&7 || so_overlap(work,size,sm_work,sm_size(sm_links)) || so_overlap(work,size,sr_work,sr_size(sr_entries)) || so_overlap(sm_work,sm_size(sm_links),sr_work,sr_size(sr_entries)) {return -22;}
    let now=sm_now;if sr_now>now {now=sr_now;}if now>9223372036854745807 || !sr_clock(now) {return -22;}
    // A lease without a session owner cannot silently become an idle identity.
    let i=0;while i<sr_entries {if load64(sr_slot(i)+32) {return -16;}i=i+1;}
    nb_zero(work,size);so_work=work;so_links=sm_links;so_active=0;so_now=now;so_sm_work=sm_work;so_sr_work=sr_work;so_sr_entries=sr_entries;so_fault=0;return 0;
}
fn so_release(q,now) {let lease=load64(q+8);if !lease {return 0;}let r=sr_finish(lease,1,now);if r {so_fault=r;return r;}store64(q+8,0);return 0;}
fn so_cleanup(now) {let i=0;while i<so_links {let q=so_slot(i);if load64(q) && load64(q+8) {let p=sm_find(load64(q));let state=load64(p+8);if state==4 || state==5 {let r=so_release(q,now);if r {return r;}}}i=i+1;}return 0;}
fn so_tick(now) {let r=so_ready();if r {return r;}if !so_clock(now) {return -22;}r=sm_tick(now);if r {return r;}so_now=now;return so_cleanup(now);}
fn so_open(token,role,local,peer,identity,config,now) {
    let r=so_ready();if r {return r;}if !so_external(local,7) || !so_external(peer,7) || !so_external(identity,7) || !sr_key(identity) || !so_external(config,8) || !so_clock(now) {return -22;}
    // Engine validation runs before any admission or caller-storage mutation.
    r=sm_open(token,role,local,peer,config,now);if r {return r;}let i=0;while i<so_links && load64(so_slot(i)) {i=i+1;}let q=so_slot(i);nb_zero(q,64);store64(q,token);nb_copy(q+16,identity,7);so_active=so_active+1;so_now=now;return so_tick(now);
}
fn so_admit(q,now) {if load64(q+8) {return 0;}let lease=sr_begin(q+16,now);if lease<0 {store64(q+24,lease);return lease;}store64(q+8,lease);store64(q+24,0);return 0;}
fn so_start(token,security_request,now) {
    let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}r=so_tick(now);if r {return r;}let p=sm_find(token);let state=load64(p+8);if state==5 {return -110;}
    if load64(p+16)!=security_request {return -22;}if state!=1 && state!=4 && !(state==8 && !security_request) {return -16;}if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 {return -75;}
    if security_request && load8(p+258)&4 && load8(p+256)==3 && !load8(p+257) && !(load64(p+24)&8) {return -22;}
    r=so_admit(q,now);if r {return r;}if security_request {r=sm_request_security(token,now);}else {r=sm_pair(token,now);}if r {let cleanup=so_release(q,now);if cleanup {return cleanup;}}return r;
}
fn so_pair(token,now) {return so_start(token,0,now);}
fn so_request_security(token,now) {return so_start(token,1,now);}
fn so_input(token,packet,size,now) {
    let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}if size<0 || size>65535 || (size && !so_external(packet,size)) {return -22;}r=so_tick(now);if r {return r;}let p=sm_find(token);let state=load64(p+8);if state==5 {return -110;}
    let code=0;if size {code=load8(packet);}let ignored_security=code==11 && size==2 && (load8(packet+1)&3)<=1 && !load64(p+16) && (state==2 || state==3 || state==6);
    if (code==1 || code==11) && !ignored_security && !load64(q+8) {
        if load64(p+168) {return -11;}if load64(p+192)==9223372036854775807 || (code==1 && load64(p+192)>=9223372036854775806) {return -75;}
        r=so_admit(q,now);if r {let reason=9;if r!=-11 && r!=-16 {reason=8;}return sm_fail(p,reason,1);}
    }
    r=sm_input(token,packet,size,now);let cleanup=so_cleanup(now);if cleanup {return cleanup;}return r;
}
fn so_consent(token,generation,accepted,now) {let r=so_ready();if r {return r;}if !so_find(token) {return -107;}if accepted!=0 && accepted!=1 {return -22;}r=so_tick(now);if r {return r;}r=sm_consent(token,generation,accepted,now);let cleanup=so_cleanup(now);if cleanup {return cleanup;}return r;}
fn so_packet_sent(token,generation,now) {let r=so_ready();if r {return r;}if !so_find(token) {return -107;}r=so_tick(now);if r {return r;}return sm_packet_sent(token,generation,now);}
fn so_next_packet(token) {let r=so_ready();if r {return r;}if !so_find(token) {return -107;}return sm_next_packet(token);}
fn so_next_event(token) {let r=so_ready();if r {return r;}if !so_find(token) {return -107;}return sm_next_event(token);}
fn so_event_consumed(token,generation,kind) {let r=so_ready();if r {return r;}if !so_find(token) {return -107;}return sm_event_consumed(token,generation,kind);}
// The future crypto owner must validate this triple immediately before using
// an input handed off by so_input. It does not mark authentication successful.
fn so_phase2(token,generation,lease,now) {
    let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}r=so_tick(now);if r {return r;}let p=sm_find(token);if load64(p+8)==5 {return -110;}if lease<=0 || load64(q+8)!=lease || load64(p+192)!=generation || load64(p+8)!=3 {return -116;}if load64(p+168) {return -11;}return 0;
}
fn so_failure(token,generation,lease,reason,reply,now) {
    if reason<1 || reason>15 || (reply!=0 && reply!=1) {return -22;}let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}r=so_tick(now);if r {return r;}let p=sm_find(token);if load64(p+8)==5 {return -110;}if lease<=0 || load64(q+8)!=lease || load64(p+192)!=generation {return -116;}
    r=sm_fail(p,reason,reply);let cleanup=so_cleanup(now);if cleanup {return cleanup;}return r;
}
fn so_close(token,now) {let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}r=so_tick(now);if r {return r;}r=so_release(q,now);if r {return r;}r=sm_close(token);if r {return r;}nb_zero(q,64);so_active=so_active-1;return 0;}
fn so_deinit() {if !so_work {return 0;}let r=so_ready();if r {return r;}if so_active {return -16;}nb_zero(so_work,so_size(so_links));so_work=0;so_links=0;so_active=0;so_now=0;so_sm_work=0;so_sr_work=0;so_sr_entries=0;so_fault=0;return 0;}
// Public256-byte snapshot:phase1 metadata224,lease8,admission key7,pad0,
// last admission error8,owner logical milliseconds8. Verified security stays0.
fn so_snapshot(token,out,capacity) {let r=so_ready();if r {return r;}let q=so_find(token);if !q {return -107;}if capacity<256 || !so_external(out,256) {return -22;}r=sm_snapshot(token,out,224);if r {return r;}nb_zero(out+224,32);store64(out+224,load64(q+8));nb_copy(out+232,q+16,7);store64(out+240,load64(q+24));store64(out+248,so_now);return 0;}
