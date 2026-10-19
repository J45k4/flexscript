import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-regi2c.flex";
global cfg=0;global memory=0;global checks=0;global ps=0x1888;global tick=0;global ready=1;global isr=0;
global clock=0;global source=0;global source_writes=0;global select=0;global routing=0;global ctrl0=0;global ctrl1=0;global foreign=0;global pending=0;global command=0;global polls=0;global hang=0;global release=0;global issued=0;global writes=0;global selectors=0;global commands=0;global alter=0;
fn cv(i){return load64(cfg+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("regi2c check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if ready{return rv_hal_state;}return 0;}
fn esp32_irq_save(){let before=ps;ps=ps&~8;return before;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_cycles(){tick=(tick+7)&4294967295;return tick;}
fn field(block){let i=0;while i<5{if cv(16+i*3)==block{return i;}i=i+1;}check(0);return 0;}
fn esp32_load32(address){
 check(!(ps&8));if address==rv_hal_state+16{return isr;}if address==cv(5){return clock;}if address==cv(6){return source;}if address==cv(3){check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));return select;}if address==cv(4){check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));return routing;}
 check(address==cv(1)||address==cv(2));check((clock&cv(12))==cv(12));if pending{check((source&cv(13))==cv(13));}if foreign==address{return cv(7);}
 if pending==address{if hang==issued&&!release{return cv(7);}if polls{polls=polls-1;return cv(7);}let block=command&255;let reg=(command>>cv(9))&255;let p=memory+block*256+reg;if command&(1<<cv(11)){store8(p,command>>cv(10));}else{command=(command&~(255<<cv(10)))|(load8(p)<<cv(10));}if pending==cv(1){ctrl0=command;}else{ctrl1=command;}pending=0;if alter{select=select^0x80000000;clock=clock^0x40000000;source=source^0x80000000;alter=0;}}
 if address==cv(1){return ctrl0;}return ctrl1;
}
fn esp32_store32(address,value){
 check(!(ps&8));writes=writes+1;value=value&4294967295;if address==cv(5){clock=value;return 0;}if address==cv(6){source_writes=source_writes+1;source=value;return 0;}if address==cv(3){selectors=selectors+1;select=value;return 0;}
 check(address==cv(1)||address==cv(2));check(!pending&&!foreign);check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));let i=field(value&255);check((select&cv(8))==(cv(8)&~(1<<cv(17+i*3))));let expected=cv(2);if routing&(1<<cv(18+i*3)){expected=cv(1);}check(address==expected);check(!(value&~0x1ffffff));command=value;pending=address;polls=1;issued=issued+1;commands=commands+1;return 0;
}
fn reset(seed){check(!esp_radio_regi2c_active);clock=(seed*0x1234567)&4294967295;source=(seed*0x3141592)&4294967295;select=(seed*0x5318429)&4294967295;source_writes=0;routing=0;ctrl0=0;ctrl1=0;foreign=0;pending=0;issued=0;commands=0;writes=0;selectors=0;hang=0;release=0;alter=0;esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;isr=0;ready=1;ps=0x1888;return 0;}
fn clean(c,s,a){check(!esp_radio_regi2c_active&&!esp_radio_regi2c_fault&&ps==0x1888&&!pending);check(clock==c&&source==s&&select==a);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));memory=alloc(65536);reset(17);
 let saved=writes;check(esp_radio_c6_regi2c(0,1,7,0,-1,100)==-22&&writes==saved);check(esp_radio_c6_regi2c(0x6d,-1,7,0,-1,100)==-22);check(esp_radio_c6_regi2c(0x6d,256,7,0,-1,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,8,0,-1,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,1,2,-1,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,1,-1,-1,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,1,0,-2,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,1,0,4,100)==-22);check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,0)==-22);check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,2147483648)==-22);check(esp_radio_c6_regi2c_recover(0)==-22&&writes==saved);
 ready=0;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-95);ready=1;rv_hal_chip=5;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-95);rv_hal_chip=13;
 esp_radio_owner=0;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16);esp_radio_owner=2;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16);esp_radio_owner=1;esp_adc_busy=1;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16);esp_adc_busy=0;esp_radio_phy_refs=1;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16);esp_radio_phy_refs=0;esp_radio_phy_clock_refs=1;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16);esp_radio_phy_clock_refs=0;isr=1;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16&&writes==saved&&ps==0x1888);isr=0;
 let i=0;while i<5{let master=0;while master<2{let value=0;while value<256{
  reset(1+i*23+master*91+value);let block=cv(16+i*3);if !master{routing=1<<cv(18+i*3);}let c=clock;let s=source;let a=select;let p=memory+block*256+value;store8(p,value);
  check(esp_radio_c6_regi2c(block,value,7,0,-1,1000)==value&&commands==1);clean(c,s,a);
  check(!esp_radio_c6_regi2c(block,value,7,0,255-value,1000)&&load8(p)==255-value&&commands==2);clean(c,s,a);
  let lo=0;while lo<8{let hi=lo;while hi<8{let mask=(1<<(hi-lo+1))-1;store8(p,value);let before=commands;check(esp_radio_c6_regi2c(block,value,hi,lo,-1,1000)==((value>>lo)&mask));check(!esp_radio_c6_regi2c(block,value,hi,lo,(value*37+11)&mask,1000));check(load8(p)==((value&~(mask<<lo))|(((value*37+11)&mask)<<lo)));check(commands==before+3-(mask==255));clean(c,s,a);hi=hi+1;}lo=lo+1;}
  value=value+1;}master=master+1;}i=i+1;}
 // A foreign transfer on either engine forbids selector writes and commands.
 i=0;while i<4{reset(23+i);source=(source&~cv(13))|((i&1)*cv(13));let c=clock;let s=source;let a=select;foreign=cv(1+(i>>1));check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16&&!commands&&!selectors&&!source_writes);check(esp_radio_c6_regi2c_idle()==-16&&!commands&&!selectors&&!source_writes);clean(c,s,a);i=i+1;}
 // Completion timeouts hold clock/selector ownership, including after an RMW
 // read. Recovery waits without replaying a possibly committed write.
 let phase=1;while phase<=2{reset(31+phase);source=source|((phase-1)*cv(13));let c=clock;let s=source;let a=select;let p=memory+0x6d*256+7;store8(p,0x25);hang=phase;tick=0xfffffff0;
 check(esp_radio_c6_regi2c(0x6d,7,7,7,1,21)==-110&&esp_radio_regi2c_active&&esp_radio_regi2c_fault&&ps==0x1888);let old=writes;let count=commands;check(count==phase);check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));check(esp_radio_c6_regi2c(0x6d,7,7,7,1,100)==-5&&writes==old&&commands==count);check(esp_radio_c6_regi2c_recover(21)==-110&&writes==old&&commands==count&&esp_radio_regi2c_active);
 esp_adc_busy=1;check(esp_radio_c6_regi2c_recover(100)==-16&&writes==old);esp_adc_busy=0;release=1;check(!esp_radio_c6_regi2c_recover(1000)&&commands==count);clean(c,s,a);check(load8(p)==(0x25+((phase==2)*128)));check(esp_radio_c6_regi2c(0x6d,7,7,0,-1,1000)==load8(p));clean(c,s,a);phase=phase+1;}
 reset(51);let c=clock;let s=source;let a=select;alter=1;check(!esp_radio_c6_regi2c(0x6d,14,7,0,128,100));clean(c^0x40000000,s^0x80000000,a^0x80000000);
 reset(69);ps=0x1880;check(!esp_radio_c6_regi2c(0x6d,14,7,0,128,100)&&ps==0x1880);ps=0x1888;
 reset(73);esp_radio_regi2c_active=1;check(esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16&&!writes);check(esp_radio_c6_regi2c_recover(100)==-16&&!writes);esp_radio_regi2c_active=0;check(!esp_radio_c6_regi2c_recover(100)&&!writes);let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
