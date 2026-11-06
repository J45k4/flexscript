import "../../lib/platform/esp32c6-wifi.flex";
// Real SDK heap/domain and IRQ state; only the already-restored final PMU
// observation has explicit clock/monitor peers. No valid PMU/RF MMIO.
global wr_tick=0;global wr_start=0;global wr_calls=0;global wr_late=0;global wr_wrap=0;
global wr_bad_window=0;global wr_before=0;global wr_current=0;global wr_config=0;global wr_ring=0;global wr_owned=0;global wr_ps=0;
fn wifi_release_cycles(){
 if esp_radio_base_active && esp_radio_base_recovery==7{
  if !wr_calls{wr_start=wr_tick;}wr_calls=wr_calls+1;if !wr_late{wr_tick=(wr_tick+7)&0xffffffff;}return wr_tick;
 }
 return esp32_cycles();
}
fn wifi_release_load32(address){
 if address==0x600b0194{if wr_late{wr_tick=(wr_start+400000)&0xffffffff;}return esp_radio_base_live;}
 return esp32_load32(address);
}
fn wr_observation(late){wr_late=late;wr_calls=0;wr_tick=0;if wr_wrap{wr_tick=0xfffffff0;}return 0;}
fn wr_seed(){
 if esp_radio_resources_begin(1){return 1;}wr_before=esp_sdk_heap_free();wr_current=esp_sdk_current;
 wr_config=esp_sdk_malloc(48);wr_ring=esp_sdk_malloc(96);wr_owned=esp_radio_cb_malloc(64,0,0,0,0,0,0,0);if !wr_config || !wr_ring || !wr_owned{return 2;}
 store64(wr_config,0x1122334455667788);store64(wr_ring,0x8877665544332211);store64(wr_owned,0xaabbccddeeff0123);
 esp_wifi_initialized=1;esp_wifi_init_config=wr_config;esp_wifi_rx_ring=wr_ring;esp_wifi_control_task=0;esp_wifi_lifecycle_busy=1;
 esp_wifi_cleanup_phase=1;esp_wifi_cleanup_ps=wr_ps;esp_wifi_cleanup_task=wr_current;
 esp_radio_base_active=1;esp_radio_base_internal=0;esp_radio_base_releasing=1;esp_radio_base_configured=1;esp_radio_modem_configured=1;esp_radio_pmu_configured=1;
 esp_radio_base_phase=2;esp_radio_base_step=7;esp_radio_base_recovery=7;esp_radio_base_command_step=2;esp_radio_base_issued=0;esp_radio_base_live=0xd00000;esp_radio_base_ps=wr_ps&~8;
 esp32_irq_save();wr_observation(1);return 0;
}
fn wr_held(){
 let actual=esp32_irq_save();esp32_irq_restore(actual);if actual&8{return 3;}
 if esp_wifi_cleanup_phase!=1 || esp_wifi_cleanup_ps!=wr_ps || esp_wifi_cleanup_task!=wr_current || !esp_wifi_lifecycle_busy || esp_wifi_cleanup_error!=-110{return 4;}
 if esp_radio_owner!=1 || !esp_radio_base_active || !esp_radio_base_releasing || !esp_radio_base_configured || esp_wifi_init_config!=wr_config || esp_wifi_rx_ring!=wr_ring || esp_sdk_heap_owner(wr_owned)!=1{return 9;}
 if load64(wr_config)!=0x1122334455667788 || load64(wr_ring)!=0x8877665544332211 || load64(wr_owned)!=0xaabbccddeeff0123{return 9;}return 0;
}
fn wr_finished(){
 let actual=esp32_irq_save();esp32_irq_restore(actual);if actual!=wr_ps{return 8;}
 if wr_bad_window{return 10;}
 if esp_radio_owner || esp_radio_base_active || esp_radio_base_configured || esp_radio_modem_configured || esp_radio_pmu_configured || esp_wifi_cleanup_phase || esp_wifi_cleanup_task || esp_wifi_lifecycle_busy || esp_wifi_initialized || esp_wifi_init_config || esp_wifi_rx_ring || esp_wifi_cleanup_error || esp_sdk_heap_free()!=wr_before{return 11;}return 0;
}
fn main(){
 // Root the target's C export thunks without entering a vendor radio domain.
 if esp32_state()&1{esp_radio_os_finish();}
 let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena) || esp_libc_stdio_init() || esp_libc_rom_init() || esp_sdk_task_init(){return 1;}wr_ps=esp32_irq_save()|8;esp32_irq_restore(wr_ps);
 while wr_wrap<2{
  if wr_seed(){return 1;}if esp_wifi_station_deinit()!=-110{return 2;}let r=wr_held();if r{return r;}
  esp_sdk_current=wr_current+16;wr_observation(1);if esp_wifi_station_deinit()!=-16 || (esp32_irq_save()&8){return 5;}esp_sdk_current=wr_current;
  wr_observation(1);if esp_wifi_station_deinit()!=-110{return 6;}r=wr_held();if r{return r;}
  wr_observation(0);if esp_wifi_station_deinit(){return 7;}r=wr_finished();if r{return r;}
  if esp_wifi_station_deinit() || esp_sdk_heap_free()!=wr_before{return 12;}wr_wrap=wr_wrap+1;
 }
 // A direct lower abort can finish first; final Wi-Fi cleanup still restores
 // the journal's outer PS after dropping domain objects and native buffers.
 wr_wrap=0;if wr_seed(){return 1;}if esp_wifi_station_deinit()!=-110{return 2;}wr_observation(0);
 if esp_radio_c6_base_release(1000) || (esp32_irq_save()&8) || esp_wifi_cleanup_phase!=1 || esp_radio_owner!=1{return 13;}
 if esp_wifi_station_deinit(){return 7;}return wr_finished();
}
