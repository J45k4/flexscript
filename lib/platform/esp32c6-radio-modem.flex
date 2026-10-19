import "esp32c6-radio-pmu-stage.flex";
// ESP-IDF fcae32885b02 modem ICG defaults and Wi-Fi LP source/divider.
// Stages register policy under the prepared PMU/calibration lease. Immediate
// PMU update strobes and RF/PHY activation belong to the enclosing startup.
global esp_radio_modem_phase=0;
global esp_radio_modem_step=0;
global esp_radio_modem_recovery=0;
global esp_radio_modem_ps=0;
global esp_radio_modem_error=0;
global esp_radio_modem_cleanup_error=0;
global esp_radio_modem_sys_map=0;
global esp_radio_modem_lp_map=0;
global esp_radio_modem_wifi=0;
global esp_radio_modem_32k=0;
global esp_radio_modem_clock=0;
fn esp_radio_c6_modem_put(address,mask,value,cycles){
 if !esp_radio_modem_active || !esp_radio_modem_internal{return -16;}let start=esp32_cycles();value=value&mask;
 // A timed-out store may have committed. Read back before any retry.
 if (esp32_load32(address)&mask)!=value{esp_reg_update(address,mask,value);}
 while 1{
  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}
  let observed=esp32_load32(address)&mask;
  if ((esp32_cycles()-start)&0xffffffff)>=cycles{return -110;}
  if observed==value{return 0;}
 }return -110;
}
fn esp_radio_c6_modem_stage(source,divider,cycles){
 if source<0 || source>5 || divider<0 || divider>4095 || cycles<1 || cycles>2147483647{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_modem_configured || !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || !esp_radio_ocode_ready || esp_radio_regi2c_active || esp_radio_cpu_clock_active || esp_radio_pll_active{esp32_irq_restore(ps);return -16;}
 // BLE/coexistence have independent users of the shared 32k selector. Never
 // retune their selected source, even when their functional clock is gated.
 let selected=esp32_load32(0x600af014)&3;let code=selected;
 if source==3{code=1;}if source==4{code=0;}if source==5{code=2;}
 if esp32_load32(0x600af018)&10 || esp32_load32(0x600af01c)&11 || (code!=selected && ((esp32_load32(0x600af004)|esp32_load32(0x600af008))&8)){esp32_irq_restore(ps);return -16;}
 esp_radio_modem_sys_map=esp32_load32(0x600a980c)&0xffffff00;esp_radio_modem_lp_map=esp32_load32(0x600af020)&0xffff0000;
 esp_radio_modem_wifi=esp32_load32(0x600af00c)&0xffff;esp_radio_modem_32k=selected;esp_radio_modem_clock=esp32_load32(0x600af018)&1;
 esp_radio_modem_ps=ps;esp_radio_modem_error=0;esp_radio_modem_cleanup_error=0;esp_radio_modem_recovery=0;esp_radio_modem_phase=1;esp_radio_modem_active=1;esp_radio_modem_internal=1;
 esp_radio_modem_step=1;result=esp_radio_c6_modem_put(0x600af018,1,0,cycles);
 if !result{esp_radio_modem_step=2;result=esp_radio_c6_modem_put(0x600a980c,0xffffff00,esp_radio_modem_sys_map|0x64646400,cycles);}
 if !result{esp_radio_modem_step=3;result=esp_radio_c6_modem_put(0x600af020,0xffff0000,esp_radio_modem_lp_map|0x66660000,cycles);}
 if !result{esp_radio_modem_step=4;result=esp_radio_c6_modem_put(0x600af00c,15,0,cycles);}
 if !result{esp_radio_modem_step=5;result=esp_radio_c6_modem_put(0x600af014,3,code,cycles);}
 let mux=1<<source;if source>=3{mux=8;}
 if !result{esp_radio_modem_step=6;result=esp_radio_c6_modem_put(0x600af00c,15,mux,cycles);}
 if !result{esp_radio_modem_step=7;result=esp_radio_c6_modem_put(0x600af00c,0xfff0,divider<<4,cycles);}
 if !result{esp_radio_modem_step=8;result=esp_radio_c6_modem_put(0x600af018,1,1,cycles);}
 esp_radio_modem_internal=0;if result{esp_radio_modem_error=result;esp_radio_modem_phase=2;}return result;
}
fn esp_radio_c6_modem_abort(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 if !esp_radio_modem_active{let result=esp_radio_c6_pmu_stage_guard();if !result && esp_radio_modem_configured{result= -16;}esp32_irq_restore(ps);return result;}
 esp_radio_modem_internal=1;let result=esp_radio_c6_pmu_stage_guard();
 // Disconnect the consumer before restoring shared source and mux settings.
 while !result && esp_radio_modem_recovery<7{
  let step=esp_radio_modem_recovery;
  if step==0{result=esp_radio_c6_modem_put(0x600af018,1,0,cycles);}
  else if step==1{result=esp_radio_c6_modem_put(0x600af00c,15,0,cycles);}
  else if step==2{result=esp_radio_c6_modem_put(0x600af014,3,esp_radio_modem_32k,cycles);}
  else if step==3{result=esp_radio_c6_modem_put(0x600af00c,0xffff,esp_radio_modem_wifi,cycles);}
  else if step==4{result=esp_radio_c6_modem_put(0x600af020,0xffff0000,esp_radio_modem_lp_map,cycles);}
  else if step==5{result=esp_radio_c6_modem_put(0x600a980c,0xffffff00,esp_radio_modem_sys_map,cycles);}
  else{result=esp_radio_c6_modem_put(0x600af018,1,esp_radio_modem_clock,cycles);}
  if !result{esp_radio_modem_recovery=step+1;}
 }
 esp_radio_modem_internal=0;esp_radio_modem_cleanup_error=result;if result{esp_radio_modem_phase=2;return result;}
 esp_radio_modem_active=0;esp_radio_modem_phase=0;esp_radio_modem_step=0;esp_radio_modem_recovery=0;esp32_irq_restore(esp_radio_modem_ps);return 0;
}
// Transfer both prepared leases to platform lifetime. The enclosing startup
// must finish immediate PMU/base-clock activation before this call, while
// PHY references are still zero; PHY/RF ownership follows the transfer.
fn esp_radio_c6_modem_commit(){
 let ps=esp32_irq_save();if !esp_radio_modem_active || esp_radio_modem_phase!=1 || esp_radio_modem_step!=8{esp32_irq_restore(ps);return -16;}
 esp_radio_modem_internal=1;let result=esp_radio_c6_pmu_commit();esp_radio_modem_internal=0;
 if result{return result;}esp_radio_modem_configured=1;esp_radio_modem_active=0;esp_radio_modem_phase=0;esp_radio_modem_step=0;esp32_irq_restore(esp_radio_modem_ps);return 0;
}
