import "esp32c6-radio-calibration.flex";
import "esp32c6-radio-modem.flex";
// Enclosing CPU0 base-clock transaction. RF/PHY remain a separate consumer.
// Live monitor fields are checked, not replaced with write-only echoes.
global esp_radio_base_phase=0;global esp_radio_base_step=0;global esp_radio_base_recovery=0;
global esp_radio_base_ps=0;global esp_radio_base_error=0;global esp_radio_base_cleanup_error=0;
global esp_radio_base_code=0;global esp_radio_base_slp=0;global esp_radio_base_sys_map=0;global esp_radio_base_lp_map=0;global esp_radio_base_live=0;
global esp_radio_base_target_code=0;global esp_radio_base_target_slp=0;global esp_radio_base_command_step=0;global esp_radio_base_issued=0;global esp_radio_base_touched=0;
fn esp_radio_c6_base_guard(){
 if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}
 if esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp_radio_hw_ready || esp32_load32(esp32_state()+16){return -16;}return 0;
}
fn esp_radio_c6_base_put(address,mask,value,cycles){
 let start=esp32_cycles();value=value&mask;
 if (esp32_load32(address)&mask)!=value{esp_reg_update(address,mask,value);}
 while 1{if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}let observed=esp32_load32(address)&mask;if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}if observed==value{return 0;}}return -110;
}
fn esp_radio_c6_base_strobe(address,command,mask,target,cycles,issue){
 if cycles<1 || cycles>2147483647 || issue<0 || issue>1 || (target&~mask){return -22;}
 if address==0x600b00dc{if command!=0x80000000 || mask!=0x600000{return -22;}}
 else if address==0x600b00d0{if command!=0x10000000 || mask!=0x800000{return -22;}}else{return -22;}
 if !esp_radio_base_active || !esp_radio_base_internal || esp_radio_owner!=1{return -16;}
 return esp32_call64(esp32_iram_callback32(esp_radio_c6_base_strobe_iram),address,command,mask,target,cycles,issue,0,0);
}
fn esp_radio_c6_base_strobe_iram(address,command,mask,target,cycles,issue,g,h){
 // The cached wrapper validates the upper bound and command tuple.
 if cycles<1{return -22;}
 let ps=esp32_irq_save();if (ps&8)|(!esp_radio_base_active){esp32_irq_restore(ps);return -16;}
 let start=esp32_cycles();if issue{esp32_store32(address,command);}
 // The status is read-only. Check the deadline after every read, including
 // a matching read, so late completion cannot be accepted.
 while 1{let observed=esp32_load32(0x600b0194)&mask;if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}if observed==target{return 0;}}return -110;
}
fn esp_radio_c6_base_command(cycles,drain){
 while esp_radio_base_command_step<2{
  if drain && !esp_radio_base_issued{return 0;}
  let address=0x600b00dc;let command=0x80000000;let mask=0x600000;let target=esp_radio_base_target_code<<21;
  if esp_radio_base_command_step{address=0x600b00d0;command=0x10000000;mask=0x800000;target=esp_radio_base_target_slp<<23;}
  let issue=!esp_radio_base_issued;esp_radio_base_issued=1;esp_radio_base_touched=1;
  let result=esp_radio_c6_base_strobe(address,command,mask,target,cycles,issue);
  if result{return result;}esp_radio_base_issued=0;esp_radio_base_command_step=esp_radio_base_command_step+1;
  if drain{return 0;}
 }return 0;
}
fn esp_radio_c6_base_prepare(source,divider,cycles){
 if source<0 || source>5 || divider<0 || divider>4095 || cycles<1 || cycles>2147483647{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_base_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_base_active || esp_radio_base_configured || esp_radio_pmu_active || esp_radio_pmu_configured || esp_radio_modem_active || esp_radio_modem_configured || esp_radio_calibration_active || esp_radio_cpu_clock_active || esp_radio_pll_active || esp_radio_ocode_active || esp_radio_regi2c_active{esp32_irq_restore(ps);return -16;}
 result=esp_radio_c6_clock_idle();if result{esp32_irq_restore(ps);return result;}
 // Reject foreign radio users and a PCR handoff that could disable flash.
 if esp32_load32(0x600a9804)&0xffe00000 || esp32_load32(0x600a9814)&0x7fffff || esp32_load32(0x600af018)&11 || (esp32_load32(0x60096018)&3)!=1{esp32_irq_restore(ps);return -16;}
 let code=esp32_load32(0x600b000c)&0xc0000000;let slp=esp32_load32(0x600b0024)&0x04000000;let live=esp32_load32(0x600b0194)&0xf00000;
 // Only take over a represented state; do not guess how to restore a live
 // selector which disagrees with its configured active-state value.
 if ((live>>21)&3)!=(code>>30) || ((live>>23)&1)!=(slp>>26){esp32_irq_restore(ps);return -16;}
 esp_radio_base_ps=ps;esp_radio_base_code=code;esp_radio_base_slp=slp;esp_radio_base_live=live;
 esp_radio_base_sys_map=esp32_load32(0x600a980c)&0xf0000000;esp_radio_base_lp_map=esp32_load32(0x600af020)&0xff000000;
 esp_radio_base_error=0;esp_radio_base_cleanup_error=0;esp_radio_base_recovery=0;esp_radio_base_command_step=0;esp_radio_base_issued=0;esp_radio_base_touched=0;
 esp_radio_base_active=1;esp_radio_base_internal=1;esp_radio_base_phase=1;esp_radio_base_step=1;
 // Keep APB access available at both the old and new code during the change.
 let bridge=4|(1<<(code>>30));
 result=esp_radio_c6_base_put(0x600a980c,0xf0000000,bridge<<28,cycles);
 if !result{result=esp_radio_c6_base_put(0x600af020,0xff000000,(bridge<<28)|(bridge<<24),cycles);}
 if !result{result=esp_radio_c6_base_put(0x600b000c,0xc0000000,0x80000000,cycles);}
 esp_radio_base_target_code=2;esp_radio_base_target_slp=slp>>26;
 if !result{result=esp_radio_c6_base_command(cycles,0);}
 if !result{result=esp_radio_c6_base_put(0x600af020,0xff000000,0x44000000,cycles);}
 if !result{result=esp_radio_c6_base_put(0x600a980c,0xf0000000,0x40000000,cycles);}
 if !result{esp_radio_base_step=2;result=esp_radio_c6_pmu_stage(cycles);}
 if !result{esp_radio_base_step=3;result=esp_radio_c6_calibration_prepare(cycles);}
 if !result{esp_radio_base_step=4;result=esp_radio_c6_modem_stage(source,divider,cycles);}
 if !result{
  esp_radio_base_step=5;result=esp_radio_c6_clock_idle();
  if !result && (esp32_load32(0x60096018)&3)!=1{result= -16;}
  if !result{esp_radio_base_target_code=(esp32_load32(0x600b000c)>>30)&3;esp_radio_base_target_slp=(esp32_load32(0x600b0024)>>26)&1;esp_radio_base_command_step=0;result=esp_radio_c6_base_command(cycles,0);}
 }
 esp_radio_base_internal=0;if result{esp_radio_base_error=result;esp_radio_base_phase=2;return result;}
 esp_radio_base_step=6;return 0;
}
fn esp_radio_c6_base_abort(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 if !esp_radio_base_active{let result=esp_radio_c6_base_guard();if !result && esp_radio_base_configured{result= -16;}esp32_irq_restore(ps);return result;}
 esp_radio_base_internal=1;let result=esp_radio_c6_base_guard();
 // Complete an issued command before changing the policy it may still sample.
 if !result{result=esp_radio_c6_base_command(cycles,1);}
 if !result && esp_radio_modem_active{result=esp_radio_c6_modem_abort(cycles);}
 if !result && esp_radio_calibration_active{result=esp_radio_c6_calibration_abort(cycles);}
 if !result && esp_radio_pmu_active{result=esp_radio_c6_pmu_abort(cycles);}
 while !result && esp_radio_base_recovery<8{
  let step=esp_radio_base_recovery;
  if step==0 && esp_radio_base_touched{let bridge=4|(1<<(esp_radio_base_code>>30));result=esp_radio_c6_base_put(0x600a980c,0xf0000000,bridge<<28,cycles);if !result{result=esp_radio_c6_base_put(0x600af020,0xff000000,(bridge<<28)|(bridge<<24),cycles);}}
  else if step==0{}
  else if step==1{result=esp_radio_c6_base_put(0x600b000c,0xc0000000,esp_radio_base_code,cycles);}
  else if step==2{result=esp_radio_c6_base_put(0x600b0024,0x04000000,esp_radio_base_slp,cycles);}
  else if step==3{esp_radio_base_target_code=esp_radio_base_code>>30;esp_radio_base_target_slp=esp_radio_base_slp>>26;esp_radio_base_command_step=0;}
  else if step==4{if esp_radio_base_touched{result=esp_radio_c6_base_command(cycles,0);}}
  else if step==5{result=esp_radio_c6_base_put(0x600af020,0xff000000,esp_radio_base_lp_map,cycles);}
  else if step==6{result=esp_radio_c6_base_put(0x600a980c,0xf0000000,esp_radio_base_sys_map,cycles);}
  else{let start=esp32_cycles();while !result && (esp32_load32(0x600b0194)&0xf00000)!=esp_radio_base_live{if ((esp32_cycles()-start)&0xffffffff)>=cycles{result= -110;}}}
  if !result{esp_radio_base_recovery=step+1;}
 }
 esp_radio_base_internal=0;esp_radio_base_cleanup_error=result;if result{esp_radio_base_phase=2;return result;}
 esp_radio_base_active=0;esp_radio_base_phase=0;esp_radio_base_step=0;esp_radio_base_recovery=0;esp32_irq_restore(esp_radio_base_ps);return 0;
}
fn esp_radio_c6_base_commit(){
 let ps=esp32_irq_save();if !esp_radio_base_active || esp_radio_base_phase!=1 || esp_radio_base_step!=6{esp32_irq_restore(ps);return -16;}
 esp_radio_base_internal=1;let result=esp_radio_c6_base_guard();if !result{result=esp_radio_c6_modem_commit();}esp_radio_base_internal=0;
 if result{return result;}esp_radio_base_configured=1;esp_radio_base_active=0;esp_radio_base_phase=0;esp_radio_base_step=0;esp32_irq_restore(esp_radio_base_ps);return 0;
}
