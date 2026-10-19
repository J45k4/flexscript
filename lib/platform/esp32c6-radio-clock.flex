import "esp32c6-radio-pmu-stage.flex";
// CPU-side clock ownership for the enclosing C6 PMU transaction. IRQs stay
// masked from a successful begin (or a partial-write failure) until restore.
// PLL power and peripheral clock configuration are preserved. MSPI follows
// the root clock; DMA and flash command/FSM owners must therefore be idle.
global esp_radio_cpu_clock_phase=0;
global esp_radio_cpu_clock_ps=0;
global esp_radio_cpu_clock_root=0;
global esp_radio_cpu_clock_cpu=0;
global esp_radio_cpu_clock_ahb=0;
global esp_radio_cpu_clock_apb=0;
global esp_radio_cpu_clock_ticks=0;
fn esp_radio_c6_clock_decode(root,cpu,ahb,apb,query,which){
 if which<0 || which>2{return -22;}
 if ((root>>24)&127)!=40 || (root&65535)!=512{return -95;}
 let source=(root>>16)&3;let cdiv=(cpu&255)+1;let adiv=(ahb&255)+1;let hz=40000000;
 if source==1{
  if ((query>>8)&1023)!=480{return -95;}hz=160000000;cdiv=((cpu>>8)&255)+1;adiv=((ahb>>8)&255)+1;
  if cdiv!=1 && cdiv!=2 && cdiv!=4{return -95;}if adiv!=4 && adiv!=8 && adiv!=16{return -95;}
  if cdiv==1 && (cpu&65536){cdiv=4;hz=480000000;}
 }else{
  if source==2{if (query&255)!=20{return -95;}hz=20000000;}else if source!=0{return -95;}
  if (cdiv&(cdiv-1)) || (adiv&(adiv-1)){return -95;}
 }
 let cpu_hz=hz/cdiv;let ahb_hz=hz/adiv;
 if source==1 && cdiv==4 && (cpu&65536) && ((cpu>>8)&255)==0{ahb_hz=160000000/adiv;}
 let pdiv=((apb>>8)&255)+1;let decrease=apb&255;
 if (pdiv!=1 && pdiv!=2 && pdiv!=4) || (decrease!=0 && decrease!=1 && decrease!=3){return -95;}
 if ahb_hz>cpu_hz || ahb_hz/pdiv>80000000{return -95;}
 if !which{return cpu_hz;}if which==1{return ahb_hz;}return ahb_hz/pdiv;
}
fn esp_radio_c6_clock_frequency(which){
 if !esp_riscv_ready() || rv_hal_chip!=13{return -95;}let ps=esp32_irq_save();
 let result=esp_radio_c6_clock_decode(esp32_load32(0x60096110),esp32_load32(0x60096118),esp32_load32(0x6009611c),esp32_load32(0x60096120),esp32_load32(0x60096124),which);
 esp32_irq_restore(ps);return result;
}
fn esp_radio_c6_clock_write(address,mask,value,cycles){
 if (esp32_load32(address)&mask)!=(value&mask){esp_reg_update(address,mask,value);}
 return esp_wait_mask(address,mask,value&mask,cycles);
}
fn esp_radio_c6_clock_idle(){
 // No DMA master may start an independent flash access during the handoff.
 let dma=esp32_load32(0x600960bc);let regdma=esp32_load32(0x600960f4);
 if ((dma&3)==1) || ((regdma&3)==1){return -16;}
 // SPI0 cache FSM and SPI1 explicit command engine must both be idle.
 if (esp32_load32(0x60002000)|esp32_load32(0x60003000))&0xfffe00ff{return -16;}
 return 0;
}
fn esp_radio_c6_clock_begin(cycles){
 return esp32_call64(esp32_iram_callback32(esp_radio_c6_clock_begin_iram),cycles,0,0,0,0,0,0,0);
}
fn esp_radio_c6_clock_begin_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();
 if result{esp32_irq_restore(ps);return result;}
 if !esp_radio_pmu_active || esp_radio_pmu_phase!=1 || esp_radio_pmu_analog_count!=3 || esp_radio_pmu_digital_count!=49 || esp_radio_regi2c_active || esp_radio_ocode_active || esp_radio_cpu_clock_active{esp32_irq_restore(ps);return -16;}
 result=esp_radio_c6_clock_idle();if result{esp32_irq_restore(ps);return result;}
 let root=esp32_load32(0x60096110);let cpu=esp32_load32(0x60096118);let ahb=esp32_load32(0x6009611c);let apb=esp32_load32(0x60096120);let query=esp32_load32(0x60096124);
 result=esp_radio_c6_clock_decode(root,cpu,ahb,apb,query,0);if result<0{esp32_irq_restore(ps);return result;}
 let ticks=esp32_call32(0x40000044,0,0,0,0,0,0,0,0);if ticks<1 || ticks>480{esp32_irq_restore(ps);return -95;}
 esp_radio_cpu_clock_root=root;esp_radio_cpu_clock_cpu=cpu;esp_radio_cpu_clock_ahb=ahb;esp_radio_cpu_clock_apb=apb;esp_radio_cpu_clock_ticks=ticks;esp_radio_cpu_clock_ps=ps;
 esp_radio_cpu_clock_active=1;esp_radio_cpu_clock_phase=1;
 // Raise the low-speed CPU rate before AHB. These fields are inactive if
 // PLL is the original source; then select XTAL only after both are ready.
 result=esp_radio_c6_clock_write(0x60096118,255,0,cycles);if result{return result;}
 result=esp_radio_c6_clock_write(0x6009611c,255,0,cycles);if result{return result;}
 result=esp_radio_c6_clock_write(0x60096110,0x30000,0,cycles);if result{return result;}
 esp32_call32(0x40000048,40,0,0,0,0,0,0,0);if esp32_call32(0x40000044,0,0,0,0,0,0,0,0)!=40{return -5;}
 esp_radio_cpu_clock_phase=2;return 0;
}
fn esp_radio_c6_clock_restore(cycles){
 return esp32_call64(esp32_iram_callback32(esp_radio_c6_clock_restore_iram),cycles,0,0,0,0,0,0,0);
}
fn esp_radio_c6_clock_restore_iram(cycles,b,c,d,e,f,g,h){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();let result=esp_radio_c6_pmu_stage_guard();
 if result{if !esp_radio_cpu_clock_active{esp32_irq_restore(ps);}return result;}
 if !esp_radio_cpu_clock_active{esp32_irq_restore(ps);return 0;}
 if !esp_radio_pmu_active || esp_radio_regi2c_active || esp_radio_ocode_active || esp_radio_pll_active{return -16;}
 result=esp_radio_c6_clock_idle();if result{return result;}
 let root=esp32_load32(0x60096110);let cpu=esp32_load32(0x60096118);let ahb=esp32_load32(0x6009611c);let apb=esp32_load32(0x60096120);let source=root&0x30000;let old_source=esp_radio_cpu_clock_root&0x30000;
 if ((root^esp_radio_cpu_clock_root)&~0x30000) || (source && source!=old_source) || ((cpu^esp_radio_cpu_clock_cpu)&0x1ff00) || ((ahb^esp_radio_cpu_clock_ahb)&0xff00) || ((apb^esp_radio_cpu_clock_apb)&65535){return -16;}
 if ((cpu&255) && (cpu&255)!=(esp_radio_cpu_clock_cpu&255)) || ((ahb&255) && (ahb&255)!=(esp_radio_cpu_clock_ahb&255)){return -16;}
 esp_radio_cpu_clock_phase=3;
 // A later PLL-off calibration consumer must restore and calibrate PLL
 // before this handoff can select it. Refuse unstable/off PLL explicitly.
 if old_source==0x10000{result=esp_wait_mask(0x600b0194,0x42000001,0x42000001,cycles);if result{return result;}}
 result=esp_radio_c6_clock_write(0x60096110,0x30000,old_source,cycles);if result{return result;}
 // Once the old source is back, lower AHB before lowering the CPU. For a
 // restored PLL source these low-speed fields are inactive again.
 result=esp_radio_c6_clock_write(0x6009611c,255,esp_radio_cpu_clock_ahb,cycles);if result{return result;}
 result=esp_radio_c6_clock_write(0x60096118,255,esp_radio_cpu_clock_cpu,cycles);if result{return result;}
 esp32_call32(0x40000048,esp_radio_cpu_clock_ticks,0,0,0,0,0,0,0);if esp32_call32(0x40000044,0,0,0,0,0,0,0,0)!=esp_radio_cpu_clock_ticks{return -5;}
 esp_radio_cpu_clock_phase=0;esp_radio_cpu_clock_active=0;esp32_irq_restore(esp_radio_cpu_clock_ps);return 0;
}
