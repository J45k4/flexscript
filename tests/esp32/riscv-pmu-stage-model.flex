import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-pmu-stage.flex";
global cfg=0;global memory=0;global checks=0;global ps=0x1888;global tick=0;global ready=1;global isr=0;
global clock=0;global source=0;global source_writes=0;global select=0;global routing=0;global ctrl0=0;global ctrl1=0;global foreign=0;global pending=0;global command=0;global polls=0;global hang=0;global release=0;global issued=0;global writes=0;global selectors=0;global commands=0;global alter=0;
global esp_radio_hw_ready=0;global pmu_bank=0;global pmu_before=0;global rf=0;global rf_old=0;
global digital_writes=0;global rf_writes=0;global total_writes=0;global restoring=0;
// The host oracle injects allocator results at this boundary; firmware tests
// separately exhaust the real RV32 native heap without replacing alloc.
global pmu_allocation_result=0;global pmu_allocation_calls=0;
fn pmu_test_alloc(size){pmu_allocation_calls=pmu_allocation_calls+1;if pmu_allocation_result{return pmu_allocation_result;}return alloc(size);}
fn cv(i){return load64(cfg+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("regi2c check ",h_int(checks)," failed\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if ready{return rv_hal_state;}return 0;}
fn esp32_irq_save(){check(!(ps&8) || !esp_radio_pmu_internal);let before=ps;ps=ps&~8;return before;}
fn esp32_irq_restore(value){check(!(value&8) || !esp_radio_pmu_internal);ps=value;return 0;}
fn esp32_cycles(){tick=(tick+7)&4294967295;return tick;}
fn field(block){let i=0;while i<5{if cv(16+i*3)==block{return i;}i=i+1;}check(0);return 0;}
fn bus_read(address){
 check(!(ps&8));if address==rv_hal_state+16{return isr;}if address==cv(5){return clock;}if address==cv(6){return source;}if address==cv(3){check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));return select;}if address==cv(4){check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));return routing;}
 check(address==cv(1)||address==cv(2));check((clock&cv(12))==cv(12));if pending{check((source&cv(13))==cv(13));}if foreign==address{return cv(7);}
 if pending==address{if hang==issued&&!release{return cv(7);}if polls{polls=polls-1;return cv(7);}let block=command&255;let reg=(command>>cv(9))&255;let p=memory+block*256+reg;if command&(1<<cv(11)){store8(p,command>>cv(10));}else{command=(command&~(255<<cv(10)))|(load8(p)<<cv(10));}if pending==cv(1){ctrl0=command;}else{ctrl1=command;}pending=0;if alter{select=select^0x80000000;clock=clock^0x40000000;source=source^0x80000000;alter=0;}}
 if address==cv(1){return ctrl0;}return ctrl1;
}
fn bus_write(address,value){
 check(!(ps&8));writes=writes+1;value=value&4294967295;if address==cv(5){clock=value;return 0;}if address==cv(6){source_writes=source_writes+1;source=value;return 0;}if address==cv(3){selectors=selectors+1;select=value;return 0;}
 check(address==cv(1)||address==cv(2));check(!pending&&!foreign);check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));let i=field(value&255);check((select&cv(8))==(cv(8)&~(1<<cv(17+i*3))));let expected=cv(2);if routing&(1<<cv(18+i*3)){expected=cv(1);}check(address==expected);check(!(value&~0x1ffffff));command=value;pending=address;polls=1;issued=issued+1;commands=commands+1;return 0;
}
fn reset(seed){check(!esp_radio_regi2c_active);clock=(seed*0x1234567)&4294967295;source=(seed*0x3141592)&4294967295;select=(seed*0x5318429)&4294967295;source_writes=0;routing=0;ctrl0=0;ctrl1=0;foreign=0;pending=0;issued=0;commands=0;writes=0;selectors=0;hang=0;release=0;alter=0;esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;isr=0;ready=1;ps=0x1888;return 0;}
fn clean(c,s,a){check(!esp_radio_regi2c_active&&!esp_radio_regi2c_fault&&ps==0x1888&&!pending);check(clock==c&&source==s&&select==a);return 0;}
fn pv(row,field){return cv(35+row*3+field);}
fn av(row,field){return cv(182+row*4+field);}
fn pmu_row(address){let i=0;while i<49{if pv(i,0)==address{return i;}i=i+1;}return -1;}
fn esp32_load32(address){
 check(!(ps&8));if address==cv(33){return 3<<27;}if address==cv(34){return 25|(28<<5);}
 if address==cv(31){return rf;}let i=pmu_row(address);if i>=0{return load64(pmu_bank+i*8);}return bus_read(address);
}
fn esp32_store32(address,value){
 check(!(ps&8));value=value&4294967295;total_writes=total_writes+1;
 if address==cv(31){rf_writes=rf_writes+1;check(esp_radio_pmu_active);rf=value;return 0;}
 let i=pmu_row(address);if i>=0{
  check(esp_radio_pmu_active && !pending && esp_radio_pmu_analog_count==3);
  let expected=digital_writes;if restoring{expected=48-(digital_writes-49);}check(i==expected);
  digital_writes=digital_writes+1;store64(pmu_bank+i*8,value);return 0;
 }
 if address==cv(1)||address==cv(2){check((rf&cv(32))==cv(32));}
 return bus_write(address,value);
}
fn stage_reset(seed,value){
 reset(seed);esp_radio_hw_ready=0;esp_radio_pmu_active=0;esp_radio_pmu_internal=0;esp_radio_pmu_phase=0;esp_radio_pmu_analog_count=0;esp_radio_pmu_digital_count=0;esp_radio_pmu_configured=0;
 digital_writes=0;rf_writes=0;total_writes=0;restoring=0;rf=((seed+1)*0x31415927)&4294967295;rf_old=rf;
 let i=0;while i<49{let v=((seed+1)*0x1234567+i*0x31415927)&4294967295;store64(pmu_before+i*8,v);store64(pmu_bank+i*8,v);i=i+1;}
 i=0;while i<3{store8(memory+0x6d*256+av(i,0),value);i=i+1;}return 0;
}
fn staged(value){
 check(esp_radio_pmu_active && !esp_radio_pmu_internal && esp_radio_pmu_phase==1 && esp_radio_pmu_analog_count==3 && esp_radio_pmu_digital_count==49 && !esp_radio_pmu_configured);
 check(digital_writes==49 && rf_writes==1 && commands==9 && ps==0x1888);
 let i=0;while i<49{check(load64(pmu_bank+i*8)==((load64(pmu_before+i*8)&~pv(i,1))|pv(i,2)));i=i+1;}
 i=0;while i<3{let mask=((1<<(av(i,1)-av(i,2)+1))-1)<<av(i,2);check(load8(memory+0x6d*256+av(i,0))==((value&~mask)|(av(i,3)<<av(i,2))));i=i+1;}check(rf==(rf_old|cv(32)));return 0;
}
fn restored(value,changed){
 check(!esp_radio_pmu_active && !esp_radio_pmu_internal && !esp_radio_pmu_phase && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count && !esp_radio_regi2c_active && !pending && ps==0x1888);
 let i=0;while i<49{check(load64(pmu_bank+i*8)==(load64(pmu_before+i*8)^(changed&~pv(i,1))));i=i+1;}
 i=0;while i<3{let mask=((1<<(av(i,1)-av(i,2)+1))-1)<<av(i,2);check(load8(memory+0x6d*256+av(i,0))==(value^(changed&255&~mask)));i=i+1;}
 check(rf==(rf_old^(changed&~cv(32))));return 0;
}
fn force_different(){store8(memory+0x6d*256+av(0,0),0);store8(memory+0x6d*256+av(1,0),0);store8(memory+0x6d*256+av(2,0),255);return 0;}
fn different_restored(){check(load8(memory+0x6d*256+av(0,0))==0 && load8(memory+0x6d*256+av(1,0))==0 && load8(memory+0x6d*256+av(2,0))==255);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==194*8);memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);stage_reset(17,0);
 check(esp_radio_c6_pmu_stage(0)==-22 && esp_radio_c6_pmu_abort(2147483648)==-22 && !total_writes);
 check(esp_radio_c6_pmu_analog(-1,1,100)==-22 && esp_radio_c6_pmu_analog(3,1,100)==-22 && esp_radio_c6_pmu_analog(0,1,100)==-16 && !total_writes);
 ready=0;check(esp_radio_c6_pmu_stage(100)==-95 && !total_writes);ready=1;rv_hal_chip=5;check(esp_radio_c6_pmu_stage(100)==-95 && esp_radio_c6_pmu_abort(100)==-95 && !total_writes);rv_hal_chip=13;
 let guard=0;while guard<6{
  esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_radio_hw_ready=0;isr=0;
  if guard==0{esp_radio_owner=0;}if guard==1{esp_adc_busy=1;}if guard==2{esp_radio_phy_refs=1;}if guard==3{esp_radio_phy_clock_refs=1;}if guard==4{esp_radio_hw_ready=1;}if guard==5{isr=1;}
  check(esp_radio_c6_pmu_stage(100)==-16 && esp_radio_c6_pmu_abort(100)==-16 && !total_writes);guard=guard+1;
 }
 // Failed allocations leave the unpublished snapshot and PMU lease untouched,
 // preserve both IRQ states, and permit a later successful allocation/reuse.
 let mode=0;while mode<2{
  stage_reset(181+mode,85);if mode{ps=0x1880;}let saved_ps=ps;
  let attempt=0;while attempt<3{
   pmu_allocation_result= -12;if attempt==1{pmu_allocation_result= -1;}
   let c=clock;let s=source;let a=select;let calls=pmu_allocation_calls;
   check(esp_radio_c6_pmu_stage(1000)==-12 && pmu_allocation_calls==calls+1);
   check(!esp_radio_pmu_saved && !esp_radio_pmu_active && !esp_radio_pmu_phase && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count && !esp_radio_regi2c_active && esp_radio_owner==1 && ps==saved_ps);
   check(!rf_writes && !digital_writes && !commands && !selectors && !source_writes && clock==c && source==s && select==a);attempt=attempt+1;
  }
  pmu_allocation_result=0;check(!esp_radio_c6_pmu_stage(1000) && esp_radio_pmu_saved>0 && ps==saved_ps);
  let snapshot=esp_radio_pmu_saved;restoring=1;check(!esp_radio_c6_pmu_abort(1000) && ps==saved_ps);
  ps=0x1888;stage_reset(191+mode,85);if mode{ps=0x1880;}let calls=pmu_allocation_calls;pmu_allocation_result= -12;
  check(!esp_radio_c6_pmu_stage(1000) && esp_radio_pmu_saved==snapshot && pmu_allocation_calls==calls && ps==saved_ps);
  restoring=1;check(!esp_radio_c6_pmu_abort(1000) && ps==saved_ps);pmu_allocation_result=0;esp_radio_pmu_saved=0;mode=mode+1;
 }
 mode=0;while mode<8{let value=0;while value<256{
  stage_reset(19+mode+value,value);if mode&1{routing=1<<cv(30);}source=(source&~1)|((mode>>1)&1);clock=(clock&~4)|((mode&4));let c=clock;let s=source;let a=select;
  check(!esp_radio_c6_pmu_stage(1000));staged(value);let before=total_writes;check(esp_radio_c6_pmu_stage(1000)==-16 && esp_radio_c6_regi2c(0x6d,0,7,0,-1,100)==-16 && total_writes==before);
  restoring=1;check(!esp_radio_c6_pmu_abort(1000));restored(value,0);clean(c,s,a);check(digital_writes==98 && rf_writes==2);before=total_writes;check(!esp_radio_c6_pmu_abort(1000) && total_writes==before);value=value+1;
 }mode=mode+1;}
 // Preserve unrelated fields changed while a complete staged state is held.
 stage_reset(79,165);check(!esp_radio_c6_pmu_stage(1000));let i=0;let changed=0xa5a5a5a5;
 while i<49{store64(pmu_bank+i*8,load64(pmu_bank+i*8)^(changed&~pv(i,1)));i=i+1;}
 i=0;while i<3{let mask=((1<<(av(i,1)-av(i,2)+1))-1)<<av(i,2);let p=memory+0x6d*256+av(i,0);store8(p,load8(p)^(changed&255&~mask));i=i+1;}rf=rf^(changed&~cv(32));restoring=1;check(!esp_radio_c6_pmu_abort(1000));restored(165,changed);
 // Every preparation read/write can time out before or after its effect.
 let phase=1;while phase<=9{
  stage_reset(83+phase,85);let c=clock;let s=source;let a=select;hang=phase;tick=0xfffffff0;
  check(esp_radio_c6_pmu_stage(21)==-110 && esp_radio_pmu_active && esp_radio_regi2c_active && esp_radio_pmu_phase==2 && !digital_writes && ps==0x1888);
  let count=commands;let before=total_writes;check(esp_radio_c6_pmu_abort(21)==-110 && esp_radio_c6_pmu_commit()==-16 && commands==count && total_writes==before && esp_radio_pmu_active);
  release=1;restoring=1;check(!esp_radio_c6_pmu_abort(1000));restored(85,0);clean(c,s,a);phase=phase+1;
 }
 // A timeout while restoring is also a retained, readback-recoverable lease.
 phase=10;while phase<=18{
  stage_reset(101+phase,0);force_different();let c=clock;let s=source;let a=select;check(!esp_radio_c6_pmu_stage(1000));hang=phase;restoring=1;
  check(esp_radio_c6_pmu_abort(21)==-110 && esp_radio_pmu_active && esp_radio_pmu_phase==2 && !esp_radio_pmu_digital_count);
  let count=commands;let before=total_writes;check(esp_radio_c6_pmu_abort(21)==-110 && commands==count && total_writes==before);release=1;check(!esp_radio_c6_pmu_abort(1000));if phase%3==0{check(commands==19);}different_restored();clean(c,s,a);phase=phase+1;
 }
 // Foreign busy engines are refused before any PMU/RF/selector publication.
 mode=0;while mode<4{stage_reset(127+mode,0);source=(source&~1)|(mode&1);let c=clock;let s=source;let a=select;foreign=cv(1+(mode>>1));check(esp_radio_c6_pmu_stage(1000)==-16 && !rf_writes && !digital_writes && !commands && !selectors && !source_writes && !esp_radio_pmu_active);clean(c,s,a);mode=mode+1;}
 stage_reset(149,0);ps=0x1880;check(!esp_radio_c6_pmu_stage(1000) && ps==0x1880);restoring=1;check(!esp_radio_c6_pmu_abort(1000) && ps==0x1880);ps=0x1888;
 stage_reset(150,0);check(!esp_radio_c6_pmu_stage(1000));hang=10;check(esp_radio_c6_pmu_analog(0,-1,21)==-110 && esp_radio_regi2c_active);check(esp_radio_c6_pmu_commit()==-16 && esp_radio_pmu_active && !esp_radio_pmu_configured);release=1;restoring=1;check(!esp_radio_c6_pmu_abort(1000));restored(0,0);
 stage_reset(151,0);check(esp_radio_c6_pmu_commit()==-16);check(!esp_radio_c6_pmu_stage(1000));let before=total_writes;check(!esp_radio_c6_pmu_commit() && esp_radio_pmu_configured && !esp_radio_pmu_active && !esp_radio_pmu_phase && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count && total_writes==before);check(esp_radio_c6_pmu_stage(1000)==-16 && !esp_radio_c6_pmu_abort(1000) && total_writes==before);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
