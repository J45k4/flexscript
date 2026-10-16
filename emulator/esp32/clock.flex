// Original ESP32 clock tree and internal analog-I2C controller. No compiler
// encoders or platform drivers are imported. Clock state occupies303104..307199.
// Device timestamps remain80MHz reference ticks. CPU retirement is converted
// through480MHz quanta, preserving40/80/160/240MHz fractional phase.
// Only independently specified40MHz-XTAL SDK PLL configurations are supported.
// Analog busy latency is configurable functional scheduling, not silicon timing.
fn se_clock(s){return s+303104;}
fn se_clock_qpc(s){if se_chip(s){return 6;}let n=load64(se_clock(s)+8);if !n{return 6;}return n;}
fn se_apb_factor(s){if se_chip(s){return 1;}let n=load64(se_clock(s)+16);if !n{return 1;}return n;}
fn se_cpu_hz(s){return 480000000/se_clock_qpc(s);}
fn se_apb_hz(s){return 80000000/se_apb_factor(s);}
fn se_bbpll_byte(s,index){return load8(se_clock(s)+1024+index);}
fn se_clock_pll(s){if se_chip(s){return 0;}if se_raw(s,0x3ff48000,0,0)&0x40540{return 0;}
 if se_bbpll_byte(s,0)!=0x18 || se_bbpll_byte(s,1)!=0x20 || se_bbpll_byte(s,2)!=0 || se_bbpll_byte(s,4)!=0x9a || se_bbpll_byte(s,5)!=0xc6 || se_bbpll_byte(s,10)!=0 || se_bbpll_byte(s,12)!=0{return 0;}
 if se_bbpll_byte(s,3)==32 && se_bbpll_byte(s,9)==0x84 && se_bbpll_byte(s,11)==0x43{return 320;}
 if se_bbpll_byte(s,3)==28 && se_bbpll_byte(s,9)==0x74 && se_bbpll_byte(s,11)==0xc3{return 480;}return 0;
}
fn se_clock_audio(s){return !se_chip(s) && load64(se_clock(s)+144);}
fn se_clock_busy(s){if se_flash_pending(s){return 1;}let i=0;while i<4{if load64(se_timer(s,i))&(1<<31){return 1;}i=i+1;}i=0;while i<3{let u=se_uart(s,i);if (load64(u) || load64(u+56)) && (load64(u+72)&(1<<27)){return 1;}i=i+1;}if load64(se_spi(s,2)) || load64(se_spi(s,3)) || load64(s+265472) || load64(s+265480) || load64(se_i2c(s,0)) || load64(se_i2c(s,1)) || se_i2s_active(s){return 1;}return 0;}
fn se_clock_apply(s){let p=se_clock(s);let source=(se_raw(s,0x3ff48070,0,0)>>27)&3;let period=se_raw(s,0x3ff0003c,0,0)&3;if source>1 || period>2{return -95;}let pll=se_clock_pll(s);let factor=2*((se_raw(s,0x3ff66000,0,0)&1023)+1);let qpc=factor*6;
 if source{if (period<2 && pll!=320) || (period==2 && pll!=480){return -95;}factor=1;qpc=6/(period+1);}
 if (qpc!=load64(p+8) && load64(p+32)) || ((factor!=load64(p+16) || pll!=load64(p+40)) && se_clock_busy(s)){return -16;}store64(p+8,qpc);store64(p+16,factor);store64(p+40,pll);store64(p+144,pll==320 && source==1);return 0;
}
fn se_clock_profile(s,download){if !s || se_chip(s) || download<0 || download>1 || load64(s+16) || load64(se_clock(s)+24) || load64(se_clock(s)+32) || load64(se_clock(s)+152) || se_clock_busy(s){return -22;}let p=se_clock(s);em_zero(p,4096);store64(p,1);store64(p+48,1);se_raw(s,0x3ff48000,1,0x1c492000);se_raw(s,0x3ff48070,1,0x08003210);se_raw(s,0x3ff0003c,1,0);se_raw(s,0x3ff66000,1,0);if download{se_raw(s,0x3ff48070,1,0x3210);store64(se_uart(s,0)+80,347|(3<<20));}else{store8(p+1024,0x18);store8(p+1025,0x20);store8(p+1027,32);store8(p+1028,0x9a);store8(p+1029,0xc6);store8(p+1033,0x84);store8(p+1035,0x43);}return se_clock_apply(s);}
fn se_clock_retired(s,delta){if delta<=0{return 0;}let p=se_clock(s);let units=delta*se_clock_qpc(s);if !se_chip(s){units=units+load64(p+24)-load64(p+32);store64(p+32,0);store64(p+24,units%6);}return units/6;}
fn se_clock_instruction_limit(s,ticks){let units=ticks*6;if !se_chip(s){units=units-load64(se_clock(s)+24)+load64(se_clock(s)+32);}let n=(units+se_clock_qpc(s)-1)/se_clock_qpc(s);if n<1{n=1;}return n;}
// p+152 counts completed idle CPU cycles. Unlike CCOUNT this monotonic
// functional time cannot be moved by guest WSR.CCOUNT. Retired instructions
// contribute one issue cycle each;the partial LX6 readiness profile adds
// measured special-register stalls through idle cycles. Full CPI/pipeline
// timing remains open.
fn se_cpu_cycles(s){return load64(load64(s)+176)+load64(se_clock(s)+152);}
fn se_clock_cycle_units(s,cycles){let units=cycles*se_clock_qpc(s);if !se_chip(s){units=units+load64(se_clock(s)+24)-load64(se_clock(s)+32);}return units;}
fn se_clock_cycle_ticks(s,cycles){let units=se_clock_cycle_units(s,cycles);return (units+5)/6;}
// Advance to an exact CPU-cycle boundary,including half/third reference ticks.
// Publish elapsed cycles before refreshing devices/IRQs,even when ticks==0.
fn se_clock_idle_cycles(s,cycles){if cycles<0 || cycles>0x100000000000000/se_clock_qpc(s){return -22;}if !cycles{return se_advance(s,0);}let cpu=load64(s);let cc=xt_sr(cpu,234);let p=se_clock(s);let units=se_clock_cycle_units(s,cycles);if !se_chip(s){store64(p+24,units%6);store64(p+32,0);}store64(p+152,load64(p+152)+cycles);let result=se_advance(s,units/6);xt_ccount_advance(cpu,cycles);return result;}
fn se_clock_idle(s,ticks){if ticks<0{return -22;}if !ticks{return se_advance(s,0);}let cpu=load64(s);let cc=xt_sr(cpu,234);let units=ticks*6;let p=se_clock(s);if !se_chip(s){units=units-load64(p+24)+load64(p+32);store64(p+24,0);store64(p+32,units%se_clock_qpc(s));}store64(p+152,load64(p+152)+units/se_clock_qpc(s));let result=se_advance(s,ticks);xt_ccount_advance(cpu,units/se_clock_qpc(s));return result;}
fn se_clock_analog_tick(s){if se_chip(s){return 0;}let p=se_clock(s);if !load64(p+64) || load64(p+72)>load64(s+16){return 0;}let word=load64(p+56);let index=(word>>8)&255;let at=p+1024+index;
 if word&(1<<24){let old=load8(at);store8(at,(word>>16)&255);let result=se_clock_apply(s);if result{store8(at,old);return result;}store64(p+96,load64(p+96)+1);}else{word=(word&~0xff0000)|(load8(at)<<16);store64(p+104,load64(p+104)+1);}store64(p+80,word);store64(p+64,0);store64(p+112,load64(s+16));return 0;
}
fn se_clock_deadline(s){if se_chip(s) || !load64(se_clock(s)+64){return -1;}let wait=load64(se_clock(s)+72)-load64(s+16);if wait<1{wait=1;}return wait;}
fn se_clock_address_known(address){return address==0x3ff48000 || address==0x3ff48070 || address==0x3ff4807c || address==0x3ff480b0 || address==0x3ff480b4 || address==0x3ff0003c || address==0x3ff66000 || address==0x3ff4e010 || address==0x6000e010;}
fn se_clock_bus(s,address,writing,value){let p=se_clock(s);if address==0x6000e010 || address==0x3ff4e010{if !writing{return load64(p+80)|(load64(p+64)<<25);}if load64(p+64){return -16;}if value&~0x1ffffff || (value&255)!=0x66 || ((value>>8)&255)>12{return -95;}if se_raw(s,0x3ff48000,0,0)&0x40540{return -5;}store64(p+56,value);store64(p+64,1);store64(p+72,load64(s+16)+load64(p+48));store64(p+80,value);store64(p+88,load64(p+88)+1);return 0;}
 if !writing{return se_raw(s,address,0,0);}let old=se_raw(s,address,0,0);se_raw(s,address,1,value);let result=se_clock_apply(s);if result{se_raw(s,address,1,old);return result;}store64(p+128,load64(p+128)+1);return 0;
}
