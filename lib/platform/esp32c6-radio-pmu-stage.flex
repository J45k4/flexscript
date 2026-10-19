import "esp32c6-radio-pmu.flex";
import "esp32c6-radio-regi2c.flex";
import "esp32c6-radio-ocode.flex";
// Reversible state staging for the complete C6 startup transaction. This does
// not issue PMU immediate commands, calibrate clocks/bandgap or enable RF.
// The caller must already supply the internal analog master's base clocks.
// A prepared or uncertain transaction retains the shared radio-domain lease.
global esp_radio_cpu_clock_active=0;
global esp_radio_pmu_saved=0;
global esp_radio_pmu_phase=0;
global esp_radio_pmu_analog_count=0;
global esp_radio_pmu_digital_count=0;
global esp_radio_pmu_rf_before=0;
global esp_radio_pmu_configured=0;
fn esp_radio_c6_pmu_stage_guard(){
 if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}
 if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_radio_hw_ready || esp32_load32(esp32_state()+16){return -16;}return 0;
}
fn esp_radio_c6_pmu_reg(row){if row==0{return 5;}if row==1{return 7;}return 13;}
fn esp_radio_c6_pmu_analog(row,data,cycles){
 if row<0 || row>2{return -22;}let ps=esp32_irq_save();if !esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}
 let high=7;let low=7;if row==2{high=3;low=2;}
 let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;let result=esp_radio_c6_regi2c(0x6d,esp_radio_c6_pmu_reg(row),high,low,data,cycles);esp_radio_pmu_internal=internal;esp32_irq_restore(ps);return result;
}
fn esp_radio_c6_pmu_stage(cycles){
 if cycles<1 || cycles>2147483647{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_pmu_active || esp_radio_pmu_configured || esp_radio_regi2c_active{esp32_irq_restore(ps);return -16;}
 result=esp_radio_c6_regi2c_idle();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_saved{
  let saved=alloc(416);if saved<=0{esp32_irq_restore(ps);return -12;}
  esp_radio_pmu_saved=saved;
 }
 let hp=esp_radio_c6_pmu_read_bias(0);let lp=esp_radio_c6_pmu_read_bias(1);
 let row=0;while row<49{store64(esp_radio_pmu_saved+row*8,esp32_load32(esp_radio_c6_pmu_address(row))&esp_radio_c6_pmu_mask(row));row=row+1;}
 esp_radio_pmu_rf_before=esp32_load32(0x600b0154)&0x0c000000;
 esp_radio_ocode_ready=0;esp_radio_pmu_active=1;esp_radio_pmu_phase=1;esp_radio_pmu_analog_count=0;esp_radio_pmu_digital_count=0;
 esp_reg_update(0x600b0154,0x0c000000,0x0c000000);
 // Snapshot all controlled analog fields before the first analog write.
 row=0;while row<3{result=esp_radio_c6_pmu_analog(row,-1,cycles);if result<0{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}store64(esp_radio_pmu_saved+392+row*8,result);row=row+1;}
 row=0;while row<3{
  let value=1;if row==2{value=0;}
  // Publish intent before the command: a timeout may mean it committed.
  esp_radio_pmu_analog_count=row+1;result=esp_radio_c6_pmu_analog(row,value,cycles);
  if result{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}row=row+1;
 }
 row=0;while row<49{
  esp_radio_pmu_digital_count=row+1;esp_reg_update(esp_radio_c6_pmu_address(row),esp_radio_c6_pmu_mask(row),esp_radio_c6_pmu_value(row,hp,lp));row=row+1;
 }
 esp32_irq_restore(ps);return 0;
}
fn esp_radio_c6_pmu_abort(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_cpu_clock_active{esp32_irq_restore(ps);return -16;}
 if !esp_radio_pmu_active{esp32_irq_restore(ps);return 0;}
 if esp_radio_ocode_active{result=esp_radio_c6_ocode_abort(cycles);if result{esp32_irq_restore(ps);return result;}}
 if esp_radio_regi2c_active{esp_radio_pmu_internal=1;result=esp_radio_c6_regi2c_recover(cycles);esp_radio_pmu_internal=0;if result{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}}
 // Restore latched digital state before disconnecting its regulator interface.
 while esp_radio_pmu_digital_count{let row=esp_radio_pmu_digital_count-1;esp_reg_update(esp_radio_c6_pmu_address(row),esp_radio_c6_pmu_mask(row),load64(esp_radio_pmu_saved+row*8));esp_radio_pmu_digital_count=row;}
 while esp_radio_pmu_analog_count{
  let row=esp_radio_pmu_analog_count-1;let before=load64(esp_radio_pmu_saved+392+row*8);
  // Read back after idle recovery. Never blindly replay an uncertain write.
  result=esp_radio_c6_pmu_analog(row,-1,cycles);if result<0{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}
  if result!=before{result=esp_radio_c6_pmu_analog(row,before,cycles);if result{esp_radio_pmu_phase=2;esp32_irq_restore(ps);return result;}}
  esp_radio_pmu_analog_count=row;
 }
 esp_reg_update(0x600b0154,0x0c000000,esp_radio_pmu_rf_before);
 esp_radio_ocode_ready=0;esp_radio_pmu_phase=0;esp_radio_pmu_active=0;esp32_irq_restore(ps);return 0;
}
// Transfer the prepared state to platform lifetime after the enclosing full
// startup has configured/calibrated its clocks and issued its immediate PMU
// commands. This flag alone never satisfies the C6 hardware-enable gate.
fn esp_radio_c6_pmu_commit(){
 let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || esp_radio_regi2c_active || esp_radio_cpu_clock_active || (esp_radio_ocode_active && (!esp_radio_ocode_ready || esp_radio_ocode_phase!=1)){esp32_irq_restore(ps);return -16;}
 esp_radio_ocode_active=0;esp_radio_ocode_phase=0;esp_radio_ocode_count=0;esp_radio_pmu_configured=1;esp_radio_pmu_phase=0;esp_radio_pmu_active=0;esp_radio_pmu_analog_count=0;esp_radio_pmu_digital_count=0;esp32_irq_restore(ps);return 0;
}
