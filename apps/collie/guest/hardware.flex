// Ordinary Flexscript hardware functions; no model tools or raw host FFI.
// Maps are lists of [key,value] pairs. Bytes are db_blob, measurements db_real.
fn device_field(map,key){let i=0;while i<db_count(map){let row=db_at(map,i);let name=db_at(row,0);if db_kind(name)==2 && worker_equal(db_word(name),key){return db_at(row,1);}i=i+1;}return db_null();}
fn hardware_call(op,args){let r=db_request(op);let i=0;while i<db_count(args){db_add(r,db_at(args,i));i=i+1;}return db_rpc(r);}
fn hardware_api(){return db_rpc(db_request("hardware_api"));}
fn hardware_api_page(offset,limit){let r=db_request("hardware_api_page");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn hardware_capabilities(){return db_rpc(db_request("hardware_capabilities"));}
fn net_list(){return db_rpc(db_request("net_list"));}
fn net_info(network){let r=db_request("net_info");db_add(r,db_text(network));return db_rpc(r);}
fn net_watch(){return db_rpc(db_request("net_watch"));}
fn net_request(transport){let r=db_request("net_request");db_add(r,db_text(transport));return db_rpc(r);}
fn net_resolve(network,host){let r=db_request("net_resolve");db_add(r,db_text(network));db_add(r,db_text(host));return db_rpc(r);}
fn net_tcp_connect(network,host,port,timeout_ms){let r=db_request("net_tcp_connect");db_add(r,db_text(network));db_add(r,db_text(host));db_add(r,db_int(port));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn net_tcp_open(network){let r=db_request("net_tcp_open");db_add(r,db_text(network));return db_rpc(r);}
fn net_tcp_dial(handle,host,port,timeout_ms){let r=db_request("net_tcp_dial");db_add(r,db_text(handle));db_add(r,db_text(host));db_add(r,db_int(port));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn net_tcp_listen(network,port,backlog){let r=db_request("net_tcp_listen");db_add(r,db_text(network));db_add(r,db_int(port));db_add(r,db_int(backlog));return db_rpc(r);}
fn net_tcp_accept(server,timeout_ms){let r=db_request("net_tcp_accept");db_add(r,db_text(server));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn net_udp_open(network,port){let r=db_request("net_udp_open");db_add(r,db_text(network));db_add(r,db_int(port));return db_rpc(r);}
fn net_udp_send(socket,host,port,value){let r=db_request("net_udp_send");db_add(r,db_text(socket));db_add(r,db_text(host));db_add(r,db_int(port));db_add(r,value);return db_rpc(r);}
fn net_udp_receive(socket,limit,timeout_ms){let r=db_request("net_udp_receive");db_add(r,db_text(socket));db_add(r,db_int(limit));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn net_http(network,url,timeout_ms){let r=db_request("net_http");db_add(r,db_text(network));db_add(r,db_text(url));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn device_read(handle,limit,timeout_ms){let r=db_request("device_read");db_add(r,db_text(handle));db_add(r,db_int(limit));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn device_write(handle,value){let r=db_request("device_write");db_add(r,db_text(handle));db_add(r,value);return db_rpc(r);}
fn device_wait(handle,timeout_ms){let r=db_request("device_wait");db_add(r,db_text(handle));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn device_info(handle){let r=db_request("device_info");db_add(r,db_text(handle));return db_rpc(r);}
fn device_close(handle){let r=db_request("device_close");db_add(r,db_text(handle));return db_word(db_rpc(r));}
fn device_error(){if !db_last_error_details{return db_null();}return db_last_error_details;}

fn sensor_list(){return db_rpc(db_request("sensor_list"));}
fn sensor_list_page(offset,limit){let r=db_request("sensor_list");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn sensor_info(id){let r=db_request("sensor_info");db_add(r,db_text(id));return db_rpc(r);}
fn sensor_open(id,period_us){let r=db_request("sensor_open");db_add(r,db_text(id));db_add(r,db_int(period_us));return db_rpc(r);}
fn battery_info(){return db_rpc(db_request("battery_info"));}
fn battery_watch(){return db_rpc(db_request("battery_watch"));}
fn thermal_info(forecast_seconds){let r=db_request("thermal_info");db_add(r,db_int(forecast_seconds));return db_rpc(r);}
fn thermal_watch(){return db_rpc(db_request("thermal_watch"));}
fn haptic_info(){return db_rpc(db_request("haptic_info"));}
fn haptic_play(duration_ms,amplitude){let r=db_request("haptic_play");db_add(r,db_int(duration_ms));db_add(r,db_int(amplitude));return db_rpc(r);}
fn haptic_waveform(timing,amplitudes){let r=db_request("haptic_waveform");db_add(r,timing);db_add(r,amplitudes);return db_rpc(r);}
fn ir_info(){return db_rpc(db_request("ir_info"));}
fn ir_transmit(frequency_hz,pattern){let r=db_request("ir_transmit");db_add(r,db_int(frequency_hz));db_add(r,pattern);return db_word(db_rpc(r));}

fn location_providers(){return db_rpc(db_request("location_providers"));}
fn location_last(provider){let r=db_request("location_last");db_add(r,db_text(provider));return db_rpc(r);}
fn location_watch(provider,period_ms,distance_mm){let r=db_request("location_watch");db_add(r,db_text(provider));db_add(r,db_int(period_ms));db_add(r,db_int(distance_mm));return db_rpc(r);}
fn gnss_status(){return db_rpc(db_request("gnss_status"));}
fn gnss_measurements(){return db_rpc(db_request("gnss_measurements"));}
fn gnss_navigation(){return db_rpc(db_request("gnss_navigation"));}
fn gnss_nmea(){return db_rpc(db_request("gnss_nmea"));}

// USB identifiers come from inventory, never host paths or file descriptors.
fn usb_list(offset,limit){let r=db_request("usb_list");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn usb_info(id){let r=db_request("usb_info");db_add(r,db_text(id));return db_rpc(r);}
fn usb_configurations(id,offset,limit){let r=db_request("usb_configurations");db_add(r,db_text(id));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn usb_interfaces(id,configuration,offset,limit){let r=db_request("usb_interfaces");db_add(r,db_text(id));db_add(r,db_int(configuration));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn usb_watch(){return db_rpc(db_request("usb_watch"));}
fn usb_open(id){let r=db_request("usb_open");db_add(r,db_text(id));return db_rpc(r);}
fn usb_descriptors(handle){let r=db_request("usb_descriptors");db_add(r,db_text(handle));return db_rpc(r);}
fn usb_configure(handle,configuration){let r=db_request("usb_configure");db_add(r,db_text(handle));db_add(r,db_int(configuration));return db_rpc(r);}
fn usb_claim(handle,interface_id,alternate,force){let r=db_request("usb_claim");db_add(r,db_text(handle));db_add(r,db_int(interface_id));db_add(r,db_int(alternate));db_add(r,db_int(force));return db_rpc(r);}
fn usb_release(handle,interface_id){let r=db_request("usb_release");db_add(r,db_text(handle));db_add(r,db_int(interface_id));return db_rpc(r);}
fn usb_control_in(handle,request_type,request,value,index,limit,timeout_ms){let r=db_request("usb_control_in");db_add(r,db_text(handle));db_add(r,db_int(request_type));db_add(r,db_int(request));db_add(r,db_int(value));db_add(r,db_int(index));db_add(r,db_int(limit));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn usb_control_out(handle,request_type,request,value,index,data,timeout_ms){let r=db_request("usb_control_out");db_add(r,db_text(handle));db_add(r,db_int(request_type));db_add(r,db_int(request));db_add(r,db_int(value));db_add(r,db_int(index));db_add(r,data);db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn usb_transfer_in(handle,endpoint,limit,timeout_ms){let r=db_request("usb_transfer_in");db_add(r,db_text(handle));db_add(r,db_int(endpoint));db_add(r,db_int(limit));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn usb_transfer_out(handle,endpoint,data,timeout_ms){let r=db_request("usb_transfer_out");db_add(r,db_text(handle));db_add(r,db_int(endpoint));db_add(r,data);db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn usb_accessories(){return db_rpc(db_request("usb_accessories"));}
fn usb_accessory_open(id){let r=db_request("usb_accessory_open");db_add(r,db_text(id));return db_rpc(r);}

// Keys stay inside Android Keystore. Aliases belong to this workspace only.
fn key_list(offset,limit){let r=db_request("key_list");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn key_info(alias){let r=db_request("key_info");db_add(r,db_text(alias));return db_rpc(r);}
fn key_generate(alias,kind,backing){let r=db_request("key_generate");db_add(r,db_text(alias));db_add(r,db_text(kind));db_add(r,db_text(backing));return db_rpc(r);}
fn key_public(alias){let r=db_request("key_public");db_add(r,db_text(alias));return db_rpc(r);}
fn key_sign(alias,data){let r=db_request("key_sign");db_add(r,db_text(alias));db_add(r,data);return db_rpc(r);}
fn key_verify(alias,data,signature){let r=db_request("key_verify");db_add(r,db_text(alias));db_add(r,data);db_add(r,signature);return db_rpc(r);}
fn key_encrypt(alias,data,aad){let r=db_request("key_encrypt");db_add(r,db_text(alias));db_add(r,data);db_add(r,aad);return db_rpc(r);}
fn key_decrypt(alias,nonce,ciphertext,aad){let r=db_request("key_decrypt");db_add(r,db_text(alias));db_add(r,nonce);db_add(r,ciphertext);db_add(r,aad);return db_rpc(r);}
fn key_delete(alias){let r=db_request("key_delete");db_add(r,db_text(alias));return db_rpc(r);}

// PCM16 little-endian, one or two channels; rate is samples per second.
fn audio_devices(offset,limit){let r=db_request("audio_devices");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn audio_watch(){return db_rpc(db_request("audio_watch"));}
fn audio_input_open(device,rate,channels){let r=db_request("audio_input_open");db_add(r,db_text(device));db_add(r,db_int(rate));db_add(r,db_int(channels));return db_rpc(r);}
fn audio_output_open(device,rate,channels){let r=db_request("audio_output_open");db_add(r,db_text(device));db_add(r,db_int(rate));db_add(r,db_int(channels));return db_rpc(r);}
fn audio_route(handle,device){let r=db_request("audio_route");db_add(r,db_text(handle));db_add(r,db_text(device));return db_rpc(r);}
fn audio_control(handle,action){let r=db_request("audio_control");db_add(r,db_text(handle));db_add(r,db_text(action));return db_rpc(r);}
fn audio_volume(handle,permille){let r=db_request("audio_volume");db_add(r,db_text(handle));db_add(r,db_int(permille));return db_rpc(r);}

fn midi_list(offset,limit){let r=db_request("midi_list");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn midi_info(id){let r=db_request("midi_info");db_add(r,db_text(id));return db_rpc(r);}
fn midi_ports(id,offset,limit){let r=db_request("midi_ports");db_add(r,db_text(id));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn midi_watch(){return db_rpc(db_request("midi_watch"));}
fn midi_open(id){let r=db_request("midi_open");db_add(r,db_text(id));return db_rpc(r);}
fn midi_bluetooth_open(address){let r=db_request("midi_bluetooth_open");db_add(r,db_text(address));return db_rpc(r);}
fn midi_port_open(device,direction,port){let r=db_request("midi_port_open");db_add(r,db_text(device));db_add(r,db_text(direction));db_add(r,db_int(port));return db_rpc(r);}
fn midi_send(port,data,timestamp_ns){let r=db_request("midi_send");db_add(r,db_text(port));db_add(r,data);db_add(r,db_int(timestamp_ns));return db_rpc(r);}
fn midi_flush(port){let r=db_request("midi_flush");db_add(r,db_text(port));return db_rpc(r);}

// DNS-SD uses a specific service type, with scoped discovery/registration handles.
fn nsd_browse(service_type,network){let r=db_request("nsd_browse");db_add(r,db_text(service_type));db_add(r,db_text(network));return db_rpc(r);}
fn nsd_register(name,service_type,port,attributes,network){let r=db_request("nsd_register");db_add(r,db_text(name));db_add(r,db_text(service_type));db_add(r,db_int(port));db_add(r,attributes);db_add(r,db_text(network));return db_rpc(r);}
fn nsd_services(browser,offset,limit){let r=db_request("nsd_services");db_add(r,db_text(browser));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn nsd_resolve(browser,service){let r=db_request("nsd_resolve");db_add(r,db_text(browser));db_add(r,db_text(service));return db_rpc(r);}
fn nsd_watch_service(browser,service){let r=db_request("nsd_watch_service");db_add(r,db_text(browser));db_add(r,db_text(service));return db_rpc(r);}

// Raw Android TUN packet transport. Encryption/peer protocols are separate.
fn vpn_status(){return db_rpc(db_request("vpn_status"));}
fn vpn_open(name,addresses,routes,dns,mtu,apps,network){let r=db_request("vpn_open");db_add(r,db_text(name));db_add(r,addresses);db_add(r,routes);db_add(r,dns);db_add(r,db_int(mtu));db_add(r,apps);db_add(r,db_text(network));return db_rpc(r);}
fn vpn_protect(vpn,socket){let r=db_request("vpn_protect");db_add(r,db_text(vpn));db_add(r,db_text(socket));return db_rpc(r);}
fn vpn_underlying(vpn,network){let r=db_request("vpn_underlying");db_add(r,db_text(vpn));db_add(r,db_text(network));return db_rpc(r);}

// Cellular diagnostics: -1 selects the default active subscription.
fn cellular_subscriptions(offset,limit){let r=db_request("cellular_subscriptions");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn cellular_watch_subscriptions(){let r=db_request("cellular_watch_subscriptions");return db_rpc(r);}
fn cellular_info(subscription){let r=db_request("cellular_info");db_add(r,db_int(subscription));return db_rpc(r);}
fn cellular_watch(subscription){let r=db_request("cellular_watch");db_add(r,db_int(subscription));return db_rpc(r);}
fn cellular_service(subscription){let r=db_request("cellular_service");db_add(r,db_int(subscription));return db_rpc(r);}
fn cellular_watch_service(subscription){let r=db_request("cellular_watch_service");db_add(r,db_int(subscription));return db_rpc(r);}
fn cellular_cells(subscription,refresh){let r=db_request("cellular_cells");db_add(r,db_int(subscription));db_add(r,db_int(refresh));return db_rpc(r);}
fn cellular_cell_page(snapshot,offset,limit){let r=db_request("cellular_cell_page");db_add(r,db_text(snapshot));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}

// Android Wi-Fi leases and copied scan snapshots.
fn wifi_info(){let r=db_request("wifi_info");return db_rpc(r);}
fn wifi_watch(){let r=db_request("wifi_watch");return db_rpc(r);}
fn wifi_connection(){let r=db_request("wifi_connection");return db_rpc(r);}
fn wifi_scan(refresh){let r=db_request("wifi_scan");db_add(r,db_int(refresh));return db_rpc(r);}
fn wifi_scan_page(snapshot,offset,limit){let r=db_request("wifi_scan_page");db_add(r,db_text(snapshot));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn wifi_request(ssid,security,password,bssid,hidden,timeout_ms){let r=db_request("wifi_request");db_add(r,db_text(ssid));db_add(r,db_text(security));db_add(r,db_text(password));db_add(r,db_text(bssid));db_add(r,db_int(hidden));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn wifi_suggest(ssid,security,password,hidden,metered,autojoin){let r=db_request("wifi_suggest");db_add(r,db_text(ssid));db_add(r,db_text(security));db_add(r,db_text(password));db_add(r,db_int(hidden));db_add(r,db_int(metered));db_add(r,db_int(autojoin));return db_rpc(r);}
fn wifi_hotspot(){let r=db_request("wifi_hotspot");return db_rpc(r);}
fn wifi_hotspot_config(hotspot){let r=db_request("wifi_hotspot_config");db_add(r,db_text(hotspot));return db_rpc(r);}

// Wi-Fi Direct channel, group and service resources; child handles share grants.
fn p2p_open(){let r=db_request("p2p_open");return db_rpc(r);}
fn p2p_discover(channel){let r=db_request("p2p_discover");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_stop_discovery(channel){let r=db_request("p2p_stop_discovery");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_peers(channel,offset,limit){let r=db_request("p2p_peers");db_add(r,db_text(channel));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn p2p_connect(channel,peer,wps,pin,owner_intent){let r=db_request("p2p_connect");db_add(r,db_text(channel));db_add(r,db_text(peer));db_add(r,db_text(wps));db_add(r,db_text(pin));db_add(r,db_int(owner_intent));return db_rpc(r);}
fn p2p_cancel(channel){let r=db_request("p2p_cancel");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_connection(channel){let r=db_request("p2p_connection");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_group(channel){let r=db_request("p2p_group");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_group_create(channel){let r=db_request("p2p_group_create");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_group_create_config(channel,name,password,band){let r=db_request("p2p_group_create_config");db_add(r,db_text(channel));db_add(r,db_text(name));db_add(r,db_text(password));db_add(r,db_int(band));return db_rpc(r);}
fn p2p_group_remove(channel){let r=db_request("p2p_group_remove");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_group_credentials(channel){let r=db_request("p2p_group_credentials");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_dns_sd_publish(channel,instance,type,attributes){let r=db_request("p2p_dns_sd_publish");db_add(r,db_text(channel));db_add(r,db_text(instance));db_add(r,db_text(type));db_add(r,attributes);return db_rpc(r);}
fn p2p_upnp_publish(channel,uuid,device,services){let r=db_request("p2p_upnp_publish");db_add(r,db_text(channel));db_add(r,db_text(uuid));db_add(r,db_text(device));db_add(r,services);return db_rpc(r);}
fn p2p_dns_sd_browse(channel,type){let r=db_request("p2p_dns_sd_browse");db_add(r,db_text(channel));db_add(r,db_text(type));return db_rpc(r);}
fn p2p_upnp_browse(channel,target){let r=db_request("p2p_upnp_browse");db_add(r,db_text(channel));db_add(r,db_text(target));return db_rpc(r);}
fn p2p_service_request(channel,protocol,query_hex){let r=db_request("p2p_service_request");db_add(r,db_text(channel));db_add(r,db_int(protocol));db_add(r,db_text(query_hex));return db_rpc(r);}
fn p2p_service_discover(channel){let r=db_request("p2p_service_discover");db_add(r,db_text(channel));return db_rpc(r);}
fn p2p_tcp_connect(channel,address,port,timeout_ms){let r=db_request("p2p_tcp_connect");db_add(r,db_text(channel));db_add(r,db_text(address));db_add(r,db_int(port));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn p2p_tcp_listen(channel,port,backlog){let r=db_request("p2p_tcp_listen");db_add(r,db_text(channel));db_add(r,db_int(port));db_add(r,db_int(backlog));return db_rpc(r);}
fn p2p_tcp_accept(listener,timeout_ms){let r=db_request("p2p_tcp_accept");db_add(r,db_text(listener));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn p2p_udp_open(channel,port){let r=db_request("p2p_udp_open");db_add(r,db_text(channel));db_add(r,db_int(port));return db_rpc(r);}
fn p2p_udp_send(socket,address,port,data){let r=db_request("p2p_udp_send");db_add(r,db_text(socket));db_add(r,db_text(address));db_add(r,db_int(port));db_add(r,data);return db_rpc(r);}
fn p2p_udp_receive(socket,limit,timeout_ms){let r=db_request("p2p_udp_receive");db_add(r,db_text(socket));db_add(r,db_int(limit));db_add(r,db_int(timeout_ms));return db_rpc(r);}

fn p2p_group_attach(channel){let r=db_request("p2p_group_attach");db_add(r,db_text(channel));return db_rpc(r);}

fn p2p_dns_sd_txt(channel,instance,type){let r=db_request("p2p_dns_sd_txt");db_add(r,db_text(channel));db_add(r,db_text(instance));db_add(r,db_text(type));return db_rpc(r);}

fn wifi_rtt_info(){return db_rpc(db_request("wifi_rtt_info"));}
fn wifi_rtt_watch(){return db_rpc(db_request("wifi_rtt_watch"));}
fn wifi_rtt_range(scan,bssids,burst){let r=db_request("wifi_rtt_range");db_add(r,db_text(scan));db_add(r,bssids);db_add(r,db_int(burst));return db_rpc(r);}

fn aware_info(){return db_rpc(db_request("aware_info"));}
fn aware_watch(){return db_rpc(db_request("aware_watch"));}
fn aware_open(){return db_rpc(db_request("aware_open"));}
fn aware_publish(attachment,name,info,filters,kind,ttl,ranging){let r=db_request("aware_publish");db_add(r,db_text(attachment));db_add(r,db_text(name));db_add(r,info);db_add(r,filters);db_add(r,db_int(kind));db_add(r,db_int(ttl));db_add(r,db_int(ranging));return db_rpc(r);}
fn aware_subscribe(attachment,name,info,filters,kind,ttl,min_mm,max_mm){let r=db_request("aware_subscribe");db_add(r,db_text(attachment));db_add(r,db_text(name));db_add(r,info);db_add(r,filters);db_add(r,db_int(kind));db_add(r,db_int(ttl));db_add(r,db_int(min_mm));db_add(r,db_int(max_mm));return db_rpc(r);}
fn aware_publish_update(discovery,name,info,filters,kind,ttl,ranging){let r=db_request("aware_publish_update");db_add(r,db_text(discovery));db_add(r,db_text(name));db_add(r,info);db_add(r,filters);db_add(r,db_int(kind));db_add(r,db_int(ttl));db_add(r,db_int(ranging));return db_rpc(r);}
fn aware_subscribe_update(discovery,name,info,filters,kind,ttl,min_mm,max_mm){let r=db_request("aware_subscribe_update");db_add(r,db_text(discovery));db_add(r,db_text(name));db_add(r,info);db_add(r,filters);db_add(r,db_int(kind));db_add(r,db_int(ttl));db_add(r,db_int(min_mm));db_add(r,db_int(max_mm));return db_rpc(r);}
fn aware_peers(discovery,offset,limit){let r=db_request("aware_peers");db_add(r,db_text(discovery));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn aware_send(discovery,peer,id,bytes){let r=db_request("aware_send");db_add(r,db_text(discovery));db_add(r,db_text(peer));db_add(r,db_int(id));db_add(r,bytes);return db_rpc(r);}
fn aware_network(discovery,peer,security,key,cipher,port,protocol,timeout){let r=db_request("aware_network");db_add(r,db_text(discovery));db_add(r,db_text(peer));db_add(r,db_text(security));db_add(r,key);db_add(r,db_int(cipher));db_add(r,db_int(port));db_add(r,db_int(protocol));db_add(r,db_int(timeout));return db_rpc(r);}
fn aware_rtt(discovery,peers,burst){let r=db_request("aware_rtt");db_add(r,db_text(discovery));db_add(r,peers);db_add(r,db_int(burst));return db_rpc(r);}

fn bt_info(){return db_rpc(db_request("bt_info"));}
fn bt_watch(){return db_rpc(db_request("bt_watch"));}
fn bt_bonded(offset,limit){let r=db_request("bt_bonded");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn bt_device(address){let r=db_request("bt_device");db_add(r,db_text(address));return db_rpc(r);}
fn bt_request_enable(){return db_rpc(db_request("bt_request_enable"));}
fn bt_request_discoverable(seconds){let r=db_request("bt_request_discoverable");db_add(r,db_int(seconds));return db_rpc(r);}
fn bt_scan(duration_ms){let r=db_request("bt_scan");db_add(r,db_int(duration_ms));return db_rpc(r);}
fn bt_scan_page(scan,offset,limit){let r=db_request("bt_scan_page");db_add(r,db_text(scan));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn bt_bond(device){let r=db_request("bt_bond");db_add(r,db_text(device));return db_rpc(r);}
fn bt_uuids(device,refresh){let r=db_request("bt_uuids");db_add(r,db_text(device));db_add(r,db_int(refresh));return db_rpc(r);}
fn bt_rfcomm_listen(name,uuid,secure){let r=db_request("bt_rfcomm_listen");db_add(r,db_text(name));db_add(r,db_text(uuid));db_add(r,db_int(secure));return db_rpc(r);}
fn bt_rfcomm_connect(device,uuid,secure,timeout_ms){let r=db_request("bt_rfcomm_connect");db_add(r,db_text(device));db_add(r,db_text(uuid));db_add(r,db_int(secure));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn bt_rfcomm_accept(listener,timeout_ms){let r=db_request("bt_rfcomm_accept");db_add(r,db_text(listener));db_add(r,db_int(timeout_ms));return db_rpc(r);}

fn ble_info(){return db_rpc(db_request("ble_info"));}
fn ble_scan(service,address,duration,mode){let r=db_request("ble_scan");db_add(r,db_text(service));db_add(r,db_text(address));db_add(r,db_int(duration));db_add(r,db_int(mode));return db_rpc(r);}
fn ble_scan_page(scan,offset,limit){let r=db_request("ble_scan_page");db_add(r,db_text(scan));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn ble_advertise(service,service_data,manufacturer,manufacturer_data,connectable,power,mode,duration){let r=db_request("ble_advertise");db_add(r,db_text(service));db_add(r,service_data);db_add(r,db_int(manufacturer));db_add(r,manufacturer_data);db_add(r,db_int(connectable));db_add(r,db_int(power));db_add(r,db_int(mode));db_add(r,db_int(duration));return db_rpc(r);}

fn ble_connect(address,timeout,operation_timeout){let r=db_request("ble_connect");db_add(r,db_text(address));db_add(r,db_int(timeout));db_add(r,db_int(operation_timeout));return db_rpc(r);}
fn ble_gatt_discover(connection,id){let r=db_request("ble_gatt_discover");db_add(r,db_text(connection));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_items(connection,parent,offset,limit){let r=db_request("ble_gatt_items");db_add(r,db_text(connection));db_add(r,db_text(parent));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn ble_gatt_read(connection,attribute,id){let r=db_request("ble_gatt_read");db_add(r,db_text(connection));db_add(r,db_text(attribute));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_write(connection,attribute,bytes,kind,id){let r=db_request("ble_gatt_write");db_add(r,db_text(connection));db_add(r,db_text(attribute));db_add(r,bytes);db_add(r,db_int(kind));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_local_notify(connection,characteristic,enabled){let r=db_request("ble_gatt_local_notify");db_add(r,db_text(connection));db_add(r,db_text(characteristic));db_add(r,db_int(enabled));return db_rpc(r);}
fn ble_gatt_mtu(connection,mtu,id){let r=db_request("ble_gatt_mtu");db_add(r,db_text(connection));db_add(r,db_int(mtu));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_rssi(connection,id){let r=db_request("ble_gatt_rssi");db_add(r,db_text(connection));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_phy_read(connection,id){let r=db_request("ble_gatt_phy_read");db_add(r,db_text(connection));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_phy(connection,tx,rx,options,id){let r=db_request("ble_gatt_phy");db_add(r,db_text(connection));db_add(r,db_int(tx));db_add(r,db_int(rx));db_add(r,db_int(options));db_add(r,db_int(id));return db_rpc(r);}
fn ble_gatt_priority(connection,priority){let r=db_request("ble_gatt_priority");db_add(r,db_text(connection));db_add(r,db_int(priority));return db_rpc(r);}

fn ble_server_open(timeout){let r=db_request("ble_server_open");db_add(r,db_int(timeout));return db_rpc(r);}
fn ble_server_add(server,uuid,kind,definitions){let r=db_request("ble_server_add");db_add(r,db_text(server));db_add(r,db_text(uuid));db_add(r,db_int(kind));db_add(r,definitions);return db_rpc(r);}
fn ble_server_items(server,parent,offset,limit){let r=db_request("ble_server_items");db_add(r,db_text(server));db_add(r,db_text(parent));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn ble_server_remove(server,service){let r=db_request("ble_server_remove");db_add(r,db_text(server));db_add(r,db_text(service));return db_rpc(r);}
fn ble_server_peers(server,offset,limit){let r=db_request("ble_server_peers");db_add(r,db_text(server));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn ble_server_requests(server,offset,limit){let r=db_request("ble_server_requests");db_add(r,db_text(server));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn ble_server_respond(server,token,status,offset,bytes){let r=db_request("ble_server_respond");db_add(r,db_text(server));db_add(r,db_text(token));db_add(r,db_int(status));db_add(r,db_int(offset));db_add(r,bytes);return db_rpc(r);}
fn ble_server_notify(server,peer,attribute,bytes,confirm,id){let r=db_request("ble_server_notify");db_add(r,db_text(server));db_add(r,db_text(peer));db_add(r,db_text(attribute));db_add(r,bytes);db_add(r,db_int(confirm));db_add(r,db_int(id));return db_rpc(r);}
fn ble_server_disconnect(server,peer){let r=db_request("ble_server_disconnect");db_add(r,db_text(server));db_add(r,db_text(peer));return db_rpc(r);}
fn ble_server_phy_read(server,peer,id){let r=db_request("ble_server_phy_read");db_add(r,db_text(server));db_add(r,db_text(peer));db_add(r,db_int(id));return db_rpc(r);}
fn ble_server_phy(server,peer,tx,rx,options,id){let r=db_request("ble_server_phy");db_add(r,db_text(server));db_add(r,db_text(peer));db_add(r,db_int(tx));db_add(r,db_int(rx));db_add(r,db_int(options));db_add(r,db_int(id));return db_rpc(r);}
fn ble_define_descriptor(rows,uuid,permissions){let row=db_list();db_add(row,db_text(uuid));db_add(row,db_int(permissions));return db_add(rows,row);}
fn ble_define_characteristic(rows,uuid,properties,permissions,descriptors){let row=db_list();db_add(row,db_text(uuid));db_add(row,db_int(properties));db_add(row,db_int(permissions));db_add(row,descriptors);return db_add(rows,row);}

fn hid_open(name,description,provider,subclass,descriptor,incoming,outgoing,timeout){let r=db_request("hid_open");db_add(r,db_text(name));db_add(r,db_text(description));db_add(r,db_text(provider));db_add(r,db_int(subclass));db_add(r,descriptor);db_add(r,incoming);db_add(r,outgoing);db_add(r,db_int(timeout));return db_rpc(r);}
fn hid_connect(endpoint,device){let r=db_request("hid_connect");db_add(r,db_text(endpoint));db_add(r,db_text(device));return db_rpc(r);}
fn hid_peers(endpoint,offset,limit){let r=db_request("hid_peers");db_add(r,db_text(endpoint));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn hid_requests(endpoint,offset,limit){let r=db_request("hid_requests");db_add(r,db_text(endpoint));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn hid_reply(endpoint,token,bytes){let r=db_request("hid_reply");db_add(r,db_text(endpoint));db_add(r,db_text(token));db_add(r,bytes);return db_rpc(r);}
fn hid_error(endpoint,token,status){let r=db_request("hid_error");db_add(r,db_text(endpoint));db_add(r,db_text(token));db_add(r,db_int(status));return db_rpc(r);}
fn hid_send(endpoint,peer,report_id,bytes){let r=db_request("hid_send");db_add(r,db_text(endpoint));db_add(r,db_text(peer));db_add(r,db_int(report_id));db_add(r,bytes);return db_rpc(r);}
fn hid_disconnect(endpoint,peer){let r=db_request("hid_disconnect");db_add(r,db_text(endpoint));db_add(r,db_text(peer));return db_rpc(r);}
fn hid_qos(service,rate,bucket,peak,latency,variation){let q=db_list();db_add(q,db_int(service));db_add(q,db_int(rate));db_add(q,db_int(bucket));db_add(q,db_int(peak));db_add(q,db_int(latency));db_add(q,db_int(variation));return q;}

fn nfc_info(){let r=db_request("nfc_info");return db_rpc(r);}
fn nfc_watch(){let r=db_request("nfc_watch");return db_rpc(r);}
fn nfc_reader(flags,presence_delay_ms){let r=db_request("nfc_reader");db_add(r,db_int(flags));db_add(r,db_int(presence_delay_ms));return db_rpc(r);}
fn nfc_tags(reader,offset,limit){let r=db_request("nfc_tags");db_add(r,db_text(reader));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn nfc_tag_info(reader,tag){let r=db_request("nfc_tag_info");db_add(r,db_text(reader));db_add(r,db_text(tag));return db_rpc(r);}
fn nfc_cached_ndef(reader,tag){let r=db_request("nfc_cached_ndef");db_add(r,db_text(reader));db_add(r,db_text(tag));return db_rpc(r);}
fn nfc_ignore(reader,tag,debounce_ms){let r=db_request("nfc_ignore");db_add(r,db_text(reader));db_add(r,db_text(tag));db_add(r,db_int(debounce_ms));return db_rpc(r);}
fn nfc_connect(reader,tag,technology){let r=db_request("nfc_connect");db_add(r,db_text(reader));db_add(r,db_text(tag));db_add(r,db_text(technology));return db_rpc(r);}
fn nfc_timeout(technology,timeout_ms){let r=db_request("nfc_timeout");db_add(r,db_text(technology));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn nfc_transceive(technology,bytes){let r=db_request("nfc_transceive");db_add(r,db_text(technology));db_add(r,bytes);return db_rpc(r);}
fn nfc_mifare_auth(technology,sector,key,key_type){let r=db_request("nfc_mifare_auth");db_add(r,db_text(technology));db_add(r,db_int(sector));db_add(r,key);db_add(r,db_int(key_type));return db_rpc(r);}
fn nfc_ndef_read(technology){let r=db_request("nfc_ndef_read");db_add(r,db_text(technology));return db_rpc(r);}
fn nfc_ndef_write(technology,bytes){let r=db_request("nfc_ndef_write");db_add(r,db_text(technology));db_add(r,bytes);return db_rpc(r);}
fn nfc_ndef_read_only(technology){let r=db_request("nfc_ndef_read_only");db_add(r,db_text(technology));return db_rpc(r);}
fn nfc_ndef_format(technology,bytes,read_only){let r=db_request("nfc_ndef_format");db_add(r,db_text(technology));db_add(r,bytes);db_add(r,db_int(read_only));return db_rpc(r);}
fn se_open(timeout_ms){let r=db_request("se_open");db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn se_readers(service,offset,limit){let r=db_request("se_readers");db_add(r,db_text(service));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn se_uicc(service,slot){let r=db_request("se_uicc");db_add(r,db_text(service));db_add(r,db_int(slot));return db_rpc(r);}
fn se_session(service,reader){let r=db_request("se_session");db_add(r,db_text(service));db_add(r,db_text(reader));return db_rpc(r);}
fn se_channel(session,aid,basic,p2){let r=db_request("se_channel");db_add(r,db_text(session));db_add(r,aid);db_add(r,db_int(basic));db_add(r,db_int(p2));return db_rpc(r);}
fn se_select_response(channel){let r=db_request("se_select_response");db_add(r,db_text(channel));return db_rpc(r);}
fn se_select_next(channel){let r=db_request("se_select_next");db_add(r,db_text(channel));return db_rpc(r);}
fn se_transmit(channel,bytes){let r=db_request("se_transmit");db_add(r,db_text(channel));db_add(r,bytes);return db_rpc(r);}

fn se_command(channel,bytes){let r=db_request("se_command");db_add(r,db_text(channel));db_add(r,db_int(bytes));return db_rpc(r);}
fn se_command_write(channel,offset,value){let r=db_request("se_command_write");db_add(r,db_text(channel));db_add(r,db_int(offset));db_add(r,value);return db_rpc(r);}
fn se_send(channel){let r=db_request("se_send");db_add(r,db_text(channel));return db_rpc(r);}
fn se_response(channel,id,offset,limit){let r=db_request("se_response");db_add(r,db_text(channel));db_add(r,db_int(id));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}

fn input_devices(offset,limit){let r=db_request("input_devices");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn input_info(device){let r=db_request("input_info");db_add(r,db_int(device));return db_rpc(r);}
fn input_ranges(device,offset,limit){let r=db_request("input_ranges");db_add(r,db_int(device));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn input_has_keys(device,keys){let r=db_request("input_has_keys");db_add(r,db_int(device));db_add(r,keys);return db_rpc(r);}
fn input_watch(device,mask,axes,history){let r=db_request("input_watch");db_add(r,db_int(device));db_add(r,db_int(mask));db_add(r,axes);db_add(r,db_int(history));return db_rpc(r);}

fn biometric_info(authenticators){let r=db_request("biometric_info");db_add(r,db_int(authenticators));return db_rpc(r);}
fn biometric_auth(title,subtitle,description,authenticators,confirmation,timeout_ms){let r=db_request("biometric_auth");db_add(r,db_text(title));db_add(r,db_text(subtitle));db_add(r,db_text(description));db_add(r,db_int(authenticators));db_add(r,db_int(confirmation));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn biometric_cancel(handle){let r=db_request("biometric_cancel");db_add(r,db_text(handle));return db_rpc(r);}

fn uwb_info(){return db_rpc(db_request("uwb_info"));}
fn uwb_watch(){return db_rpc(db_request("uwb_watch"));}
fn uwb_range(role,peers,options){let r=db_request("uwb_range");db_add(r,db_int(role));db_add(r,peers);db_add(r,options);return db_rpc(r);}
fn uwb_stop(handle){let r=db_request("uwb_stop");db_add(r,db_text(handle));return db_rpc(r);}
fn uwb_add(handle,peer){let r=db_request("uwb_add");db_add(r,db_text(handle));db_add(r,peer);return db_rpc(r);}
fn uwb_remove(handle,uuid){let r=db_request("uwb_remove");db_add(r,db_text(handle));db_add(r,db_text(uuid));return db_rpc(r);}
fn uwb_interval(handle,skip){let r=db_request("uwb_interval");db_add(r,db_text(handle));db_add(r,db_int(skip));return db_rpc(r);}

// Android document trees: grants persist; tree handles and document tokens do not.
fn document_pick(ticket,writable){let r=db_request("document_pick");db_add(r,db_text(ticket));db_add(r,db_int(writable));return db_rpc(r);}
fn document_trees(offset,limit){let r=db_request("document_trees");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn document_forget(grant){let r=db_request("document_forget");db_add(r,db_text(grant));return db_rpc(r);}
fn document_tree_open(grant){let r=db_request("document_tree_open");db_add(r,db_text(grant));return db_rpc(r);}
fn document_info(tree,document){let r=db_request("document_info");db_add(r,db_text(tree));db_add(r,db_text(document));return db_rpc(r);}
fn document_children(tree,document,offset,limit){let r=db_request("document_children");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn document_file_open(tree,document,mode){let r=db_request("document_file_open");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(mode));return db_rpc(r);}
fn document_seek(file,offset){let r=db_request("document_seek");db_add(r,db_text(file));db_add(r,db_int(offset));return db_rpc(r);}
fn document_create(tree,parent,name,mime){let r=db_request("document_create");db_add(r,db_text(tree));db_add(r,db_text(parent));db_add(r,db_text(name));db_add(r,db_text(mime));return db_rpc(r);}
fn document_rename(tree,document,name){let r=db_request("document_rename");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(name));return db_rpc(r);}
fn document_delete(tree,document){let r=db_request("document_delete");db_add(r,db_text(tree));db_add(r,db_text(document));return db_rpc(r);}

fn document_types(tree,document,mime_filter){let r=db_request("document_types");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(mime_filter));return db_rpc(r);}
fn document_typed_open(tree,document,mime){let r=db_request("document_typed_open");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(mime));return db_rpc(r);}
fn document_copy(tree,document,target_parent){let r=db_request("document_copy");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(target_parent));return db_rpc(r);}
fn document_move(tree,document,source_parent,target_parent){let r=db_request("document_move");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(source_parent));db_add(r,db_text(target_parent));return db_rpc(r);}
fn document_remove(tree,document,parent){let r=db_request("document_remove");db_add(r,db_text(tree));db_add(r,db_text(document));db_add(r,db_text(parent));return db_rpc(r);}

// Public Camera2 resources; settings/options remain ordinary typed Flexscript data.
fn camera_list(offset,limit){let r=db_request("camera_list");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_info(camera_id){let r=db_request("camera_info");db_add(r,db_text(camera_id));return db_rpc(r);}
fn camera_keys(camera_id,kind,offset,limit){let r=db_request("camera_keys");db_add(r,db_text(camera_id));db_add(r,db_int(kind));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_value(camera_id,key,offset,limit){let r=db_request("camera_value");db_add(r,db_text(camera_id));db_add(r,db_text(key));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_formats(camera_id,offset,limit){let r=db_request("camera_formats");db_add(r,db_text(camera_id));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_output_sizes(camera_id,format,offset,limit){let r=db_request("camera_output_sizes");db_add(r,db_text(camera_id));db_add(r,db_int(format));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_watch(){let r=db_request("camera_watch");return db_rpc(r);}
fn camera_open(camera_id,timeout_ms){let r=db_request("camera_open");db_add(r,db_text(camera_id));db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn camera_torch_open(camera_id,strength){let r=db_request("camera_torch_open");db_add(r,db_text(camera_id));db_add(r,db_int(strength));return db_rpc(r);}
fn camera_configure(camera,outputs,timeout_ms){let r=db_request("camera_configure");db_add(r,db_text(camera));db_add(r,outputs);db_add(r,db_int(timeout_ms));return db_rpc(r);}
fn camera_capture(camera,template,settings,repeat){let r=db_request("camera_capture");db_add(r,db_text(camera));db_add(r,db_int(template));db_add(r,settings);db_add(r,db_int(repeat));return db_rpc(r);}
fn camera_stop(camera){let r=db_request("camera_stop");db_add(r,db_text(camera));return db_rpc(r);}
fn camera_frames(camera,offset,limit){let r=db_request("camera_frames");db_add(r,db_text(camera));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_frame_info(camera,frame){let r=db_request("camera_frame_info");db_add(r,db_text(camera));db_add(r,db_text(frame));return db_rpc(r);}
fn camera_frame_read(camera,frame,plane,offset,limit){let r=db_request("camera_frame_read");db_add(r,db_text(camera));db_add(r,db_text(frame));db_add(r,db_int(plane));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_frame_close(camera,frame){let r=db_request("camera_frame_close");db_add(r,db_text(camera));db_add(r,db_text(frame));return db_rpc(r);}
fn camera_result_keys(camera,result,offset,limit){let r=db_request("camera_result_keys");db_add(r,db_text(camera));db_add(r,db_text(result));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_result_value(camera,result,key,offset,limit){let r=db_request("camera_result_value");db_add(r,db_text(camera));db_add(r,db_text(result));db_add(r,db_text(key));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn camera_video_start(camera,options,settings){let r=db_request("camera_video_start");db_add(r,db_text(camera));db_add(r,options);db_add(r,settings);return db_rpc(r);}
fn camera_video_audio_start(camera,options,settings){let r=db_request("camera_video_audio_start");db_add(r,db_text(camera));db_add(r,options);db_add(r,settings);return db_rpc(r);}
fn camera_video_stop(video){let r=db_request("camera_video_stop");db_add(r,db_text(video));return db_rpc(r);}
fn camera_video_pause(video){let r=db_request("camera_video_pause");db_add(r,db_text(video));return db_rpc(r);}
fn camera_video_resume(video){let r=db_request("camera_video_resume");db_add(r,db_text(video));return db_rpc(r);}
fn camera_video_seek(video,offset){let r=db_request("camera_video_seek");db_add(r,db_text(video));db_add(r,db_int(offset));return db_rpc(r);}
fn camera_shutdown(camera){let r=db_request("camera_shutdown");db_add(r,db_text(camera));return db_rpc(r);}

// NFC service routing and asynchronous command replies; the guest owns protocol bytes.
fn hce_info(){let r=db_request("hce_info");return db_rpc(r);}
fn hce_open(category,aids,reply_timeout_ms){let r=db_request("hce_open");db_add(r,db_int(category));db_add(r,aids);db_add(r,db_int(reply_timeout_ms));return db_rpc(r);}
fn hcef_open(system_code,nfcid2,reply_timeout_ms){let r=db_request("hcef_open");db_add(r,db_text(system_code));db_add(r,db_text(nfcid2));db_add(r,db_int(reply_timeout_ms));return db_rpc(r);}
fn hce_request(session){let r=db_request("hce_request");db_add(r,db_text(session));return db_rpc(r);}
fn hce_reply(session,request,bytes){let r=db_request("hce_reply");db_add(r,db_text(session));db_add(r,db_text(request));db_add(r,bytes);return db_rpc(r);}
fn hce_unhandled(session,request){let r=db_request("hce_unhandled");db_add(r,db_text(session));db_add(r,db_text(request));return db_rpc(r);}
fn hce_shutdown(session){let r=db_request("hce_shutdown");db_add(r,db_text(session));return db_rpc(r);}
fn hce_request_read(session,request,offset,limit){let r=db_request("hce_request_read");db_add(r,db_text(session));db_add(r,db_text(request));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn hce_reply_begin(session,request,total){let r=db_request("hce_reply_begin");db_add(r,db_text(session));db_add(r,db_text(request));db_add(r,db_int(total));return db_rpc(r);}
fn hce_reply_write(session,request,offset,bytes){let r=db_request("hce_reply_write");db_add(r,db_text(session));db_add(r,db_text(request));db_add(r,db_int(offset));db_add(r,bytes);return db_rpc(r);}
fn hce_reply_commit(session,request){let r=db_request("hce_reply_commit");db_add(r,db_text(session));db_add(r,db_text(request));return db_rpc(r);}

// Explicit Android session consent; frames and recording share one SDK projection.
fn screen_info(){let r=db_request("screen_info");return db_rpc(r);}
fn screen_open(ticket,width,height,density_dpi,scope){let r=db_request("screen_open");db_add(r,db_text(ticket));db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_int(density_dpi));db_add(r,db_int(scope));return db_rpc(r);}
fn screen_tickets(offset,limit){let r=db_request("screen_tickets");db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn screen_forget(ticket){let r=db_request("screen_forget");db_add(r,db_text(ticket));return db_rpc(r);}
fn screen_shutdown(screen){let r=db_request("screen_shutdown");db_add(r,db_text(screen));return db_rpc(r);}
fn screen_resize(screen,width,height,density_dpi){let r=db_request("screen_resize");db_add(r,db_text(screen));db_add(r,db_int(width));db_add(r,db_int(height));db_add(r,db_int(density_dpi));return db_rpc(r);}
fn screen_pause(screen,paused){let r=db_request("screen_pause");db_add(r,db_text(screen));db_add(r,db_int(paused));return db_rpc(r);}
fn screen_rotation(screen,rotation){let r=db_request("screen_rotation");db_add(r,db_text(screen));db_add(r,db_int(rotation));return db_rpc(r);}
fn screen_frames(screen,offset,limit){let r=db_request("screen_frames");db_add(r,db_text(screen));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn screen_frame_info(screen,frame){let r=db_request("screen_frame_info");db_add(r,db_text(screen));db_add(r,db_text(frame));return db_rpc(r);}
fn screen_frame_read(screen,frame,plane,offset,limit){let r=db_request("screen_frame_read");db_add(r,db_text(screen));db_add(r,db_text(frame));db_add(r,db_int(plane));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn screen_frame_close(screen,frame){let r=db_request("screen_frame_close");db_add(r,db_text(screen));db_add(r,db_text(frame));return db_rpc(r);}
fn screen_video_start(screen,options){let r=db_request("screen_video_start");db_add(r,db_text(screen));db_add(r,options);return db_rpc(r);}
fn screen_video_audio_start(screen,options){let r=db_request("screen_video_audio_start");db_add(r,db_text(screen));db_add(r,options);return db_rpc(r);}
fn screen_video_stop(video){let r=db_request("screen_video_stop");db_add(r,db_text(video));return db_rpc(r);}
fn screen_video_pause(video){let r=db_request("screen_video_pause");db_add(r,db_text(video));return db_rpc(r);}
fn screen_video_resume(video){let r=db_request("screen_video_resume");db_add(r,db_text(video));return db_rpc(r);}
fn screen_video_seek(video,offset){let r=db_request("screen_video_seek");db_add(r,db_text(video));db_add(r,db_int(offset));return db_rpc(r);}

// Explicitly user-enabled Android accessibility service and owned SDK references.
fn accessibility_info(){let r=db_request("accessibility_info");return db_rpc(r);}
fn accessibility_open(mask,packages,notification_timeout_ms){let r=db_request("accessibility_open");db_add(r,db_int(mask));db_add(r,packages);db_add(r,db_int(notification_timeout_ms));return db_rpc(r);}
fn accessibility_windows(session,display,offset,limit){let r=db_request("accessibility_windows");db_add(r,db_text(session));db_add(r,db_int(display));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn accessibility_root(session,window){let r=db_request("accessibility_root");db_add(r,db_text(session));db_add(r,db_int(window));return db_rpc(r);}
fn accessibility_node(session,node){let r=db_request("accessibility_node");db_add(r,db_text(session));db_add(r,db_text(node));return db_rpc(r);}
fn accessibility_children(session,node,offset,limit){let r=db_request("accessibility_children");db_add(r,db_text(session));db_add(r,db_text(node));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn accessibility_parent(session,node){let r=db_request("accessibility_parent");db_add(r,db_text(session));db_add(r,db_text(node));return db_rpc(r);}
fn accessibility_node_close(session,node){let r=db_request("accessibility_node_close");db_add(r,db_text(session));db_add(r,db_text(node));return db_rpc(r);}
fn accessibility_clear(session){let r=db_request("accessibility_clear");db_add(r,db_text(session));return db_rpc(r);}
fn accessibility_actions(session,node,offset,limit){let r=db_request("accessibility_actions");db_add(r,db_text(session));db_add(r,db_text(node));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn accessibility_text(session,node,field,offset,limit){let r=db_request("accessibility_text");db_add(r,db_text(session));db_add(r,db_text(node));db_add(r,db_int(field));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn accessibility_action(session,node,action,arguments){let r=db_request("accessibility_action");db_add(r,db_text(session));db_add(r,db_text(node));db_add(r,db_int(action));db_add(r,arguments);return db_rpc(r);}
fn accessibility_global_actions(session,offset,limit){let r=db_request("accessibility_global_actions");db_add(r,db_text(session));db_add(r,db_int(offset));db_add(r,db_int(limit));return db_rpc(r);}
fn accessibility_global_action(session,action){let r=db_request("accessibility_global_action");db_add(r,db_text(session));db_add(r,db_int(action));return db_rpc(r);}
fn accessibility_gesture(session,strokes,display){let r=db_request("accessibility_gesture");db_add(r,db_text(session));db_add(r,strokes);db_add(r,db_int(display));return db_rpc(r);}
fn accessibility_gesture_state(session,gesture){let r=db_request("accessibility_gesture_state");db_add(r,db_text(session));db_add(r,db_text(gesture));return db_rpc(r);}
