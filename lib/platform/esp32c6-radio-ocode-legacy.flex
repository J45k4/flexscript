import "esp32c6-radio-pll.flex";
// Power-on software OCODE for untrimmed C6 parts. The enclosing PMU, XTAL,
// PLL-off and continuous analog-clock leases must already be held. Success
// retains the newly calibrated internal OCODE, matching vendor startup;
// failure requires explicit legacy abort before PLL/CPU clock restoration.
fn esp_radio_c6_ocode_legacy_stage(cycles){return esp32_call64(esp32_iram_callback32(esp_radio_c6_ocode_legacy_stage_iram),cycles,0,0,0,0,0,0,0);}
fn esp_radio_c6_ocode_legacy_stage_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();
 if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || !esp_radio_cpu_clock_active || esp_radio_cpu_clock_phase!=2 || !esp_radio_pll_active || esp_radio_pll_phase!=2 || !esp_radio_pll_master_clock_owned || esp_radio_regi2c_active || esp_radio_ocode_active || esp_radio_ocode_ready{esp32_irq_restore(ps);return -16;}
 if (esp32_load32(0x60096110)&0x30000) || (esp32_load32(0x60096118)&255) || (esp32_load32(0x6009611c)&255) || (esp32_load32(0x600b0194)&0x62000000) || !(esp32_load32(0x600af018)&4){esp32_irq_restore(ps);return -16;}
 result=esp_radio_c6_pll_idle();if result{esp32_irq_restore(ps);return result;}
 // Retained trims and factory-coded parts use the existing reset-aware stage.
 let reason=esp32_call32(0x40000018,0,0,0,0,0,0,0,0);if reason<0 || reason>255{esp32_irq_restore(ps);return -5;}
 if reason!=1{esp32_irq_restore(ps);return -95;}
 let version=esp32_load32(0x600b0850);if version&0xf8000000{esp32_irq_restore(ps);return -95;}
 esp_radio_ocode_legacy=1;esp_radio_ocode_active=1;esp_radio_ocode_phase=1;esp_radio_ocode_count=0;
 result=esp_radio_c6_ocode_bus(2,-1,cycles);if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}esp_radio_ocode_before_reset=result;
 result=esp_radio_c6_ocode_bus(1,-1,cycles);if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return -16;}
 // Both reset writes are intentional strobes, including matching old bits.
 // Publish intent before a possibly committed command; abort reads it back.
 esp_radio_ocode_count=3;result=esp_radio_c6_ocode_bus(2,0,cycles);
 if !result{result=esp_radio_c6_ocode_bus(2,1,cycles);}
 if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 result=esp_radio_c6_ocode_legacy_wait(cycles);
 if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 // Keep the new internal result and RESETB=1, matching vendor startup.
 esp_radio_ocode_legacy=0;esp_radio_ocode_active=0;esp_radio_ocode_phase=0;esp_radio_ocode_count=0;esp_radio_ocode_ready=1;esp32_irq_restore(ps);return 0;
}
fn esp_radio_c6_ocode_legacy_abort(cycles){return esp32_call64(esp32_iram_callback32(esp_radio_c6_ocode_legacy_abort_iram),cycles,0,0,0,0,0,0,0);}
fn esp_radio_c6_ocode_legacy_abort_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_ocode_legacy{esp32_irq_restore(ps);if esp_radio_ocode_active{return -16;}return 0;}
 result=esp_radio_c6_ocode_abort(cycles);esp32_irq_restore(ps);return result;
}
