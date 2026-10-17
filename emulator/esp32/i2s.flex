// Original ESP32 I2S, independent mapped-SRAM DMA and GPIO serial engines.
// Two8192-byte contexts at282624. Engines RX0/TX256, registers1024,
// DMA RX2048/TX2304. Functional stereo Philips16/32, PLL_D2 clock profile.
// FIFO port/threshold timing, companding, APLL and other audio modes remain
// explicit unsupported operations; no platform or compiler helper is called.
fn se_i2s(s,bus){return s+282624+bus*8192;}
fn se_i2s_engine(s,bus,direction){return se_i2s(s,bus)+direction*256;}
fn se_i2s_dma(s,bus,direction){return se_i2s(s,bus)+2048+direction*256;}
fn se_i2s_base(bus){return 0x3ff4f000+bus*122880;}
fn se_i2s_get(s,bus,offset){return em_u32(se_i2s(s,bus)+1024+offset);}
fn se_i2s_put(s,bus,offset,value){em_put32(se_i2s(s,bus)+1024+offset,value);return 0;}
fn se_i2s_enabled(s,bus){return !se_chip(s) && se_enabled(s,4+bus*17);}
fn se_i2s_running(s,bus){return se_i2s_enabled(s,bus) && se_clock_audio(s) && (se_i2s_get(s,bus,0xac)&(1<<20));}
fn se_i2s_bits(s,bus,direction){return (se_i2s_get(s,bus,0xb0)>>(18-direction*6))&63;}
fn se_i2s_signal(bus,direction,which){if direction{if which==2{return 163+bus*26;}return 23+bus+which*2;}if which==2{return 155+bus*26;}if bus{return 164+which;}return 27+which;}
fn se_i2s_event(s,bus,bits){se_i2s_put(s,bus,12,se_i2s_get(s,bus,12)|bits);return 0;}
fn se_i2s_irq(s,bus){if !se_i2s_enabled(s,bus){return 0;}return se_i2s_get(s,bus,12)&se_i2s_get(s,bus,20);}
// DMA faults are peripheral events, never CPU memory faults. Only mapped
// internal DRAM can participate; descriptor pointers are the actual32-bit ABI.
fn se_i2s_memory(s,address,size,permission){if address<0x3ffae000 || address>=0x40000000 || size<1 || size>0x40000000-address{return 0;}let cpu=load64(s);let region=xt_load_region(cpu,address,size);if !region || (load64(region+24)&permission)!=permission{return 0;}return load64(region+16)+address-load64(region);}
fn se_i2s_dma_error(s,bus,direction){let q=se_i2s_dma(s,bus,direction);store64(q,0);store64(q+80,1);let offset=0x34-direction*4;se_i2s_put(s,bus,offset,se_i2s_get(s,bus,offset)|0x80000000);let bit=13+direction;return se_i2s_event(s,bus,1<<bit);}
fn se_i2s_dma_load(s,bus,direction,address){let q=se_i2s_dma(s,bus,direction);let permission=1;let control=se_i2s_get(s,bus,0x60);if !direction || (control&64){permission=3;}let desc=se_i2s_memory(s,address,12,permission);
 if (address&3) || !desc{se_i2s_dma_error(s,bus,direction);return 0;}let head=em_u32(desc);let size=head&4095;let used=(head>>12)&4095;
 if !size || (size&3) || (em_u32(desc+4)&3) || (direction && (!used || (used&3) || used>size)) || ((control&4096) && !(head&0x80000000)){se_i2s_dma_error(s,bus,direction);return 0;}
 store64(q,1);store64(q+8,address);store64(q+16,em_u32(desc+4));store64(q+24,size);store64(q+32,used);store64(q+40,0);store64(q+48,em_u32(desc+8));store64(q+56,head);store64(q+72,0);store64(q+80,0);store64(q+88,1);let offset=0x48;if direction{offset=0x54;}se_i2s_put(s,bus,offset,address);return 1;
}
fn se_i2s_dma_stop(s,bus,direction){let q=se_i2s_dma(s,bus,direction);store64(q,0);let offset=0x34-direction*4;se_i2s_put(s,bus,offset,(se_i2s_get(s,bus,offset)&0xfffff)|0x80000000);return 0;}
fn se_i2s_dma_start(s,bus,direction,value){let q=se_i2s_dma(s,bus,direction);em_zero(q,256);let offset=0x34-direction*4;se_i2s_put(s,bus,offset,value&0xfffff);se_i2s_dma_load(s,bus,direction,0x3ff00000|(value&0xfffff));return 0;}
fn se_i2s_tx_eof(s,bus,address){se_i2s_put(s,bus,0x40,se_i2s_get(s,bus,0x38));se_i2s_put(s,bus,0x38,address);return se_i2s_event(s,bus,1<<12);}
fn se_i2s_tx_word(s,bus){let q=se_i2s_dma(s,bus,1);if !load64(q){return -1;}let at=load64(q+40);if at==load64(q+32){let next=load64(q+48);if !next{store64(q,0);store64(q+80,1);se_i2s_put(s,bus,0x30,se_i2s_get(s,bus,0x30)|0x80000000);se_i2s_event(s,bus,1<<16);return -1;}if !se_i2s_dma_load(s,bus,1,next){return -1;}at=0;}
 let data=se_i2s_memory(s,load64(q+16)+at,4,1);if !data{se_i2s_dma_error(s,bus,1);return -1;}let word=em_u32(data);at=at+4;store64(q+40,at);
 if at==load64(q+32){let address=load64(q+8);if se_i2s_get(s,bus,0x60)&64{let desc=se_i2s_memory(s,address,4,2);if !desc{se_i2s_dma_error(s,bus,1);return -1;}em_put32(desc,load64(q+56)&0x7fffffff);}se_i2s_event(s,bus,1<<11);if load64(q+56)&0x40000000{if se_i2s_get(s,bus,0x60)&256{store64(se_i2s_engine(s,bus,1)+160,address);}else{se_i2s_tx_eof(s,bus,address);}}}
 return word;
}
fn se_i2s_rx_word(s,bus,word){let q=se_i2s_dma(s,bus,0);if !load64(q){se_i2s_event(s,bus,1<<6);return 0;}let at=load64(q+40);if load64(q+72){if !se_i2s_dma_load(s,bus,0,load64(q+48)){return 0;}at=0;}
 let data=se_i2s_memory(s,load64(q+16)+at,4,2);if !data{return se_i2s_dma_error(s,bus,0);}em_put32(data,word);at=at+4;store64(q+40,at);let words=(load64(q+64)+1)&0xffffffff;store64(q+64,words);let count=se_i2s_get(s,bus,0x24);let eof=count && words>=count;
 if eof || at==load64(q+24){let address=load64(q+8);let desc=se_i2s_memory(s,address,12,3);if !desc{return se_i2s_dma_error(s,bus,0);}let head=(load64(q+56)&~0xc0fff000)|(at<<12);if eof{head=head|0x40000000;store64(q+64,0);se_i2s_put(s,bus,0x3c,address);se_i2s_event(s,bus,1<<9);}em_put32(desc,head);store64(q+72,1);se_i2s_event(s,bus,1<<8);
  if !load64(q+48){store64(q,0);se_i2s_put(s,bus,0x34,se_i2s_get(s,bus,0x34)|0x80000000);if !eof{se_i2s_event(s,bus,1<<15);}}
 }return 0;
}
fn se_i2s_receive(s,bus,ws,data){let e=se_i2s_engine(s,bus,0);let old=load64(e+104);let bits=se_i2s_bits(s,bus,0);
 if load64(e+112){let n=load64(e+120)+1;let value=((load64(e+128)<<1)|data)&0xffffffff;store64(e+120,n);store64(e+128,value);if n==bits{let slot=load64(e+136);if bits==32{se_i2s_rx_word(s,bus,value);}else if !slot{store64(e+144,value);}else{let packed=load64(e+144)|(value<<16);if !(se_i2s_get(s,bus,8)&(1<<17)){packed=(load64(e+144)<<16)|value;}se_i2s_rx_word(s,bus,packed);}store64(e+120,0);store64(e+128,0);}}
 if ws!=old{if !ws{store64(e+112,1);store64(e+136,0);}else if load64(e+112){store64(e+136,1);}store64(e+120,0);store64(e+128,0);}store64(e+104,ws);return 0;
}
fn se_i2s_inputs(s){if se_chip(s){return 0;}let bus=0;while bus<2{let e=se_i2s_engine(s,bus,0);if load64(e) && se_i2s_running(s,bus){let conf=se_i2s_get(s,bus,8);let bck=0;let ws=0;if conf&(1<<18){let tx=se_i2s_engine(s,bus,1);bck=load64(tx+16);ws=load64(tx+80);}else if !(conf&128){bck=load64(e+16);ws=load64(e+80);}else{bck=se_gpio_signal(s,se_i2s_signal(bus,0,0));ws=se_gpio_signal(s,se_i2s_signal(bus,0,1));if bck<0 || ws<0{return -95;}}
  let previous=load64(e+96);store64(e+96,bck);if bck && !previous{let data=se_gpio_signal(s,se_i2s_signal(bus,0,2));if data<0{return data;}se_i2s_receive(s,bus,ws,data);}
 }bus=bus+1;}return 0;
}
fn se_i2s_drive(s,bus,direction){let e=se_i2s_engine(s,bus,direction);let result=0;if direction{result=se_gpio_peripheral(s,se_i2s_signal(bus,1,2),load64(e+88),1);if result{return result;}}result=se_gpio_peripheral(s,se_i2s_signal(bus,direction,1),load64(e+80),1);if result{return result;}result=se_gpio_peripheral(s,se_i2s_signal(bus,direction,0),load64(e+16),1);if result{return result;}return se_i2s_inputs(s);}
fn se_i2s_core_stop(s,bus,direction){let e=se_i2s_engine(s,bus,direction);store64(e,0);store64(e+16,0);let result=se_gpio_peripheral(s,se_i2s_signal(bus,direction,0),0,0);if result{return result;}result=se_gpio_peripheral(s,se_i2s_signal(bus,direction,1),0,0);if result{return result;}if direction{return se_gpio_peripheral(s,se_i2s_signal(bus,1,2),load64(e+88),0);}return 0;}
fn se_i2s_validate(s,bus,direction){let bits=se_i2s_bits(s,bus,direction);let conf=se_i2s_get(s,bus,8);let fifo=se_i2s_get(s,bus,0x20);let mode=(fifo>>(16-direction*3))&7;let bad=0xa200;let bypass=128;let channel=(se_i2s_get(s,bus,0x2c)>>3)&3;if direction{bad=0x5140;bypass=8;channel=se_i2s_get(s,bus,0x2c)&7;}
 if (bits!=16 && bits!=32) || (conf&bad) || channel || (fifo&4095)!=2080 || !(fifo&4096) || !(fifo&(1<<(20-direction))) || mode!=((bits==32)*2) || !(conf&(1<<(11-direction))) || !(se_i2s_get(s,bus,0xa0)&bypass) || se_i2s_get(s,bus,0xa8) || se_i2s_get(s,bus,0xb4) || se_i2s_get(s,bus,0x1c) || (se_i2s_get(s,bus,0x60)&0x2030){return -95;}
 if bits==32 && (conf&(1<<(17-direction))){return -95;}if !direction && se_gpio_signal(s,se_i2s_signal(bus,0,2))<0{return -95;}return 0;
}
fn se_i2s_clock_setup(s,bus,direction){let e=se_i2s_engine(s,bus,direction);let clk=se_i2s_get(s,bus,0xac);if clk&(1<<21){return -95;}let a=(clk>>14)&63;let b=(clk>>8)&63;let n=clk&255;if !n{n=256;}if !a{if b{return -95;}a=1;}if b>=a{return -95;}let divider=(se_i2s_get(s,bus,0xb0)>>(6-direction*6))&63;if !divider{divider=64;}store64(e+48,(n*a+b)*divider);store64(e+56,a*4);store64(e+64,load64(s+16));store64(e+72,0);return 0;}
fn se_i2s_schedule(s,bus,direction){let e=se_i2s_engine(s,bus,direction);let phase=load64(e+72)+load64(e+48);let den=load64(e+56);store64(e+64,load64(e+64)+phase/den);store64(e+72,phase%den);store64(e+8,load64(e+64)+(load64(e+72)!=0));return 0;}
fn se_i2s_tx_load(s,bus,slot){let e=se_i2s_engine(s,bus,1);let bits=se_i2s_bits(s,bus,1);if bits==16 && slot{store64(e+32,load64(e+40));return 1;}let word=se_i2s_tx_word(s,bus);if word<0{return 0;}if bits==16{let left=word&65535;let right=word>>16;if !(se_i2s_get(s,bus,8)&(1<<16)){left=word>>16;right=word&65535;}store64(e+32,left);store64(e+40,right);if load64(e+160){store64(e+168,load64(e+160));store64(e+160,0);}}else{store64(e+32,word);}return 1;}
fn se_i2s_start(s,bus,direction){let result=se_i2s_validate(s,bus,direction);if result{return result;}let e=se_i2s_engine(s,bus,direction);em_zero(e,256);store64(e,1);let conf=se_i2s_get(s,bus,8);if !direction && (conf&128){return se_i2s_inputs(s);}result=se_i2s_clock_setup(s,bus,direction);if result{store64(e,0);return result;}if direction && !se_i2s_tx_load(s,bus,0){se_i2s_event(s,bus,1<<7);store64(e,0);return 0;}store64(e+24,0);store64(e+16,0);store64(e+80,0);store64(e+88,0);result=se_i2s_drive(s,bus,direction);if result{return result;}return se_i2s_schedule(s,bus,direction);}
fn se_i2s_edge(s,bus,direction){let e=se_i2s_engine(s,bus,direction);let bits=se_i2s_bits(s,bus,direction);let level=!load64(e+16);store64(e+16,level);let pos=load64(e+24);
 if !level{let slot=0;let next=pos+1;if next>bits*2{next=1;slot=0;if direction && !se_i2s_tx_load(s,bus,slot){if se_i2s_get(s,bus,0xa0)&256{return se_i2s_core_stop(s,bus,1);}store64(e+32,0);se_i2s_event(s,bus,1<<7);}}else if next==bits+1{slot=1;if direction && !se_i2s_tx_load(s,bus,slot){store64(e+32,0);se_i2s_event(s,bus,1<<7);}}
  pos=next;store64(e+24,pos);let ws=pos>=bits && pos<bits*2;store64(e+80,ws);if direction{let index=pos-1;if pos>bits{index=pos-bits-1;}store64(e+88,(load64(e+32)>>(bits-1-index))&1);}
 }
 let result=se_i2s_drive(s,bus,direction);if result{return result;}if level && direction && (pos==bits || pos==bits*2){let address=load64(e+160);if se_i2s_bits(s,bus,1)==16 && pos==bits*2{address=load64(e+168);store64(e+168,0);}if address{se_i2s_tx_eof(s,bus,address);store64(e+160,0);}}
 if load64(e){return se_i2s_schedule(s,bus,direction);}return 0;
}
fn se_i2s_tick(s,bus,delta){let direction=0;while direction<2{let e=se_i2s_engine(s,bus,direction);if load64(e){let slave=!direction && (se_i2s_get(s,bus,8)&128);if !slave{if !se_i2s_running(s,bus){store64(e+8,load64(e+8)+delta);store64(e+64,load64(e+64)+delta);}else{let i=0;while load64(e) && load64(e+8)<=load64(s+16) && i<1024{let result=se_i2s_edge(s,bus,direction);if result{return result;}i=i+1;}if i==1024 && load64(e) && load64(e+8)<=load64(s+16){return -40;}}}}direction=direction+1;}return 0;}
fn se_i2s_deadline(s){if se_chip(s){return -1;}let next= -1;let bus=0;while bus<2{if se_i2s_running(s,bus){let direction=0;while direction<2{let e=se_i2s_engine(s,bus,direction);let slave=!direction && (se_i2s_get(s,bus,8)&128);if load64(e) && !slave{let wait=load64(e+8)-load64(s+16);if wait<1{wait=1;}if next<0 || wait<next{next=wait;}}direction=direction+1;}}bus=bus+1;}return next;}
fn se_i2s_active(s){if se_chip(s){return 0;}return load64(se_i2s_engine(s,0,0))|load64(se_i2s_engine(s,0,1))|load64(se_i2s_engine(s,1,0))|load64(se_i2s_engine(s,1,1));}
fn se_i2s_reset(s,bus){let result=se_i2s_core_stop(s,bus,0);if result{return result;}result=se_i2s_core_stop(s,bus,1);if result{return result;}em_zero(se_i2s(s,bus),8192);se_i2s_put(s,bus,0x20,0x1820);se_i2s_put(s,bus,0x24,64);se_i2s_put(s,bus,0x60,256);se_i2s_put(s,bus,0xa0,0x88);se_i2s_put(s,bus,0xac,4);se_i2s_put(s,bus,0xb0,6|(6<<6)|(16<<12)|(16<<18));se_i2s_put(s,bus,0xfc,0x16042000);return 0;}
fn se_i2s_bus(s,bus,offset,writing,value){if !se_i2s_enabled(s,bus){return -5;}if offset==0 || offset==4{return -95;}if offset==12 || offset==16{if writing{return -13;}let raw=se_i2s_get(s,bus,12);if offset==16{return raw&se_i2s_get(s,bus,20);}return raw|0x2a;}if offset==24{if writing{se_i2s_put(s,bus,12,se_i2s_get(s,bus,12)&~value);}return 0;}
 if offset==0xbc{if writing{return -13;}let value=!load64(se_i2s_engine(s,bus,1));let conf=se_i2s_get(s,bus,8);return value|((conf&4)>>1)|((conf&8)>>1);}
 if offset==0x38 || offset==0x3c || offset==0x40 || (offset>=0x48 && offset<=0x5c){if writing{return -13;}return se_i2s_get(s,bus,offset);}
 if offset==0x30 || offset==0x34{let direction=offset==0x30;if writing{if value&(1<<30){return -95;}if value&(1<<28){se_i2s_dma_stop(s,bus,direction);}else if value&(1<<29){se_i2s_dma_start(s,bus,direction,value);}else{se_i2s_put(s,bus,offset,(se_i2s_get(s,bus,offset)&0x80000000)|(value&0xfffff));}}return se_i2s_get(s,bus,offset);}
 let mask=0;if offset==8{mask=0x7ffff;}if offset==20{mask=0x1ffc0;}if offset==0x1c{mask=0x1ffffff;}if offset==0x20{mask=0x1fffff;}if offset==0x24 || offset==0x28 || offset==0xfc{mask=0xffffffff;}if offset==0x2c{mask=31;}if offset==0x60{mask=0x3fff;}if offset==0x74{mask=4095;}if offset==0xa0{mask=1023;}if offset==0xa4{mask=15;}if offset==0xa8{mask=255;}if offset==0xac{mask=0x3fffff;}if offset==0xb0{mask=0xffffff;}if offset==0xb4{mask=0x3ffffff;}if offset==0xb8{mask=0xfffff;}if !mask{return -95;}
 if writing{if offset==20 && (value&~mask){return -95;}let previous=se_i2s_get(s,bus,offset);if (offset==0x1c || offset==0x20 || offset==0x2c || offset==0xa0 || offset==0xa8 || offset==0xb0 || offset==0xb4) && value!=previous && (load64(se_i2s_engine(s,bus,0)) || load64(se_i2s_engine(s,bus,1))){return -95;}if offset==0xac && ((value^previous)&~(1<<20)) && (load64(se_i2s_engine(s,bus,0)) || load64(se_i2s_engine(s,bus,1))){return -95;}se_i2s_put(s,bus,offset,value&mask);
  if offset==0x60{let direction=0;while direction<2{if value&(1<<direction){em_zero(se_i2s_dma(s,bus,direction),256);se_i2s_dma_stop(s,bus,direction);}direction=direction+1;}}
  if offset==8{let direction=0;while direction<2{let reset=1<<(1-direction);let start=1<<(5-direction);let fifo=1<<(3-direction);let e=se_i2s_engine(s,bus,direction);if (value&(reset|fifo)) || !(value&start){let result=se_i2s_core_stop(s,bus,direction);if result{return result;}em_zero(e,256);}else if !load64(e){let result=se_i2s_start(s,bus,direction);if result{return result;}}direction=direction+1;}}
 }return se_i2s_get(s,bus,offset);
}
