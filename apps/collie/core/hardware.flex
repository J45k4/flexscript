// Shared hardware operation schema. Android transports cannot choose their own
// guest permission, reinterpret arbitrary method names, or return host pointers.
import "permissions.flex";
global hw_registry=0;
fn hw_operation(rows,name,permission,min,max){let row=j_object();j_set(row,"name",j_string(name));j_set(row,"permission",j_string(permission));j_set(row,"min",j_int(min));j_set(row,"max",j_int(max));j_push(rows,row);return 0;}
fn hw_operations(){
    if hw_registry{return hw_registry;}let rows=j_array();
    hw_operation(rows,"hardware_capabilities","progress",0,0);
    hw_operation(rows,"hardware_api","progress",0,0);
    hw_operation(rows,"hardware_api_page","progress",2,2);
    hw_operation(rows,"net_list","network",0,0);
    hw_operation(rows,"net_info","network",1,1);
    hw_operation(rows,"net_watch","network",0,0);
    hw_operation(rows,"net_request","network",1,1);
    hw_operation(rows,"net_resolve","network",2,2);
    hw_operation(rows,"net_tcp_connect","network",4,4);
    hw_operation(rows,"net_tcp_open","network",1,1);
    hw_operation(rows,"net_tcp_dial","hardware_handle",4,4);
    hw_operation(rows,"net_tcp_listen","network",3,3);
    hw_operation(rows,"net_tcp_accept","network",2,2);
    hw_operation(rows,"net_udp_open","network",2,2);
    hw_operation(rows,"net_udp_send","network",4,4);
    hw_operation(rows,"net_udp_receive","network",3,3);
    hw_operation(rows,"net_http","network",3,3);
    hw_operation(rows,"device_read","hardware_handle",3,3);
    hw_operation(rows,"device_write","hardware_handle",2,2);
    hw_operation(rows,"device_wait","hardware_handle",2,2);
    hw_operation(rows,"device_info","hardware_handle",1,1);
    hw_operation(rows,"device_close","hardware_handle",1,1);
    hw_operation(rows,"sensor_list","sensors",0,2);
    hw_operation(rows,"sensor_info","sensors",1,1);
    hw_operation(rows,"sensor_open","sensors",2,2);
    hw_operation(rows,"battery_info","device_status",0,0);
    hw_operation(rows,"battery_watch","device_status",0,0);
    hw_operation(rows,"thermal_info","device_status",1,1);
    hw_operation(rows,"thermal_watch","device_status",0,0);
    hw_operation(rows,"haptic_info","haptics",0,0);
    hw_operation(rows,"haptic_play","haptics",2,2);
    hw_operation(rows,"haptic_waveform","haptics",2,2);
    hw_operation(rows,"ir_info","infrared",0,0);
    hw_operation(rows,"ir_transmit","infrared",2,2);
    hw_operation(rows,"location_providers","location",0,0);
    hw_operation(rows,"location_last","location",1,1);
    hw_operation(rows,"location_watch","location",3,3);
    hw_operation(rows,"gnss_status","location",0,0);
    hw_operation(rows,"gnss_measurements","location",0,0);
    hw_operation(rows,"gnss_navigation","location",0,0);
    hw_operation(rows,"gnss_nmea","location",0,0);
    hw_operation(rows,"usb_list","usb",2,2);
    hw_operation(rows,"usb_info","usb",1,1);
    hw_operation(rows,"usb_configurations","usb",3,3);
    hw_operation(rows,"usb_interfaces","usb",4,4);
    hw_operation(rows,"usb_watch","usb",0,0);
    hw_operation(rows,"usb_open","usb",1,1);
    hw_operation(rows,"usb_descriptors","hardware_handle",1,1);
    hw_operation(rows,"usb_configure","hardware_handle",2,2);
    hw_operation(rows,"usb_claim","hardware_handle",4,4);
    hw_operation(rows,"usb_release","hardware_handle",2,2);
    hw_operation(rows,"usb_control_in","hardware_handle",7,7);
    hw_operation(rows,"usb_control_out","hardware_handle",7,7);
    hw_operation(rows,"usb_transfer_in","hardware_handle",4,4);
    hw_operation(rows,"usb_transfer_out","hardware_handle",4,4);
    hw_operation(rows,"usb_accessories","usb",0,0);
    hw_operation(rows,"usb_accessory_open","usb",1,1);
    hw_operation(rows,"key_list","keystore",2,2);
    hw_operation(rows,"key_info","keystore",1,1);
    hw_operation(rows,"key_generate","keystore",3,3);
    hw_operation(rows,"key_public","keystore",1,1);
    hw_operation(rows,"key_sign","keystore",2,2);
    hw_operation(rows,"key_verify","keystore",3,3);
    hw_operation(rows,"key_encrypt","keystore",3,3);
    hw_operation(rows,"key_decrypt","keystore",4,4);
    hw_operation(rows,"key_delete","keystore",1,1);
    hw_operation(rows,"audio_devices","audio",2,2);
    hw_operation(rows,"audio_watch","audio",0,0);
    hw_operation(rows,"audio_input_open","microphone",3,3);
    hw_operation(rows,"audio_output_open","audio",3,3);
    hw_operation(rows,"audio_route","hardware_handle",2,2);
    hw_operation(rows,"audio_control","hardware_handle",2,2);
    hw_operation(rows,"audio_volume","hardware_handle",2,2);
    hw_operation(rows,"midi_list","midi",2,2);
    hw_operation(rows,"midi_info","midi",1,1);
    hw_operation(rows,"midi_ports","midi",3,3);
    hw_operation(rows,"midi_watch","midi",0,0);
    hw_operation(rows,"midi_open","midi",1,1);
    hw_operation(rows,"midi_bluetooth_open","midi",1,1);
    hw_operation(rows,"midi_port_open","hardware_handle",3,3);
    hw_operation(rows,"midi_send","hardware_handle",3,3);
    hw_operation(rows,"midi_flush","hardware_handle",1,1);
    hw_operation(rows,"nsd_browse","network",2,2);
    hw_operation(rows,"nsd_register","network",5,5);
    hw_operation(rows,"nsd_services","hardware_handle",3,3);
    hw_operation(rows,"nsd_resolve","hardware_handle",2,2);
    hw_operation(rows,"nsd_watch_service","hardware_handle",2,2);
    hw_operation(rows,"vpn_status","vpn",0,0);
    hw_operation(rows,"vpn_open","vpn",7,7);
    hw_operation(rows,"vpn_protect","hardware_handle",2,2);
    hw_operation(rows,"vpn_underlying","hardware_handle",2,2);
    hw_operation(rows,"cellular_subscriptions","cellular",2,2);
    hw_operation(rows,"cellular_watch_subscriptions","cellular",0,0);
    hw_operation(rows,"cellular_info","cellular",1,1);
    hw_operation(rows,"cellular_watch","cellular",1,1);
    hw_operation(rows,"cellular_service","cellular",1,1);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"cellular_watch_service","cellular",1,1);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"cellular_cells","cellular",2,2);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"cellular_cell_page","hardware_handle",3,3);
    hw_operation(rows,"wifi_info","wifi",0,0);
    hw_operation(rows,"wifi_watch","wifi",0,0);
    hw_operation(rows,"wifi_connection","wifi",0,0);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"wifi_scan","wifi",1,1);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"wifi_scan_page","hardware_handle",3,3);
    hw_operation(rows,"wifi_request","wifi",6,6);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"wifi_suggest","wifi",6,6);
    hw_operation(rows,"wifi_hotspot","wifi",0,0);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"wifi_hotspot_config","hardware_handle",1,1);
    hw_operation(rows,"p2p_open","wifi",0,0);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"p2p_discover","hardware_handle",1,1);
    hw_operation(rows,"p2p_stop_discovery","hardware_handle",1,1);
    hw_operation(rows,"p2p_peers","hardware_handle",3,3);
    hw_operation(rows,"p2p_connect","hardware_handle",5,5);
    hw_operation(rows,"p2p_cancel","hardware_handle",1,1);
    hw_operation(rows,"p2p_connection","hardware_handle",1,1);
    hw_operation(rows,"p2p_group","hardware_handle",1,1);
    hw_operation(rows,"p2p_group_create","hardware_handle",1,1);
    hw_operation(rows,"p2p_group_create_config","hardware_handle",4,4);
    hw_operation(rows,"p2p_group_attach","hardware_handle",1,1);
    hw_operation(rows,"p2p_group_remove","hardware_handle",1,1);
    hw_operation(rows,"p2p_group_credentials","hardware_handle",1,1);
    hw_operation(rows,"p2p_dns_sd_publish","hardware_handle",4,4);
    hw_operation(rows,"p2p_upnp_publish","hardware_handle",4,4);
    hw_operation(rows,"p2p_dns_sd_browse","hardware_handle",2,2);
    hw_operation(rows,"p2p_dns_sd_txt","hardware_handle",3,3);
    hw_operation(rows,"p2p_upnp_browse","hardware_handle",2,2);
    hw_operation(rows,"p2p_service_request","hardware_handle",3,3);
    hw_operation(rows,"p2p_service_discover","hardware_handle",1,1);
    hw_operation(rows,"p2p_tcp_connect","hardware_handle",4,4);
    hw_operation(rows,"p2p_tcp_listen","hardware_handle",3,3);
    hw_operation(rows,"p2p_tcp_accept","hardware_handle",2,2);
    hw_operation(rows,"p2p_udp_open","hardware_handle",2,2);
    hw_operation(rows,"p2p_udp_send","hardware_handle",4,4);
    hw_operation(rows,"p2p_udp_receive","hardware_handle",3,3);
    hw_operation(rows,"wifi_rtt_info","wifi",0,0);
    hw_operation(rows,"wifi_rtt_watch","wifi",0,0);
    hw_operation(rows,"wifi_rtt_range","hardware_handle",3,3);
    hw_operation(rows,"aware_info","wifi",0,0);
    hw_operation(rows,"aware_watch","wifi",0,0);
    hw_operation(rows,"aware_open","wifi",0,0);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"aware_publish","hardware_handle",7,7);
    hw_operation(rows,"aware_subscribe","hardware_handle",8,8);
    hw_operation(rows,"aware_publish_update","hardware_handle",7,7);
    hw_operation(rows,"aware_subscribe_update","hardware_handle",8,8);
    hw_operation(rows,"aware_peers","hardware_handle",3,3);
    hw_operation(rows,"aware_send","hardware_handle",4,4);
    hw_operation(rows,"aware_network","hardware_handle",8,8);
    hw_operation(rows,"aware_rtt","hardware_handle",3,3);
    hw_operation(rows,"bt_info","bluetooth",0,0);
    hw_operation(rows,"bt_watch","bluetooth",0,0);
    hw_operation(rows,"bt_bonded","bluetooth",2,2);
    hw_operation(rows,"bt_device","bluetooth",1,1);
    hw_operation(rows,"bt_request_enable","bluetooth",0,0);
    hw_operation(rows,"bt_request_discoverable","bluetooth",1,1);
    hw_operation(rows,"bt_scan","bluetooth",1,1);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"bt_scan_page","hardware_handle",3,3);
    hw_operation(rows,"bt_bond","hardware_handle",1,1);
    hw_operation(rows,"bt_uuids","hardware_handle",2,2);
    hw_operation(rows,"bt_rfcomm_listen","bluetooth",3,3);
    hw_operation(rows,"bt_rfcomm_connect","hardware_handle",4,4);
    hw_operation(rows,"bt_rfcomm_accept","hardware_handle",2,2);
    hw_operation(rows,"ble_info","bluetooth",0,0);
    hw_operation(rows,"ble_scan","bluetooth",4,4);
    j_set(j_at(rows,j_count(rows)-1),"also",j_string("location"));
    hw_operation(rows,"ble_scan_page","hardware_handle",3,3);
    hw_operation(rows,"ble_advertise","bluetooth",8,8);
    hw_operation(rows,"ble_connect","bluetooth",3,3);
    hw_operation(rows,"ble_gatt_discover","hardware_handle",2,2);
    hw_operation(rows,"ble_gatt_items","hardware_handle",4,4);
    hw_operation(rows,"ble_gatt_read","hardware_handle",3,3);
    hw_operation(rows,"ble_gatt_write","hardware_handle",5,5);
    hw_operation(rows,"ble_gatt_local_notify","hardware_handle",3,3);
    hw_operation(rows,"ble_gatt_mtu","hardware_handle",3,3);
    hw_operation(rows,"ble_gatt_rssi","hardware_handle",2,2);
    hw_operation(rows,"ble_gatt_phy_read","hardware_handle",2,2);
    hw_operation(rows,"ble_gatt_phy","hardware_handle",5,5);
    hw_operation(rows,"ble_gatt_priority","hardware_handle",2,2);
    hw_operation(rows,"ble_server_open","bluetooth",1,1);
    hw_operation(rows,"ble_server_add","hardware_handle",4,4);
    hw_operation(rows,"ble_server_items","hardware_handle",4,4);
    hw_operation(rows,"ble_server_remove","hardware_handle",2,2);
    hw_operation(rows,"ble_server_peers","hardware_handle",3,3);
    hw_operation(rows,"ble_server_requests","hardware_handle",3,3);
    hw_operation(rows,"ble_server_respond","hardware_handle",5,5);
    hw_operation(rows,"ble_server_notify","hardware_handle",6,6);
    hw_operation(rows,"ble_server_disconnect","hardware_handle",2,2);
    hw_operation(rows,"ble_server_phy_read","hardware_handle",3,3);
    hw_operation(rows,"ble_server_phy","hardware_handle",6,6);
    hw_operation(rows,"hid_open","bluetooth",8,8);
    hw_operation(rows,"hid_connect","hardware_handle",2,2);
    hw_operation(rows,"hid_peers","hardware_handle",3,3);
    hw_operation(rows,"hid_requests","hardware_handle",3,3);
    hw_operation(rows,"hid_reply","hardware_handle",3,3);
    hw_operation(rows,"hid_error","hardware_handle",3,3);
    hw_operation(rows,"hid_send","hardware_handle",4,4);
    hw_operation(rows,"hid_disconnect","hardware_handle",2,2);
    hw_operation(rows,"nfc_info","nfc",0,0);
    hw_operation(rows,"nfc_watch","nfc",0,0);
    hw_operation(rows,"nfc_reader","nfc",2,2);
    hw_operation(rows,"nfc_tags","hardware_handle",3,3);
    hw_operation(rows,"nfc_tag_info","hardware_handle",2,2);
    hw_operation(rows,"nfc_cached_ndef","hardware_handle",2,2);
    hw_operation(rows,"nfc_ignore","hardware_handle",3,3);
    hw_operation(rows,"nfc_connect","hardware_handle",3,3);
    hw_operation(rows,"nfc_timeout","hardware_handle",2,2);
    hw_operation(rows,"nfc_transceive","hardware_handle",2,2);
    hw_operation(rows,"nfc_mifare_auth","hardware_handle",4,4);
    hw_operation(rows,"nfc_ndef_read","hardware_handle",1,1);
    hw_operation(rows,"nfc_ndef_write","hardware_handle",2,2);
    hw_operation(rows,"nfc_ndef_read_only","hardware_handle",1,1);
    hw_operation(rows,"nfc_ndef_format","hardware_handle",3,3);
    hw_operation(rows,"se_open","secure_element",1,1);
    hw_operation(rows,"se_readers","hardware_handle",3,3);
    hw_operation(rows,"se_uicc","hardware_handle",2,2);
    hw_operation(rows,"se_session","hardware_handle",2,2);
    hw_operation(rows,"se_channel","hardware_handle",4,4);
    hw_operation(rows,"se_select_response","hardware_handle",1,1);
    hw_operation(rows,"se_select_next","hardware_handle",1,1);
    hw_operation(rows,"se_transmit","hardware_handle",2,2);
    hw_operation(rows,"se_command","hardware_handle",2,2);
    hw_operation(rows,"se_command_write","hardware_handle",3,3);
    hw_operation(rows,"se_send","hardware_handle",1,1);
    hw_operation(rows,"se_response","hardware_handle",4,4);
    hw_operation(rows,"input_devices","input",2,2);
    hw_operation(rows,"input_info","input",1,1);
    hw_operation(rows,"input_ranges","input",3,3);
    hw_operation(rows,"input_has_keys","input",2,2);
    hw_operation(rows,"input_watch","input",4,4);
    hw_operation(rows,"biometric_info","biometrics",1,1);
    hw_operation(rows,"biometric_auth","biometrics",6,6);
    hw_operation(rows,"biometric_cancel","hardware_handle",1,1);
    hw_operation(rows,"uwb_info","uwb",0,0);
    hw_operation(rows,"uwb_watch","uwb",0,0);
    hw_operation(rows,"uwb_range","uwb",3,3);
    hw_operation(rows,"uwb_stop","hardware_handle",1,1);
    hw_operation(rows,"uwb_add","hardware_handle",2,2);
    hw_operation(rows,"uwb_remove","hardware_handle",2,2);
    hw_operation(rows,"uwb_interval","hardware_handle",2,2);
    hw_operation(rows,"document_pick","documents",2,2);
    hw_operation(rows,"document_trees","documents",2,2);
    hw_operation(rows,"document_forget","documents",1,1);
    hw_operation(rows,"document_tree_open","documents",1,1);
    hw_operation(rows,"document_info","documents",2,2);
    hw_operation(rows,"document_children","documents",4,4);
    hw_operation(rows,"document_file_open","documents",3,3);
    hw_operation(rows,"document_seek","documents",2,2);
    hw_operation(rows,"document_create","documents",4,4);
    hw_operation(rows,"document_rename","documents",3,3);
    hw_operation(rows,"document_delete","documents",2,2);
    hw_operation(rows,"document_types","documents",3,3);
    hw_operation(rows,"document_typed_open","documents",3,3);
    hw_operation(rows,"document_copy","documents",3,3);
    hw_operation(rows,"document_move","documents",4,4);
    hw_operation(rows,"document_remove","documents",3,3);
    hw_registry=rows;return rows;
}
fn hw_find(name){let rows=hw_operations();let i=0;while i<j_count(rows){let row=j_at(rows,i);if h_equal(cj_text(row,"name"),name){return row;}i=i+1;}return 0;}
fn hw_error(code,message){let e=db_list();db_add(e,db_text(code));db_add(e,db_text(message));return e;}
// JSON exists only at the platform boundary. Guest values remain the ordinary
// bounded FlexDB value types, including binary blobs and exact float bit patterns.
fn hw_json(value,depth){
    if depth>16 || !value{return 0;}let kind=db_kind(value);
    if kind==0{return cj_null();}if kind==1{return j_int(db_word(value));}
    if kind==2{return j_string(db_word(value));}
    if kind==3{let o=j_object();j_set(o,"$bytes",j_string(ci_base64(db_word(value),db_bytes(value))));return o;}
    if kind==4{let o=j_object();j_set(o,"$real",j_int(db_word(value)));return o;}
    if kind==5{let o=j_array();let i=0;while i<db_count(value){let item=hw_json(db_at(value,i),depth+1);if !item{return 0;}j_push(o,item);i=i+1;}return o;}return 0;
}
fn hw_b64_digit(c){let text="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";let i=0;while i<64{if load8(text+i)==c{return i;}i=i+1;}return -1;}
fn hw_bytes(text){
    let n=h_len(text);if n%4 || n>43692{return 0;}let bytes=n/4*3;if n && load8(text+n-1)==61{bytes=bytes-1;}if n>1 && load8(text+n-2)==61{bytes=bytes-1;}if bytes>32768{return 0;}
    let out=alloc(bytes+1);let at=0;let i=0;while i<n{let a=hw_b64_digit(load8(text+i));let b=hw_b64_digit(load8(text+i+1));let c=0;let d=0;let x=load8(text+i+2);let y=load8(text+i+3);
        if x!=61{c=hw_b64_digit(x);}if y!=61{d=hw_b64_digit(y);}
        if a<0 || b<0 || c<0 || d<0 || (x==61 && (y!=61 || i+4!=n || b%16)) || (y==61 && (i+4!=n || c%4)){return 0;}
        let value=(a<<18)|(b<<12)|(c<<6)|d;store8(out+at,(value>>16)&255);at=at+1;if x!=61{store8(out+at,(value>>8)&255);at=at+1;}if y!=61{store8(out+at,value&255);at=at+1;}i=i+4;
    }return db_blob(out,bytes);
}
// The API JSON reader intentionally keeps 19-digit metadata opaque. Hardware
// integers use a checked signed parser rather than losing their low bits.
fn hw_integer(value){
    if j_kind(value)==1{return db_int(j_value(value));}if j_kind(value)!=6{return 0;}
    let text=j_value(value);let i=0;let negative=load8(text)==45;if negative{i=1;}if !load8(text+i){return 0;}
    let limit=-9223372036854775807;if negative{limit=limit-1;}let floor=limit/10;let digit_limit=-(limit%10);let n=0;
    while load8(text+i){let digit=load8(text+i)-48;if digit<0 || digit>9 || n<floor || (n==floor && digit>digit_limit){return 0;}n=n*10-digit;i=i+1;}
    if !negative{n=-n;}return db_int(n);
}
fn hw_value(value,depth){
    if !value || depth>16{return 0;}let kind=j_kind(value);
    if kind==0{return db_null();}if kind==1 || kind==6{return hw_integer(value);}if kind==5{return db_int(j_value(value));}if kind==2{return db_text(j_value(value));}
    if kind==3{let out=db_list();let i=0;while i<j_count(value){let item=hw_value(j_at(value,i),depth+1);if !item || !db_add(out,item){return 0;}i=i+1;}return out;}
    if kind==4{
        let bytes=cj_get(value,"$bytes");if bytes{if j_count(value)!=1 || j_kind(bytes)!=2{return 0;}return hw_bytes(j_value(bytes));}
        let real=cj_get(value,"$real");if real{if j_count(value)!=1{return 0;}let bits=hw_integer(real);if !bits{return 0;}return db_real(db_word(bits));}
        let out=db_list();let fields=j_value(value);let i=0;while i<h_count(fields){let pair=h_at(fields,i);let row=db_list();let item=hw_value(load64(pair+8),depth+1);if !item{return 0;}db_add(row,db_text(load64(pair)));db_add(row,item);if !db_add(out,row){return 0;}i=i+1;}return out;
    }return 0;
}
