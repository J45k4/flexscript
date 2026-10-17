import "bytes.flex";
// Pairing admission ledger. Owner serializes calls and supplies canonical peer
// admission keys:canonical public/static identity,or kind2+six zeros for the
// single unresolved-peer bucket. Kind2 is internal metadata,never an address.
// Caller storage128+64*entries. No allocation, radio, crypto or persistence I/O.
// Record:used,interval,notBefore,nextDecay,lease,identity7,padding/reserved16.
global sr_work=0;
global sr_entries=0;
global sr_min=0;
global sr_max=0;
global sr_decay=0;
global sr_now=0;
global sr_floor=0;
fn sr_size(entries) {if entries<1 || entries>32 {return -22;}return 128+64*entries;}
fn sr_range(p,n) {return p>0 && n>=0 && p<=9223372036854775807-n;}
fn sr_external(p,n) {return sr_range(p,n) && !(p<sr_work+sr_size(sr_entries) && sr_work<p+n);}
fn sr_clock(now) {return now>=sr_now && now>=0 && now<=9223372036854775807-sr_max-sr_decay;}
fn sr_identity(p) {return sr_external(p,7) && (load8(p)==0 || (load8(p)==1 && (load8(p+6)&192)==192));}
// Preserve the canonical identity validator for callers that require an address.
fn sr_key(p) {return sr_identity(p) || (sr_external(p,7) && load8(p)==2 && sr_zero(p+1,6));}
fn sr_slot(i) {return sr_work+128+i*64;}
fn sr_find(identity) {let i=0;while i<sr_entries {let p=sr_slot(i);if load64(p) && nb_equal(p+40,identity,7) {return p;}i=i+1;}return 0;}
fn sr_wait_at(p) {let until=load64(p+16);if until>sr_now {return until-sr_now;}return 0;}
fn sr_age(p) {
    let delay=load64(p+8);let next=load64(p+24);if !delay || !next || sr_now<next {return 0;}
    let periods=(sr_now-next)/sr_decay+1;let n=periods;while n && delay {if delay<=sr_min {delay=0;}else {delay=delay/2;if delay<sr_min {delay=sr_min;}}n=n-1;}
    store64(p+8,delay);if delay {store64(p+24,sr_now+(sr_decay-(sr_now-next)%sr_decay));}else {store64(p+24,0);}return 0;
}
fn sr_grow(delay) {if !delay {return sr_min;}if delay>=sr_max || delay>sr_max/2 {return sr_max;}return delay*2;}
fn sr_init(work,capacity,entries,min_wait,max_wait,decay_period,now) {
    if sr_work {return -16;}let size=sr_size(entries);if size<0 || capacity<size || !sr_range(work,capacity) || work&7 || min_wait<1 || min_wait>3600000 || max_wait<min_wait || max_wait>86400000 || decay_period<1 || decay_period>604800000 || now<0 || now>9223372036854775807-max_wait-decay_period {return -22;}
    nb_zero(work,size);sr_work=work;sr_entries=entries;sr_min=min_wait;sr_max=max_wait;sr_decay=decay_period;sr_now=now;return 0;
}
// Return milliseconds still blocked,0 ready,-16 another live attempt for this
// identity. A denied query never restarts the wait or raises the penalty.
fn sr_wait(identity,now) {
    if !sr_work {return -19;}if !sr_key(identity) || !sr_clock(now) {return -22;}sr_now=now;let p=sr_find(identity);if !p {return 0;}sr_age(p);if load64(p+32) {return -16;}return sr_wait_at(p);
}
// A positive result is an attempt lease, not authenticated link security.
fn sr_begin(identity,now) {
    if !sr_work {return -19;}if !sr_key(identity) || !sr_clock(now) {return -22;}if sr_floor==9223372036854775807 {return -75;}sr_now=now;let p=sr_find(identity);
    if p {sr_age(p);if load64(p+32) {return -16;}if sr_wait_at(p) {return -11;}}
    else {let i=0;while i<sr_entries && !p {let q=sr_slot(i);if !load64(q) {p=q;}else {sr_age(q);if !load64(q+32) && !load64(q+8) && !sr_wait_at(q) {p=q;}}i=i+1;}if !p {return -105;}nb_zero(p,64);store64(p,1);nb_copy(p+40,identity,7);}
    sr_floor=sr_floor+1;store64(p+32,sr_floor);return sr_floor;
}
// result0 requires a completed, verified pairing. Any failure, timeout, abort
// or disconnect uses result1. Success cannot erase previous failure history.
fn sr_finish(lease,result,now) {
    if !sr_work {return -19;}if lease<=0 || (result!=0 && result!=1) || !sr_clock(now) {return -22;}let i=0;let p=0;while i<sr_entries && !p {let q=sr_slot(i);if load64(q) && load64(q+32)==lease {p=q;}i=i+1;}if !p {return -116;}
    sr_now=now;sr_age(p);if result {let delay=sr_grow(load64(p+8));store64(p+8,delay);store64(p+16,now+delay);store64(p+24,now+sr_decay);}store64(p+32,0);return 0;
}
fn sr_deinit(now) {
    if !sr_work {return 0;}if !sr_clock(now) {return -22;}sr_now=now;let i=0;while i<sr_entries {let p=sr_slot(i);if load64(p) {sr_age(p);if load64(p+32) || load64(p+8) || sr_wait_at(p) {return -16;}}i=i+1;}
    nb_zero(sr_work,sr_size(sr_entries));sr_work=0;sr_entries=0;sr_min=0;sr_max=0;sr_decay=0;sr_now=0;return 0;
}
fn sr_checkpoint_size() {if !sr_work {return -19;}return 64+40*sr_entries;}
// Canonical little-endian codec. Storage must authenticate/anti-rollback this
// blob; the codec does not. Durations restart conservatively on restore, so no
// trusted wall clock is required. Persist an admitted attempt before proceeding.
fn sr_export(out,capacity,now) {
    if !sr_work {return -19;}let size=sr_checkpoint_size();if capacity<size || !sr_external(out,size) || !sr_clock(now) {return -22;}sr_now=now;nb_zero(out,size);nb_copy(out,"SMPTRY01",8);store64(out+8,sr_entries);store64(out+16,sr_min);store64(out+24,sr_max);store64(out+32,sr_decay);store64(out+40,sr_floor);let count=0;let i=0;
    while i<sr_entries {let p=sr_slot(i);if load64(p) {sr_age(p);if load64(p+8) || sr_wait_at(p) || load64(p+32) {let q=out+64+count*40;nb_copy(q,p+40,7);store64(q+8,load64(p+8));store64(q+16,sr_wait_at(p));if load64(p+8) {store64(q+24,load64(p+24)-now);}store64(q+32,load64(p+32)!=0);count=count+1;}}i=i+1;}store64(out+48,count);return size;
}
fn sr_zero(p,size) {let i=0;while i<size {if load8(p+i) {return 0;}i=i+1;}return 1;}
fn sr_delay_valid(value) {return value==0 || (value>=sr_min && value<=sr_max);}
// Import only into an empty ledger, with exact capacity/policy. Validate all
// bytes and duplicate identities before changing storage or the logical clock.
// An in-flight exported attempt becomes a failed attempt after a restart.
// Read-only semantic preflight for restore;returns the validated record count.
fn sr_validate(input,size,now) {
    if !sr_work {return -19;}if size!=sr_checkpoint_size() || !sr_external(input,size) || !sr_clock(now) {return -22;}
    let i=0;while i<sr_entries {if load64(sr_slot(i)) {return -16;}i=i+1;}
    if !nb_equal(input,"SMPTRY01",8) || load64(input+8)!=sr_entries || load64(input+16)!=sr_min || load64(input+24)!=sr_max || load64(input+32)!=sr_decay || load64(input+40)<0 || load64(input+48)<0 || load64(input+48)>sr_entries || load64(input+56) {return -22;}if load64(input+40)<sr_floor {return -116;}
    let count=load64(input+48);i=0;while i<count {let q=input+64+i*40;let delay=load64(q+8);let wait=load64(q+16);let decay=load64(q+24);let live=load64(q+32);
        if !sr_key(q) || load8(q+7) || !sr_delay_valid(delay) || wait<0 || wait>sr_max || decay<0 || decay>sr_decay || (delay && !decay) || (!delay && decay) || (live!=0 && live!=1) || (live && (wait || !load64(input+40))) || (!delay && !wait && !live) {return -22;}
        let j=0;while j<i {if nb_equal(input+64+j*40,q,7) {return -22;}j=j+1;}i=i+1;}
    if !sr_zero(input+64+count*40,(sr_entries-count)*40) {return -22;}
    return count;
}
fn sr_import(input,size,now) {
    let count=sr_validate(input,size,now);if count<0 {return count;}let i=0;
    sr_now=now;sr_floor=load64(input+40);i=0;while i<count {let q=input+64+i*40;let p=sr_slot(i);store64(p,1);store64(p+8,load64(q+8));store64(p+16,now+load64(q+16));if load64(q+8) {store64(p+24,now+load64(q+24));}nb_copy(p+40,q,7);
        if load64(q+32) {let delay=sr_grow(load64(p+8));store64(p+8,delay);store64(p+16,now+delay);store64(p+24,now+sr_decay);}i=i+1;}return 0;
}

// Copy,never move,history before publishing or forgetting an identity binding.
// Both keys must be idle. The larger interval/wait/decay deadline is retained;
// neither a successful reconnect nor an address change can erase a penalty.
fn sr_inherit(source,target,now) {
    if !sr_work {return -19;}if !sr_key(source) || !sr_key(target) || !sr_clock(now) {return -22;}let from=sr_find(source);let to=sr_find(target);
    if (from && load64(from+32)) || (to && load64(to+32)) {return -16;}sr_now=now;if from {sr_age(from);}if to && to!=from {sr_age(to);}if !from || from==to || (!load64(from+8) && !sr_wait_at(from)) {return 0;}
    if !to {let i=0;while i<sr_entries && !to {let q=sr_slot(i);if !load64(q) {to=q;}else {sr_age(q);if !load64(q+32) && !load64(q+8) && !sr_wait_at(q) {to=q;}}i=i+1;}if !to {return -105;}nb_zero(to,64);store64(to,1);nb_copy(to+40,target,7);}
    let interval=load64(from+8);if load64(to+8)>interval {interval=load64(to+8);}let until=load64(from+16);if load64(to+16)>until {until=load64(to+16);}let decay=load64(from+24);if load64(to+24)>decay {decay=load64(to+24);}
    store64(to+8,interval);store64(to+16,until);if interval {store64(to+24,decay);}else {store64(to+24,0);}return 0;
}
