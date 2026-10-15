// Allocation-free, canonical key/value snapshots over two independent NOR banks.
// The caller owns two bank buffers and drives the explicit erase/program/read
// protocol. No media writes occur while mounting, editing or reading values.
global kv_work=0;
global kv_bank_size=0;
global kv_active= -1;
global kv_generation=0;
global kv_used=0;
global kv_count=0;
global kv_mounted=0;
global kv_dirty=0;
global kv_busy=0;
global kv_fault=0;
global kv_stage=0;
global kv_target=0;
global kv_phase=0;
global kv_verified=0;
global kv_value=0;
global kv_value_size=0;
global kv_value_type=0;
global kv_io_kind=0;
global kv_io_offset=0;
global kv_io_buffer=0;
global kv_io_size=0;
fn kv_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn kv_put32(p,n) {store8(p,n);store8(p+1,n>>8);store8(p+2,n>>16);store8(p+3,n>>24);return 0;}
fn kv_copy(out,input,size) {let i=0;while i<size {store8(out+i,load8(input+i));i=i+1;}return 0;}
fn kv_equal(a,b,size) {let i=0;while i<size {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn kv_fill(p,size,value) {let i=0;while i<size {store8(p+i,value);i=i+1;}return 0;}
fn kv_crc(p,size) {let crc=4294967295;let i=0;while i<size {crc=crc^load8(p+i);let j=0;while j<8 {let bit=crc&1;crc=crc>>1;if bit {crc=crc^0xedb88320;}j=j+1;}i=i+1;}return crc^4294967295;}
fn kv_size(bank) {if bank<4096 || bank>65536 || (bank&4095) {return -22;}return bank*2+264;}
fn kv_init(work,capacity,bank) {
    let size=kv_size(bank);if size<0 || work<=0 || work>9223372036854775807-size || capacity<size {return -22;}
    kv_work=work;kv_bank_size=bank;kv_active= -1;kv_generation=0;kv_used=0;kv_count=0;kv_mounted=0;kv_dirty=0;kv_busy=0;kv_fault=0;kv_stage=0;kv_phase=0;kv_verified=0;kv_value=0;kv_value_size=0;kv_value_type=0;kv_io_kind=0;return 0;
}
fn kv_bank_buffer(bank) {if !kv_work || bank<0 || bank>1 {return 0;}return kv_work+bank*kv_bank_size;}
fn kv_key_compare(a,an,b,bn) {let i=0;while i<an && i<bn {let x=load8(a+i);let y=load8(b+i);if x<y {return -1;}if x>y {return 1;}i=i+1;}if an<bn {return -1;}if an>bn {return 1;}return 0;}
fn kv_record_size(p) {return (8+load8(p)+kv_u32(p+4)+3)&~3;}
fn kv_valid(p) {
    if kv_u32(p)!=0x564b5846 || kv_u32(p+4)!=1 || kv_u32(p+28)!=0x3cc35aa5 || kv_u32(p+24)!=kv_crc(p,24) {return 0;}
    let used=kv_u32(p+12);let count=kv_u32(p+16);if used>kv_bank_size-32 || (used&3) || count>128 || kv_u32(p+20)!=kv_crc(p+32,used) {return 0;}
    let at=0;let n=0;let previous=0;
    while at<used {if used-at<8 {return 0;}let r=p+32+at;let key=load8(r);let value=kv_u32(r+4);if key<1 || key>63 || !load8(r+1) || load8(r+2) || load8(r+3) || value>kv_bank_size-40-key {return 0;}
        let size=kv_record_size(r);if size>used-at {return 0;}if previous && kv_key_compare(previous+8,load8(previous),r+8,key)>=0 {return 0;}
        let i=8+key+value;while i<size {if load8(r+i)!=255 {return 0;}i=i+1;}previous=r;at=at+size;n=n+1;if n>128 {return 0;}
    }return at==used && n==count;
}
fn kv_blank(p,size) {let i=0;while i<size {if load8(p+i)!=255 {return 0;}i=i+1;}return 1;}
// Load both full banks into kv_bank_buffer(0/1) before mounting. -61 means
// both are erased, -74 means no unambiguous valid snapshot. Neither formats.
fn kv_mount() {
    if !kv_work {return -22;}if kv_busy {return -16;}kv_mounted=0;kv_value=0;kv_value_size=0;kv_value_type=0;kv_fault=0;
    let a=kv_bank_buffer(0);let b=kv_bank_buffer(1);let av=kv_valid(a);let bv=kv_valid(b);let active= -1;
    if av && bv {let delta=(kv_u32(b+8)-kv_u32(a+8))&4294967295;if !delta {let n=kv_u32(a+12);if n!=kv_u32(b+12) || !kv_equal(a,b,n+32) {return -74;}active=0;}else if delta==2147483648 {return -74;}else if delta<2147483648 {active=1;}else {active=0;}}
    else if av {active=0;}else if bv {active=1;}
    if active<0 {if kv_blank(a,kv_bank_size) && kv_blank(b,kv_bank_size) {return -61;}return -74;}
    kv_active=active;let p=kv_bank_buffer(active);kv_generation=kv_u32(p+8);kv_used=kv_u32(p+12);kv_count=kv_u32(p+16);kv_stage=kv_bank_buffer(1-active);kv_copy(kv_stage,p,kv_bank_size);kv_dirty=0;kv_mounted=1;return 0;
}
// Explicit provisioning is accepted only for two completely erased banks.
fn kv_create() {
    if !kv_work {return -22;}if kv_busy || kv_mounted {return -16;}if !kv_blank(kv_bank_buffer(0),kv_bank_size) || !kv_blank(kv_bank_buffer(1),kv_bank_size) {return -74;}
    kv_active= -1;kv_generation=0;kv_used=0;kv_count=0;kv_stage=kv_bank_buffer(0);kv_dirty=1;kv_fault=0;kv_mounted=1;return 0;
}
fn kv_find(key,size) {let at=0;while at<kv_used {let p=kv_stage+32+at;let c=kv_key_compare(p+8,load8(p),key,size);if c>=0 {return at;}at=at+kv_record_size(p);}return at;}
fn kv_get(key,size) {
    kv_value=0;kv_value_size=0;kv_value_type=0;if !kv_mounted {return -107;}if key<=0 || size<1 || size>63 {return -22;}
    let at=kv_find(key,size);if at==kv_used {return -2;}let p=kv_stage+32+at;if kv_key_compare(p+8,load8(p),key,size) {return -2;}kv_value=p+8+size;kv_value_size=kv_u32(p+4);kv_value_type=load8(p+1);return 0;
}
// Input must not overlap either workspace bank or scratch: values returned by
// kv_get are borrowed views and must be copied before using them in kv_set.
fn kv_outside(p,size) {if size<0 || p<0 || p>9223372036854775807-size || (size && !p) {return 0;}if !size {return 1;}return p+size<=kv_work || p>=kv_work+kv_size(kv_bank_size);}
fn kv_set(key,ksize,type,value,vsize) {
    if !kv_mounted {return -107;}if kv_busy || kv_fault {return -16;}if ksize<1 || ksize>63 || type<1 || type>255 || !kv_outside(key,ksize) || !kv_outside(value,vsize) || vsize>kv_bank_size-40-ksize {return -22;}
    let at=kv_find(key,ksize);let old=0;let p=kv_stage+32+at;if at<kv_used && !kv_key_compare(p+8,load8(p),key,ksize) {old=kv_record_size(p);if load8(p+1)==type && kv_u32(p+4)==vsize && kv_equal(p+8+ksize,value,vsize) {return 0;}}
    let size=(8+ksize+vsize+3)&~3;let end=kv_used-old+size;if end>kv_bank_size-32 || (!old && kv_count==128) {return -28;}
    let tail=kv_used-at-old;let i=0;if size>old {i=tail;while i {i=i-1;store8(p+size+i,load8(p+old+i));}}else {while i<tail {store8(p+size+i,load8(p+old+i));i=i+1;}}
    kv_fill(p,size,255);store8(p,ksize);store8(p+1,type);store8(p+2,0);store8(p+3,0);kv_put32(p+4,vsize);kv_copy(p+8,key,ksize);kv_copy(p+8+ksize,value,vsize);if end<kv_used {kv_fill(kv_stage+32+end,kv_used-end,255);}kv_used=end;if !old {kv_count=kv_count+1;}kv_dirty=1;kv_value=0;return 0;
}
fn kv_delete(key,size) {
    if !kv_mounted {return -107;}if kv_busy || kv_fault {return -16;}if key<=0 || size<1 || size>63 {return -22;}let at=kv_find(key,size);if at==kv_used {return -2;}let p=kv_stage+32+at;if kv_key_compare(p+8,load8(p),key,size) {return -2;}
    let n=kv_record_size(p);let tail=kv_used-at-n;kv_copy(p,p+n,tail);kv_fill(kv_stage+32+kv_used-n,n,255);kv_used=kv_used-n;kv_count=kv_count-1;kv_dirty=1;kv_value=0;return 0;
}
fn kv_rollback() {if !kv_mounted {return -107;}if kv_busy || kv_fault {return -16;}if kv_active<0 {kv_fill(kv_stage,kv_bank_size,255);kv_used=0;kv_count=0;kv_dirty=1;}else {let p=kv_bank_buffer(kv_active);kv_copy(kv_stage,p,kv_bank_size);kv_used=kv_u32(p+12);kv_count=kv_u32(p+16);kv_dirty=0;}kv_value=0;return 0;}
// Return 1 for a started commit, 0 for unchanged, or a negative error. Once
// started, drain kv_next_io/kv_io_done; an I/O failure requires reloading media.
fn kv_commit() {
    if !kv_mounted {return -107;}if kv_busy || kv_fault {return -16;}if !kv_dirty {return 0;}
    if kv_active>=0 {let p=kv_bank_buffer(kv_active);if kv_used==kv_u32(p+12) && kv_count==kv_u32(p+16) && kv_equal(kv_stage+32,p+32,kv_used) {kv_dirty=0;return 0;}}
    let p=kv_stage;kv_put32(p,0x564b5846);kv_put32(p+4,1);kv_put32(p+8,(kv_generation+1)&4294967295);kv_put32(p+12,kv_used);kv_put32(p+16,kv_count);kv_put32(p+20,kv_crc(p+32,kv_used));kv_put32(p+24,kv_crc(p,24));kv_put32(p+28,4294967295);
    kv_target=0;if kv_active>=0 {kv_target=1-kv_active;}kv_phase=1;kv_verified=0;kv_busy=1;kv_io_kind=0;kv_value=0;return 1;
}
// kind1 erase,2 program,3 read; offsets relative to the two-bank region.
// Reads use the separate256-byte scratch. Repeated peeks retain the same I/O.
fn kv_next_io() {
    if !kv_busy {kv_io_kind=0;return 0;}let base=kv_target*kv_bank_size;kv_io_kind=0;kv_io_buffer=0;
    if kv_phase==1 {kv_io_kind=1;kv_io_offset=base;kv_io_size=kv_bank_size;}
    else if kv_phase==2 {kv_io_kind=2;kv_io_offset=base;kv_io_buffer=kv_stage;kv_io_size=28;}
    else if kv_phase==3 {kv_io_kind=2;kv_io_offset=base+32;kv_io_buffer=kv_stage+32;kv_io_size=kv_used;}
    else if kv_phase==4 {kv_io_kind=3;kv_io_offset=base+kv_verified;kv_io_buffer=kv_work+kv_bank_size*2;kv_io_size=32+kv_used-kv_verified;if kv_io_size>256 {kv_io_size=256;}}
    else if kv_phase==5 {kv_io_kind=2;kv_io_offset=base+28;kv_io_buffer=kv_stage+28;kv_io_size=4;}
    else if kv_phase==6 {kv_io_kind=3;kv_io_offset=base+28;kv_io_buffer=kv_work+kv_bank_size*2;kv_io_size=4;}return kv_io_kind;
}
fn kv_io_fail(error) {kv_busy=0;kv_fault=error;kv_io_kind=0;kv_value=0;return error;}
fn kv_io_done(result) {
    if !kv_busy || !kv_io_kind {return -16;}if result!=kv_io_size {if result>=0 {result= -5;}return kv_io_fail(result);}
    if kv_phase==4 {if !kv_equal(kv_io_buffer,kv_stage+kv_verified,kv_io_size) {return kv_io_fail(-5);}kv_verified=kv_verified+kv_io_size;if kv_verified==32+kv_used {kv_put32(kv_stage+28,0x3cc35aa5);kv_phase=5;}}
    else if kv_phase==6 {if kv_u32(kv_io_buffer)!=0x3cc35aa5 {return kv_io_fail(-5);}kv_active=kv_target;kv_generation=kv_u32(kv_stage+8);let p=kv_bank_buffer(1-kv_active);kv_copy(p,kv_stage,kv_bank_size);kv_stage=p;kv_dirty=0;kv_busy=0;kv_phase=0;}
    else {kv_phase=kv_phase+1;if kv_phase==3 && !kv_used {kv_phase=4;}}kv_io_kind=0;return kv_busy;
}
