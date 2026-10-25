import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/sensor-direct.flex";
fn record(p,token,type,counter,timestamp){let i=0;while i<104{store8(p+i,0);i=i+1;}store64(p,104|(token<<32));store64(p+8,type|(counter<<32));store64(p+16,timestamp);return p;}
fn rejects(p,n){h_assert(!sensor_direct_records(db_blob(p,n)) && db_last_error_details,"malformed ABI page rejected with diagnostic");return 0;}
fn float_case(p,index,input,expected){store64(p+index*4,input);let r=sensor_direct_f32(db_blob(p,64),index);h_assert(db_kind(r)==4&&db_word(r)==expected,"f32 payload preserves exact numeric bits");return 0;}
fn main(){
    let p=alloc(32768);let i=0;while i<32768{store8(p+i,0);i=i+1;}
    h_assert(db_count(sensor_direct_records(db_blob(p,0)))==0,"empty page");
    let rows=sensor_direct_records(db_blob(p,104));h_assert(db_count(rows)==1&&db_kind(db_at(rows,0))==0,"uninitialized record remains a null slot");
    // Independent public ABI layout, deliberately using binary canaries.
    record(p,0x12345678,65537,4294967295,0x123456789abcdef);i=0;while i<64{store8(p+24+i,(i*17+128)%256);i=i+1;}
    rows=sensor_direct_records(db_blob(p,104));let row=db_at(rows,0);h_assert(db_count(row)==5&&db_word(db_at(row,0))==0x12345678&&db_word(db_at(row,1))==65537&&db_word(db_at(row,2))==4294967295&&db_word(db_at(row,3))==0x123456789abcdef,"little-endian ABI header and unsigned counter");
    let payload=db_at(row,4);i=0;while i<64{h_assert(load8(db_word(payload)+i)==(i*17+128)%256,"opaque union bytes preserved");i=i+1;}
    h_assert(db_word(sensor_direct_i64(payload,0))==0xf7e6d5c4b3a29180,"signed integer union is not converted through float");
    record(p+104,7,1,1,99);rows=sensor_direct_records(db_blob(p,312));h_assert(db_count(rows)==3&&db_word(db_at(db_at(rows,0),2))==4294967295&&db_word(db_at(db_at(rows,1),2))==1&&db_kind(db_at(rows,2))==0,"slot ordering and empty slots retained across counter wrap");
    h_assert(sensor_direct_counter_distance(1,4294967295)==1&&sensor_direct_counter_distance(3,4294967294)==4&&sensor_direct_counter_distance(7,7)==0&&sensor_direct_counter_distance(4294967295,1)==4294967294,"counter arithmetic skips zero");
    h_assert(sensor_direct_counter_distance(0,1)==-1&&sensor_direct_counter_distance(1,4294967296)==-1,"out-of-range counters rejected");
    float_case(p,0,0,0);float_case(p,0,0x80000000,0x8000000000000000);float_case(p,0,0x3f800000,0x3ff0000000000000);float_case(p,0,0xc1480000,0xc029000000000000);float_case(p,0,0x7f7fffff,0x47efffffe0000000);
    float_case(p,0,1,0x36a0000000000000);float_case(p,0,0x007fffff,0x380fffffc0000000);float_case(p,0,0x00800000,0x3810000000000000);float_case(p,0,0x80000001,0xb6a0000000000000);
    float_case(p,0,0x7f800000,0x7ff0000000000000);float_case(p,0,0xff800000,0xfff0000000000000);float_case(p,0,0x7fc12345,0x7ff82468a0000000);float_case(p,0,0x7f800001,0x7ff0000020000000);
    store64(p+56,0x8000000000000000);h_assert(db_word(sensor_direct_i64(db_blob(p,64),7))==0x8000000000000000,"final i64 union element");
    store8(p+60,0);store8(p+61,0);store8(p+62,128);store8(p+63,63);h_assert(db_word(sensor_direct_f32(db_blob(p,64),15))==0x3ff0000000000000,"final float union element");
    h_assert(!sensor_direct_f32(db_blob(p,63),0)&&!sensor_direct_f32(db_blob(p,64),16)&&!sensor_direct_i64(db_blob(p,64),-1)&&!sensor_direct_i64(db_int(64),0),"union bounds and types");
    record(p,1,1,1,1);rejects(p,103);rejects(p,105);store8(p,103);rejects(p,104);record(p,0,1,1,1);rejects(p,104);record(p,2147483648,1,1,1);rejects(p,104);record(p,1,0,1,1);rejects(p,104);record(p,1,1,1,-1);rejects(p,104);record(p,1,1,1,1);store8(p+103,1);rejects(p,104);
    h_assert(!sensor_direct_records(db_text("")),"nonbinary input rejected");
    i=0;while i<315{record(p+i*104,i+1,1,i+1,i+1);i=i+1;}rows=sensor_direct_records(db_blob(p,32760));h_assert(db_count(rows)==315&&db_word(db_at(db_at(rows,314),0))==315,"maximum bounded page");rejects(p,32768);
    h_print(1,"PASS direct-sensor ABI: raw slots, union bytes, IEEE754 edge values, unsigned wrap, malformed records and32KiB bounds\n");return 0;
}
