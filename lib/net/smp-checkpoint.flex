import "smp-crypto.flex";
// Authenticated retry-checkpoint envelope. No allocation,media I/O,entropy or
// rollback anchor. Storage key uses conventional AES octets,not SMP scalar order.
// Header48:domain8,sequence8,revision8,payload bytes8,device/store scope16.
// Payload is the complete SMPTRY01 blob,followed by a full16-byte AES-CMAC tag.
// Scalar header fields are little endian; every input/output/work area disjoint.
fn ck_size(bytes) {if bytes<104 || bytes>1344 || (bytes-64)%40 {return -22;}return bytes+64;}
fn ck_seal_work(bytes) {let n=ck_size(bytes);if n<0 {return n;}return n+96;}
fn ck_payload(p,n) {return ck_size(n)>0 && smp_range(p,n) && nb_equal(p,"SMPTRY01",8) && load64(p+8)==(n-64)/40;}
fn ck_disjoint(key,scope,input,n,out,on,work,wn) {
    return !smp_overlap(key,16,scope,16) && !smp_overlap(key,16,input,n) && !smp_overlap(scope,16,input,n) && !smp_overlap(out,on,key,16) && !smp_overlap(out,on,scope,16) && !smp_overlap(out,on,input,n) && !smp_overlap(work,wn,key,16) && !smp_overlap(work,wn,scope,16) && !smp_overlap(work,wn,input,n) && !smp_overlap(work,wn,out,on);
}
fn ck_clear(work,n,result) {nb_zero(work,n);return result;}
fn ck_seal(key,scope,sequence,revision,payload,bytes,out,capacity,work,work_capacity) {
    let size=ck_size(bytes);if size<0 || sequence<1 || revision<1 || !smp_range(key,16) || !smp_range(scope,16) || !smp_range(payload,bytes) || capacity<size || !smp_range(out,capacity) || work_capacity<size+96 || !smp_range(work,work_capacity) {return -22;}
    if !ck_disjoint(key,scope,payload,bytes,out,size,work,size+96) || !ck_payload(payload,bytes) {return -22;}
    nb_zero(work,size+96);let frame=work+96;nb_copy(frame,"FSMPCK01",8);store64(frame+8,sequence);store64(frame+16,revision);store64(frame+24,bytes);nb_copy(frame+32,scope,16);nb_copy(frame+48,payload,bytes);
    let r=smp_cmac(key,frame,48+bytes,frame+48+bytes,work,96);if r {return ck_clear(work,size+96,r);}nb_copy(out,frame,size);return ck_clear(work,size+96,size);
}
// Expected sequence is always exact. expected_revision0 is reserved for a
// trusted restore path that has no previous RAM revision; commit readback must
// supply the exact frozen revision. Authenticating a sequence does not establish
// a trusted rollback floor,and the payload still needs sr_import validation.
fn ck_open(key,scope,sequence,expected_revision,frame,size,out,capacity,work,work_capacity) {
    if sequence<1 || expected_revision<0 || !smp_range(key,16) || !smp_range(scope,16) || size<0 || !smp_range(frame,size) || capacity<0 || !smp_range(out,capacity) || work_capacity<112 || !smp_range(work,work_capacity) {return -22;}
    let bytes=size-64;if ck_size(bytes)<0 {return -74;}if capacity<bytes {return -22;}if !ck_disjoint(key,scope,frame,size,out,bytes,work,112) {return -22;}
    if !nb_equal(frame,"FSMPCK01",8) || load64(frame+24)!=bytes || load64(frame+8)<1 || load64(frame+16)<1 || !smp_equal(scope,frame+32,16) {return -74;}
    if load64(frame+8)!=sequence || (expected_revision && load64(frame+16)!=expected_revision) {return -116;}
    nb_zero(work,112);let r=smp_cmac(key,frame,48+bytes,work+96,work,96);if r {return ck_clear(work,112,r);}
    if !smp_equal(work+96,frame+48+bytes,16) || !ck_payload(frame+48,bytes) {return ck_clear(work,112,-74);}nb_copy(out,frame+48,bytes);return ck_clear(work,112,bytes);
}
