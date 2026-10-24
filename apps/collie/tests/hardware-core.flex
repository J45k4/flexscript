import "../adapters/workspace.flex";
import "../providers/images.flex";
import "../core/hardware.flex";
fn ci_load(id,size){return -1;}
fn main(argc,argv){
    h_environment(argc,argv);let bytes=alloc(32768);let i=0;while i<32768{store8(bytes+i,i%256);i=i+1;}
    let blob=db_blob(bytes,32768);let encoded=hw_json(blob,0);let restored=hw_value(encoded,0);h_assert(db_bytes(restored)==32768,"binary round trip size");i=0;while i<32768{h_assert(load8(db_word(restored)+i)==i%256,"binary round trip content");i=i+1;}
    let bad=h_args("A===","AA=A","AAA=AAAA","AB==","AAB=","!!!!");i=0;while i<h_count(bad){h_assert(!hw_bytes(h_at(bad,i)),"malformed base64 rejection");i=i+1;}
    h_assert(db_bytes(hw_bytes(""))==0,"empty binary value");
    let value=db_list();db_add(value,db_int(-9223372036854775807-1));db_add(value,db_real(0x7ff8000000000001));db_add(value,db_null());db_add(value,db_text("exact"));restored=hw_value(c_json(j_dump(hw_json(value,0))),0);
    h_assert(db_word(db_at(restored,0))==(-9223372036854775807-1) && db_kind(db_at(restored,1))==4 && db_word(db_at(restored,1))==0x7ff8000000000001 && db_kind(db_at(restored,2))==0,"integer and float bits preserved");
    h_assert(!hw_value(c_json("9223372036854775808"),0) && !hw_value(c_json("-9223372036854775809"),0) && !hw_value(c_json("1.25"),0),"invalid integer metadata rejection");
    h_assert(hw_find("net_tcp_connect") && !hw_find("net_unknown") && !hw_find("java.lang.Runtime"),"explicit operation registry");
    h_assert(h_equal(cj_text(hw_find("hardware_access_info"),"permission"),"progress") && !cj_int(hw_find("hardware_access_info"),"min") && !cj_int(hw_find("hardware_access_info"),"max") && !hw_find("usb_gadget"),"read-only access discovery does not register raw hardware dispatch");
    h_assert(h_equal(cj_text(hw_find("camera_physical_info"),"permission"),"camera") && cj_int(hw_find("camera_physical_info"),"min")==2 && h_equal(cj_text(hw_find("camera_physical_result_value"),"permission"),"hardware_handle") && cj_int(hw_find("camera_physical_result_value"),"min")==6 && cj_int(hw_find("camera_result_physical"),"max")==4,"physical metadata retains Camera consent and parent-result ownership");
    h_assert(h_equal(cj_text(hw_find("usb_control_out"),"permission"),"hardware_handle") && h_equal(cj_text(hw_find("usb_open"),"permission"),"usb") && cj_int(hw_find("usb_control_in"),"min")==7,"USB ownership and permission schema");
    h_assert(h_equal(cj_text(hw_find("cellular_cells"),"permission"),"cellular") && h_equal(cj_text(hw_find("cellular_cells"),"also"),"location"),"cell data requires two grants");
    h_assert(h_equal(cj_text(hw_find("wifi_scan"),"also"),"location") && h_equal(cj_text(hw_find("wifi_suggest"),"permission"),"wifi"),"Wi-Fi scan and suggestion gates differ");
    h_assert(h_equal(cj_text(hw_find("p2p_open"),"also"),"location") && h_equal(cj_text(hw_find("p2p_udp_send"),"permission"),"hardware_handle") && hw_find("p2p_group_attach"),"P2P channel/child permissions and explicit attach registry");
    let old=j_parse("{\"internet\":true,\"files_read\":false}");let policy=j_get(cp_permissions(old),"policy");h_assert(j_value(j_get(policy,"internet")) && !j_value(j_get(policy,"files_read")) && h_equal(cj_text(policy,"network"),"ask"),"hardware migration asks rather than enabling access");
    h_assert(h_equal(cj_text(hw_find("bt_info"),"permission"),"bluetooth") && h_equal(cj_text(hw_find("bt_scan"),"also"),"location") && h_equal(cj_text(hw_find("bt_rfcomm_connect"),"permission"),"hardware_handle") && cj_int(hw_find("bt_rfcomm_connect"),"min")==4,"Bluetooth inventory, discovery and owned connection grants");
    h_assert(h_equal(cj_text(hw_find("ble_scan"),"permission"),"bluetooth") && h_equal(cj_text(hw_find("ble_scan"),"also"),"location") && h_equal(cj_text(hw_find("ble_scan_page"),"permission"),"hardware_handle") && cj_int(hw_find("ble_advertise"),"min")==8,"BLE scan and owned snapshot grants");
    h_print(1,"PASS shared hardware codec: 32768 binary bytes, malformed frames, exact numeric values, registry and permission migration\n");return 0;
}
