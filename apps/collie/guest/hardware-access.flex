// Portable capability descriptions. OS facts do not enable an absent adapter.
// Public alternatives preserve their own lazy grants and Android consent.
fn hardware_access_field(map,key,value){let pair=db_list();db_add(pair,db_text(key));db_add(pair,value);db_add(map,pair);return map;}
fn hardware_restriction(rows,id,reason,alternative){
    let row=db_list();hardware_access_field(row,"id",db_text(id));
    hardware_access_field(row,"implemented",db_int(0));
    hardware_access_field(row,"supported",db_null());
    hardware_access_field(row,"available",db_int(0));
    hardware_access_field(row,"permission",db_text("progress"));
    hardware_access_field(row,"discovery_implemented",db_int(1));
    hardware_access_field(row,"code",db_text("adapter_unimplemented"));
    hardware_access_field(row,"requires",db_text("privileged_or_vendor_integration"));
    hardware_access_field(row,"reason",db_text(reason));
    hardware_access_field(row,"alternative",db_text(alternative));db_add(rows,row);return rows;
}
fn hardware_restriction_rows(){
    let rows=db_list();
    hardware_restriction(rows,"wifi_monitor","Raw 802.11 monitor frames need a suitable driver and privileged integration; scan results are not raw frames.","wifi_scan, wifi_scan_page");
    hardware_restriction(rows,"wifi_frame_injection","Arbitrary 802.11 frame transmission needs a suitable driver and privileged integration.","net_udp_open, net_udp_send");
    hardware_restriction(rows,"cellular_raw_radio","Baseband/IQ transport is vendor-specific and is not exposed by Collie's telephony diagnostics.","cellular_info, cellular_cells");
    hardware_restriction(rows,"cellular_radio_control","Modem power, bands and global SIM/radio controls require platform or carrier integration.","cellular_subscriptions, net_request");
    hardware_restriction(rows,"usb_gadget","Selecting device-side USB functions and emulating a USB keyboard need platform gadget integration; USB host and accessory mode do not provide it.","usb_list, usb_accessories, hid_open");
    hardware_restriction(rows,"bluetooth_raw_hci","Raw HCI/controller commands need a platform or vendor transport; the public Bluetooth profiles are separate.","bt_info, ble_scan, hid_open");
    hardware_restriction(rows,"internal_i2c","Internal I2C buses need an explicitly supported vendor service or device-node integration.","usb_list, serial_ports");
    hardware_restriction(rows,"internal_spi","Internal SPI buses need an explicitly supported vendor service or device-node integration.","usb_list, serial_ports");
    hardware_restriction(rows,"internal_gpio","Internal GPIO controllers need an explicitly supported vendor service or device-node integration.","usb_list, serial_ports");
    hardware_restriction(rows,"cpu_clock_control","CPU clocks and governor controls need platform/vendor policy; thermal readings do not grant clock control.","thermal_info, thermal_watch");
    hardware_restriction(rows,"gpu_clock_control","GPU clocks and governor controls need platform/vendor policy.","thermal_info, thermal_watch");
    hardware_restriction(rows,"charging_control","Charging enable/current/voltage controls are vendor-specific; battery readings do not grant charging control.","battery_info, battery_watch");
    hardware_restriction(rows,"global_routing_control","Global routes, forwarding and tethering need platform integration; per-network sockets and approved VPN sessions have narrower scope.","net_list, net_request, vpn_open");
    hardware_restriction(rows,"raw_input_injection","Raw cross-app input injection needs platform privileges; user-enabled accessibility actions/gestures are a separate public API.","input_watch, accessibility_open, accessibility_gesture");
    hardware_restriction(rows,"raw_device_nodes","Arbitrary host device nodes are not exposed to the VM; ownership, SELinux and driver permissions require an explicit integration.","hardware_capabilities");
    hardware_restriction(rows,"vendor_hardware_services","No vendor Binder/HAL transport is configured. Its presence, access and supported operations remain unknown.","hardware_access_info");
    return rows;
}
fn hardware_restrictions(){
    let facts=hardware_access_info();if !facts{return 0;}
    let report=db_list();hardware_access_field(report,"platform",facts);
    hardware_access_field(report,"restrictions",hardware_restriction_rows());return report;
}
