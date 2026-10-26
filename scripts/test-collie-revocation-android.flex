// Revoke an allowed device while a real program is running; parent cleanup.
import "lib/collie-android-test.flex";
fn main(argc,argv){
    if at_init(argc,argv,"revocation",j_object())<0{return at_self_test();}
    if !at_child{return at_parent(argc,argv);}
    let flags=c_json("{\"hardware_revocation_tests\":true,\"initial_permissions\":{\"wifi\":true,\"db_read\":true,\"db_write\":true}}");at_sdk(ut_prefix,flags);return at_finish(j_object());
}
