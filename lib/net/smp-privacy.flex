import "smp-session.flex";
import "smp-crypto.flex";
// Host privacy lookup over an immutable,owner-supplied bond view. No allocation,
// entropy,radio,trust promotion or persistence. Serialize view/session changes.
// Record32:identity7,flags1(IRK present1,verified saved-key reconnect2),IRK16,
// reserved zero8. A newly distributed identity must remain pending(flags0/1).
// Output32:admission key7,reserved0,candidate identity7,status0/1pending/2known,
// 1-based record hint8,verified link security8(always0). Unknown key is2+zeros.
// Resolution recognizes an identity claim; it never authenticates the link.
fn sp_bits(p,n) {let zero=1;let ones=1;let i=0;while i<n {let value=load8(p+i);let mask=255;if i==n-1 {mask=63;value=value&mask;}if value {zero=0;}if value!=mask {ones=0;}i=i+1;}return !zero && !ones;}
fn sp_address(p) {if !smp_range(p,7) {return 0;}if load8(p)==0 {return 1;}if load8(p)!=1 {return 0;}let kind=load8(p+6)&192;if kind==128 {return 0;}if kind==64 {return sp_bits(p+4,3);}return sp_bits(p+1,6);}
fn sp_identity(p) {return sp_address(p) && (load8(p)==0 || (load8(p+6)&192)==192);}
fn sp_table(records,count) {
    if count<0 || count>32 || (count && !smp_range(records,count*32)) {return 0;}let i=0;while i<count {let p=records+i*32;let flags=load8(p+7);
        if !sp_identity(p) || flags>3 || !sr_zero(p+24,8) || (!(flags&1) && !sr_zero(p+8,16)) {return 0;}let j=0;while j<i {if nb_equal(p,records+j*32,7) {return 0;}j=j+1;}i=i+1;}return 1;
}
fn sp_done(work,result) {nb_zero(work,608);return result;}
fn sp_resolve(peer,records,count,out,work,capacity) {
    if count<0 || count>32 || capacity<608 || !smp_range(work,capacity) || !smp_range(out,32) || !sp_address(peer) || !sp_table(records,count) {return -22;}
    if smp_overlap(work,608,peer,7) || smp_overlap(work,608,records,count*32) || smp_overlap(work,608,out,32) || smp_overlap(out,32,peer,7) || smp_overlap(out,32,records,count*32) {return -22;}
    nb_zero(work,608);store8(work+512,2);let rpa=load8(peer)==1 && (load8(peer+6)&192)==64;let direct=sp_identity(peer);let matches=0;let i=0;
    while i<count {let p=records+i*32;let flags=load8(p+7);let match=0;if direct {match=nb_equal(peer,p,7);}else if rpa && flags&1 {let r=smp_ah(p+8,peer+4,work+544,work,512);if r {return sp_done(work,r);}match=smp_equal(work+544,peer+1,3);}
        if match {matches=matches+1;nb_copy(work+520,p,7);let status=1;if flags&2 {status=2;nb_copy(work+512,p,7);}store8(work+527,status);store64(work+528,i+1);}i=i+1;}
    if matches>1 {return sp_done(work,-129);}nb_copy(out,work+512,32);return sp_done(work,0);
}
// Resolve then open under the same serialized view. Scratch640 includes a
// temporary result32 after the resolver's608 bytes; all640 are wiped on exit
// once resolution starts. Actual connection addresses remain unchanged.
fn sp_open(token,role,local,peer,records,count,config,work,capacity,now) {
    let r=so_ready();if r {return r;}if count<0 || count>32 || capacity<640 || !so_external(work,capacity) || !so_external(local,7) || !so_external(peer,7) || !so_external(config,8) || (count && !so_external(records,count*32)) {return -22;}
    if smp_overlap(work,640,local,7) || smp_overlap(work,640,peer,7) || smp_overlap(work,640,config,8) || smp_overlap(work,640,records,count*32) || !sp_address(local) || !sp_address(peer) || !sm_config(config) || role<0 || role>1 || token<=sm_token_floor || !so_clock(now) {return -22;}if so_active==so_links {return -105;}
    r=sp_resolve(peer,records,count,work+608,work,608);if !r {r=so_open(token,role,local,peer,work+608,config,now);}nb_zero(work,640);return r;
}
// Before publishing a newly confirmed identity (or before forgetting one),
// conservatively inherit history. This does not verify a reconnect or modify a
// bond view. The real security/storage owner supplies that evidence separately.
fn sp_inherit_identity(identity,to_identity,now,work,capacity) {
    if !sr_work {return -19;}if to_identity!=0 && to_identity!=1 {return -22;}if capacity<16 || !so_external(work,capacity) || !so_external(identity,7) || !sp_identity(identity) || smp_overlap(work,16,identity,7) {return -22;}
    nb_zero(work,16);store8(work,2);let r=0;if to_identity {r=sr_inherit(work,identity,now);}else {r=sr_inherit(identity,work,now);}nb_zero(work,16);return r;
}
