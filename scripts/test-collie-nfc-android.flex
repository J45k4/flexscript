// Real NFC/OMAPI SDK/VM/consent and portable codec checks; no RF/APDU claim.
import "lib/collie-android-test.flex";
fn main(argc,argv){
    if at_init(argc,argv,"nfc",j_object())<0{return at_self_test();}
    if !at_child{return at_parent(argc,argv);}
    let o=at_vm(h_cat(ut_prefix,"-pure"),"fn main(){let r=db_list();db_add(r,ndef_record(0,db_blob(\"\",0),db_blob(\"\",0),db_blob(\"\",0)));let b=ndef_encode(r);let parsed=ndef_parse(b);return db_count(parsed)-1;}",c_json("{\"nfc\":false,\"secure_element\":false,\"db_read\":false,\"db_write\":false}"));let signals=cj_get(o,"signals");h_assert(!signals||j_count(signals)==0,j_dump(o));at_pass("portable NDEF computation runs in the actual VM with NFC/SE/database grants denied");
    let sdk=at_sdk(ut_prefix,c_json("{\"hardware_nfc_tests\":true,\"initial_permissions\":{\"nfc\":true,\"secure_element\":true,\"db_read\":true,\"db_write\":true}}"));h_assert(!at_bool(cj_get(sdk,"radio_verified"))&&!at_bool(cj_get(sdk,"apdu_io_verified")),"Protocol fixtures cannot claim RF/APDU verification");
    let keys=h_args("nfc","secure_element",0,0,0,0);let sources=h_args("fn main(){nfc_info();return 0;}","fn main(){let h=se_open(2000);if !h{return 1;}return device_close(db_word(h))-1;}",0,0,0,0);let i=0;
    while i<2{let key=h_at(keys,i);let sid=h_cat3(ut_prefix,"-",h_replace(key,"_","-"));let policy=j_object();j_set(policy,key,j_string("ask"));let name=at_conversation(sid,h_at(sources,i),policy);at_pending(sid,key,"permission",name);at_click("text","Allow requested access",0);at_observation(at_result(name));let state=ut_read(h_cat3("files/workspaces/",sid,"/session.json"));h_assert(at_bool(cj_get(cj_get(state,"permissions"),key)),j_dump(state));at_pass(h_cat3("actual Android Collie first-use ",key," approval resumes the original VM caller without a separate unrelated runtime prompt"));i=i+1;}
    let report=j_object();j_set(report,"radio_verified",j_bool(0));j_set(report,"apdu_io_verified",j_bool(0));return at_finish(report);
}
