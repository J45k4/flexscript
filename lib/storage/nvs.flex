import "settings.flex";
// Bounded native namespace/type/handle layer. Storage is the Flexscript two-bank
// format, not ESP-IDF NVS partitions. Caller serializes access and commits media.
global nv_work=0;
global nv_handles=0;
global nv_ready=0;
global nv_failed=0;
global nv_next_token=0;
global nv_opened=0;
global nv_error=0;
global nv_key_size=0;
fn nv_size(handles) {if handles<1 || handles>32 {return -22;}return 64+handles*32;}
fn nv_health() {if !nv_ready || !kv_mounted {return 0x1101;}if nv_failed || kv_fault || kv_busy {return 0x110b;}return 0;}
fn nv_name(name,size) {if name<=0 || size<1 || size>15 {return 0;}let i=0;while i<size {if !load8(name+i) {return 0;}i=i+1;}return 1;}
fn nv_type_size(type) {if type==1 || type==17 {return 1;}if type==2 || type==18 {return 2;}if type==4 || type==20 {return 4;}if type==8 || type==24 {return 8;}if type==33 || type==66 {return 0;}return -1;}
fn nv_value_valid(type,p,size) {let scalar=nv_type_size(type);if scalar<0 || size<0 || (size && p<=0) {return 0;}if scalar {return size==scalar;}if type==33 {if !size || load8(p+size-1) {return 0;}let i=0;while i<size-1 {if !load8(p+i) {return 0;}i=i+1;}}return 1;}
fn nv_map(error) {if !error {return 0;}if error== -2 {return 0x1102;}if error== -28 {return 0x1105;}if error== -12 {return 0x101;}if error== -22 {return 0x102;}return 0x110b;}
fn nv_marker(name,size) {store8(nv_work,0);kv_copy(nv_work+1,name,size);nv_key_size=size+1;return nv_work;}
fn nv_at(index) {return nv_work+64+index*32;}
fn nv_handle(token,write) {
    nv_error=nv_health();if nv_error {return 0;}let i=0;while i<nv_handles {let p=nv_at(i);if token>0 && token<=4294967295 && kv_u32(p)==token {if write && !load8(p+4) {nv_error=0x1104;return 0;}return p;}i=i+1;}nv_error=0x1107;return 0;
}
fn nv_key(handle,key,size) {
    if size>15 {return 0x1109;}if !nv_name(key,size) {return 0x1106;}let n=load8(handle+5);store8(nv_work,n);kv_copy(nv_work+1,handle+8,n);kv_copy(nv_work+1+n,key,size);nv_key_size=1+n+size;return 0;
}
// Init/recovery invalidates every handle. Tokens are never reused in one boot.
fn nv_init(work,capacity,handles) {
    let needed=nv_size(handles);if needed<0 || work<=0 || work>9223372036854775807-needed || capacity<needed || !kv_outside(work,needed) {return 0x102;}if !kv_mounted {return 0x1101;}if kv_busy || kv_fault {return 0x110b;}
    nv_ready=0;nv_failed=0;nv_work=work;nv_handles=handles;nv_opened=0;kv_fill(work,needed,0);
    // Validate owned records. Plain application keys whose first byte is>15
    // belong to other users of the store and are left alone.
    let at=0;while at<kv_used {let p=kv_stage+32+at;let n=load8(p);let key=p+8;let tag=load8(key);let type=load8(p+1);let size=kv_u32(p+4);
        if !tag {if n<2 || n>16 || !nv_name(key+1,n-1) || type!=254 || size {return 0x110b;}}
        else if tag<=15 {if n<=1+tag || n>1+tag+15 || !nv_name(key+1,tag) || !nv_name(key+1+tag,n-1-tag) || !nv_value_valid(type,key+n,size) {return 0x110b;}nv_marker(key+1,tag);if kv_get(nv_work,nv_key_size) || kv_value_type!=254 || kv_value_size {return 0x110b;}}
        at=at+kv_record_size(p);
    }nv_ready=1;return 0;
}
fn nv_open(name,size,mode) {
    nv_opened=0;let error=nv_health();if error {return error;}if !nv_name(name,size) {return 0x1106;}if mode!=0 && mode!=1 {return 0x102;}if nv_next_token>=4294967295 {return 0x101;}
    let free= -1;let i=0;while i<nv_handles && free<0 {if !kv_u32(nv_at(i)) {free=i;}i=i+1;}if free<0 {return 0x101;}
    nv_marker(name,size);error=kv_get(nv_work,nv_key_size);if error== -2 {if !mode {return 0x1102;}error=kv_set(nv_work,nv_key_size,254,0,0);if error {return nv_map(error);}}
    else if error || kv_value_type!=254 || kv_value_size {return 0x110b;}
    nv_next_token=nv_next_token+1;let p=nv_at(free);kv_fill(p,32,0);kv_put32(p,nv_next_token);store8(p+4,mode);store8(p+5,size);kv_copy(p+8,name,size);nv_opened=nv_next_token;return 0;
}
fn nv_close(token) {if !nv_ready {return 0;}let i=0;while i<nv_handles {let p=nv_at(i);if token>0 && token<=4294967295 && kv_u32(p)==token {kv_fill(p,32,0);return 0;}i=i+1;}return 0;}
fn nv_get(token,key,size,type) {let p=nv_handle(token,0);if !p {return nv_error;}if nv_type_size(type)<0 {return 0x102;}let error=nv_key(p,key,size);if error {return error;}error=kv_get(nv_work,nv_key_size);if error {return nv_map(error);}if kv_value_type!=type {return 0x1103;}if !nv_value_valid(type,kv_value,kv_value_size) {nv_failed=1;return 0x110b;}return 0;}
fn nv_set(token,key,size,type,value,length) {
    let p=nv_handle(token,1);if !p {return nv_error;}let error=nv_key(p,key,size);if error {return error;}if length>kv_bank_size-40-1-load8(p+5)-size {return 0x110e;}if !nv_value_valid(type,value,length) {return 0x102;}
    return nv_map(kv_set(nv_work,nv_key_size,type,value,length));
}
fn nv_erase(token,key,size) {let p=nv_handle(token,1);if !p {return nv_error;}let error=nv_key(p,key,size);if error {return error;}return nv_map(kv_delete(nv_work,nv_key_size));}
fn nv_erase_all(token) {
    let p=nv_handle(token,1);if !p {return nv_error;}let ns=load8(p+5);let at=0;while at<kv_used {let r=kv_stage+32+at;let size=load8(r);if load8(r+8)==ns && size>ns+1 && kv_equal(r+9,p+8,ns) {kv_copy(nv_work,r+8,size);let error=kv_delete(nv_work,size);if error {return nv_map(error);}}else {at=at+kv_record_size(r);}}return 0;
}
fn nv_commit_check(token) {if !nv_handle(token,0) {return nv_error;}return 0;}
fn nv_fail() {nv_failed=1;return 0;}
