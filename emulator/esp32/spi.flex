// Independent master FIFO engine. No firmware-driver/compiler imports.
// Two8192-byte contexts at244000: metadata256, register bank1024,
// S3 applied configuration256, TX snapshot64, RX snapshot64, edge trace4096.
// Deadlines are half CPU ticks, keeping80MHz SPI edges on the80MHz CPU clock.
// Command/address/dummy and separate TX/RX phases precede completion.
// Slave, DMA, SIO and extra bus widths/delay modes remain explicit faults.
fn se_spi(s,bus){return s+244000+(bus-2)*8192;}
fn se_spi_base(s,bus){if se_chip(s){return 0x60024000+(bus-2)*4096;}return 0x3ff64000+(bus-2)*4096;}
fn se_spi_reg(s,bus,offset){return se_spi(s,bus)+256+offset;}
fn se_spi_get(s,bus,offset){return em_u32(se_spi_reg(s,bus,offset));}
fn se_spi_put(s,bus,offset,value){em_put32(se_spi_reg(s,bus,offset),value);return 0;}
fn se_spi_user(s){if se_chip(s){return 16;}return 28;}
fn se_spi_clock(s){if se_chip(s){return 12;}return 24;}
fn se_spi_misc(s){if se_chip(s){return 32;}return 52;}
fn se_spi_fifo(s){if se_chip(s){return 152;}return 128;}
fn se_spi_slave(s){if se_chip(s){return 224;}return 56;}
fn se_spi_usr(s){if se_chip(s){return 1<<24;}return 1<<18;}
fn se_spi_signal(s,bus,kind){if !se_chip(s){if bus==2{if kind==0{return 8;}if kind==1{return 10;}if kind==2{return 9;}if kind==3{return 11;}return 57+kind;}return 63+kind+(kind==1)-(kind==2)+2*(kind>=3);}
 if bus==2{if kind==0{return 101;}if kind==1{return 103;}if kind==2{return 102;}return 107+kind;}if kind==5{return 127;}if kind>=6{return -95;}if kind==0{return 66;}if kind==1{return 68;}if kind==2{return 67;}return 68+kind;}
fn se_spi_cfg(s,bus,offset){if se_chip(s){return em_u32(se_spi(s,bus)+1280+offset);}return se_spi_get(s,bus,offset);}
fn se_spi_running(s,bus){if !se_enabled(s,6+(bus-2)*10){return 0;}if se_chip(s){return (se_spi_get(s,bus,232)&3)==3;}return 1;}
fn se_spi_output(s,bus,kind,level,enable){let signal=se_spi_signal(s,bus,kind);if signal<0{if enable{return signal;}return 0;}return se_gpio_peripheral(s,signal,level,enable);}
fn se_spi_pins(s,bus,active){let p=se_spi(s,bus);let misc=se_spi_cfg(s,bus,se_spi_misc(s));let count=3;let polshift=6;if se_chip(s){count=6;polshift=7;}let i=0;while i<count{let enable=!(misc&(1<<i));let level=1;if active && enable{level=0;}level=level^((misc>>(polshift+i))&1);let result=se_spi_output(s,bus,3+i,level,enable);if result{return result;}i=i+1;}return 0;}
fn se_spi_idle(s,bus){let p=se_spi(s,bus);let misc=se_spi_cfg(s,bus,se_spi_misc(s));let idle=(misc>>29)&1;let result=se_spi_output(s,bus,0,idle,1);if result{return result;}let dout=0;if se_chip(s){dout=(se_spi_cfg(s,bus,8)>>19)&1;}result=se_spi_output(s,bus,1,dout,1);if result{return result;}return se_spi_pins(s,bus,0);}
fn se_spi_reset(s,bus){let p=se_spi(s,bus);em_zero(p,8192);let count=3;if se_chip(s){count=6;}let k=0;while k<count+3{if k!=2{se_spi_output(s,bus,k,0,0);}k=k+1;}
 // Reset values of the modeled configuration fields from the register headers.
 se_spi_put(s,bus,se_spi_clock(s),0x80003043);let misc_reset=(1<<count)-2;if !se_chip(s){misc_reset=misc_reset|24;}se_spi_put(s,bus,se_spi_misc(s),misc_reset);if se_chip(s){se_spi_put(s,bus,8,0x003c0000);se_spi_put(s,bus,16,0x800000c0);se_spi_put(s,bus,20,0xb8410007);se_spi_put(s,bus,24,0x78000000);se_spi_put(s,bus,232,0);se_spi_put(s,bus,224,0x02800000);}else{se_spi_put(s,bus,8,0x0020a400);se_spi_put(s,bus,12,0x5fff0000);se_spi_put(s,bus,240,0x800a0050);se_spi_put(s,bus,244,0x800f0000);se_spi_put(s,bus,20,0x11);se_spi_put(s,bus,28,0x80000040);se_spi_put(s,bus,32,0x5c000007);se_spi_put(s,bus,36,0x70000000);se_spi_put(s,bus,56,512);}return 0;}
fn se_spi_bit_index(bit,lsb){let shift=bit&7;if !lsb{shift=7-shift;}return (bit&~7)+shift;}
// Header136..232: command/address/dummy lengths and words, data/RX start,
// duplex, dummy-idle;208 completion delay,216 completion deadline,224 setup,
//232 CS hold duration;240 holds the final idle half-cycle.
// Words are latched at USR. Original CPHA1 edge placement follows RMT captures.
fn se_spi_rx_index(s,bus,bit){let p=se_spi(s,bus);let index=bit-load64(p+184);if index<0 || index>=load64(p+32){return -1;}return index;}
fn se_spi_dummy(s,bus,bit){let p=se_spi(s,bus);let start=load64(p+136)+load64(p+144);return bit>=start && bit<load64(p+176);}
fn se_spi_tx_bit(s,bus,bit){let p=se_spi(s,bus);let command=load64(p+136);let address=load64(p+144);let lsb=load64(p+80);
 if bit<command{return (load64(p+160)>>se_spi_bit_index(bit,lsb))&1;}let at=bit-command;
 if at<address{let index=63-at;if lsb{index=56-(at&~7)+(at&7);}return (load64(p+168)>>index)&1;}
 let data=bit-load64(p+176);if data<0 || data>=load64(p+24){return 0;}let index=se_spi_bit_index(data,lsb);return (load8(p+1536+index/8)>>(index&7))&1;}
fn se_spi_sample(s,bus,bit){let p=se_spi(s,bus);let data=se_spi_rx_index(s,bus,bit);if data<0{return 0;}let level=se_gpio_signal(s,se_spi_signal(s,bus,2));if level<0{return level;}let index=se_spi_bit_index(data,load64(p+88));let at=p+1600+index/8;let mask=1<<(index&7);store8(at,(load8(at)&~mask)|(level<<(index&7)));return 0;}
fn se_spi_start(s,bus){let p=se_spi(s,bus);let user=se_spi_cfg(s,bus,se_spi_user(s));let ctrl=se_spi_cfg(s,bus,8);let misc=se_spi_cfg(s,bus,se_spi_misc(s));if load64(p){return -16;}if !se_spi_running(s,bus){return -5;}
 let usermask=1|0xf0|(31<<24)|(7<<29);let ctrlmask=(3<<25)|0x0020a400;let mismask=0x600001df;let lenmask=0xffffff;if se_chip(s){lenmask=0x3ffff;}let txlen=0;let rxlen=0;let txlsb=(ctrl>>26)&1;let rxlsb=(ctrl>>25)&1;
 if se_chip(s){usermask=1|(1<<9)|0xc0|(31<<24)|(7<<29);ctrlmask=(1<<25)|(1<<23)|0x003c0000;mismask=0x60001fbf;txlsb=(ctrl>>25)&1;rxlsb=(ctrl>>23)&1;}
 if (user&~usermask) || (ctrl&~ctrlmask) || (misc&~mismask){return -95;}
 if !se_chip(s) && (se_spi_cfg(s,bus,20)&~255){return -95;}if se_chip(s) && se_spi_get(s,bus,48){return -95;}
 let slave=se_spi_get(s,bus,se_spi_slave(s));let smask=1<<30;if se_chip(s){smask=1<<26;}if slave&smask{return -95;}
 if user&(1<<27){let offset=40;if se_chip(s){offset=28;}txlen=(se_spi_cfg(s,bus,offset)&lenmask)+1;}
 if user&(1<<28){let offset=44;if se_chip(s){offset=28;}rxlen=(se_spi_cfg(s,bus,offset)&lenmask)+1;}
 let txcap=512;let rxcap=512;if user&(1<<25){txcap=256;}if user&(1<<24){rxcap=256;}if txlen>txcap || rxlen>rxcap{return -95;}
 let u1=se_spi_cfg(s,bus,se_spi_user(s)+4);let u2=se_spi_cfg(s,bus,se_spi_user(s)+8);let command=0;let address=0;let dummy=0;let addrshift=26;let addrmask=63;if se_chip(s){addrshift=27;addrmask=31;}
 if user&(1<<31){command=((u2>>28)&15)+1;}if user&(1<<30){address=((u1>>addrshift)&addrmask)+1;}if user&(1<<29){dummy=(u1&255)+1;}
 let half=!(user&1);if dummy && (!half || (txlen && rxlen)){return -95;}if (user&(1<<26)) && !half{return -95;}
 let setup=0;let hold=0;let setupbit=32;let holdbit=16;let timing=se_spi_cfg(s,bus,20);let st=timing&15;let ht=(timing>>4)&15;
 if se_chip(s){setupbit=128;holdbit=64;st=(u1>>17)&31;ht=(u1>>22)&31;}
 if user&setupbit{setup=st+1;}if user&holdbit{hold=ht;}
 // Original rev3 wire/event captures distinguish CS hold from engine DONE.
 // CTRL1 limits DONE, independent of USER.CS_HOLD; raw command low byte52
 // selects a one-period DONE delay even with the command phase disabled.
 let completion=hold;if !se_chip(s){completion=((se_spi_cfg(s,bus,12)>>28)&15)+1;if (u2&255)==0x52{completion=1;}if hold>completion{hold=completion;}}
if !half && setup && (command || address){return -95;}
 let prefix=command+address+dummy;let data=txlen;if half{data=txlen+rxlen;}else if rxlen>data{data=rxlen;}let bits=prefix+data;if !bits{return -22;}
 let clock=se_spi_cfg(s,bus,se_spi_clock(s));let factor=se_apb_factor(s);let premask=8191;if se_chip(s){premask=15;if !(se_spi_get(s,bus,232)&4){factor=2;}}
 let high=factor;let low=factor;if !(clock&(1<<31)){let pre=((clock>>18)&premask)+1;let n=((clock>>12)&63)+1;let h=((clock>>6)&63)+1;let l=(clock&63)+1;if h>=n || l!=n{return -95;}high=h*pre*factor*2;low=(n-h)*pre*factor*2;}
 let cpol=(misc>>29)&1;let edge=7;if se_chip(s){edge=9;}let cpha=((user>>edge)&1)^cpol;
 let fifo=se_spi_reg(s,bus,se_spi_fifo(s));let txoff=0;let rxoff=0;if user&(1<<25){txoff=32;}if user&(1<<24){rxoff=32;}
 em_zero(p+1536,128);em_copy(p+1536,fifo+txoff,64-txoff);em_copy(p+1600,fifo+rxoff,64-rxoff);
 // Original rev3 hardware writes whole received bytes, clearing their unused bits.
 // Later bytes retain their prior FIFO contents; S3 padding awaits silicon proof.
 if !se_chip(s){em_zero(p+1600,(rxlen+7)/8);}
 store64(p,2);store64(p+16,0);store64(p+24,txlen);store64(p+32,rxlen);store64(p+40,bits);store64(p+48,cpol);store64(p+56,cpha);store64(p+64,high);store64(p+72,low);store64(p+80,txlsb);store64(p+88,rxlsb);store64(p+96,rxoff);store64(p+104,0);store64(p+112,0);store64(p+120,misc);store64(p+128,load64(s+16)*2);
 store64(p+136,command);store64(p+144,address);store64(p+152,dummy);store64(p+160,u2&65535);let addr=se_spi_cfg(s,bus,4)<<32;if !se_chip(s){addr=addr|se_spi_cfg(s,bus,48);}store64(p+168,addr);store64(p+176,prefix);let rxstart=prefix;if half{rxstart=rxstart+txlen;}store64(p+184,rxstart);store64(p+192,half);store64(p+200,(user>>26)&1);store64(p+208,completion*(high+low));store64(p+216,0);store64(p+224,setup*(high+low));store64(p+232,hold*(high+low));
 let first=low;if cpol{first=high;}store64(p+240,0);if !se_chip(s) && cpha{store64(p+240,first);first=0;}store64(p+8,load64(s+16)*2+first+load64(p+224));se_spi_put(s,bus,0,se_spi_usr(s));let result=se_spi_pins(s,bus,1);if result{return result;}result=se_spi_output(s,bus,0,cpol,1);if result{return result;}let bit=0;if !cpha{bit=se_spi_tx_bit(s,bus,0);}result=se_spi_output(s,bus,1,bit,1);if result{return result;}
 // With no setup, original CPHA1 starts its leading edge at CS assertion.
 // Retire this zero-time event now so WAITI never adds a spurious CPU tick.
 return se_spi_tick(s,bus,0);
}
fn se_spi_finish(s,bus){let p=se_spi(s,bus);let rx=load64(p+32);if rx{em_copy(se_spi_reg(s,bus,se_spi_fifo(s))+load64(p+96),p+1600,(rx+7)/8);}store64(p,0);se_spi_put(s,bus,0,0);if se_chip(s){se_spi_put(s,bus,60,se_spi_get(s,bus,60)|4096);}else{se_spi_put(s,bus,56,se_spi_get(s,bus,56)|16);}store64(p+112,load64(p+112)+1);
 let result=0;if !(load64(p+120)&(1<<30)){result=se_spi_pins(s,bus,0);}return result;}
fn se_spi_tick(s,bus,delta){let p=se_spi(s,bus);if !load64(p){return 0;}if !se_spi_running(s,bus){store64(p+8,load64(p+8)+delta*2);if load64(p+216){store64(p+216,load64(p+216)+delta*2);}return 0;}let now=load64(s+16)*2;
 if load64(p)==1{if load64(p+8)<=now{em_copy(p+1280,p+256,256);store64(p,0);se_spi_put(s,bus,0,0);let result=se_spi_idle(s,bus);if result{return se_fail(s,result,se_spi_base(s,bus));}}return 0;}
 while load64(p) && load64(p+8)<=now{if load64(p)==3 || load64(p)==4{if load64(p)==3{if !(load64(p+120)&(1<<30)){let released=se_spi_pins(s,bus,0);if released{return se_fail(s,released,se_spi_base(s,bus));}}if load64(p+216)>now{store64(p,4);store64(p+8,load64(p+216));return 0;}}let finished=se_spi_finish(s,bus);if finished{return se_fail(s,finished,se_spi_base(s,bus));}return 0;}let edge=load64(p+16);let bit=edge/2;let trailing=edge&1;let cpol=load64(p+48);let cpha=load64(p+56);let level=cpol^(!trailing);if load64(p+200) && se_spi_dummy(s,bus,bit){level=cpol;}let result=0;
 if !trailing && cpha{result=se_spi_output(s,bus,1,se_spi_tx_bit(s,bus,bit),1);if result{return se_fail(s,result,se_spi_base(s,bus));}}
 result=se_spi_output(s,bus,0,level,1);if result{return se_fail(s,result,se_spi_base(s,bus));}
 if trailing==cpha{result=se_spi_sample(s,bus,bit);if result{return se_fail(s,result,se_spi_base(s,bus));}}
 let n=load64(p+104);if n>=4096{return se_fail(s,-75,se_spi_base(s,bus));}let mosi=load64(s+226000+se_spi_signal(s,bus,1)*16);store8(p+4096+n,level|((mosi&1)<<1)|((trailing==cpha && se_spi_rx_index(s,bus,bit)>=0)<<2));store64(p+104,n+1);
 edge=edge+1;store64(p+16,edge);if edge==load64(p+40)*2{let tail=load64(p+240);let cswait=load64(p+232)+tail;let finishwait=load64(p+208)+tail;store64(p+216,load64(p+8)+finishwait);if cswait{store64(p,3);store64(p+8,load64(p+8)+cswait);}else{if !(load64(p+120)&(1<<30)){result=se_spi_pins(s,bus,0);if result{return se_fail(s,result,se_spi_base(s,bus));}}if finishwait{store64(p,4);store64(p+8,load64(p+216));}else{result=se_spi_finish(s,bus);if result{return se_fail(s,result,se_spi_base(s,bus));}}}}else{if trailing && !cpha{result=se_spi_output(s,bus,1,se_spi_tx_bit(s,bus,bit+1),1);if result{return se_fail(s,result,se_spi_base(s,bus));}}let wait=load64(p+64);if !(cpol^(!trailing)){wait=load64(p+72);}store64(p+8,load64(p+8)+wait);}}
 return 0;
}
fn se_spi_irq(s,bus){if !se_spi_running(s,bus){return 0;}if se_chip(s){return se_spi_get(s,bus,52)&se_spi_get(s,bus,60)&4096;}let slave=se_spi_get(s,bus,56);return (slave&16) && (slave&512);}
fn se_spi_bus(s,bus,offset,writing,value){if !se_enabled(s,6+(bus-2)*10){return -5;}let p=se_spi(s,bus);if offset==0{if !writing{return se_spi_get(s,bus,0);}if !value{return 0;}if load64(p){return -16;}if se_chip(s) && value==(1<<23){if !se_spi_running(s,bus){return -5;}store64(p,1);store64(p+8,load64(s+16)*2+2);se_spi_put(s,bus,0,value);return 0;}if value!=se_spi_usr(s){return -95;}return se_spi_start(s,bus);}
 if se_chip(s) && offset>=52 && offset<=68{if offset==52{if writing{if value&~4096{return -95;}se_spi_put(s,bus,offset,value);}return se_spi_get(s,bus,offset);}if offset==56{if writing{se_spi_put(s,bus,60,se_spi_get(s,bus,60)&~value);}return 0;}if offset==60{if writing{return -13;}return se_spi_get(s,bus,60);}if offset==64{if writing{return -13;}return se_spi_get(s,bus,60)&se_spi_get(s,bus,52);}if writing{if value&~4096{return -95;}se_spi_put(s,bus,60,se_spi_get(s,bus,60)|value);}return 0;}
 if offset==se_spi_slave(s){if writing{let allowed=528;if se_chip(s){allowed=0x03c00000;}if value&~allowed{return -95;}se_spi_put(s,bus,offset,value);}return se_spi_get(s,bus,offset);}
 let fifo=se_spi_fifo(s);let known=(offset>=fifo && offset<fifo+64) || offset==4 || offset==8 || offset==se_spi_clock(s) || (offset>=se_spi_user(s) && offset<=se_spi_user(s)+8) || offset==se_spi_misc(s);if !se_chip(s) && (offset==12 || offset==20 || offset==40 || offset==44 || offset==48 || offset==240 || offset==244){known=1;}if se_chip(s) && (offset==28 || offset==48 || offset==232){known=1;}if !known{return -95;}
 if writing{if offset==232 && (value&~7){return -95;}if se_chip(s) && offset==48 && value{return -95;}se_spi_put(s,bus,offset,value);if !se_chip(s) && !load64(p) && (offset==se_spi_misc(s) || offset==8){let result=se_spi_idle(s,bus);if result{return result;}}}return se_spi_get(s,bus,offset);
}
