import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-pmu-stage.flex";
global power_bank=0;global power_before=0;global power_writes=0;global power_hang= -1;global power_release=0;global power_late=0;
global stage_seed=0;global cfg=0;global memory=0;global checks=0;global ps=0x1888;global tick=0;global ready=1;global isr=0;
global clock=0;global source=0;global source_writes=0;global select=0;global routing=0;global ctrl0=0;global ctrl1=0;global foreign=0;global pending=0;global command=0;global polls=0;global hang=0;global release=0;global issued=0;global writes=0;global selectors=0;global commands=0;global alter=0;
global esp_radio_hw_ready=0;global pmu_bank=0;global pmu_before=0;global rf=0;global rf_old=0;
global reset_reason=1;global reset_reads=0;global fuse_reads=0;global fuse_version=0x18000000;global fuse_code=0;global trim_code_writes=0;global trim_force_writes=0;
global digital_writes=0;global rf_writes=0;global total_writes=0;global restoring=0;
// The host oracle injects allocator results at this boundary; firmware tests
// separately exhaust the real RV32 native heap without replacing alloc.
global pmu_allocation_result=0;global pmu_allocation_calls=0;
fn pmu_test_alloc(size){pmu_allocation_calls=pmu_allocation_calls+1;if pmu_allocation_result{return pmu_allocation_result;}return alloc(size);}
fn tv(i){return cv(194+i);}
fn esp32_call32(address,a,b,c,d,e,f,g,h){check(address==tv(12) && !a && !b && !c && !d && !e && !f && !g && !h && !(ps&8));reset_reads=reset_reads+1;return reset_reason;}
fn cv(i){return load64(cfg+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("regi2c check ",h_int(checks)," failed\n"));h_print(2,h_cat3("seed ",h_int(stage_seed),h_cat3(" command ",h_int(issued),"\n")));syscall(60,1,0,0,0,0,0);}return 0;}
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
 check(!(ps&8));
 if (address==cv(1)||address==cv(2)) && (value&255)==tv(5) && (value&(1<<cv(11))){
  let reg=(value>>cv(9))&255;if reg==tv(6){trim_code_writes=trim_code_writes+1;}else{check(reg==tv(9));trim_force_writes=trim_force_writes+1;check(load8(memory+tv(5)*256+tv(6))==fuse_code || restoring);}
 }
 writes=writes+1;value=value&4294967295;if address==cv(5){clock=value;return 0;}if address==cv(6){source_writes=source_writes+1;source=value;return 0;}if address==cv(3){selectors=selectors+1;select=value;return 0;}
 check(address==cv(1)||address==cv(2));check(!pending&&!foreign);check((clock&cv(12))==cv(12)&&(source&cv(13))==cv(13));let i=field(value&255);check((select&cv(8))==(cv(8)&~(1<<cv(17+i*3))));let expected=cv(2);if routing&(1<<cv(18+i*3)){expected=cv(1);}check(address==expected);check(!(value&~0x1ffffff));command=value;pending=address;polls=1;issued=issued+1;commands=commands+1;return 0;
}
fn reset(seed){check(!esp_radio_regi2c_active);clock=(seed*0x1234567)&4294967295;source=(seed*0x3141592)&4294967295;select=(seed*0x5318429)&4294967295;source_writes=0;routing=0;ctrl0=0;ctrl1=0;foreign=0;pending=0;issued=0;commands=0;writes=0;selectors=0;hang=0;release=0;alter=0;esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;isr=0;ready=1;ps=0x1888;return 0;}
fn clean(c,s,a){check(!esp_radio_regi2c_active&&!esp_radio_regi2c_fault&&ps==0x1888&&!pending);check(clock==c&&source==s&&select==a);return 0;}
fn pv(row,field){return cv(35+row*3+field);}
fn av(row,field){return cv(182+row*4+field);}
fn pmu_row(address){let i=0;while i<49{if pv(i,0)==address{return i;}i=i+1;}return -1;}
fn power_row(address){let row=0;while row<6{if esp_radio_c6_power_address(row)==address{return row;}row=row+1;}return -1;}
fn esp32_load32(address){
 let power=power_row(address);if power>=0{check(!(ps&8));if power_late{power_late=power_late-1;if !power_late{tick=(tick+100)&0xffffffff;}}return load64(power_bank+power*8);}
 check(!(ps&8));if address==cv(33){fuse_reads=fuse_reads+1;return fuse_version;}if address==cv(34){return 25|(28<<5);}if address==tv(1){fuse_reads=fuse_reads+1;return (fuse_code<<tv(4))|0xa5a00000|0x1ff;}
 if address==cv(31){return rf;}let i=pmu_row(address);if i>=0{return load64(pmu_bank+i*8);}return bus_read(address);
}
fn esp32_store32(address,value){
 check(!(ps&8));value=value&4294967295;total_writes=total_writes+1;let power=power_row(address);if power>=0{check(esp_radio_pmu_active && value!=load64(power_bank+power*8));if restoring{check(!esp_radio_pmu_digital_count && !esp_radio_pmu_analog_count && !pending && !esp_radio_ocode_active);}else{check(esp_radio_pmu_digital_count==49 && esp_radio_pmu_analog_count==3);}power_writes=power_writes+1;if power_hang==power && !power_release{return 0;}store64(power_bank+power*8,value);return 0;}
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
 stage_seed=seed;if !power_bank{power_bank=alloc(48);power_before=alloc(48);}power_writes=0;power_hang= -1;power_release=0;power_late=0;esp_radio_pmu_force_count=0;let pr=0;while pr<6{let v=((seed+1)*0x31415927+pr*0x1234567)&0xffffffff;if pr<3{v=v&~35;}if pr==4{v=v&~15;}store64(power_bank+pr*8,v);store64(power_before+pr*8,v);pr=pr+1;}
 check(!esp_radio_ocode_active);esp_radio_ocode_ready=0;esp_radio_ocode_phase=0;esp_radio_ocode_count=0;reset_reason=1;fuse_version=3<<27;fuse_code=0;trim_code_writes=0;trim_force_writes=0;reset(seed);esp_radio_hw_ready=0;esp_radio_pmu_active=0;esp_radio_pmu_internal=0;esp_radio_pmu_phase=0;esp_radio_pmu_analog_count=0;esp_radio_pmu_digital_count=0;esp_radio_pmu_configured=0;
 digital_writes=0;rf_writes=0;total_writes=0;restoring=0;rf=((seed+1)*0x31415927)&4294967295;rf_old=rf;
 let i=0;while i<49{let v=((seed+1)*0x1234567+i*0x31415927)&4294967295;store64(pmu_before+i*8,v);store64(pmu_bank+i*8,v);i=i+1;}
 i=0;while i<3{store8(memory+0x6d*256+av(i,0),value);i=i+1;}return 0;
}
fn staged(value){
 check(esp_radio_pmu_active && !esp_radio_pmu_internal && esp_radio_pmu_phase==1 && esp_radio_pmu_analog_count==3 && esp_radio_pmu_digital_count==49 && !esp_radio_pmu_configured);
 check(esp_radio_pmu_force_count==6);let pr=0;while pr<6{check(load64(power_bank+pr*8)==(load64(power_before+pr*8)&~esp_radio_c6_power_mask(pr)));pr=pr+1;}
 check(digital_writes==49 && rf_writes==1 && commands==9 && ps==0x1888);
 let i=0;while i<49{check(load64(pmu_bank+i*8)==((load64(pmu_before+i*8)&~pv(i,1))|pv(i,2)));i=i+1;}
 i=0;while i<3{let mask=((1<<(av(i,1)-av(i,2)+1))-1)<<av(i,2);check(load8(memory+0x6d*256+av(i,0))==((value&~mask)|(av(i,3)<<av(i,2))));i=i+1;}check(rf==(rf_old|cv(32)));return 0;
}
fn restored(value,changed){
 check(!esp_radio_pmu_active && !esp_radio_pmu_internal && !esp_radio_pmu_phase && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count && !esp_radio_regi2c_active && !pending && ps==0x1888);
 let i=0;while i<49{check(load64(pmu_bank+i*8)==(load64(pmu_before+i*8)^(changed&~pv(i,1))));i=i+1;}
 i=0;while i<3{let mask=((1<<(av(i,1)-av(i,2)+1))-1)<<av(i,2);check(load8(memory+0x6d*256+av(i,0))==(value^(changed&255&~mask)));i=i+1;}
 check(!esp_radio_pmu_force_count);let pr=0;while pr<6{check(load64(power_bank+pr*8)==load64(power_before+pr*8));pr=pr+1;}
 check(rf==(rf_old^(changed&~cv(32))));return 0;
}
fn force_different(){store8(memory+0x6d*256+av(0,0),0);store8(memory+0x6d*256+av(1,0),0);store8(memory+0x6d*256+av(2,0),255);return 0;}
fn different_restored(){check(load8(memory+0x6d*256+av(0,0))==0 && load8(memory+0x6d*256+av(1,0))==0 && load8(memory+0x6d*256+av(2,0))==255);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==207*8);memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);stage_reset(17,0);
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
 // All reset reasons retain analog state unless the ROM reports power-on.
 let reason=0;while reason<256{if reason!=1{
  stage_reset(211+reason,85);check(!esp_radio_c6_pmu_stage(1000));reset_reason=reason;let before=total_writes;let reads=fuse_reads;let calls=reset_reads;
  check(!esp_radio_c6_ocode_stage(1000) && esp_radio_ocode_ready && !esp_radio_ocode_active && fuse_reads==reads && reset_reads==calls+1 && total_writes==before);
  check(esp_radio_c6_ocode_stage(1000)==-16 && total_writes==before);restoring=1;check(!esp_radio_c6_pmu_abort(1000) && !esp_radio_ocode_ready);
 }reason=reason+1;}
 // Every encoded block version chooses fused trim except exactly0.0.
 let version=0;while version<32{
  stage_reset(241+version,85);check(!esp_radio_c6_pmu_stage(1000));fuse_version=((version>>3)<<tv(2))|((version&7)<<tv(3));fuse_code=0xa7;
  let reads=fuse_reads;let before=total_writes;let result=esp_radio_c6_ocode_stage(1000);
  if !version{check(result==-95 && !esp_radio_ocode_active && !esp_radio_ocode_ready && fuse_reads==reads+1 && total_writes==before);}
  else{check(!result && esp_radio_ocode_active && esp_radio_ocode_ready && fuse_reads==reads+2);}
  restoring=1;check(!esp_radio_c6_pmu_abort(1000) && !esp_radio_ocode_active);
  version=version+1;
 }
 // Full trim bytes, both old force values, unrelated bits and IRQ states.
 let value=0;while value<256{mode=0;while mode<4{
  stage_reset(277+value+mode,85);check(!esp_radio_c6_pmu_stage(1000));let data=memory+tv(5)*256;let prior=(value*37+11)&255;let force=0xa5^(mode&1)*(1<<tv(11));store8(data+tv(6),prior);store8(data+tv(9),force);fuse_code=value;
  if mode&2{ps=0x1880;}let saved_ps=ps;let c=clock;let s=source;let a=select;
  check(!esp_radio_c6_ocode_stage(1000) && ps==saved_ps && esp_radio_ocode_ready && esp_radio_ocode_active && esp_radio_ocode_count==2);
  check(load8(data+tv(6))==value && load8(data+tv(9))==(force|(1<<tv(11))) && clock==c && source==s && select==a);
  let before=total_writes;check(esp_radio_c6_ocode_stage(1000)==-16 && total_writes==before);
  // Foreign changes outside the owned force bit survive rollback.
  store8(data+tv(9),load8(data+tv(9))^0x95);restoring=1;check(!esp_radio_c6_pmu_abort(1000) && ps==saved_ps);
  check(load8(data+tv(6))==prior && load8(data+tv(9))==(force^0x95) && !esp_radio_ocode_active && !esp_radio_ocode_ready && !esp_radio_pmu_active);
  ps=0x1888;mode=mode+1;
 }value=value+1;}
 // Every snapshot/preparation command and rollback command can time out.
 phase=1;while phase<=5{
  stage_reset(311+phase,85);check(!esp_radio_c6_pmu_stage(1000));let data=memory+tv(5)*256;store8(data+tv(6),85);store8(data+tv(9),0);fuse_code=0xa7;hang=issued+phase;tick=0xfffffff0;
  check(esp_radio_c6_ocode_stage(21)==-110 && esp_radio_ocode_active && esp_radio_ocode_phase==2 && esp_radio_pmu_active && ps==0x1888);
  check(esp_radio_c6_pmu_commit()==-16);let count=commands;let before=total_writes;restoring=1;
  check(esp_radio_c6_pmu_abort(21)==-110 && commands==count && total_writes==before && esp_radio_pmu_digital_count==49 && esp_radio_ocode_active);
  release=1;let recover_ps=esp32_irq_save();esp_radio_pmu_internal=1;check(!esp_radio_c6_regi2c_recover(1000));esp_radio_pmu_internal=0;esp32_irq_restore(recover_ps);
  check(esp_radio_c6_pmu_commit()==-16 && esp_radio_ocode_active && esp_radio_pmu_active);
  check(!esp_radio_c6_pmu_abort(1000) && load8(data+tv(6))==85 && !load8(data+tv(9)) && !esp_radio_ocode_active && !esp_radio_pmu_active);
  phase=phase+1;
 }
 phase=1;while phase<=5{
  stage_reset(337+phase,85);check(!esp_radio_c6_pmu_stage(1000));let data=memory+tv(5)*256;store8(data+tv(6),85);store8(data+tv(9),0);fuse_code=0xa7;check(!esp_radio_c6_ocode_stage(1000));hang=issued+phase;restoring=1;
  check(esp_radio_c6_pmu_abort(21)==-110 && esp_radio_ocode_active && esp_radio_pmu_digital_count==49 && esp_radio_c6_pmu_commit()==-16);
  let count=commands;let before=total_writes;check(esp_radio_c6_pmu_abort(21)==-110 && commands==count && total_writes==before);
  release=1;check(!esp_radio_c6_pmu_abort(1000));check(load8(data+tv(6))==85 && !load8(data+tv(9)) && trim_code_writes==2 && trim_force_writes==2 && !esp_radio_ocode_active && !esp_radio_pmu_active);phase=phase+1;
 }
 // Expected reset/fuse decisions and trim writes come from the actual
 // pinned pmu_init/ocode_init C functions, with their hardware effects stubbed.
 let policy=h_read(load64(argv+16));let rows=load64(policy);check(h_file_size==8+rows*56 && rows==32768);let at=policy+8;let vector=0;
 while vector<rows{
  stage_reset(401+vector,85);check(!esp_radio_c6_pmu_stage(1000));reset_reason=load64(at);let encoded=load64(at+8);fuse_version=((encoded>>3)<<tv(2))|((encoded&7)<<tv(3));fuse_code=load64(at+16);let expected=load64(at+24);let before=total_writes;let reads=fuse_reads;
  let status=esp_radio_c6_ocode_stage(1000);
  if expected==2{check(status==-95 && !esp_radio_ocode_active && !esp_radio_ocode_ready && total_writes==before && fuse_reads==reads+1);}
  else{
   check(!status && esp_radio_ocode_ready && esp_radio_ocode_active==(expected==1));
   if expected{let data=memory+tv(5)*256;check(load64(at+32)==2 && load8(data+tv(6))==load64(at+40) && ((load8(data+tv(9))>>tv(11))&1)==load64(at+48) && fuse_reads==reads+2);}
   else{check(!load64(at+32) && fuse_reads==reads && total_writes==before);}
  }
  restoring=1;check(!esp_radio_c6_pmu_abort(1000));at=at+56;vector=vector+1;
 }
 // A completed trim is retained only by the enclosing atomic PMU commit.
 stage_reset(359,85);check(esp_radio_c6_ocode_stage(0)==-22 && esp_radio_c6_ocode_abort(0)==-22 && esp_radio_c6_ocode_stage(1000)==-16 && esp_radio_c6_ocode_abort(1000)==-16);
 check(!esp_radio_c6_pmu_stage(1000));fuse_code=0xa7;check(!esp_radio_c6_ocode_stage(1000));let trim_before=total_writes;
 check(!esp_radio_c6_pmu_commit() && esp_radio_pmu_configured && esp_radio_ocode_ready && !esp_radio_ocode_active && !esp_radio_ocode_phase && !esp_radio_ocode_count && total_writes==trim_before);check(esp_radio_c6_ocode_abort(1000)==-16 && total_writes==trim_before);
 stage_reset(151,0);check(esp_radio_c6_pmu_commit()==-16);check(!esp_radio_c6_pmu_stage(1000));let before=total_writes;check(!esp_radio_c6_pmu_commit() && esp_radio_pmu_configured && !esp_radio_pmu_active && !esp_radio_pmu_phase && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count && total_writes==before);check(esp_radio_c6_pmu_stage(1000)==-16 && !esp_radio_c6_pmu_abort(1000) && total_writes==before);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
