// Combined with the independently generated PMU/PLL model helpers.
global cal_meta=0;global cal_flags=9;global cal_running=0;global cal_reset_writes=0;global cal_starts=0;global cal_reads=0;global cal_old_reset=0;global cal_reserved=0;global cal_status_old=0;
fn ocv(i){return load64(cal_meta+i*8);}
fn cal_commit(command){
 let reg=(command>>cv(9))&255;if reg!=ocv(1){return 0;}
 check(!(pll_power&pcv(12)) && (clock&cv(12))==cv(12) && !(ps&8) && esp_radio_ocode_legacy && esp_radio_ocode_count==3);
 let value=(command>>cv(10))&255;let p=memory+ocv(0)*256+reg;let old=load8(p);check(!((value^old)&~(1<<ocv(2))));cal_reset_writes=cal_reset_writes+1;
 if !(value&(1<<ocv(2))){cal_running=0;store8(memory+ocv(0)*256+ocv(3),cal_status_old&~ocv(6));}
 if !(old&(1<<ocv(2))) && (value&(1<<ocv(2))){cal_running=1;cal_starts=cal_starts+1;}
 return 0;
}
fn cal_read(block,reg){
 if block==ocv(0) && reg==ocv(3){
  check(!(pll_power&pcv(12)) && (clock&cv(12))==cv(12) && esp_radio_ocode_legacy && !(ps&8));cal_reads=cal_reads+1;
  if cal_running{store8(memory+block*256+reg,(cal_status_old&~ocv(6))|(cal_flags&ocv(6)));if (cal_flags&ocv(6))==ocv(6){cal_running=0;}}
 }
 return 0;
}
fn cal_reset(mode){
 check(!esp_radio_ocode_active && !esp_radio_ocode_legacy);pll_case=mode;pll_reset(1401+mode,(mode>>4)&1,1,1,(mode>>5)&1,(mode>>3)&1);
 clock=(clock&~cv(12))|((mode>>1)&1)*cv(12);pll_master_before=clock;if mode&4{routing=1<<cv(21);}
 reset_reason=1;fuse_version=0;let p=memory+ocv(0)*256+ocv(1);cal_old_reset=mode&1;cal_reserved=(mode*7)&254;store8(p,cal_reserved|cal_old_reset);
 store8(memory+ocv(0)*256+5,0x9b);store8(memory+ocv(0)*256+6,mode^0xa5);cal_status_old=0xa6;store8(memory+ocv(0)*256+ocv(3),cal_status_old|cal_old_reset*ocv(6));cal_running=0;cal_flags=ocv(6);cal_reset_writes=0;cal_starts=0;cal_reads=0;
 return 0;
}
fn cal_assert_reset(before){check(load8(memory+ocv(0)*256+ocv(1))==(cal_reserved|before));return 0;}
fn cal_finish(old,ana,mspi){check(!esp_radio_ocode_active && !esp_radio_ocode_legacy && !cal_running && ps==0x1880);pll_finish(old,ana,mspi);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==3504);pll_meta=cfg+207*8;cal_meta=cfg+2656;memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);pll_consumers=alloc(120);
 let mode=0;while mode<64{cal_reset(mode);let old=pll_power;let ana=pll_ana;let mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));
  check(!esp_radio_c6_ocode_legacy_stage(1000) && esp_radio_ocode_ready && !esp_radio_ocode_active && !esp_radio_ocode_legacy && cal_reset_writes==2 && cal_starts==1 && cal_reads==1 && ps==0x1880);cal_assert_reset(1);
  check(esp_radio_c6_ocode_legacy_stage(1000)==-16);cal_finish(old,ana,mspi);cal_assert_reset(1);mode=mode+1;
 }
 // All vendor O_DONE/BG_O_DONE combinations; other status bits are ignored.
 let flags=0;while flags<16{cal_reset(301+(flags&1));let old=pll_power;let ana=pll_ana;let mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));cal_flags=flags;let expected=load64(cal_meta+80+flags*48+8);
  let result=esp_radio_c6_ocode_legacy_stage(400);
  if expected{check(!result && esp_radio_ocode_ready);cal_assert_reset(1);}else{
   check(result==-110 && esp_radio_ocode_active && esp_radio_ocode_legacy && !esp_radio_ocode_ready && ps==0x1880);
   check(esp_radio_c6_pll_restore(1000)==-16 && esp_radio_c6_clock_restore(1000)==-16 && esp_radio_c6_pmu_abort(1000)==-16 && esp_radio_c6_pmu_commit()==-16);
   cal_flags=ocv(6);check(!esp_radio_c6_ocode_legacy_abort(1000));cal_assert_reset(cal_old_reset);
  }cal_finish(old,ana,mspi);flags=flags+1;
 }
 // Retained-reset/factory policy refusal never pulses reset; bad ROM words fail.
 cal_reset(402);let old=pll_power;let ana=pll_ana;let mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));
 let reason=0;while reason<256{if reason!=1{reset_reason=reason;let reads=fuse_reads;check(esp_radio_c6_ocode_legacy_stage(1000)==-95 && fuse_reads==reads && !cal_reset_writes && !esp_radio_ocode_active);}reason=reason+1;}
 reset_reason=1;let version=1;while version<32{fuse_version=version<<27;check(esp_radio_c6_ocode_legacy_stage(1000)==-95 && !cal_reset_writes && !esp_radio_ocode_active);version=version+1;}
 reset_reason=256;check(esp_radio_c6_ocode_legacy_stage(1000)==-5 && !cal_reset_writes);reset_reason=1;fuse_version=0;cal_finish(old,ana,mspi);
 // Every snapshot/reset/status bus command may time out and then recover.
 let phase=1;while phase<=7{cal_reset(500+(phase&1));old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));hang=issued+phase;
  check(esp_radio_c6_ocode_legacy_stage(1000)==-110 && esp_radio_ocode_active && ps==0x1880);let count=commands;
  check(esp_radio_c6_ocode_legacy_abort(1000)==-110 && commands==count && esp_radio_ocode_active);release=1;check(!esp_radio_c6_ocode_legacy_abort(1000));cal_assert_reset(cal_old_reset);cal_finish(old,ana,mspi);phase=phase+1;
 }
 // Abort read/RMW/write failures retain intent; committed resets are not replayed.
 phase=1;while phase<=3{cal_reset(600);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));cal_flags=0;check(esp_radio_c6_ocode_legacy_stage(400)==-110);cal_flags=ocv(6);hang=issued+phase;
  check(esp_radio_c6_ocode_legacy_abort(1000)==-110 && esp_radio_ocode_active);let count=commands;check(esp_radio_c6_ocode_legacy_abort(1000)==-110 && commands==count);release=1;check(!esp_radio_c6_ocode_legacy_abort(1000) && cal_reset_writes==3);cal_assert_reset(0);cal_finish(old,ana,mspi);phase=phase+1;
 }
 // Restoring RESETB=1 can restart calibration: the done wait is mandatory.
 cal_reset(701);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));hang=issued+5;
 check(esp_radio_c6_ocode_legacy_stage(1000)==-110);release=1;cal_flags=0;check(esp_radio_c6_ocode_legacy_abort(400)==-110 && esp_radio_ocode_active && cal_running);let count=cal_reset_writes;cal_flags=ocv(6);check(!esp_radio_c6_ocode_legacy_abort(1000) && cal_reset_writes==count);cal_assert_reset(1);cal_finish(old,ana,mspi);
 // Forced factory code refuses software calibration without changing reset.
 cal_reset(802);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));store8(memory+ocv(0)*256+5,0xdb);
 check(esp_radio_c6_ocode_legacy_stage(1000)==-16 && esp_radio_ocode_active && !cal_reset_writes);check(!esp_radio_c6_ocode_legacy_abort(1000));cal_assert_reset(cal_old_reset);cal_finish(old,ana,mspi);
 // Every owned-clock prerequisite is checked independently before reset.
 cal_reset(850);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));
 esp_radio_pll_phase=1;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);esp_radio_pll_phase=2;
 esp_radio_pll_active=0;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);esp_radio_pll_active=1;
 esp_radio_cpu_clock_active=0;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);esp_radio_cpu_clock_active=1;
 esp_radio_pll_master_clock_owned=0;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);esp_radio_pll_master_clock_owned=1;
 clock=clock&~cv(12);check(esp_radio_c6_ocode_legacy_stage(1000)==-16);clock=clock|cv(12);
 pll_power=pll_power|pcv(30);check(esp_radio_c6_ocode_legacy_stage(1000)==-16);pll_power=pll_power&~pcv(30);
 pll_cpu=1;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);pll_cpu=0;
 pll_ahb=pll_ahb|1;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);pll_ahb=pll_ahb&~255;
 pll_root=pll_root|0x10000;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);pll_root=pll_root&~0x30000;
 pll_usb=1;check(esp_radio_c6_ocode_legacy_stage(1000)==-16);pll_usb=0;check(!cal_reset_writes && !esp_radio_ocode_active);cal_finish(old,ana,mspi);
 // A flag read completing at the deadline does not turn a timeout into success.
 cal_reset(880);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(!esp_radio_c6_pll_begin(1000));
 check(esp_radio_c6_ocode_legacy_stage(28)==-110 && cal_reads==1 && cal_reset_writes==2 && esp_radio_ocode_active);check(!esp_radio_c6_ocode_legacy_abort(1000));cal_finish(old,ana,mspi);
 // Clock/budget/lease guards and the nominal10ms limit preserve signed statuses.
 cal_reset(902);old=pll_power;ana=pll_ana;mspi=pll_mspi;check(esp_radio_c6_ocode_legacy_stage(1000)==-16 && !cal_reset_writes);check(!esp_radio_c6_pll_begin(1000));
 ready=0;check(esp_radio_c6_ocode_legacy_stage(1000)==-95 && esp_radio_c6_ocode_legacy_abort(1000)==-95 && ps==0x1880);ready=1;rv_hal_chip=5;check(esp_radio_c6_ocode_legacy_stage(1000)==-95 && esp_radio_c6_ocode_legacy_abort(1000)==-95);rv_hal_chip=13;
 check(esp_radio_c6_ocode_legacy_stage(0)==-22 && esp_radio_c6_ocode_legacy_abort(2147483648)==-22);
 tick=0xffffffc0;cal_flags=0;let start=tick;check(esp_radio_c6_ocode_legacy_stage(1000000)==-110 && ((tick-start)&0xffffffff)<401000 && ((tick-start)&0xffffffff)>=400000);cal_flags=ocv(6);check(!esp_radio_c6_ocode_legacy_abort(1000));cal_finish(old,ana,mspi);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
