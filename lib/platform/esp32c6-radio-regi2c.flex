import "esp32-analog-state.flex";
// C6 CPU0 internal analog-I2C: pinned esp-hal 0f0ebd92 / esp-pacs 33d9b66.
// This prerequisite does not initialize the PMU or enable the radio domain.
// data=-1 reads a field; otherwise write the bounded field value. No automatic
// retry: a completion timeout can mean the analog write has already happened.
global esp_radio_regi2c_fault=0;
// Latched for the current/last claimed transaction; busy rejections retain it.
global esp_radio_regi2c_write_issued=0;
global esp_radio_regi2c_clock=0;
global esp_radio_regi2c_source=0;
global esp_radio_regi2c_select=0;
fn esp_radio_c6_regi2c_guard(){
 if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}
 if (esp_radio_pmu_active && !esp_radio_pmu_internal) || esp_radio_owner!=1 || esp_adc_busy || esp_radio_phy_refs || esp_radio_phy_clock_refs || esp32_load32(esp32_state()+16){return -16;}return 0;
}
fn esp_radio_c6_regi2c_block(block){
 if block==0x6a{return 6;}if block==0x66{return 7;}if block==0x61{return 8;}if block==0x69{return 9;}if block==0x6d{return 10;}return -1;
}
fn esp_radio_c6_regi2c_wait(control,start,cycles){
 while esp32_load32(control)&0x2000000{if ((esp32_cycles()-start)&4294967295)>=cycles{return -110;}}return 0;
}
fn esp_radio_c6_regi2c_restore(){
 esp_reg_update(0x600af81c,0xffffff,esp_radio_regi2c_select);
 esp_reg_update(0x600af010,1,esp_radio_regi2c_source);
 esp_reg_update(0x600af018,4,esp_radio_regi2c_clock);
 esp_radio_regi2c_active=0;esp_radio_regi2c_fault=0;return 0;
}
// Inspect both engines using their current source. Enabling the register
// clock is reversible; changing a busy engine's source is not permitted.
fn esp_radio_c6_regi2c_idle(){
 let ps=esp32_irq_save();let result=esp_radio_c6_regi2c_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_regi2c_active{esp32_irq_restore(ps);return -16;}
 let clock=esp32_load32(0x600af018)&4;esp_reg_update(0x600af018,4,4);
 let busy=(esp32_load32(0x600af800)|esp32_load32(0x600af804))&0x2000000;
 esp_reg_update(0x600af018,4,clock);esp32_irq_restore(ps);if busy{return -16;}return 0;
}
fn esp_radio_c6_regi2c(block,reg,msb,lsb,data,cycles){
 let bit=esp_radio_c6_regi2c_block(block);
 if bit<0 || reg<0 || reg>255 || lsb<0 || msb<lsb || msb>7 || data< -1 || cycles<1 || cycles>2147483647{return -22;}
 let mask=(1<<(msb-lsb+1))-1;if data>mask{return -22;}
 let ps=esp32_irq_save();let result=esp_radio_c6_regi2c_guard();if result{esp32_irq_restore(ps);return result;}
 if esp_radio_regi2c_active{let error= -16;if esp_radio_regi2c_fault{error= -5;}esp32_irq_restore(ps);return error;}
 esp_radio_regi2c_clock=esp32_load32(0x600af018)&4;esp_radio_regi2c_source=esp32_load32(0x600af010)&1;
 esp_reg_update(0x600af018,4,4);
 // ANA_CONF1 selects slaves for both masters. Neither may be in flight.
 if (esp32_load32(0x600af800)|esp32_load32(0x600af804))&0x2000000{esp_reg_update(0x600af018,4,esp_radio_regi2c_clock);esp32_irq_restore(ps);return -16;}
 esp_radio_regi2c_write_issued=0;
 esp_reg_update(0x600af010,1,1);
 esp_radio_regi2c_select=esp32_load32(0x600af81c)&0xffffff;esp_radio_regi2c_active=1;let control=0x600af804;if esp32_load32(0x600af820)&(1<<(bit+2)){control=0x600af800;}
 esp_reg_update(0x600af81c,0xffffff,0xffffff&~(1<<bit));let start=esp32_cycles();let value=0;
 if data<0 || mask!=255{
  esp32_store32(control,block|(reg<<8));result=esp_radio_c6_regi2c_wait(control,start,cycles);
  if !result{value=(esp32_load32(control)>>16)&255;}
 }
 if !result && data>=0{value=(value&~(mask<<lsb))|(data<<lsb);esp_radio_regi2c_write_issued=1;esp32_store32(control,block|(reg<<8)|(value<<16)|0x1000000);result=esp_radio_c6_regi2c_wait(control,start,cycles);}
 if result{esp_radio_regi2c_fault=1;esp32_irq_restore(ps);return result;}
 esp_radio_c6_regi2c_restore();esp32_irq_restore(ps);if data<0{return (value>>lsb)&mask;}return 0;
}
// Wait for both engines without resetting a possibly committed transfer. A
// successful recovery releases the lease; callers must read back uncertain data.
fn esp_radio_c6_regi2c_recover(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_regi2c_guard();if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_regi2c_active{esp32_irq_restore(ps);return 0;}if !esp_radio_regi2c_fault{esp32_irq_restore(ps);return -16;}
 let start=esp32_cycles();result=esp_radio_c6_regi2c_wait(0x600af800,start,cycles);if !result{result=esp_radio_c6_regi2c_wait(0x600af804,start,cycles);}if !result{esp_radio_c6_regi2c_restore();}esp32_irq_restore(ps);return result;
}
