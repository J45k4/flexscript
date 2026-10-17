import "smp-checkpoint-pending.flex";
import "../storage/settings.flex";
// Serialized settings commit owner. Kinds1/2/3 are actual kv erase/program/read
// operations. Kind4 loads the trusted anchor;kind5 atomically compares/advances
// it. A test or RAM anchor is not physical restart rollback protection.
// Initialize only after verified restore/provisioning. No implicit formatting,
// bootstrap,anchor reset,recovery or other concurrent settings writer is allowed.
global cs_work=0;
global cs_entries=0;
global cs_gate=0;
global cs_store=0;
global cs_bank=0;
global cs_generation=0;
global cs_state=0;
global cs_error=0;
global cs_sequence=0;
global cs_revision=0;
global cs_now=0;
global cs_floor=0;
global cs_io_token=0;
global cs_io_kind=0;
global cs_io_offset=0;
global cs_io_buffer=0;
global cs_io_size=0;
global cs_io_expected=0;
global cs_io_desired=0;
global cs_io_scope=0;
fn cs_size(entries) {let n=sd_size(entries);if n<0 {return n;}return 480+80*entries;}
fn cs_frame() {return cs_work+128;}
fn cs_scratch() {return cs_frame()+ck_size(64+40*cs_entries);}
fn cs_clear_io() {cs_io_token=0;cs_io_kind=0;cs_io_offset=0;cs_io_buffer=0;cs_io_size=0;cs_io_expected=0;cs_io_desired=0;cs_io_scope=0;return 0;}
fn cs_clear_frame() {nb_zero(cs_frame(),cs_size(cs_entries)-128);return 0;}
fn cs_ready() {
    if !cs_work {return -19;}if cs_error {return cs_error;}
    if sd_work!=cs_gate || sd_entries!=cs_entries || kv_work!=cs_store || kv_bank_size!=cs_bank {return -116;}return sd_ready();
}
fn cs_init(work,capacity,key,scope) {
    if cs_work {return -16;}let r=sd_ready();if r {return r;}if !kv_mounted || kv_busy || kv_dirty || kv_fault {return -16;}
    let size=cs_size(sd_entries);if capacity<size || work&7 || !sd_external(work,capacity) || !sd_external(key,16) || !sd_external(scope,16) || !kv_outside(work,capacity) || !kv_outside(key,16) || !kv_outside(scope,16) || smp_overlap(work,capacity,key,16) || smp_overlap(work,capacity,scope,16) || smp_overlap(key,16,scope,16) {return -22;}
    nb_zero(work,size);nb_copy(work+64,key,16);nb_copy(work+80,scope,16);cs_work=work;cs_entries=sd_entries;cs_gate=sd_work;cs_store=kv_work;cs_bank=kv_bank_size;cs_generation=kv_generation;cs_state=0;cs_error=0;cs_sequence=0;cs_revision=0;cs_now=0;cs_clear_io();return 0;
}
// Only call after the outstanding provider operation has finished/quiesced.
// An uncertain advance is terminal;recovery must reload the trusted anchor.
fn cs_fail(status,now) {
    if status>=0 {status=-5;}if cs_state==2 && kv_work==cs_store && kv_busy {kv_io_fail(status);}cs_error=status;cs_state=0;cs_clear_io();cs_clear_frame();
    if sd_work==cs_gate && sd_busy && sd_frozen_sequence==cs_sequence && sd_frozen_revision==cs_revision {let r=sd_done(cs_sequence,cs_revision,status,now);if r!=status {sd_fault(status);}}return status;
}
fn cs_start(now) {
    let r=cs_ready();if r {return r;}if cs_state || cs_io_token {return -16;}if !so_clock(now) {return -22;}
    if !kv_mounted || kv_busy || kv_dirty || kv_fault || kv_generation!=cs_generation {return -16;}
    if !sd_busy {r=sd_checkpoint(now);if r<=0 {return r;}}r=sd_checkpoint_peek();if r<0 {return r;}if !r {return -116;}
    cs_sequence=sd_checkpoint_sequence;cs_revision=sd_checkpoint_revision;cs_now=now;
    r=ck_pending_seal(cs_work+64,cs_work+80,cs_frame(),ck_size(64+40*cs_entries),cs_scratch(),ck_seal_work(64+40*cs_entries));if r<0 {return cs_fail(r,now);}cs_state=1;return 1;
}
// Repeated peeks return the same token and immutable request. Do not touch
// settings,workspace or provider buffers while the request is outstanding.
fn cs_next_io() {
    let r=cs_ready();if r {return r;}if cs_io_token {return cs_io_kind;}if !cs_state {return 0;}
    if cs_floor==9223372036854775807 {return cs_fail(-75,cs_now);}
    cs_clear_io();if cs_state==1 || cs_state==4 {cs_io_kind=4;}
    else if cs_state==3 {cs_io_kind=5;cs_io_expected=cs_sequence-1;cs_io_desired=cs_sequence;}
    else if cs_state==2 {r=kv_next_io();if r<1 {return cs_fail(-5,cs_now);}cs_io_kind=r;cs_io_offset=kv_io_offset;cs_io_buffer=kv_io_buffer;cs_io_size=kv_io_size;}
    else {return cs_fail(-116,cs_now);}
    if cs_io_kind>=4 {cs_io_scope=cs_work+80;}cs_floor=cs_floor+1;cs_io_token=cs_floor;return cs_io_kind;
}
// settings has compared the entire body readback,then the programmed commit
// marker. Authenticate those exact verified bytes before advancing the anchor.
fn cs_media_verified(now) {
    if kv_busy || kv_fault || kv_dirty || !kv_mounted || kv_verified!=32+kv_used || kv_generation!=((cs_generation+1)&4294967295) {return cs_fail(-5,now);}
    let r=kv_get("smp.retry",9);if r || kv_value_type!=66 || kv_value_size!=ck_size(64+40*cs_entries) {return cs_fail(-74,now);}
    r=ck_pending_verify(cs_work+64,cs_work+80,kv_value,kv_value_size,cs_scratch(),ck_seal_work(64+40*cs_entries));if r {return cs_fail(r,now);}cs_generation=kv_generation;cs_state=3;return 1;
}
// Media result is its exact byte count and value must be0. Anchor result is0
// (negative errors propagate),with the trusted loaded/advanced value in value.
// Even a successful CAS is confirmed by another trusted load before sd_done.
fn cs_io_done(token,result,value,now) {
    if !cs_work {return -19;}if cs_error {return cs_error;}if !cs_io_token || token!=cs_io_token {return -116;}if now<cs_now || !so_clock(now) {return -22;}
    let kind=cs_io_kind;if (kind>=4 && result>0) || (kind<4 && value) {return -22;}
    let r=cs_ready();if r {return cs_fail(r,now);}cs_now=now;cs_clear_io();if result<0 {return cs_fail(result,now);}
    if kind<4 {r=kv_io_done(result);if r<0 {return cs_fail(r,now);}if !r {return cs_media_verified(now);}return 1;}
    if cs_state==1 {
        if value<0 || value!=cs_sequence-1 || value!=sd_sequence {return cs_fail(-116,now);}
        if !kv_mounted || kv_busy || kv_dirty || kv_fault || kv_generation!=cs_generation {return cs_fail(-16,now);}
        r=kv_set("smp.retry",9,66,cs_frame(),ck_size(64+40*cs_entries));if r {return cs_fail(r,now);}r=kv_commit();if r!=1 {return cs_fail(-5,now);}cs_state=2;return 1;
    }
    if value!=cs_sequence {return cs_fail(-116,now);}if cs_state==3 {cs_state=4;return 1;}
    if cs_state!=4 {return cs_fail(-116,now);}r=sd_done(cs_sequence,cs_revision,0,now);if r {return cs_fail(r,now);}cs_state=0;cs_sequence=0;cs_revision=0;cs_clear_frame();return 0;
}
fn cs_deinit() {if !cs_work {return 0;}if cs_error {return cs_error;}if cs_state || cs_io_token {return -16;}nb_zero(cs_work,cs_size(cs_entries));cs_work=0;cs_entries=0;cs_gate=0;cs_store=0;cs_bank=0;cs_generation=0;cs_sequence=0;cs_revision=0;cs_now=0;cs_clear_io();return 0;}
