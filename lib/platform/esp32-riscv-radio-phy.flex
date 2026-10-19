import "esp32-riscv-radio-phy-data.flex";
// Shared single-CPU PHY buffers/lifecycle. Actual vendor calls require an
// initialized owned chip domain; ABI/table construction never enables RF.
global esp_radio_phy_backup=0;
global esp_radio_phy_backup_valid=0;
fn esp_radio_phy_buffers_init(){
 let ps=esp32_irq_save();if esp_radio_phy_cal && esp_radio_phy_init_data && (rv_hal_chip!=5 || esp_radio_phy_backup){esp32_irq_restore(ps);return 0;}
 if esp_radio_phy_cal || esp_radio_phy_init_data || esp_radio_phy_backup || esp_radio_phy_refs{esp32_irq_restore(ps);return -16;}
 let cal=esp_sdk_calloc(1,1904);let data=esp_sdk_calloc(1,128);let backup=0;if rv_hal_chip==5{backup=esp_sdk_calloc(1,84);}
 if !cal || !data || (rv_hal_chip==5 && !backup){esp_sdk_free(cal);esp_sdk_free(data);esp_sdk_free(backup);esp32_irq_restore(ps);return -12;}
 esp_radio_phy_defaults(data);esp_radio_phy_cal=cal;esp_radio_phy_init_data=data;esp_radio_phy_backup=backup;esp_radio_phy_calibrated=0;esp_radio_phy_backup_valid=0;esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_enable(){
 let ps=esp32_irq_save();if esp_radio_regi2c_active || esp_radio_pmu_active || !esp_radio_hw_ready || esp_radio_owner!=1 || esp_adc_busy || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}if esp_radio_phy_refs==9223372036854775807{esp32_irq_restore(ps);return -75;}
 let result=esp_radio_phy_buffers_init();if !result{result=esp_radio_phy_clock(1);}if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_phy_refs{
  let conf=0;let conf1=0;if rv_hal_chip==13{conf=esp32_load32(0x600a9804)&0x10000000;conf1=esp32_load32(0x600a9814)&0x601ff;esp_reg_update(0x600a9804,0x10000000,0x10000000);esp_reg_update(0x600a9814,0x601ff,0x601ff);}
  if esp_radio_phy_calibrated{esp32_call32(esp32_external("phy_wakeup_init"),0,0,0,0,0,0,0,0);if rv_hal_chip==5 && esp_radio_phy_backup_valid{esp32_call32(esp32_external("phy_dig_reg_backup"),0,esp_radio_phy_backup,0,0,0,0,0,0);esp_radio_phy_backup_valid=0;}}
  else{esp32_call32(esp32_external("phy_init_param_set"),1,0,0,0,0,0,0,0);esp32_call32(esp32_external("phy_bbpll_en_usb"),1,0,0,0,0,0,0,0);esp_radio_phy_result=esp32_call32(esp32_external("register_chipv7_phy"),esp_radio_phy_init_data,esp_radio_phy_cal,2,0,0,0,0,0);esp_radio_phy_calibrated=1;}
  if rv_hal_chip==13{esp_reg_update(0x600a9804,0x10000000,conf);esp_reg_update(0x600a9814,0x601ff,conf1);}
 }esp_radio_phy_refs=esp_radio_phy_refs+1;esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_disable(){
 let ps=esp32_irq_save();if esp_radio_regi2c_active || esp_radio_pmu_active || !esp_radio_hw_ready || esp_radio_owner!=1 || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}if esp_radio_phy_refs{esp_radio_phy_refs=esp_radio_phy_refs-1;if !esp_radio_phy_refs{if rv_hal_chip==5{esp32_call32(esp32_external("phy_dig_reg_backup"),1,esp_radio_phy_backup,0,0,0,0,0,0);esp_radio_phy_backup_valid=1;}esp32_call32(esp32_external("phy_close_rf"),0,0,0,0,0,0,0,0);esp32_call32(esp32_external("phy_xpd_tsens"),0,0,0,0,0,0,0,0);}esp_radio_phy_clock(0);}esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_release_buffers(){let ps=esp32_irq_save();if esp_radio_phy_refs || esp_radio_phy_clock_refs{esp32_irq_restore(ps);return -16;}esp_sdk_free(esp_radio_phy_cal);esp_sdk_free(esp_radio_phy_init_data);esp_sdk_free(esp_radio_phy_backup);esp_radio_phy_cal=0;esp_radio_phy_init_data=0;esp_radio_phy_backup=0;esp_radio_phy_calibrated=0;esp_radio_phy_backup_valid=0;esp32_irq_restore(ps);return 0;}
fn esp_radio_cb_phy_on(a,b,c,d,e,f,g,h){let ps=esp32_irq_save();let result=esp_radio_phy_enable();if !result{esp32_call32(esp32_external("phy_wifi_enable_set"),1,0,0,0,0,0,0,0);}esp32_irq_restore(ps);if result{return esp_radio_fail(0x2001);}return 0;}
fn esp_radio_cb_phy_off(a,b,c,d,e,f,g,h){let ps=esp32_irq_save();if !esp_radio_phy_refs{esp32_irq_restore(ps);return 0;}esp32_call32(esp32_external("phy_wifi_enable_set"),0,0,0,0,0,0,0,0);let result=esp_radio_phy_disable();esp32_irq_restore(ps);return result;}
