import "esp32-analog-state.flex";
// Pinned IDF5.5.1 registers and esp-hal0f0ebd92 radio clock policy.
// CPU0 standalone Wi-Fi; radio ownership precedes all clock/reset changes.
global esp_radio_hw_ready=0;
global esp_radio_hw_iso=0;
global esp_radio_hw_power=0;
global esp_radio_hw_clock=0;
global esp_radio_rng_last=0;
fn esp_radio_hardware_init(){
 if !esp_riscv_ready(){return -95;}let ps=esp32_irq_save();if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active || esp_radio_hw_ready || esp_radio_owner!=1 || esp_adc_busy || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 // C6 additionally needs the HP/LP modem-domain base clock/power setup; its
 // OSI ABI can be built before that port is available, but cannot enable RF.
 if rv_hal_chip!=5{esp32_irq_restore(ps);return -95;}
 esp_radio_hw_iso=esp32_load32(0x6000808c);esp_radio_hw_power=esp32_load32(0x60008088);esp_radio_hw_clock=esp32_load32(0x60026014);
 esp_reg_update(0x6000808c,0x10400000,0);esp_reg_update(0x60008088,0x20800,0);esp32_store32(0x60026014,(esp_radio_hw_clock&~0x1020)|0x00fb9fcf);esp_radio_hw_ready=1;esp32_irq_restore(ps);return 0;
}
fn esp_radio_hardware_deinit(){let ps=esp32_irq_save();if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}if !esp_radio_hw_ready{esp32_irq_restore(ps);return 0;}if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 esp_reg_update(0x60026014,0x00fbbfef,esp_radio_hw_clock);esp_reg_update(0x6000808c,0x10400000,esp_radio_hw_iso);esp_reg_update(0x60008088,0x20800,esp_radio_hw_power);esp_radio_hw_ready=0;esp32_irq_restore(ps);return 0;}
fn esp_radio_hw_require(){if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active || !esp_radio_hw_ready || esp_radio_owner!=1{return esp32_call32(0,0,0,0,0,0,0,0,0);}return 0;}
fn esp_radio_random_word(){
 let ps=esp32_irq_save();let now=esp32_cycles();while ((now-esp_radio_rng_last)&4294967295)<128{now=esp32_cycles();}esp_radio_rng_last=now;let address=0x600260b0;if rv_hal_chip==13{address=0x600b2808;}let value=esp32_load32(address);esp32_irq_restore(ps);return value;
}
fn esp_radio_cb_slowclk_cal(a,b,c,d,e,f,g,h){let address=0x60008054;if rv_hal_chip==13{address=0x600b1004;}return esp32_load32(address)>>7;}
fn esp_radio_cb_read_mac(a,b,c,d,e,f,g,h){
 if b>2 || !esp_buffer_valid(a,6){return -1;}let address=0x60008844;if rv_hal_chip==13{address=0x600b0844;}let lo=esp32_load32(address);let hi=esp32_load32(address+4);let mac=(((hi&65535)<<32)|lo)+b;let i=0;while i<6{store8(a+i,mac>>(40-i*8));i=i+1;}return 0;
}
fn esp_radio_wifi_clock(enable){if enable<0 || enable>1{return -22;}let ps=esp32_irq_save();esp_radio_hw_require();if rv_hal_chip==13{esp_reg_update(0x600a9814,0x7ff,enable*0x7ff);esp_reg_update(0x600af018,2,enable*2);}esp32_irq_restore(ps);return 0;}
fn esp_radio_cb_wifi_clock_on(a,b,c,d,e,f,g,h){return esp_radio_wifi_clock(1);}
fn esp_radio_cb_wifi_clock_off(a,b,c,d,e,f,g,h){return esp_radio_wifi_clock(0);}
fn esp_radio_cb_wifi_reset(a,b,c,d,e,f,g,h){
 let ps=esp32_irq_save();esp_radio_hw_require();
 // The pinned C6 radio callback is intentionally empty. C3 uses fresh RMW
 // for each edge so unrelated reset fields changed after assertion survive.
 if rv_hal_chip==5{esp_reg_update(0x60026018,4,4);esp_reg_update(0x60026018,4,0);}
 esp32_irq_restore(ps);return 0;
}
fn esp_radio_phy_clock(enable){
 if enable<0 || enable>1{return -22;}let ps=esp32_irq_save();if esp_radio_base_active || esp_radio_regi2c_active || esp_radio_pmu_active || !esp_radio_hw_ready || esp_radio_owner!=1 || (enable && esp_adc_busy) || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 if enable && esp_radio_phy_clock_refs==9223372036854775807{esp32_irq_restore(ps);return -75;}let change=0;if enable{change=!esp_radio_phy_clock_refs;esp_radio_phy_clock_refs=esp_radio_phy_clock_refs+1;}else if esp_radio_phy_clock_refs{esp_radio_phy_clock_refs=esp_radio_phy_clock_refs-1;change=!esp_radio_phy_clock_refs;}
 if change{if rv_hal_chip==5{esp_reg_update(0x60026014,0x78078f,enable*0x78078f);}else{esp_reg_update(0x600a9814,0x1e000,enable*0x1e000);esp_reg_update(0x600af018,4,enable*4);esp_reg_update(0x600af010,1,enable);}}esp32_irq_restore(ps);return 0;
}
