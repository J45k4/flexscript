import "smp-session.flex";
// Serialized durable-effect barrier. The owner and ledger must be initialized
// first. All session/ledger mutations use this API while attached. Storage must
// commit the exact copied checkpoint AND its trusted sequence before sd_done.
// This module does not authenticate bytes,perform I/O or invent a rollback anchor.
// Work:header64,shadow records64*entries,key revisions8*entries,checkpoint.
global sd_work=0;
global sd_entries=0;
global sd_owner=0;
global sd_engine=0;
global sd_link_count=0;
global sd_ledger=0;
global sd_revision=0;
global sd_revision_floor=0;
global sd_durable=0;
global sd_sequence=0;
global sd_sequence_floor=0;
global sd_seen_floor=0;
global sd_busy=0;
global sd_frozen_revision=0;
global sd_frozen_sequence=0;
global sd_error=0;
global sd_sensitive_work=0;
global sd_sensitive_bytes=0;
global sd_checkpoint_buffer=0;
global sd_checkpoint_bytes=0;
global sd_checkpoint_revision=0;
global sd_checkpoint_sequence=0;
fn sd_size(entries) {if entries<1 || entries>32 {return -22;}return 128+112*entries;}
fn sd_shadow(i) {return sd_work+64+i*64;}
fn sd_key_revision(i) {return sd_work+64+sd_entries*64+i*8;}
fn sd_frozen() {return sd_work+64+sd_entries*72;}
fn sd_external(p,n) {return so_external(p,n) && !so_overlap(p,n,sd_work,sd_size(sd_entries)) && (!sd_sensitive_work || !so_overlap(p,n,sd_sensitive_work,sd_sensitive_bytes));}
fn sd_views() {sd_checkpoint_buffer=0;sd_checkpoint_bytes=0;sd_checkpoint_revision=0;sd_checkpoint_sequence=0;return 0;}
fn sd_fault(status) {sd_error=status;if sd_sensitive_work {nb_zero(sd_sensitive_work,sd_sensitive_bytes);}sm_views(sm_packet_connection);sm_views(sm_event_connection);if sd_engine && sd_link_count>=1 && sd_link_count<=4 {let i=0;while i<sd_link_count {nb_zero(sd_engine+256+i*1536+512,1024);i=i+1;}}return status;}
fn sd_ready() {if !sd_work {return -19;}if sd_error {return sd_error;}if so_work!=sd_owner || sm_work!=sd_engine || sm_links!=sd_link_count || sr_work!=sd_ledger || sr_entries!=sd_entries {return sd_fault(-116);}let r=so_ready();if r {return sd_fault(r);}return r;}
fn sd_init(work,capacity,sequence) {
    if sd_work {return -16;}let r=so_ready();if r {return r;}if so_active {return -16;}let size=sd_size(sr_entries);if size<0 || capacity<size || !so_external(work,capacity) || work&7 || sequence<0 {return -22;}if sequence<sd_sequence_floor {return -116;}if sequence==9223372036854775807 || sd_revision_floor==9223372036854775807 {return -75;}
    nb_zero(work,size);sd_work=work;sd_entries=sr_entries;sd_owner=so_work;sd_engine=sm_work;sd_link_count=sm_links;sd_ledger=sr_work;sd_seen_floor=sr_floor;sd_revision_floor=sd_revision_floor+1;sd_revision=sd_revision_floor;sd_durable=0;sd_sequence=sequence;sd_sequence_floor=sequence;sd_busy=0;sd_frozen_revision=0;sd_frozen_sequence=0;sd_error=0;sd_views();let i=0;while i<sd_entries {nb_copy(sd_shadow(i),sr_slot(i),64);store64(sd_key_revision(i),sd_revision);i=i+1;}return 0;
}
// One optional caller-owned sensitive extent for keys that precede an attempt.
// Register before opening connections;unregister after all owners have closed.
// Its memory stays reserved until explicit release andis erased onfault.
fn sd_sensitive_register(work,size) {
    let r=sd_ready();if r {return r;}if sd_sensitive_work || so_active || sd_busy {return -16;}if size<8 || size>65536 || work&7 || !sd_external(work,size) {return -22;}nb_zero(work,size);sd_sensitive_work=work;sd_sensitive_bytes=size;return 0;
}
fn sd_sensitive_release(work) {
    let r=sd_ready();if r {return r;}if !sd_sensitive_work || sd_sensitive_work!=work {return -116;}if so_active || sd_busy {return -16;}nb_zero(sd_sensitive_work,sd_sensitive_bytes);sd_sensitive_work=0;sd_sensitive_bytes=0;return 0;
}
// Capture one revision for a whole ledger mutation batch. Quiet decay is also
// recorded,without turning elapsed milliseconds alone into repeated writes.
fn sd_sync() {
    let r=sd_ready();if r {return r;}if sr_floor<sd_seen_floor {return sd_fault(-116);}let changed=sr_floor!=sd_seen_floor;let i=0;while i<sd_entries {if !nb_equal(sd_shadow(i),sr_slot(i),64) {changed=1;}i=i+1;}if !changed {return 0;}if sd_revision_floor==9223372036854775807 {return sd_fault(-75);}
    sd_revision_floor=sd_revision_floor+1;sd_revision=sd_revision_floor;sd_seen_floor=sr_floor;i=0;
    while i<sd_entries {let old=sd_shadow(i);let current=sr_slot(i);if !nb_equal(old,current,64) {let j=0;while j<so_links {let q=so_slot(j);if load64(q) && ((load64(old) && nb_equal(q+16,old+40,7)) || (load64(current) && nb_equal(q+16,current+40,7))) {sm_views(load64(q));}j=j+1;}nb_copy(old,current,64);store64(sd_key_revision(i),sd_revision);}i=i+1;}return 0;
}
fn sd_required(token) {let q=so_find(token);if !q {return -107;}let p=sr_find(q+16);if !p {return sd_revision;}let i=(p-sr_work-128)/64;return load64(sd_key_revision(i));}
fn sd_allowed(token) {let required=sd_required(token);if required<0 {return required;}if required>sd_durable {return -11;}return 0;}
fn sd_tick(now) {let r=sd_ready();if r {return r;}r=so_tick(now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_open(token,role,local,peer,key,config,now) {let r=sd_ready();if r {return r;}if !sd_external(local,7) || !sd_external(peer,7) || !sd_external(key,7) || !sd_external(config,8) {return -22;}r=so_open(token,role,local,peer,key,config,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_pair(token,now) {let r=sd_ready();if r {return r;}r=so_pair(token,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_request_security(token,now) {let r=sd_ready();if r {return r;}r=so_request_security(token,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_input(token,packet,size,now) {
    let r=sd_ready();if r {return r;}let q=so_find(token);if !q {return -107;}if size<0 || size>65535 || (size && !sd_external(packet,size)) {return -22;}r=sd_tick(now);if r {return r;}
    let code=0;if size {code=load8(packet);}if load64(q+8) && code>=1 && code<=14 && code!=5 {r=sd_allowed(token);if r {return r;}}
    r=so_input(token,packet,size,now);let capture=sd_sync();if capture {return capture;}if r==2 {let allowed=sd_allowed(token);if allowed {return allowed;}}return r;
}
fn sd_consent(token,generation,accepted,now) {let r=sd_ready();if r {return r;}if accepted!=0 && accepted!=1 {return -22;}if !so_find(token) {return -107;}r=sd_tick(now);if r {return r;}if accepted {r=sd_allowed(token);if r {return r;}}r=so_consent(token,generation,accepted,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_packet_sent(token,generation,now) {let r=sd_ready();if r {return r;}r=so_packet_sent(token,generation,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_event_consumed(token,generation,kind) {let r=sd_ready();if r {return r;}return so_event_consumed(token,generation,kind);}
fn sd_next_packet(token) {let r=sd_sync();if r {return r;}let p=sm_find(token);if !so_find(token) {return -107;}if load64(p+8)==5 {return -110;}if !load64(p+168) {return 0;}r=sd_allowed(token);if r {return r;}return so_next_packet(token);}
fn sd_next_event(token) {let r=sd_sync();if r {return r;}let p=sm_find(token);if !so_find(token) {return -107;}if !load64(p+184) {return 0;}r=sd_allowed(token);if r {return r;}return so_next_event(token);}
fn sd_phase2(token,generation,lease,now) {let r=sd_ready();if r {return r;}r=so_phase2(token,generation,lease,now);let capture=sd_sync();if capture {return capture;}if r {return r;}return sd_allowed(token);}
fn sd_failure(token,generation,lease,reason,reply,now) {let r=sd_ready();if r {return r;}r=so_failure(token,generation,lease,reason,reply,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_close(token,now) {let r=sd_ready();if r {return r;}r=so_close(token,now);let capture=sd_sync();if capture {return capture;}return r;}
fn sd_inherit(source,target,now) {let r=sd_ready();if r {return r;}if !sd_external(source,7) || !sd_external(target,7) {return -22;}if !so_clock(now) {return -22;}r=sr_inherit(source,target,now);let capture=sd_sync();if capture {return capture;}return r;}
// Freeze at most one immutable payload. Later mutations retain a newer dirty
// revision while the storage owner holds this exact sequence/revision lease.
fn sd_checkpoint(now) {
    let r=sd_tick(now);if r {return r;}if sd_busy {return -16;}if sd_revision<=sd_durable {return 0;}if sd_sequence==9223372036854775807 {return sd_fault(-75);}
    r=sr_export(sd_frozen(),sr_checkpoint_size(),now);if r<0 {return r;}let capture=sd_sync();if capture {nb_zero(sd_frozen(),sr_checkpoint_size());return capture;}sd_busy=1;sd_frozen_revision=sd_revision;sd_frozen_sequence=sd_sequence+1;return 1;
}
fn sd_checkpoint_peek() {let r=sd_ready();if r {return r;}if !sd_busy {return 0;}sd_checkpoint_buffer=sd_frozen();sd_checkpoint_bytes=sr_checkpoint_size();sd_checkpoint_revision=sd_frozen_revision;sd_checkpoint_sequence=sd_frozen_sequence;return sd_checkpoint_bytes;}
// Storage acknowledgment is valid only after exact readback/authentication and
// trusted counter advancement. Apply timeouts before potentially releasing it.
fn sd_done(sequence,revision,status,now) {
    let r=sd_ready();if r {return r;}if status>0 {return -22;}if !sd_busy || sequence!=sd_frozen_sequence || revision!=sd_frozen_revision {return -116;}if !so_clock(now) {return -22;}r=sd_tick(now);if r {return r;}
    if status<0 {sd_fault(status);sd_busy=0;sd_frozen_revision=0;sd_frozen_sequence=0;nb_zero(sd_frozen(),sr_checkpoint_size());sd_views();return status;}
    sd_sequence=sequence;sd_sequence_floor=sequence;sd_durable=revision;sd_busy=0;sd_frozen_revision=0;sd_frozen_sequence=0;nb_zero(sd_frozen(),sr_checkpoint_size());sd_views();return 0;
}
fn sd_deinit() {if !sd_work {return 0;}let r=sd_sync();if r {return r;}if so_active || sd_busy || sd_sensitive_work || sd_revision>sd_durable {return -16;}nb_zero(sd_work,sd_size(sd_entries));sd_work=0;sd_entries=0;sd_owner=0;sd_engine=0;sd_link_count=0;sd_ledger=0;sd_revision=0;sd_durable=0;sd_sequence=0;sd_seen_floor=0;sd_frozen_revision=0;sd_frozen_sequence=0;sd_error=0;sd_views();return 0;}
// Debug metadata does not authorize protocol effects. The final16 bytes expose
// required/durable revisions after the ordinary256-byte copied owner snapshot.
fn sd_snapshot(token,out,capacity) {let r=sd_sync();if r {return r;}if capacity<272 || !sd_external(out,272) {return -22;}r=so_snapshot(token,out,256);if r {return r;}store64(out+256,sd_required(token));store64(out+264,sd_durable);return 0;}
