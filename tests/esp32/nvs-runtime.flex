import "../../lib/storage/nvs.flex";
import "settings-fixture.flex";
fn main() {
    if nv_health()!=0x1101 || kt_begin(4096) || kt_reload()!= -61 || kv_create() || kt_commit() {return 1;}let work=alloc(nv_size(4));let value=alloc(256);if nv_init(work,nv_size(4),4) || nv_open("wifi",4,0)!=0x1102 || nv_open("wifi",4,1) {return 2;}let a=nv_opened;if !a || nv_open("ble",3,1) {return 3;}let b=nv_opened;
    store8(value,255);if nv_set(a,"count",5,17,value,1) || nv_get(a,"count",5,17) || kv_value_size!=1 || load8(kv_value)!=255 || nv_get(a,"count",5,1)!=0x1103 || nv_get(b,"count",5,17)!=0x1102 {return 4;}
    // Replacing a key with another type is allowed, as in the upstream store.
    store8(value,42);if nv_set(a,"count",5,1,value,1) || nv_get(a,"count",5,17)!=0x1103 || nv_get(a,"count",5,1) || load8(kv_value)!=42 {return 5;}
    if nv_open("wifi",4,0) {return 6;}let ro=nv_opened;if nv_set(ro,"x",1,1,value,1)!=0x1104 || nv_erase(ro,"count",5)!=0x1104 || nv_commit_check(ro) || nv_get(ro,"count",5,1) {return 7;}
    if nv_open("wifi",4,1) {return 8;}let other=nv_opened;let before=kv_count;if nv_open("new",3,1)!=0x101 || kv_count!=before {return 9;}nv_close(other);if nv_open("new",3,1) || nv_opened==other || nv_get(other,"count",5,1)!=0x1107 {return 10;}nv_close(nv_opened);
    if nv_open("",0,1)!=0x1106 || nv_open("0123456789abcdef",16,1)!=0x1106 || nv_open("wifi",4,2)!=0x102 || nv_get(a,"",0,1)!=0x1106 || nv_erase(a,"0123456789abcdef",16)!=0x1109 || nv_set(a,"x",1,66,0,0) || nv_get(a,"x",1,66) || kv_value_size {return 11;}
    let i=0;while i<200 {store8(value+i,i);i=i+1;}if nv_set(b,"blob",4,66,value,200) || nv_set(a,"text",4,33,"hello",6) || nv_set(a,"bad",3,33,"hello",5)!=0x102 || nv_set(a,"bad",3,99,value,1)!=0x102 || kt_commit() {return 12;}
    if kt_reload() || nv_init(work,nv_size(4),4) || nv_get(a,"count",5,1)!=0x1107 || nv_open("wifi",4,0) {return 13;}ro=nv_opened;if nv_get(ro,"text",4,33) || kv_value_size!=6 || !kv_equal(kv_value,"hello",6) || nv_open("ble",3,1) {return 14;}b=nv_opened;if nv_get(b,"blob",4,66) || kv_value_size!=200 || !kv_equal(kv_value,value,200) {return 15;}
    if nv_erase_all(b) || nv_get(b,"blob",4,66)!=0x1102 || nv_get(ro,"count",5,1) || kt_commit() || kt_reload() || nv_init(work,nv_size(4),4) || nv_open("ble",3,0) {return 16;}
    nv_fail();if nv_open("wifi",4,0)!=0x110b || nv_get(nv_opened,"x",1,66)!=0x110b || nv_init(work,nv_size(4),4) {return 17;}
    let previous=nv_next_token;nv_next_token=4294967294;if nv_open("ble",3,0) || nv_opened!=4294967295 || nv_open("ble",3,0)!=0x101 {return 18;}nv_next_token=previous;
    // A raw KV entry with an invalid NVS-owned record is rejected on rebind.
    store8(value,1);store8(value+1,97);store8(value+2,98);if kv_set(value,3,1,"x",1) || nv_init(work,nv_size(4),4)!=0x110b || nv_ready {return 19;}
    return 0;
}
