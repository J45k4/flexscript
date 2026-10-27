// Real consent, unsupported and ownership checks on an emulator without NAN.
import "lib/collie-android-test.flex";
fn main(argc,argv){
    if at_init(argc,argv,"aware",j_object())<0{return at_self_test();}
    if !at_child{return at_parent(argc,argv);}
    let features=h_out(ut_ok(ut_args("shell","pm","list","features",0,0),""));h_assert(!h_has(features,"android.hardware.wifi.aware"),"This fixture requires a target without NAN; no radio proof is simulated");let grants=at_flags(at_package());
    let sid=h_cat(ut_prefix,"-consent");let source="fn main(){if aware_open(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"unsupported\"){return 2;}return 0;}";let name=at_conversation(sid,source,c_json("{\"db_read\":true,\"db_write\":true}"));at_pending(sid,"wifi","permission",name);at_click("text","Allow requested access",0);at_pending(sid,"location","permission",name);at_click("text","Allow requested access",0);at_observation(at_result(name));at_pass("Aware attach checkpoints Wi-Fi and Location separately and resumes the original VM before returning the actual unsupported result");
    let keys=h_args("wifi","location",0,0,0,0);let i=0;while i<2{let key=h_at(keys,i);let policy=c_json("{\"wifi\":true,\"location\":true}");j_set(policy,key,j_bool(0));at_vm(h_cat3(ut_prefix,"-denied-",key),"fn main(){if aware_open(){return 1;}let e=device_error();if !worker_equal(db_word(db_at(e,0)),\"permission_denied\"){return 2;}return 0;}",policy);at_pass(h_cat3("Aware attach enforces the ",key," denial through the real VM broker"));i=i+1;}
    at_sdk(sid,c_json("{\"hardware_aware_tests\":true}"));h_assert(h_equal(j_dump(grants),j_dump(at_flags(at_package()))),"Unsupported Aware changed Android runtime consent");at_pass("an unsupported Aware device never triggers or changes Android Location/Nearby runtime consent");let report=j_object();j_set(report,"radio_verified",j_bool(0));return at_finish(report);
}
