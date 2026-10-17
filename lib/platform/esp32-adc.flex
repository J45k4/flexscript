import "esp32-common.flex";
import "esp32-analog-state.flex";
// Original ESP32 RTC one-shot ADC: raw12-bit counts, attenuation codes0..3.
// One serialized, IRQ-masked conversion; shared SAR/AMP/hall/DAC-sync fields
// are restored on every exit. ADC2 never takes control from an active PHY.
global ea_channels=0;
global ea_saved=0;
global ea_saved_count=0;
fn ea_index(unit,channel){if unit<1 || unit>2 || channel<0 || (unit==1 && channel>7) || channel>9{return -1;}return (unit-1)*8+channel;}
fn esp_adc_pin(unit,channel){let i=ea_index(unit,channel);if i<0{return -22;}return esp_gpio_hex("24252627202122230400020f0d0c0e1b191a",i*2);}
fn ea_rtc(pin){if pin>=36{return pin-36;}if pin>=34{return pin-30;}if pin==32{return 9;}if pin==33{return 8;}if pin==25{return 6;}if pin==26{return 7;}if pin==4{return 10;}if pin==0{return 11;}if pin==2{return 12;}if pin==15{return 13;}if pin==13{return 14;}if pin==12{return 15;}if pin==14{return 16;}return 17;}
fn ea_function_shift(pin){if pin>=36{return 22-(pin-36)*5;}if pin>=34{return 26-(pin-34)*5;}if pin==32{return 9;}if pin==33 || pin==25 || pin==26{return 15;}return 17;}
fn ea_hold_mask(pin){if pin>=36{return 1<<(31-(pin-36));}if pin>=34{return 1<<(31-(pin-34));}if pin==32{return 1<<24;}if pin==33 || pin==25 || pin==26{return 1<<29;}return 1<<31;}
fn ea_force_hold(pin){if pin>=36{return 1<<(4+pin-36);}if pin>=34{return 1<<(pin-34);}if pin==25{return 1<<2;}if pin==26{return 1<<3;}if pin==32{return 1<<16;}if pin==33{return 1<<17;}let rt=ea_rtc(pin);return 1<<(rt-2);}
fn ea_pad_init(pin){
 let descriptor=esp_gpio_rtc_descriptor(pin);let address=0x3ff48400+(descriptor&255);let mux=1<<(descriptor>>8);let shift=ea_function_shift(pin);let ie=1<<(shift-3);if pin<34{ie=1<<(shift-4);}let pull=0;if pin<34{pull=3<<27;if pin==32{pull=3<<22;}}
 if (esp32_load32(address)&ea_hold_mask(pin)) || (esp32_load32(0x3ff480c8)&ea_force_hold(pin)){return -16;}if (pin==32 || pin==33) && (esp32_load32(0x3ff4848c)&(1<<19)){return -16;}
 let disable=0x3ff44028;if pin>=32{disable=0x3ff44034;}esp32_store32(disable,1<<(pin&31));esp32_store32(0x3ff48414,1<<(ea_rtc(pin)+14));esp_reg_update(esp_gpio_mux_address(pin),1<<9,0);
 let mask=mux|(3<<shift)|ie|(1<<(shift-1))|pull;let value=mux;if pin==25 || pin==26{mask=mask|(1<<18)|(1<<10);value=value|(1<<10);}esp_reg_update(address,mask,value);return 0;
}
fn esp_adc_init(unit,channel,attenuation){
 let index=ea_index(unit,channel);if index<0 || attenuation<0 || attenuation>3{return -22;}let ps=esp32_irq_save();if esp_adc_busy || (unit==2 && (esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs)){esp32_irq_restore(ps);return -16;}
 if !ea_channels{let p=alloc(288);if p<=0{esp32_irq_restore(ps);return -12;}let i=0;while i<288{store8(p+i,0);i=i+1;}ea_channels=p;}
 if !ea_saved{let p=alloc(384);if p<=0{esp32_irq_restore(ps);return -12;}ea_saved=p;}
 let error=ea_pad_init(esp_adc_pin(unit,channel));if error{esp32_irq_restore(ps);return error;}store64(ea_channels+index*16,1);store64(ea_channels+index*16+8,attenuation);esp32_irq_restore(ps);return 0;
}
fn ea_patch(address,mask,value){let p=ea_saved+ea_saved_count*24;let old=esp32_load32(address);if address==0x3ff48854 || address==0x3ff48894{old=old&~(1<<17);}store64(p,address);store64(p+8,mask);store64(p+16,old);ea_saved_count=ea_saved_count+1;esp_reg_update(address,mask,value);return 0;}
fn ea_restore(){while ea_saved_count{ea_saved_count=ea_saved_count-1;let p=ea_saved+ea_saved_count*24;esp_reg_update(load64(p),load64(p+8),load64(p+16));}return 0;}
fn ea_expired(start,cycles){return ((esp32_cycles()-start)&4294967295)>=cycles;}
fn esp_adc_read(unit,channel,cycles){
 let index=ea_index(unit,channel);if index<0 || cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();if !ea_channels || !load64(ea_channels+index*16){esp32_irq_restore(ps);return -19;}if esp_adc_busy || (unit==2 && (esp_radio_owner || esp_radio_phy_refs || esp_radio_phy_clock_refs)){esp32_irq_restore(ps);return -16;}
 let read=0x3ff48800;let base=0x3ff48854;let inv=1<<28;let dig=1<<27;let width=3;let stop=1<<23;if unit==2{read=0x3ff48890;base=0x3ff48894;inv=1<<29;dig=3<<27;width=12;stop=1<<22;}
 let busy=dig;if unit==2{busy=1<<28;}if esp32_load32(read)&busy{esp32_irq_restore(ps);return -16;}esp_adc_busy=unit;ea_saved_count=0;let start=esp32_cycles();
 ea_patch(0x3ff4880c,0xffff|(15<<16),1|(2<<16)|(3<<18));ea_patch(0x3ff48808,0xffffffff,65537);ea_patch(0x3ff48810,0xfff0,0);ea_patch(0x3ff48478,1<<31,0);
 let sf_mask=width|stop;let sf_value=width;if unit==2{sf_mask=sf_mask|(7<<5);sf_value=sf_value|(4<<5);}ea_patch(0x3ff4882c,sf_mask,sf_value);
 ea_patch(read,255|(3<<16)|dig|inv,1|(3<<16)|inv);ea_patch(0x3ff48834+(unit-1)*4,3<<(channel*2),load64(ea_channels+index*16+8)<<(channel*2));
 if unit==1{ea_patch(0x3ff48858,3<<26,3<<26);ea_patch(0x3ff488a0,15,0);}else{ea_patch(0x3ff66010,4,4);}
 ea_patch(base,(1<<17)|(1<<18)|(4095<<19)|(1<<31),(1<<18)|(1<<31)|(1<<(channel+19)));
 let error=0;if unit==1{while !error && (esp32_load32(0x3ff4883c)&(255<<22)){if ea_expired(start,cycles){error= -110;}}}
 if !error && ea_expired(start,cycles){error= -110;}if !error{esp_reg_update(base,1<<17,0);esp_reg_update(base,1<<17,1<<17);while !error && !(esp32_load32(base)&(1<<16)){if ea_expired(start,cycles){error= -110;}}}
 let result=error;if !error{result=esp32_load32(base)&4095;}if error{esp_reg_update(0x3ff4882c,stop,stop);}esp_reg_update(base,(1<<17)|(4095<<19),0);ea_restore();esp_adc_busy=0;esp32_irq_restore(ps);return result;
}
fn esp_adc_deinit(unit,channel){let index=ea_index(unit,channel);if index<0{return -22;}let ps=esp32_irq_save();if esp_adc_busy{esp32_irq_restore(ps);return -16;}if !ea_channels || !load64(ea_channels+index*16){esp32_irq_restore(ps);return 0;}esp_gpio_input(esp_adc_pin(unit,channel),0);store64(ea_channels+index*16,0);esp32_irq_restore(ps);return 0;}
