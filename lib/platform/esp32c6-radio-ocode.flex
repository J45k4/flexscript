// C6 power-on factory bandgap trim, pinned IDF fcae32885b02 ocode_init.c.
// Imported by PMU staging; the enclosing PMU lease owns RF/regulator power.
// Legacy (untrimmed) parts still require software calibration and PLL ownership.
global esp_radio_ocode_active=0;
global esp_radio_ocode_legacy=0;
global esp_radio_ocode_before_reset=0;
global esp_radio_ocode_ready=0;
global esp_radio_ocode_phase=0;
global esp_radio_ocode_count=0;
global esp_radio_ocode_before_code=0;
global esp_radio_ocode_before_force=0;
fn esp_radio_c6_ocode_bus(row,data,cycles){
 if row<0 || row>2 || (row==2 && !esp_radio_ocode_legacy){return -22;}let ps=esp32_irq_save();
 if !esp_radio_pmu_active || !esp_radio_ocode_active{esp32_irq_restore(ps);return -16;}
 let reg=6;let high=7;let low=0;if row{reg=5;high=6;low=6;}if row==2{reg=0;high=0;low=0;}
 let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;
 let result=esp_radio_c6_regi2c(0x61,reg,high,low,data,cycles);
 esp_radio_pmu_internal=internal;esp32_irq_restore(ps);return result;
}
// The40MHz XTAL lease supplies a monotonic nominal10ms ceiling without
// depending on slow-clock retention stores. Call only with PLL off/IRQ masked.
fn esp_radio_c6_ocode_legacy_wait(cycles){
 let limit=cycles;if limit>400000{limit=400000;}let start=esp32_cycles();
 while 1{
  let elapsed=(esp32_cycles()-start)&0xffffffff;if elapsed>=limit{return -110;}
  let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;
  let result=esp_radio_c6_regi2c(0x61,3,7,0,-1,limit-elapsed);esp_radio_pmu_internal=internal;
  if result<0{return result;}
  if ((esp32_cycles()-start)&0xffffffff)>=limit{return -110;}
  if (result&9)==9{return 0;}
 }
}
fn esp_radio_c6_ocode_stage(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || esp_radio_regi2c_active || esp_radio_ocode_active || esp_radio_ocode_ready{esp32_irq_restore(ps);return -16;}
 let reason=esp32_call32(0x40000018,0,0,0,0,0,0,0,0);
 if reason<0 || reason>255{esp32_irq_restore(ps);return -5;}
 // The analog domain retains its trim across non-power-on resets. Do not
 // even read the calibration fuses on those paths, matching the vendor code.
 if reason!=1{esp_radio_ocode_ready=1;esp32_irq_restore(ps);return 0;}
 let version=esp32_load32(0x600b0850);version=(version>>30)*100+((version>>27)&7);
 if !version{esp32_irq_restore(ps);return -95;}
 let code=(esp32_load32(0x600b086c)>>9)&255;
 esp_radio_ocode_active=1;esp_radio_ocode_phase=1;esp_radio_ocode_count=0;
 result=esp_radio_c6_ocode_bus(0,-1,cycles);
 if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}esp_radio_ocode_before_code=result;
 result=esp_radio_c6_ocode_bus(1,-1,cycles);
 if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}esp_radio_ocode_before_force=result;
 // Journal intent before each command: a timeout may follow its effect.
 esp_radio_ocode_count=1;result=esp_radio_c6_ocode_bus(0,code,cycles);
 if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 esp_radio_ocode_count=2;result=esp_radio_c6_ocode_bus(1,1,cycles);
 if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 esp_radio_ocode_ready=1;esp32_irq_restore(ps);return 0;
}
// Roll back trims while the outer PMU lease and RF-I2C power are still held.
// Uncertain writes are read back after idle recovery, never blindly replayed.
fn esp_radio_c6_ocode_abort(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}
 if !esp_radio_ocode_active{esp_radio_ocode_ready=0;esp32_irq_restore(ps);return 0;}
 if esp_radio_regi2c_active{
  let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;
  result=esp_radio_c6_regi2c_recover(cycles);esp_radio_pmu_internal=internal;
  if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
 }
 if esp_radio_ocode_legacy{
  // Abort a pending calibration before the PLL/CPU clocks can be restored.
  if !esp_radio_cpu_clock_active || (esp32_load32(0x600b0194)&0x62000000){esp32_irq_restore(ps);return -16;}
  if esp_radio_ocode_count{
   result=esp_radio_c6_ocode_bus(2,-1,cycles);if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
   if result!=esp_radio_ocode_before_reset{result=esp_radio_c6_ocode_bus(2,esp_radio_ocode_before_reset,cycles);if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}}
  }
  if esp_radio_ocode_count && esp_radio_ocode_before_reset{result=esp_radio_c6_ocode_legacy_wait(cycles);if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}}
  esp_radio_ocode_legacy=0;esp_radio_ocode_count=0;
 }
 while esp_radio_ocode_count{
  let row=esp_radio_ocode_count-1;let before=esp_radio_ocode_before_code;if row{before=esp_radio_ocode_before_force;}
  result=esp_radio_c6_ocode_bus(row,-1,cycles);
  if result<0{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}
  if result!=before{result=esp_radio_c6_ocode_bus(row,before,cycles);if result{esp_radio_ocode_phase=2;esp32_irq_restore(ps);return result;}}
  esp_radio_ocode_count=row;
 }
 esp_radio_ocode_ready=0;esp_radio_ocode_phase=0;esp_radio_ocode_active=0;esp32_irq_restore(ps);return 0;
}
