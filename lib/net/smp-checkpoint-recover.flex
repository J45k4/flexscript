import "smp-checkpoint-store.flex";
// Boot-only recovery over two freshly read,unmounted raw settings-bank images.
// No media writes,formatting,provisioning or implicit anchor reset. The ledger
// is initialized empty;session/durable/commit owners must not be attached yet.
global cr_work=0;
global cr_entries=0;
global cr_ledger=0;
global cr_store=0;
global cr_bank=0;
global cr_generation=0;
global cr_active=0;
global cr_state=0;
global cr_error=0;
global cr_now=0;
global cr_anchor=0;
global cr_sequence=0;
global cr_revision=0;
global cr_floor=0;
global cr_io_token=0;
global cr_io_kind=0;
global cr_io_scope=0;
global cr_io_expected=0;
global cr_io_desired=0;
fn cr_size(entries) {if sr_size(entries)<0 {return -22;}return 432+80*entries;}
fn cr_frame() {return cr_work+128;}
fn cr_payload() {return cr_frame()+ck_size(64+40*cr_entries);}
fn cr_scratch() {return cr_payload()+64+40*cr_entries;}
fn cr_clear_io() {cr_io_token=0;cr_io_kind=0;cr_io_scope=0;cr_io_expected=0;cr_io_desired=0;return 0;}
fn cr_empty() {let i=0;while i<sr_entries {if load64(sr_slot(i)) {return 0;}i=i+1;}return 1;}
fn cr_ready() {
    if !cr_work {return -19;}if cr_error {return cr_error;}if so_work || sd_work || cs_work || sm_active {return -16;}
    if sr_work!=cr_ledger || sr_entries!=cr_entries || kv_work!=cr_store || kv_bank_size!=cr_bank {return -116;}
    if sr_min!=load64(cr_work) || sr_max!=load64(cr_work+8) || sr_decay!=load64(cr_work+16) || sr_floor!=load64(cr_work+24) || sr_now!=load64(cr_work+32) || !cr_empty() {return -116;}
    if kv_busy || kv_dirty || kv_fault {return -16;}if cr_state<=1 {if kv_mounted {return -16;}}else {if !kv_mounted || kv_generation!=cr_generation || kv_active!=cr_active {return -116;}}return 0;
}
fn cr_init(work,capacity,key,scope) {
    if cr_work {return -16;}if !sr_work || !kv_work {return -19;}if so_work || sd_work || cs_work || sm_active || !cr_empty() || kv_mounted || kv_busy || kv_dirty || kv_fault {return -16;}
    let size=cr_size(sr_entries);if capacity<size || work&7 || !so_external(work,capacity) || !so_external(key,16) || !so_external(scope,16) || !kv_outside(work,capacity) || !kv_outside(key,16) || !kv_outside(scope,16) || smp_overlap(work,capacity,key,16) || smp_overlap(work,capacity,scope,16) || smp_overlap(key,16,scope,16) {return -22;}
    nb_zero(work,size);store64(work,sr_min);store64(work+8,sr_max);store64(work+16,sr_decay);store64(work+24,sr_floor);store64(work+32,sr_now);nb_copy(work+64,key,16);nb_copy(work+80,scope,16);
    cr_work=work;cr_entries=sr_entries;cr_ledger=sr_work;cr_store=kv_work;cr_bank=kv_bank_size;cr_generation=0;cr_active=0;cr_state=0;cr_error=0;cr_now=sr_now;cr_anchor=0;cr_sequence=0;cr_revision=0;cr_clear_io();return 0;
}
// Provider completion must be quiesced before this can clear its scope view.
fn cr_fail(status) {if status>=0 {status=-5;}cr_error=status;cr_state=0;cr_sequence=0;cr_revision=0;cr_clear_io();nb_zero(cr_work,cr_size(cr_entries));return status;}
fn cr_start(now) {let r=cr_ready();if r {return r;}if cr_state || cr_io_token {return -16;}if now<cr_now || !sr_clock(now) {return -22;}cr_now=now;cr_state=1;return 1;}
fn cr_next_io() {
    if !cr_work {return -19;}if cr_error {return cr_error;}if cr_state==4 {return 0;}let r=cr_ready();if r {return r;}if cr_io_token {return cr_io_kind;}if !cr_state {return 0;}
    if cr_floor==9223372036854775807 {return cr_fail(-75);}cr_clear_io();cr_io_kind=4;if cr_state==2 {cr_io_kind=5;cr_io_expected=cr_anchor;cr_io_desired=cr_sequence;}cr_io_scope=cr_work+80;cr_floor=cr_floor+1;cr_io_token=cr_floor;return cr_io_kind;
}
// kv_valid has bounded and validated every record before this traversal.
fn cr_bank_frame(bank) {
    let p=kv_bank_buffer(bank);let at=0;let used=kv_u32(p+12);while at<used {let q=p+32+at;if load8(q)==9 && nb_equal(q+8,"smp.retry",9) {if load8(q+1)!=66 || kv_u32(q+4)!=ck_size(64+40*cr_entries) {return -74;}return q+17;}at=at+kv_record_size(q);}return 0;
}
fn cr_decode(frame,sequence,revision,now) {
    let bytes=64+40*cr_entries;let r=ck_open(cr_work+64,cr_work+80,sequence,revision,frame,ck_size(bytes),cr_payload(),bytes,cr_scratch(),112);if r<0 {return r;}r=sr_validate(cr_payload(),bytes,now);if r==-22 {return -74;}return r;
}
fn cr_scan(now) {
    let size=ck_size(64+40*cr_entries);let i=0;let valid=0;while i<2 {
        let bank=kv_bank_buffer(i);if kv_valid(bank) {valid=valid+1;let frame=cr_bank_frame(i);if frame<0 {return frame;}if frame {
            let sequence=load64(frame+8);if sequence<1 {return -74;}let r=cr_decode(frame,sequence,0,now);if r<0 {return r;}
            if sequence>cr_anchor+1 {return -116;}if cr_sequence==sequence && !nb_equal(cr_frame(),frame,size) {return -74;}
            if sequence>cr_sequence {nb_copy(cr_frame(),frame,size);cr_sequence=sequence;cr_revision=load64(frame+16);}
        }}i=i+1;
    }
    if !valid {if kv_blank(kv_bank_buffer(0),cr_bank) && kv_blank(kv_bank_buffer(1),cr_bank) {return -61;}return -74;}
    if !cr_sequence {if !cr_anchor {return -61;}return -116;}if cr_sequence<cr_anchor {return -116;}
    let r=cr_decode(cr_frame(),cr_sequence,cr_revision,now);if r<0 {return r;}r=kv_mount();if r {return r;}
    r=kv_get("smp.retry",9);if r || kv_value_type!=66 || kv_value_size!=size || !nb_equal(kv_value,cr_frame(),size) {return -116;}cr_generation=kv_generation;cr_active=kv_active;return 0;
}
// Only trusted-anchor operations are requested. Media is supplied as freshly
// read bank images before initialization. Import occurs only after confirm.
fn cr_io_done(token,result,value,now) {
    if !cr_work {return -19;}if cr_error {return cr_error;}if !cr_io_token || token!=cr_io_token {return -116;}if result>0 || now<cr_now || !sr_clock(now) {return -22;}
    let r=cr_ready();if r {return cr_fail(r);}cr_now=now;cr_clear_io();if result<0 {return cr_fail(result);}
    if cr_state==1 {
        if value<0 {return cr_fail(-116);}if value==9223372036854775807 {return cr_fail(-75);}cr_anchor=value;r=cr_scan(now);if r {return cr_fail(r);}cr_state=3;if cr_sequence==cr_anchor+1 {cr_state=2;}return 1;
    }
    if value!=cr_sequence {return cr_fail(-116);}if cr_state==2 {cr_state=3;return 1;}if cr_state!=3 {return cr_fail(-116);}
    r=kv_get("smp.retry",9);if r || kv_value_type!=66 || kv_value_size!=ck_size(64+40*cr_entries) || !nb_equal(kv_value,cr_frame(),kv_value_size) {return cr_fail(-116);}
    r=cr_decode(cr_frame(),cr_sequence,cr_revision,now);if r<0 {return cr_fail(r);}r=sr_import(cr_payload(),64+40*cr_entries,now);if r {return cr_fail(r);}cr_state=4;nb_zero(cr_work,cr_size(cr_entries));return 0;
}
fn cr_deinit() {if !cr_work {return 0;}if cr_error {return cr_error;}if cr_io_token || (cr_state && cr_state!=4) {return -16;}nb_zero(cr_work,cr_size(cr_entries));cr_work=0;cr_entries=0;cr_ledger=0;cr_store=0;cr_bank=0;cr_generation=0;cr_active=0;cr_state=0;cr_now=0;cr_anchor=0;cr_sequence=0;cr_revision=0;cr_clear_io();return 0;}
