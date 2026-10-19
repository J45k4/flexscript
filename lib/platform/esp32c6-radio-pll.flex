import "esp32c6-radio-clock.flex";
// Owned 40MHz-XTAL/480MHz-BBPLL power cycle. The CPU XTAL and outer PMU
// leases remain held throughout; this component never restores caller IRQs.
global esp_radio_pll_consumers=0;
global esp_radio_pll_phase=0;
global esp_radio_pll_old_master_clock=0;
global esp_radio_pll_master_clock_owned=0;
global esp_radio_pll_old_state=0;
global esp_radio_pll_old_ana=0;
global esp_radio_pll_old_mspi=0;
global esp_radio_pll_off_intent=0;
global esp_radio_pll_mspi_owned=0;
global esp_radio_pll_cal_step=0;
global esp_radio_pll_cal_row=0;
global esp_radio_pll_settled=0;
global esp_radio_pll_cal_pending=0;
fn esp_radio_c6_pll_consumer(keep){
 if keep<0 || keep>1{return -22;}if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}
 let ps=esp32_irq_save();if esp_radio_pll_active || (esp_radio_calibration_active && !esp_radio_calibration_internal){esp32_irq_restore(ps);return -16;}
 if keep{if esp_radio_pll_consumers==9223372036854775807{esp32_irq_restore(ps);return -75;}esp_radio_pll_consumers=esp_radio_pll_consumers+1;}
 else{if !esp_radio_pll_consumers{esp32_irq_restore(ps);return -22;}esp_radio_pll_consumers=esp_radio_pll_consumers-1;}
 esp32_irq_restore(ps);return 0;
}
fn esp_radio_c6_pll_consumer_address(row){
 if row<0 || row>14{return -22;}let offset=4;
 if row==1{offset=0x10;}if row==2{offset=0x30;}if row==3{offset=0x38;}
 if row==4 || row==5{offset=0x40+(row-4)*4;}if row==6 || row==7{offset=0x4c+(row-6)*4;}
 if row==8{offset=0x70;}if row==9{offset=0x78;}if row==10{offset=0x84;}if row==11{offset=0xa0;}if row==12{offset=0xb8;}if row==13{offset=0xc4;}if row==14{offset=0xec;}return 0x60096000+offset;
}
fn esp_radio_c6_pll_consumer_word(row,value){
 if !(value&0x400000){return 0;}let source=(value>>20)&3;if row==12{source=source&1;}
 if row==8 || row==9{return source==1 || source==2;}
 if (row>=4 && row<=7) || row==10 || row==13{return source==1 || source==3;}
 return source==1;
}
fn esp_radio_c6_pll_idle(){
 if esp_radio_pll_consumers || (esp32_load32(0x6009608c)&3)==1{return -16;}
 let row=0;while row<15{if esp_radio_c6_pll_consumer_word(row,esp32_load32(esp_radio_c6_pll_consumer_address(row))){return -16;}row=row+1;}
 // Keep APB-only modem gates independent; any functional modem clock is busy.
 if (esp32_load32(0x600a9804)&0xef400000) || (esp32_load32(0x600a9814)&0xfcfbff){return -16;}
 return esp_radio_c6_clock_idle();
}
fn esp_radio_c6_pll_reg(row){if row==0{return 2;}if row==1{return 3;}if row==2 || row==3 || row==6{return 5;}if row==4{return 6;}return 9;}
fn esp_radio_c6_pll_high(row){if row==2{return 2;}if row==3{return 6;}if row==5{return 1;}return 7;}
fn esp_radio_c6_pll_low(row){if row==3{return 4;}if row==6{return 7;}return 0;}
fn esp_radio_c6_pll_value(row){if row==0{return 0x50;}if row==1{return 8;}if row==4{return 0x73;}if row==5{return 2;}return 0;}
fn esp_radio_c6_pll_bus(row,data,cycles){
 if row<0 || row>6{return -22;}if !esp_radio_pll_active || !esp_radio_cpu_clock_active{return -16;}
 let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;
 let result=esp_radio_c6_regi2c(0x66,esp_radio_c6_pll_reg(row),esp_radio_c6_pll_high(row),esp_radio_c6_pll_low(row),data,cycles);esp_radio_pmu_internal=internal;return result;
}
// Program every canonical coefficient once after calibration starts. A timed
// out RMW read has not issued its write; distinguish it from an uncertain
// write before deciding whether matching readback permits skipping a retry.
fn esp_radio_c6_pll_program(row,cycles){
 let value=esp_radio_c6_pll_value(row);let result=0;
 if esp_radio_pll_cal_pending==2{result=esp_radio_c6_pll_bus(row,-1,cycles);if result<0{return result;}if result==value{esp_radio_pll_cal_pending=0;return 0;}}
 esp_radio_pll_cal_pending=1;result=esp_radio_c6_pll_bus(row,value,cycles);
 if result==-110 && esp_radio_regi2c_active{
  if esp_radio_regi2c_write_issued{esp_radio_pll_cal_pending=2;}
 }
 if !result{esp_radio_pll_cal_pending=0;}return result;
}
fn esp_radio_c6_pll_guard(){
 let result=esp_radio_c6_pmu_stage_guard();if result{return result;}
 if !esp_radio_pmu_active || !esp_radio_cpu_clock_active || esp_radio_cpu_clock_phase!=2 || esp_radio_ocode_active{return -16;}
 if (esp32_load32(0x60096110)&0x30000) || (esp32_load32(0x60096118)&255) || (esp32_load32(0x6009611c)&255){return -16;}
 return 0;
}
fn esp_radio_c6_pll_begin(cycles){return esp32_call64(esp32_iram_callback32(esp_radio_c6_pll_begin_iram),cycles,0,0,0,0,0,0,0);}
fn esp_radio_c6_pll_begin_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pll_guard();
 if result{if !esp_radio_cpu_clock_active{esp32_irq_restore(ps);}return result;}
 if esp_radio_pll_active || esp_radio_regi2c_active{return -16;}result=esp_radio_c6_pll_idle();if result{return result;}
 let state=esp32_load32(0x600b0194);let on=state&0x40000000;
 if on{if (state&0x70000001)!=0x70000001{return -95;}}
 else{if state&0x62000000{return -95;}}
 let ana=esp32_load32(0x600af818);if ana&8{return -16;}if on && (ana&12)!=4{return -95;}
 esp_radio_pll_old_state=state&0x72000000;esp_radio_pll_old_ana=ana&12;esp_radio_pll_old_mspi=esp32_load32(0x60096018)&4;
 esp_radio_pll_off_intent=0;esp_radio_pll_mspi_owned=0;esp_radio_pll_master_clock_owned=0;esp_radio_pll_cal_step=0;esp_radio_pll_cal_row=0;esp_radio_pll_settled=0;esp_radio_pll_cal_pending=0;esp_radio_pll_phase=1;esp_radio_pll_active=1;
 // Hold the analog master clock across asynchronous calibration, not just
 // individual bus commands; nested transactions restore this held state.
 esp_radio_pll_old_master_clock=esp32_load32(0x600af018)&4;esp_radio_pll_master_clock_owned=1;
 result=esp_radio_c6_clock_write(0x600af018,4,4,cycles);if result{return result;}
 if on{
  result=esp_radio_c6_pll_bus(6,-1,cycles);if result<0{return result;}if result{return -16;}
  let row=0;while row<6{result=esp_radio_c6_pll_bus(row,-1,cycles);if result<0{return result;}if result!=esp_radio_c6_pll_value(row){return -95;}row=row+1;}
 }
 result=esp_radio_c6_pll_idle();if result{return result;}
 esp_radio_pll_mspi_owned=1;result=esp_radio_c6_clock_write(0x60096018,4,0,cycles);if result{return result;}
 // PMU tie commands are write triggers. Write only the intended command,
 // and inspect actual power state rather than reading/replaying trigger bits.
 esp_radio_pll_off_intent=1;state=esp32_load32(0x600b0194);
 if state&0x02000000{esp32_store32(0x600b00cc,1);}
 if state&0x60000000{esp32_store32(0x600b00cc,0x30);}
 result=esp_wait_mask(0x600b0194,0x62000000,0,cycles);if result{return result;}
 esp_radio_pll_phase=2;return 0;
}
fn esp_radio_c6_pll_restore(cycles){return esp32_call64(esp32_iram_callback32(esp_radio_c6_pll_restore_iram),cycles,0,0,0,0,0,0,0);}
fn esp_radio_c6_pll_restore_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pll_guard();
 if result{if !esp_radio_cpu_clock_active{esp32_irq_restore(ps);}return result;}
 if !esp_radio_pll_active{return 0;}
 result=esp_radio_c6_pll_idle();if result{return result;}
 if esp_radio_regi2c_active{let internal=esp_radio_pmu_internal;esp_radio_pmu_internal=1;result=esp_radio_c6_regi2c_recover(cycles);esp_radio_pmu_internal=internal;if result{return result;}}
 if esp_radio_pll_off_intent && (esp_radio_pll_old_state&0x40000000){
  esp_radio_pll_phase=3;let state=esp32_load32(0x600b0194);let missing=0x70000000&~state;
  if missing{esp32_store32(0x600b00cc,missing);}result=esp_wait_mask(0x600b0194,0x70000000,0x70000000,cycles);if result{return result;}
  if !(esp32_load32(0x600b0194)&0x02000000){esp32_store32(0x600b00cc,0x02000000);}
  result=esp_wait_mask(0x600b0194,0x02000000,0x02000000,cycles);if result{return result;}
  if esp_radio_pll_cal_step<1{result=esp_radio_c6_clock_write(0x600af818,4,0,cycles);if result{return result;}esp_radio_pll_cal_step=1;}
  if esp_radio_pll_cal_step<2{result=esp_radio_c6_clock_write(0x600af818,8,8,cycles);if result{return result;}esp_radio_pll_cal_step=2;}
  while esp_radio_pll_cal_row<6{
   let row=esp_radio_pll_cal_row;result=esp_radio_c6_pll_program(row,cycles);if result{return result;}esp_radio_pll_cal_row=row+1;
  }
  if esp_radio_pll_cal_step<3{
   result=esp_wait_mask(0x600af818,0x1000000,0x1000000,cycles);if result{return result;}
   if !esp_radio_pll_settled{if cycles<400{return -110;}let start=esp32_cycles();while ((esp32_cycles()-start)&0xffffffff)<400{}esp_radio_pll_settled=1;}
   result=esp_radio_c6_clock_write(0x600af818,8,0,cycles);if result{return result;}esp_radio_pll_cal_step=3;
  }
  if esp_radio_pll_cal_step<4{result=esp_radio_c6_clock_write(0x600af818,4,4,cycles);if result{return result;}esp_radio_pll_cal_step=4;}
  result=esp_radio_c6_clock_write(0x600af818,12,esp_radio_pll_old_ana,cycles);if result{return result;}
 }
 if esp_radio_pll_off_intent && (esp_radio_pll_old_state&0x40000000) && !(esp_radio_pll_old_state&0x02000000){
  if esp32_load32(0x600b0194)&0x02000000{esp32_store32(0x600b00cc,1);}
 }
 if esp_radio_pll_off_intent{
  let mask=0x72000000;let expected=esp_radio_pll_old_state;
  if expected&0x40000000{mask=mask|1;expected=expected|1;}
  result=esp_wait_mask(0x600b0194,mask,expected,cycles);if result{return result;}
 }
 if esp_radio_pll_mspi_owned{result=esp_radio_c6_clock_write(0x60096018,4,esp_radio_pll_old_mspi,cycles);if result{return result;}}
 if esp_radio_pll_master_clock_owned{result=esp_radio_c6_clock_write(0x600af018,4,esp_radio_pll_old_master_clock,cycles);if result{return result;}}
 esp_radio_pll_master_clock_owned=0;esp_radio_pll_phase=0;esp_radio_pll_active=0;return 0;
}
