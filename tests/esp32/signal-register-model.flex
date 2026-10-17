import "../../lib/platform/esp32-pwm.flex";
import "../../lib/platform/esp32-rmt.flex";
global sr_ref=0;global sr_regs=0;global sr_count=0;global sr_checks=0;global sr_ps=0;global sr_ticks=0;global sr_tx_calls=0;global sr_tx_error=0;global sr_tx_stall=0;global sr_stuck=0;global sr_active=0;global sr_rx_count=4;global sr_rx_mode=0;global sr_partial=0;global sr_rx_starts=0;
fn ref(i){return load64(sr_ref+16+i*8);}
fn si(address){let i=0;while i<sr_count{if load64(sr_regs+i*16)==address{return i;}i=i+1;}store64(sr_regs+i*16,address);sr_count=sr_count+1;return i;}
fn sg(address){return load64(sr_regs+si(address)*16+8);}
fn ss(address,value){store64(sr_regs+si(address)*16+8,value&0xffffffff);return 0;}
fn check(ok,id){sr_checks=sr_checks+1;if !ok{let p=alloc(16);store64(p,id);store64(p+8,sr_checks);syscall(1,2,p,16,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_irq_save(){let old=sr_ps;sr_ps=15;return old;}
fn esp32_irq_restore(ps){sr_ps=ps;return 0;}
fn esp32_cycles(){sr_ticks=(sr_ticks+1000000)&0xffffffff;return sr_ticks;}
fn esp32_load32(address){
 if address>=0x3ffb0000 && address<0x3ffe0000{return load8(address)|(load8(address+1)<<8)|(load8(address+2)<<16)|(load8(address+3)<<24);}
 if address>=ref(30) && address<ref(30)+2048{let channel=(address-ref(30))/256;check(!(sg(ref(22)+ref(23)+channel*ref(24)+4)&ref(36)),100);}return sg(address);
}
fn esp32_store32(address,value){
 value=value&0xffffffff;if address>=0x3ffb0000 && address<0x3ffe0000{let i=0;while i<4{store8(address+i,value>>(i*8));i=i+1;}return 0;}
 let old=sg(address);ss(address,value);if address==ref(22)+ref(28){ss(ref(22)+ref(26),sg(ref(22)+ref(26))&~value);}
 let channel=0;while channel<8{let config=ref(22)+ref(23)+channel*ref(24)+4;let mask=ref(47)<<(channel*3);let active=sr_active+channel*8;let memory=ref(30)+channel*256;
  if address==config{
   if value&ref(41){ss(ref(22)+ref(25)+channel*4,channel*64);}
   if value&ref(42) && load64(active)==1 && sg(memory)==0 && !sr_stuck{ss(ref(22)+ref(26),sg(ref(22)+ref(26))|mask);store64(active,0);}
   if value&ref(39){check((sg(ref(22)+ref(23))&(ref(31)|ref(33)))==ref(31) && (sg(ref(54))&ref(53)),106);sr_tx_calls=sr_tx_calls+1;check(!(value&ref(36)),101);let i=0;while i<64 && sg(memory+i*4){check(i<64 && sg(memory+i*4)==ref(57+i%16),102);i=i+1;}check(i>0 && i<=63,103);store64(active,1);ss(config,value&~ref(39));if sr_tx_error{ss(ref(22)+ref(26),sg(ref(22)+ref(26))|(ref(49)<<(channel*3)));}else if !sr_tx_stall{ss(ref(22)+ref(26),sg(ref(22)+ref(26))|mask);store64(active,0);}}
   if (value&ref(40)) && !(old&ref(40)){
    sr_rx_starts=sr_rx_starts+1;check((sg(ref(22)+ref(23))&(ref(31)|ref(33)))==ref(31),107);check(value&ref(36),104);let blocks=1;let mask=0;while blocks<=8{mask=mask|ref(73+blocks);blocks=blocks+1;}let encoded=sg(config-4)&mask;blocks=1;while blocks<=8 && ref(73+blocks)!=encoded{blocks=blocks+1;}check(blocks<=8,700);let i=0;while i<blocks*64{check(sg(memory+i*4)==0,105);i=i+1;}i=0;while i<sr_rx_count{let word=ref(57+i%16);if sr_partial && i==sr_rx_count-1{word=word&65535;}ss(memory+i*4,word);i=i+1;}
    let count=sr_rx_count;if sr_rx_mode==3{count=0;}ss(ref(22)+ref(25)+channel*4,channel*64+count);
    if sr_rx_mode==0{ss(ref(22)+ref(26),sg(ref(22)+ref(26))|(ref(48)<<(channel*3)));}if sr_rx_mode==2{ss(ref(22)+ref(26),sg(ref(22)+ref(26))|(ref(49)<<(channel*3)));}
   }
  }channel=channel+1;
 }return 0;
}
fn timer_expect(timer,hz,bits){let div=(20480000000+hz*(1<<bits)-1)/(hz*(1<<bits));let expect=(div<<5)|bits|ref(10);if timer>=4{expect=expect|ref(11);}let base=ref(0)+ref(3);if timer>=4{base=ref(0)+ref(4);}base=base+(timer&3)*8;check(esp_pwm_timer(timer,hz,bits)==(20480000000+div*(1<<bits)/2)/(div*(1<<bits)),200);check(sg(base)==expect && (sg(ref(54))&ref(20)),201);return 0;}
fn rx_case(channel,buffer,mode,count,capacity,partial){sr_rx_mode=mode;sr_rx_count=count;sr_partial=partial;let i=0;while i<capacity{esp32_store32(buffer+i*4,0x55aa55aa);i=i+1;}check(esp_rmt_rx_start(channel)==0,300);check(esp_rmt_rx_start(channel)== -16,301);let expected=count;if expected>capacity{expected=capacity;}if mode==2{expected= -75;}if mode==3{expected= -110;}sr_ticks=0xfffffff0;let got=esp_rmt_rx_finish(channel,buffer,capacity,3000000);check(got==expected,302);i=0;while i<capacity{let word=0x55aa55aa;if got>i{word=ref(57+i%16);if partial && i==count-1{word=word&65535;}}check(esp32_load32(buffer+i*4)==word,303);i=i+1;}check(!(sg(ref(22)+ref(23)+channel*ref(24)+4)&(ref(36)|ref(40))),304);return 0;}
fn main(argc,argv){if argc!=2{return 99;}sr_ref=alloc(672);let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0 || syscall(0,fd,sr_ref,672,0,0,0)!=672{return 98;}syscall(3,fd,0,0,0,0,0);if load64(sr_ref)!=0x5349475245470003 || load64(sr_ref+8)!=82{return 97;}
 sr_regs=alloc(131072);sr_active=alloc(64);let i=0;while i<64{store8(sr_active+i,0);i=i+1;}let ram=syscall(9,0x3ffb0000,196608,3,0x100022,-1,0);if ram!=0x3ffb0000{return 96;}let data=ram+1024;let dest=ram+4096;
 check(esp_pwm_channel(0,0,21)== -19 && esp_pwm_duty(0,1)== -19 && esp_rmt_write(0,data,1,100)== -19,1);
 let t=0;while t<8{timer_expect(t,1000,10);let group=t/4;let c=group*8+(t&3);let base=ref(0)+ref(1+group)+(c&7)*20;check(esp_pwm_channel(c,t,21)==0,2);check((sg(base)&31)==((t&3)|ref(14)|(group*ref(16))),3);let signal=ref(18+group)+(c&7);check(sg(0x3ff44530+21*4)==(signal|1024),4);check(esp_pwm_timer(t,2000,10)== -16 && esp_pwm_timer_deinit(t)== -16,5);
 check(!(sg(base+12)&ref(73)),600);let duty=0;while duty<4{let value=duty*255;check(esp_pwm_duty(c,value)==0 && sg(base+8)==value*16 && sg(base+12)==ref(17),6);check(esp_pwm_duty(c,value+1)== -16,601);ss(base+12,sg(base+12)&~ref(73));duty=duty+1;}check(esp_pwm_duty(c,1024)== -22 && esp_pwm_duty(c,-1)== -22,7);check(esp_pwm_stop(c,1)==0 && (sg(base)&12)==ref(15),8);check(esp_pwm_duty(c,512)==0 && (sg(base)&ref(14)),9);check(esp_pwm_channel(c,t,21)== -16,10);check(esp_pwm_channel_deinit(c)==0 && esp_pwm_channel_deinit(c)==0 && esp_pwm_timer_deinit(t)==0,11);t=t+1;}
 let c=0;while c<16{let timer=(c/8)*4+(c&3);timer_expect(timer,1000,10);check(esp_pwm_channel(c,timer,21)==0,120);let base=ref(0)+ref(1+c/8)+(c&7)*20;check((sg(base)&31)==((timer&3)|ref(14)|((c/8)*ref(16))),121);check(sg(0x3ff44530+21*4)==(ref(18+c/8)+(c&7)|1024),122);check(esp_pwm_duty(c,1023)==0 && sg(base+8)==16368,123);check(esp_pwm_channel_deinit(c)==0 && esp_pwm_timer_deinit(timer)==0,124);c=c+1;}
 timer_expect(0,1,20);check(esp_pwm_timer_deinit(0)==0,125);check(!(sg(ref(54))&ref(20)),12);check(esp_pwm_timer(0,40000000,1)==40000000 && esp_pwm_timer_deinit(0)==0,13);check(esp_pwm_timer(0,1000000,20)== -22 && esp_pwm_timer(8,1000,10)== -22 && esp_pwm_channel(8,0,21)== -22,14);
 i=0;while i<63{esp32_store32(data+i*4,ref(57+i%16));if i<16{check(esp_rmt_symbol(i&1,3+i*11,!(i&1),5+i*17)==ref(57+i),15);}i=i+1;}
 check(esp_rmt_symbol(2,1,0,1)== -22 && esp_rmt_symbol(0,0,1,3)== -22 && esp_rmt_symbol(0,1,1,32768)== -22,16);
 let ch=0;while ch<8{let divider=80;if ch==7{divider=256;}check(esp_rmt_tx_init(ch,21,divider,ch&1)==0,20);let config=ref(22)+ref(23)+ch*ref(24);let c0=(divider&255)|ref(32);if !ch{c0=c0|ref(31);}check(sg(config)==c0 && sg(config+4)==(ref(34)|ref(37)|((ch&1)*ref(38))),21);check((sg(ref(22)+ref(29))&3)==ref(35),22);check(sg(0x3ff44530+21*4)==(ref(51)+ch+1024),23);check(esp_rmt_tick_hz(ch)==80000000/divider,24);check(esp_rmt_tx_init(ch,21,80,0)== -16,25);
 check(esp_rmt_write(ch,data,16,100000000)==16,26);check(esp_rmt_write(ch,data,63,100000000)==63,260);sr_tx_error=1;check(esp_rmt_write(ch,data,3,100000000)== -5,27);sr_tx_error=0;check(esp_rmt_write(ch,data,2,100000000)==2,28);sr_tx_stall=1;sr_ticks=0xfffffff0;check(esp_rmt_write(ch,data,2,3000000)== -110,29);sr_tx_stall=0;check(esp_rmt_write(ch,data,2,100000000)==2,30);
 check(esp_rmt_write(ch,data,64,100)== -22 && esp_rmt_write(ch,data+1,1,100)== -22 && esp_rmt_write(ch,0x3ffdffff,1,100)== -22,31);sr_tx_stall=1;sr_stuck=1;check(esp_rmt_write(ch,data,2,3000000)== -110,320);check(esp_rmt_write(ch,data,2,100000000)== -16 && esp_rmt_deinit(ch)== -110,321);
 let other=(ch+1)%8;check(esp_rmt_tx_init(other,23,80,0)==0,322);sr_tx_stall=0;check(esp_rmt_write(other,data,2,100000000)==2,323);check(esp_rmt_deinit(other)==0 && load64(er_state(ch)+8)==3,324);
 ss(ref(22)+ref(26),sg(ref(22)+ref(26))|(ref(47)<<(ch*3)));store64(sr_active+ch*8,0);sr_stuck=0;check(esp_rmt_write(ch,data,2,100000000)==2,325);check(esp_rmt_deinit(ch)==0 && esp_rmt_deinit(ch)==0,32);
 check(esp_rmt_rx_init(ch,19,80,20000,3)==0,33);config=ref(22)+ref(23)+ch*ref(24);c0=80|(20000<<8)|ref(32);if !ch{c0=c0|ref(31);}check(sg(config)==c0 && sg(config+4)==(ref(34)|ref(36)|ref(45)|(3<<8)),34);check(sg(0x3ff44130+(ref(52)+ch)*4)==(19|128),35);
 let starts=sr_rx_starts;check(esp_rmt_read(ch,dest+1,8,100000000)== -22 && esp_rmt_read(ch,dest,65,100000000)== -22 && esp_rmt_read(ch,dest,8,0)== -22 && sr_rx_starts==starts,350);
 sr_rx_mode=0;sr_rx_count=4;sr_partial=0;check(esp_rmt_read(ch,dest,8,3000000)==4,351);rx_case(ch,dest,0,16,64,0);rx_case(ch,dest,0,4,8,0);rx_case(ch,dest,0,5,8,1);rx_case(ch,dest,1,12,8,0);rx_case(ch,dest,2,4,8,0);rx_case(ch,dest,3,0,8,0);rx_case(ch,dest,0,2,8,0);check(esp_rmt_deinit(ch)==0,36);ch=ch+1;}
 check(!(sg(ref(54))&ref(53)),37);check(esp_rmt_tx_init(0,34,80,0)== -22 && esp_rmt_rx_init(8,19,80,100,0)== -22 && esp_rmt_rx_init(0,19,257,100,0)== -22,38);check(!sr_ps,39);

 // Legal contiguous ranges and observable reservation/capacity behavior.
 ch=0;while ch<8{let blocks=1;while blocks<=8-ch{let capacity=blocks*64;check(esp_rmt_rx_init_blocks(ch,19,80,20000,0,blocks)==0,710);let config=ref(22)+ref(23)+ch*ref(24);let expected=80|(20000<<8)|ref(73+blocks);if !ch{expected=expected|ref(31);}check(sg(config)==expected,711);
 let peer=ch;while peer<ch+blocks{check(esp_rmt_tx_init(peer,21,80,0)== -16 && esp_rmt_rx_init(peer,23,80,100,0)== -16,712);peer=peer+1;}
 check(esp_rmt_read(ch,dest,capacity+1,3000000)== -22,713);rx_case(ch,dest,0,capacity-1,capacity,1);rx_case(ch,dest,1,capacity-1,capacity-2,0);rx_case(ch,dest,2,4,capacity,0);rx_case(ch,dest,3,0,capacity,0);
 sr_rx_mode=0;sr_rx_count=1;check(esp_rmt_rx_start(ch)==0,714);let starts=sr_rx_starts;check(esp_rmt_rx_finish(ch,dest,capacity+1,3000000)== -22 && sr_rx_starts==starts && load64(er_state(ch)+8)==1,715);check(esp_rmt_rx_finish(ch,dest,capacity,3000000)==1,716);
 if blocks>1{check(esp_rmt_deinit(ch+1)==0 && esp_rmt_tx_init(ch+1,21,80,0)== -16,717);}check(esp_rmt_deinit(ch)==0,718);let reserve=ch+blocks-1;check(esp_rmt_tx_init(reserve,21,80,0)==0 && esp_rmt_deinit(reserve)==0,719);blocks=blocks+1;}ch=ch+1;}
 check(esp_rmt_rx_init_blocks(0,19,80,100,0,0)== -22 && esp_rmt_rx_init_blocks(0,19,80,100,0,9)== -22 && esp_rmt_rx_init_blocks(7,19,80,100,0,2)== -22,720);
 check(esp_rmt_rx_init_blocks(0,19,80,20000,0,3)==0 && esp_rmt_rx_init_blocks(3,23,80,20000,0,2)==0,721);check(esp_rmt_rx_init_blocks(2,4,80,20000,0,2)== -16,722);check(esp_rmt_deinit(0)==0 && (sg(ref(54))&ref(53)),723);check(esp_rmt_tx_init(4,21,80,0)== -16,726);check(esp_rmt_tx_init(1,21,80,0)==0 && esp_rmt_deinit(1)==0 && (sg(ref(54))&ref(53)),724);check(esp_rmt_deinit(3)==0 && !(sg(ref(54))&ref(53)) && !sr_ps,725);
 let out=alloc(8);store64(out,sr_checks);syscall(1,1,out,8,0,0,0);return 0;
}
