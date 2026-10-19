import "esp32c6-radio-ocode-legacy.flex";
// Coordinates an already prepared PMU. Clock-changing work enters the existing
// IRAM callbacks; this ordinary caller may execute from cached flash at XTAL.
// The outer IRQ mask spans all callbacks and is restored only after cleanup.
global esp_radio_calibration_phase=0;
global esp_radio_calibration_step=0;
global esp_radio_calibration_mode=0;
global esp_radio_calibration_ps=0;
global esp_radio_calibration_error=0;
global esp_radio_calibration_cleanup_error=0;
fn esp_radio_c6_calibration_prepare(cycles){
 if cycles<1 || cycles>2147483647{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || esp_radio_cpu_clock_active || esp_radio_pll_active || esp_radio_regi2c_active || esp_radio_ocode_active || esp_radio_ocode_ready{esp32_irq_restore(ps);return -16;}
 // Select before changing the CPU or PLL. Component stages revalidate the
 // immutable reset/eFuse policy; retained resets never read trim fuses.
 let reason=esp32_call32(0x40000018,0,0,0,0,0,0,0,0);if reason<0 || reason>255{esp32_irq_restore(ps);return -5;}
 let mode=2;if reason==1{mode=1;if !(esp32_load32(0x600b0850)&0xf8000000){mode=3;}}
 esp_radio_calibration_ps=ps;esp_radio_calibration_mode=mode;esp_radio_calibration_error=0;esp_radio_calibration_cleanup_error=0;
 esp_radio_calibration_step=1;esp_radio_calibration_phase=1;esp_radio_calibration_active=1;esp_radio_calibration_internal=1;
 if mode!=3{result=esp_radio_c6_ocode_stage(cycles);}else{
  esp_radio_calibration_step=2;result=esp_radio_c6_clock_begin(cycles);
  if !result{esp_radio_calibration_step=3;result=esp_radio_c6_pll_begin(cycles);}
  if !result{esp_radio_calibration_step=4;result=esp_radio_c6_ocode_legacy_stage(cycles);}
  if !result{esp_radio_calibration_step=5;result=esp_radio_c6_pll_restore(cycles);}
  if !result{esp_radio_calibration_step=6;result=esp_radio_c6_clock_restore(cycles);}
 }
 if !result && !esp_radio_ocode_ready{result= -5;}
 esp_radio_calibration_internal=0;
 if result{esp_radio_calibration_error=result;esp_radio_calibration_phase=2;return result;}
 esp_radio_calibration_step=0;esp_radio_calibration_phase=0;esp_radio_calibration_active=0;esp32_irq_restore(esp_radio_calibration_ps);return 0;
}
// Resume cleanup only: never replay preparation or clear its original error.
// A successful abort leaves the caller's PMU prepared for PMU abort/retry.
fn esp_radio_c6_calibration_abort(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 if !esp_radio_calibration_active{let result=esp_radio_c6_pmu_stage_guard();esp32_irq_restore(ps);return result;}
 esp_radio_calibration_internal=1;let result=esp_radio_c6_pmu_stage_guard();
 if !result && esp_radio_ocode_active{if esp_radio_ocode_legacy{result=esp_radio_c6_ocode_legacy_abort(cycles);}else{result=esp_radio_c6_ocode_abort(cycles);}}
 if !result && esp_radio_pll_active{result=esp_radio_c6_pll_restore(cycles);}
 if !result && esp_radio_cpu_clock_active{result=esp_radio_c6_clock_restore(cycles);}
 esp_radio_calibration_internal=0;esp_radio_calibration_cleanup_error=result;
 if result{return result;}
 esp_radio_ocode_ready=0;esp_radio_calibration_step=0;esp_radio_calibration_phase=0;esp_radio_calibration_active=0;esp32_irq_restore(esp_radio_calibration_ps);return 0;
}
