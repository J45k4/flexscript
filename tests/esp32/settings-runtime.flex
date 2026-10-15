import "settings-fixture.flex";
fn main() {
    if kv_size(0)!= -22 || kv_size(4097)!= -22 || kv_size(131072)!= -22 || kv_size(4096)!=8456 || kv_init(0,8456,4096)!= -22 {return 1;}
    if kt_begin(4096) || kt_reload()!= -61 || kv_mounted || kv_create() || kt_commit() || kv_generation!=1 || kv_active!=0 || kt_reload() || kv_count || kv_used {return 2;}
    if kv_set("z",1,1,"last",4) || kv_set("a",1,2,"first",5) || kv_set("m",1,3,0,0) || kv_count!=3 || !kt_has("a",1,2,"first",5) || !kt_has("m",1,3,0,0) || kv_get("b",1)!= -2 {return 3;}
    if kt_commit() || kv_generation!=2 || kv_active!=1 || kt_reload() || !kt_has("z",1,1,"last",4) || !kt_has("a",1,2,"first",5) {return 4;}
    if kv_set("a",1,2,"first",5) || kv_dirty || kv_commit() || kv_set("a",1,5,"x",1) || !kt_has("a",1,5,"x",1) || kv_set("a",1,6,"longer value",12) || !kt_has("z",1,1,"last",4) || kv_rollback() || !kt_has("a",1,2,"first",5) || kv_dirty {return 5;}
    if kv_get("z",1) || kv_set("a",1,1,kv_value,kv_value_size)!= -22 || kv_set(kv_value,1,1,"x",1)!= -22 || kv_set("a",1,0,"x",1)!= -22 || kv_set("a",1,1,0,1)!= -22 || kv_set("a",1,1,"x",-1)!= -22 {return 6;}
    if kv_delete("b",1)!= -2 || kv_delete("m",1) || kv_count!=2 || kv_get("m",1)!= -2 || !kt_has("z",1,1,"last",4) || kt_commit() || kt_reload() || kv_count!=2 {return 7;}
    if kv_set("z",1,1,"next",4) || kv_commit()!=1 || kv_set("a",1,1,"x",1)!= -16 || kv_delete("a",1)!= -16 || kv_rollback()!= -16 || kv_commit()!= -16 || kv_mount()!= -16 || kv_io_done(0)!= -16 || kv_next_io()!=1 || kv_io_done(1)!= -5 || !kv_fault || kv_busy || kv_commit()!= -16 || kt_reload() || !kt_has("z",1,1,"last",4) {return 8;}
    // A readback failure cannot publish a new snapshot in RAM or on reboot.
    if kv_set("z",1,1,"next",4) {return 9;}kt_corrupt_at=kt_operations+3;if kt_commit()!= -5 || !kv_fault || kt_reload() || !kt_has("z",1,1,"last",4) {return 10;}kt_corrupt_at= -1;
    // Failure while programming the commit marker preserves the old bank.
    if kv_set("z",1,1,"next",4) {return 11;}kt_fail_at=kt_operations+4;if kt_commit()!= -5 || kt_reload() || !kt_has("z",1,1,"last",4) {return 12;}kt_fail_at= -1;
    if kv_set("z",1,1,"next",4) || kt_commit() || kt_reload() || !kt_has("z",1,1,"next",4) {return 13;}
    // Modular generation order, including wrap through zero.
    let p=kt_disk+kv_active*kv_bank_size;kv_put32(p+8,4294967295);kv_put32(p+24,kv_crc(p,24));let other=kt_disk+(1-kv_active)*kv_bank_size;kv_fill(other,kv_bank_size,255);
    if kt_reload() || kv_generation!=4294967295 || kv_set("a",1,2,"wrap",4) || kt_commit() || kv_generation || kt_reload() || !kt_has("a",1,2,"wrap",4) {return 14;}
    // Full media remains unchanged on mount error; never auto-format damage.
    kv_fill(kt_disk,8192,255);store8(kt_disk,0);if kt_reload()!= -74 || kv_mounted || kv_create()!= -74 || load8(kt_disk)!=0 || kv_get("x",1)!= -107 {return 15;}
    kv_fill(kt_disk,8192,255);if kt_reload()!= -61 || kv_create() {return 16;}let value=alloc(4096);kv_fill(value,4096,42);if kv_set("big",3,1,value,4052) || kv_used!=4064 || kv_set("x",1,1,"v",1)!= -28 || kv_count!=1 || !kt_has("big",3,1,value,4052) || kv_set("big",3,1,value,4054)!= -22 || kt_commit() || kt_reload() || !kt_has("big",3,1,value,4052) {return 17;}
    // An absent persisted key can be added then removed without another erase.
    let ops=kt_operations;if kv_delete("big",3) || kt_commit() || kv_count || kv_set("x",1,1,"v",1) || kv_delete("x",1) || kv_commit() || kt_operations==ops {return 18;}
    // Entry count, binary keys, maximum key length, copied input and no-op commits.
    kv_fill(kt_disk,8192,255);if kt_reload()!= -61 || kv_create() || kt_commit() {return 19;}let key=alloc(64);let i=0;while i<128 {store8(key,i);if kv_set(key,1,1,key,1) {return 20;}i=i+1;}store8(key,128);if kv_set(key,1,1,key,1)!= -28 || kv_count!=128 || kt_commit() || kt_reload() {return 21;}
    i=0;while i<128 {store8(key,i);if !kt_has(key,1,1,key,1) || kv_delete(key,1) {return 22;}i=i+1;}kv_fill(key,64,65);if kv_set(key,64,1,0,0)!= -22 || kv_set(key,63,255,value,0) || kt_commit() || kt_reload() || !kt_has(key,63,255,0,0) {return 23;}
    if kv_set("copy",4,1,key,63) {return 24;}store8(key,66);if kv_get("copy",4) || kv_value_size!=63 || load8(kv_value)!=65 || kv_rollback() || kv_count!=1 || kv_set("temporary",9,1,0,0) || kv_delete("temporary",9) || kv_commit() || kv_dirty {return 25;}
    // Every failed I/O releases busy state, preserves its error and prevents
    // another commit until both banks have actually been loaded from media.
    let baseline=alloc(8192);kv_copy(baseline,kt_disk,8192);i=0;while i<6 {kv_copy(kt_disk,baseline,8192);if kt_reload() || kv_set("failure",7,1,"new",3) {return 26;}kt_fail_at=kt_operations+i;let r=kt_commit();if r!= -5 || kv_busy || kv_fault!= -5 || kv_commit()!= -16 || kv_io_done(0)!= -16 || kt_reload() {return 27;}if i!=5 && kv_get("failure",7)!= -2 {return 28;}if i==5 && !kt_has("failure",7,1,"new",3) {return 28;}kt_fail_at= -1;i=i+1;}
    // Empty snapshots still verify their header before publishing the marker.
    kv_copy(kt_disk,baseline,8192);if kt_reload() || kv_fill(key,63,65) || kv_delete(key,63) || kt_commit() || kt_reload() || kv_count || kv_used {return 29;}
    if kv_set("timeout",7,1,"x",1) || kv_commit()!=1 || kv_next_io()!=1 || kv_io_done(-110)!= -110 || kv_fault!= -110 || kv_next_io() || kt_reload() || kv_get("timeout",7)!= -2 {return 30;}
    return 0;
}
