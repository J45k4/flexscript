// Compile every migrated guest assertion with the production ARM64 VM before
// device use. This complements the actual SDK/radio tests, without claiming I/O.
import "lib/collie-test.flex";
import "lib/android-ble-set-test.flex";
fn main(argc,argv){
    ct_init(argc,argv);let names=h_args("camera","bluetooth","cellular","wifi","hardware","lazy-permissions");h_add(names,"input");h_add(names,"screen");h_add(names,"documents");h_add(names,"uwb-provider");h_add(names,"ble");h_add(names,"gatt");h_add(names,"gatt-server");h_add(names,"bluetooth-peer");h_add(names,"ble-set");h_add(names,"ble-lifecycle");h_add(names,"hid");h_add(names,"uwb-peer");h_add(names,"p2p");h_add(names,"signals");h_add(names,"workers");let i=0;while i<h_count(names){let file=h_cat3("apps/collie/tests/",h_at(names,i),"-live.flex");ct_vm(h_cat(h_read(file),"\nfn main(){return 0;}"));ct_pass(h_cat("production VM compiles every assertion in ",file));i=i+1;}
    bp_source=h_read("apps/collie/tests/ble-set-live.flex");bs_service="12345678-1234-4234-8234-123456789abc";bs_peer=c_json("{\"manufacturers\":{\"1\":\"0081ff\",\"65535\":\"ff00\"},\"oversized_manufacturers\":{\"1\":\"0081ff\",\"65535\":\"ff00\"}}");let preamble=bs_data("ad","00ff815a",1,0);let source=h_cat3(bp_source,"\nfn main(){",h_cat(preamble,"return 0;}"));ct_vm(source);ct_pass("native advertising-data construction compiles and executes inside the production VM with binary manufacturer/service fields");return ct_done(j_object(),"android-test-programs-report.json");
}
