import "settings-fixture.flex";
fn main() {
    let bank=8192;while bank<=65536 {if kt_begin(bank) || kt_reload()!= -61 || kv_create() || kt_commit() {return 1;}let value=alloc(bank);if value<=0 {return 2;}let i=0;while i<bank {store8(value+i,(i*17+3)&255);i=i+1;}let size=bank-64;
        if kv_set("long",4,254,value,size) || kt_commit() || kt_reload() || !kt_has("long",4,254,value,size) || kv_set("long",4,254,value,size+32)!= -22 || kv_set("another",7,1,"x",1) || kt_commit() || kt_reload() || kv_count!=2 || kv_delete("long",4) || kt_commit() || kt_reload() || kv_count!=1 || !kt_has("another",7,1,"x",1) {return 3;}
        bank=bank*2;
    }return 0;
}
