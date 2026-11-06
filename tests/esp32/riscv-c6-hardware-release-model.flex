// Actual Wi-Fi final-cleanup and C6 hardware/base code with explicit vendor,
// SDK quiescence and native-buffer ownership boundaries. No RF execution.
global esp_sdk_current=37;global esp_sdk_timer_active=0;
global esp_radio_isr=0;global esp_radio_isr_arg=0;global esp_radio_osi=0;global esp_radio_event_hook=0;global esp_radio_scan_done=0;global esp_radio_scan_status=0;
global wifi_mock_stops=0;global wifi_mock_deinits=0;global wifi_mock_supplicants=0;global wifi_mock_ready=0;global wifi_mock_locks=0;global wifi_mock_phy=0;global wifi_mock_end=0;global wifi_mock_frees=0;global wifi_mock_now=0;global wifi_mock_delays=0;
global wifi_mock_vendor_error=0;global wifi_mock_end_error=0;
fn esp32_external(name){if h_equal(name,"esp_wifi_stop"){return 101;}if h_equal(name,"esp_wifi_deinit_internal"){return 103;}check(h_equal(name,"esp_supplicant_deinit"));return 105;}
fn esp32_call32(address,a,b,c,d,e,f,g,h){
 if address==101 || address==103 || address==105{
  check((ps&8) && !a && !b && !c && !d && !e && !f && !g && !h && esp_radio_owner==1 && !esp_wifi_cleanup_phase);
  if address==101{wifi_mock_stops=wifi_mock_stops+1;}else if address==103{wifi_mock_deinits=wifi_mock_deinits+1;return wifi_mock_vendor_error;}else{wifi_mock_supplicants=wifi_mock_supplicants+1;}return 0;
 }
 return hardware_model_call32(address,a,b,c,d,e,f,g,h);
}
fn esp_sdk_irq_blocked(value){return !(value&8);}
fn esp_sdk_now(){check(!esp_wifi_cleanup_phase);wifi_mock_now=wifi_mock_now+1000;return wifi_mock_now;}
fn esp_sdk_delay(ms){check(!esp_wifi_cleanup_phase && ms==1);wifi_mock_delays=wifi_mock_delays+1;return 0;}
fn esp_radio_resources_ready(){check(!esp_wifi_cleanup_phase && esp_radio_owner==1);wifi_mock_ready=wifi_mock_ready+1;return 0;}
fn esp_wifi_platform_reset_locks(){check(!(ps&8) && !esp_wifi_cleanup_phase);wifi_mock_locks=wifi_mock_locks+1;return 0;}
fn esp_radio_phy_release_buffers(){check(!(ps&8) && !esp_wifi_cleanup_phase && !esp_radio_phy_refs && !esp_radio_phy_clock_refs);wifi_mock_phy=wifi_mock_phy+1;return 0;}
fn esp_radio_resources_end(handler){
 check(handler==123 && !(ps&8) && esp_wifi_cleanup_phase==1 && !esp_radio_base_active && !esp_radio_base_configured && !esp_radio_hw_ready && esp_radio_owner==1);
 wifi_mock_end=wifi_mock_end+1;if wifi_mock_end_error{return wifi_mock_end_error;}esp_radio_owner=0;return 0;
}
fn esp_sdk_free(pointer){check(!(ps&8) && esp_wifi_cleanup_phase==1 && !esp_radio_owner && (pointer==0xe001 || pointer==0xe002));wifi_mock_frees=wifi_mock_frees+1;return 0;}
fn wifi_mock_seed(startup,branch){
 lifetime_prepare(8+startup,branch,1);esp_wifi_cleanup_phase=0;esp_wifi_cleanup_ps=0;esp_wifi_cleanup_task=0;
 esp_sdk_current=37;esp_sdk_timer_active=0;esp_wifi_control_task=37;esp_wifi_lifecycle_busy=0;esp_wifi_cleanup_error=0;esp_wifi_control_active=0;esp_wifi_rx_busy=0;esp_wifi_rx_reading=0;esp_wifi_rx_callbacks=0;esp_wifi_tx_active=0;
 esp_wifi_initialized=1;esp_wifi_vendor_initialized=1;esp_wifi_vendor_running=1;esp_wifi_supplicant=1;esp_wifi_started=1;esp_wifi_linked=1;esp_wifi_want_link=1;esp_wifi_init_config=0xe001;esp_wifi_rx_ring=0xe002;esp_wifi_rx_count=2;
 esp_radio_isr=88;esp_radio_isr_arg=99;esp_radio_osi=111;esp_radio_event_hook=112;esp_radio_scan_done=113;esp_radio_scan_status=0;
 wifi_mock_stops=0;wifi_mock_deinits=0;wifi_mock_supplicants=0;wifi_mock_ready=0;wifi_mock_locks=0;wifi_mock_phy=0;wifi_mock_end=0;wifi_mock_frees=0;wifi_mock_now=0;wifi_mock_delays=0;wifi_mock_vendor_error=0;wifi_mock_end_error=0;
 restoring=1;return 0;
}
fn wifi_mock_held(){
 lifetime_held();check(!esp_radio_hw_ready && esp_wifi_cleanup_phase==1 && esp_wifi_cleanup_ps==0x1888 && esp_wifi_cleanup_task==37 && esp_wifi_lifecycle_busy && esp_wifi_cleanup_error==-110);
 check(esp_wifi_initialized && esp_wifi_init_config==0xe001 && esp_wifi_rx_ring==0xe002 && esp_wifi_control_task==37 && esp_radio_owner==1 && !wifi_mock_end && !wifi_mock_frees);
 check(wifi_mock_stops==1 && wifi_mock_deinits==1 && wifi_mock_supplicants==1 && wifi_mock_ready==1 && wifi_mock_locks==1 && wifi_mock_phy==1 && !wifi_mock_delays && base_requests==6);return 0;
}
fn wifi_mock_finished(){
 check(!esp_wifi_cleanup_phase && !esp_wifi_cleanup_ps && !esp_wifi_cleanup_task && !esp_wifi_lifecycle_busy && !esp_wifi_cleanup_error && ps==0x1888);
 check(!esp_radio_owner && !esp_radio_base_active && !esp_radio_base_configured && !esp_radio_modem_configured && !esp_radio_pmu_configured && !esp_radio_hw_ready);
 check(!esp_wifi_initialized && !esp_wifi_init_config && !esp_wifi_rx_ring && !esp_wifi_control_task && !esp_radio_isr && !esp_radio_isr_arg && !esp_radio_osi && !esp_radio_event_hook && !esp_radio_scan_done && esp_radio_scan_status==-1 && wifi_mock_frees==2);
 esp_radio_owner=1;lifetime_restored(0);esp_radio_owner=0;return 0;
}
fn wifi_release_suite(){
 let branch=0;while branch<3{let startup=0;while startup<2{
  wifi_mock_seed(startup,branch);check(!esp_wifi_station_deinit());wifi_mock_finished();let calls=wifi_mock_end;let writes=base_stores;check(!esp_wifi_station_deinit() && calls==wifi_mock_end && writes==base_stores && ps==0x1888);
  wifi_mock_seed(startup,branch);base_final_mode=1;base_final_delta=400000;
  check(esp_wifi_station_deinit()==-110);wifi_mock_held();let generation=esp_wifi_generation;
  base_final_calls=0;base_final_reads=0;check(esp_wifi_station_deinit()==-110 && esp_wifi_generation==generation);wifi_mock_held();
  // A different control context cannot adopt the retained final-cleanup mask.
  esp_wifi_control_task=0;esp_sdk_current=99;check(esp_wifi_station_deinit()==-16 && !(ps&8) && esp_wifi_cleanup_task==37 && base_requests==6);esp_sdk_current=37;esp_wifi_control_task=37;
  isr=1;check(esp_wifi_station_deinit()==-16 && !(ps&8));isr=0;esp_sdk_timer_active=1;check(esp_wifi_station_deinit()==-16 && !(ps&8));esp_sdk_timer_active=0;
  esp_wifi_tx_active=1;check(esp_wifi_station_deinit()==-16 && !(ps&8));esp_wifi_tx_active=0;esp_radio_owner=2;check(esp_wifi_station_deinit()==-16 && !(ps&8));esp_radio_owner=1;
  wifi_mock_held();base_final_mode=0;check(!esp_wifi_station_deinit() && esp_wifi_generation==generation);wifi_mock_finished();
  startup=startup+1;
 }branch=branch+1;}
 // The lower receipt may be finished directly; the Wi-Fi journal still owns
 // final domain/buffer cleanup and the original unmasked caller PS.
 wifi_mock_seed(1,1);base_final_mode=1;base_final_delta=400000;check(esp_wifi_station_deinit()==-110);base_final_mode=0;check(!esp_radio_c6_base_release(1000) && !(ps&8) && esp_wifi_cleanup_phase==1 && esp_radio_owner==1);check(!esp_wifi_station_deinit());wifi_mock_finished();
 // Non-retained errors restore ordinary IRQ state and permit normal retries.
 wifi_mock_seed(1,1);wifi_mock_vendor_error=13;check(esp_wifi_station_deinit()==13 && !esp_wifi_cleanup_phase && !esp_wifi_lifecycle_busy && ps==0x1888 && esp_radio_hw_ready && esp_radio_base_configured && !esp_radio_base_active && !wifi_mock_frees);wifi_mock_vendor_error=0;check(!esp_wifi_station_deinit() && wifi_mock_deinits==2 && wifi_mock_stops==1);wifi_mock_finished();
 wifi_mock_seed(1,1);wifi_mock_end_error=-16;check(esp_wifi_station_deinit()==-16 && !esp_wifi_cleanup_phase && !esp_wifi_lifecycle_busy && ps==0x1888 && esp_radio_owner==1 && !esp_radio_base_configured && !wifi_mock_frees);wifi_mock_end_error=0;check(!esp_wifi_station_deinit() && wifi_mock_end==2 && base_requests==6);wifi_mock_finished();
 // Hardware init remains a refusal, and empty hardware teardown is idempotent.
 esp_radio_owner=1;let writes=base_stores;check(esp_radio_hardware_init()==-95 && !esp_radio_hw_ready && base_stores==writes);check(!esp_radio_hardware_deinit() && base_stores==writes && ps==0x1888);return 0;
}
