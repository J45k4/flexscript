import "gpio-pads.flex";
// GPIO/RTC pad ownership around independently compiled numeric SDK tables.
// State: held/live pad caches220000 (49*64), scratch drives224000,
// peripheral output signals226000 (256*16), descriptors236000.
// Digital peripheral producers publish real signal/OE changes through
// se_gpio_peripheral; dedicated peripheral IO_MUX routes remain separate work.
fn se_gpio_rtc_base(s){if se_chip(s){return 0x60008400;}return 0x3ff48400;}
fn se_gpio_rtc_shift(s){if se_chip(s){return 10;}return 14;}
fn se_gpio_force_address(s){if se_chip(s){return 0x600080d8;}return 0x3ff480c8;}
fn se_gpio_digital_hold_address(s){if se_chip(s){return 0x600080dc;}return 0x3ff48474;}
fn se_gpio_function(s){if se_chip(s){return 1;}return 2;}
fn se_gpio_register_pins(s){if se_chip(s){return 54;}return 40;}
fn se_gpio_bank_mask(s,high){if !high{return 0xffffffff;}if se_chip(s){return 0x3fffff;}return 255;}
fn se_valid_pin(s,pin){return (se_gpio_desc(s,pin,1)&1)!=0;}
fn se_gpio_mux_offset(s,pin){let base=0x3ff49000;if se_chip(s){base=0x60009000;}return se_gpio_desc(s,pin,0)-base;}
fn se_gpio_hold(s,pin){let address=se_gpio_desc(s,pin,3);if address && (se_raw(s,address,0,0)&se_gpio_desc(s,pin,9)){return 1;}if se_raw(s,se_gpio_force_address(s),0,0)&se_gpio_desc(s,pin,10){return 1;}return (se_raw(s,se_gpio_digital_hold_address(s),0,0)&se_gpio_desc(s,pin,11))!=0;}
fn se_gpio_pad(s,pin){let p=s+220000+pin*64;let held=se_gpio_hold(s,pin);if !held || !load64(p){let channel=se_gpio_desc(s,pin,2)-1;let rtc=0;let pad=0;if channel>=0{pad=se_raw(s,se_gpio_desc(s,pin,3),0,0);rtc=(pad&se_gpio_desc(s,pin,4))!=0;}let mux=load64(s+7168+pin*8);let pull=0;let ie=0;let drive= -1;
 if channel>=0 && (!se_chip(s) || rtc){if pad&se_gpio_desc(s,pin,7){pull=pull|2;}if pad&se_gpio_desc(s,pin,8){pull=pull|1;}}else{pull=(mux>>7)&3;}
 if rtc{if ((pad>>se_gpio_desc(s,pin,5))&3)==0{if pad&se_gpio_desc(s,pin,6){ie=2;}let bit=1<<(channel+se_gpio_rtc_shift(s));if (load64(s+328)&bit) && (se_gpio_desc(s,pin,1)&2){let value=(load64(s+320)&bit)!=0;let open=se_raw(s,se_gpio_rtc_base(s)+0x28+channel*4,0,0)&4;if !open || !value{drive=value;}}}}
 else{if mux&512{ie=1;}if ((mux>>12)&7)==se_gpio_function(s) && (se_gpio_desc(s,pin,1)&2){let matrix=load64(s+6656+pin*8);let signal=matrix&511;let enable=(load64(s+144)>>pin)&1;let value=(load64(s+136)>>pin)&1;if signal<256{value=load64(s+226000+signal*16);if !(matrix&(1<<10)){enable=load64(s+226008+signal*16);}}if matrix&(1<<11){enable=!enable;}value=value^((matrix>>9)&1);if enable && (!(load64(s+4096+pin*8)&4) || !value){drive=value;}}}
 store64(p+8,drive);store64(p+16,pull);store64(p+24,ie);store64(p+32,channel+1);}
 store64(p,held);return p;}
fn se_gpio_driver(s,pin){let p=se_gpio_pad(s,pin);let drive=load64(p+8);let external=load64(s+7680+pin*8);if drive>=0 && external>=0 && drive!=external{return -2;}if drive>=0{return drive;}return external;}
fn se_gpio_cpu_status(s,core,nmi){let shift=15;if se_chip(s){shift=13;}else if core{shift=13;}shift=shift+nmi;let enabled=0;let pin=0;while pin<se_gpio_register_pins(s){if load64(s+4096+pin*8)&(1<<shift){enabled=enabled|(1<<pin);}pin=pin+1;}return load64(s+152)&enabled;}
fn se_gpio_update(s){
 // Resolve every pin before committing either input samples or edge latches.
 let pin=0;while pin<49{if se_valid_pin(s,pin){let drive=se_gpio_driver(s,pin);if drive== -2{return -5;}store64(s+224000+pin*8,drive);}pin=pin+1;}
 let physical=0;let input=0;let rtc_input=0;pin=0;while pin<49{if se_valid_pin(s,pin){let value=load64(s+224000+pin*8);let p=s+220000+pin*64;let pull=load64(p+16);let wire=load64(s+8192+pin*8);if wire>=0{let other=load64(s+224000+wire*8);if value>=0 && other>=0 && value!=other{return -5;}if value<0{value=other;}pull=pull|load64(s+220016+wire*64);}if value<0{value=(pull&2)!=0;}if value{physical=physical|(1<<pin);if load64(p+24)&1{input=input|(1<<pin);}if load64(p+24)&2{rtc_input=rtc_input|(1<<(load64(p+32)-1+se_gpio_rtc_shift(s)));}}}pin=pin+1;}
 let before=load64(s+120);let pending=load64(s+152);pin=0;while pin<49{if se_valid_pin(s,pin){let event=(load64(s+4096+pin*8)>>7)&7;let old=(before>>pin)&1;let bit=(input>>pin)&1;if (event==1 && !old && bit) || (event==2 && old && !bit) || (event==3 && old!=bit) || (event==4 && !bit) || (event==5 && bit){pending=pending|(1<<pin);}}pin=pin+1;}store64(s+120,input);store64(s+152,pending);store64(s+336,rtc_input);store64(s+344,physical);let rmt=se_rmt_inputs(s);if rmt{return rmt;}let i2c=se_i2c_inputs(s);if i2c{return i2c;}let audio=se_i2s_inputs(s);if audio{return audio;}se_irqs(s);return 0;
}
fn se_gpio_drive(s,pin,value){if !se_valid_pin(s,pin) || value< -1 || value>1{return -22;}let old=load64(s+7680+pin*8);store64(s+7680+pin*8,value);let result=se_gpio_update(s);if result{store64(s+7680+pin*8,old);se_gpio_update(s);}return result;}
fn se_gpio_wire(s,a,b){if !se_valid_pin(s,a) || !se_valid_pin(s,b) || a==b || load64(s+8192+a*8)>=0 || load64(s+8192+b*8)>=0{return -22;}store64(s+8192+a*8,b);store64(s+8192+b*8,a);let result=se_gpio_update(s);if result{store64(s+8192+a*8,-1);store64(s+8192+b*8,-1);se_gpio_update(s);}return result;}
fn se_gpio_unwire(s,pin){if !se_valid_pin(s,pin){return -22;}let other=load64(s+8192+pin*8);if other<0{return 0;}store64(s+8192+pin*8,-1);store64(s+8192+other*8,-1);return se_gpio_update(s);}
fn se_gpio_level(s,pin){if !se_valid_pin(s,pin){return -22;}return (load64(s+344)>>pin)&1;}
fn se_gpio_signal(s,signal){if signal<0 || signal>255{return -22;}let config=load64(s+4608+signal*8);if !(config&128){return -95;}let pin=config&63;let value=0;if pin==56{value=1;}else{let zero=48;if se_chip(s){zero=60;}if pin!=zero{if !se_valid_pin(s,pin){return -95;}value=(load64(s+120)>>pin)&1;}}return value^((config>>6)&1);}
fn se_gpio_peripheral(s,signal,value,enable){if signal<0 || signal>255 || value<0 || value>1 || enable<0 || enable>1{return -22;}let p=s+226000+signal*16;let old=load64(p);let oe=load64(p+8);store64(p,value);store64(p+8,enable);let result=se_gpio_update(s);if result{store64(p,old);store64(p+8,oe);se_gpio_update(s);}return result;}
fn se_gpio_status_read(s,address){let base=se_gpio_base(s);let low=0x68;let high=0x7c;if se_chip(s){low=0x5c;high=0x68;}let cpu=0;let nmi=0;let shift=0;let known=0;if address==base+low{known=1;}if address==base+high{known=1;shift=32;}if address==base+low+4{known=1;nmi=1;}if address==base+high+4{known=1;nmi=1;shift=32;}if !se_chip(s){if address==base+0x60{known=1;cpu=1;}if address==base+0x64{known=1;cpu=1;nmi=1;}if address==base+0x74{known=1;cpu=1;shift=32;}if address==base+0x78{known=1;cpu=1;nmi=1;shift=32;}}if !known{return -95;}return (se_gpio_cpu_status(s,cpu,nmi)>>shift)&0xffffffff;}
fn se_gpio_rtc_bus(s,address,writing,value){let base=se_gpio_rtc_base(s);let mask=0xffffc000;if se_chip(s){mask=0xfffffc00;}if address>=base && address<=base+0x14{let offset=address-base;let p=s+320;if offset>=12{p=s+328;offset=offset-12;}if writing{let bits=value&mask;let old=load64(p);if !offset{store64(p,bits);}else if offset==4{store64(p,old|bits);}else{store64(p,old&~bits);}let result=se_gpio_update(s);if result{return result;}}if offset{return 0;}return load64(p);}
 if address==base+0x24{if writing{return -13;}return load64(s+336);}
 let count=18;if se_chip(s){count=22;}if address>=base+0x28 && address<base+0x28+count*4{let result=se_raw(s,address,writing,value);if writing{let error=se_gpio_update(s);if error{return error;}}return result;}
 let known=address==se_gpio_force_address(s) || address==se_gpio_digital_hold_address(s);let pin=0;while pin<49 && !known{if se_valid_pin(s,pin) && address==se_gpio_desc(s,pin,3){known=1;}pin=pin+1;}if known{let result=se_raw(s,address,writing,value);if writing{let error=se_gpio_update(s);if error{return error;}}return result;}return -95;
}
