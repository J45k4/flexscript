import "../lib/json.flex";
import "../guest/runtime.flex";
import "../guest/uwb.flex";

fn main(){
    let local=db_blob("AB",2);let remote=db_blob("CD",2);let key=db_blob("0123456789abcdef",16);let empty=db_blob("",0);
    let peer=uwb_peer("12345678-1234-1234-1234-123456789abc",4294967295,3,local,remote,9,10,2,1,key,2147483648,empty);
    h_assert(db_count(peer)==12,"UWB peer has the declared12 typed fields");
    h_assert(db_kind(db_at(peer,0))==2 && h_equal(db_word(db_at(peer,0)),"12345678-1234-1234-1234-123456789abc"),"peer identity stays text");
    h_assert(db_word(db_at(peer,1))==4294967295 && db_word(db_at(peer,10))==2147483648,"unsigned32-bit IDs stay exact in ordinary VM values");
    h_assert(db_kind(db_at(peer,3))==3 && db_bytes(db_at(peer,3))==2 && load8(db_word(db_at(peer,4)))==67,"addresses stay binary rather than host pointers");
    h_assert(db_kind(db_at(peer,9))==3 && db_bytes(db_at(peer,9))==16 && db_bytes(db_at(peer,11))==0,"binary keys and explicit unset sub-key");
    let n=db_encode(peer);h_assert(n>0,"peer fits the bounded transport");let restored=db_decode(db_wire,n);
    h_assert(db_count(restored)==12 && db_word(db_at(restored,1))==4294967295 && db_bytes(db_at(restored,9))==16,"complete peer survives typed codec round trip");
    let options=uwb_options(1,65535,0,3,1,20000,120000);h_assert(db_count(options)==7 && db_word(db_at(options,1))==65535 && db_word(db_at(options,5))==20000 && db_word(db_at(options,6))==120000,"options retain explicit SDK controls without any platform I/O");
    h_print(1,"PASS pure UWB records and typed transport; no ranging or hardware grant used\n");return 0;
}
