// Uses the primary PMU/PLL/OCODE helpers with actual CPU clock handoff calls.
global flow_ps=0;global flow_root=0;global flow_cpu=0;global flow_ahb=0;global flow_ticks=0;global flow_power=0;global flow_ana=0;global flow_mspi=0;global flow_ignore_restore_root=0;
fn flow_reset(mode,branch){
 check(!esp_radio_calibration_active && !esp_radio_calibration_internal);cal_reset(mode);flow_ps=esp_radio_cpu_clock_ps;flow_root=esp_radio_cpu_clock_root;flow_cpu=pll_cpu;flow_ahb=pll_ahb;flow_ticks=esp_radio_cpu_clock_ticks;flow_power=pll_power;flow_ana=pll_ana;flow_mspi=pll_mspi;
 esp_radio_cpu_clock_active=0;esp_radio_cpu_clock_phase=0;pll_root=flow_root;pll_rom_ticks=flow_ticks;ps=flow_ps;flow_ignore_restore_root=0;
 if branch==1{fuse_version=3<<27;fuse_code=(mode*7)&255;}if branch==2{reset_reason=2+(mode%254);}
 return 0;
}
fn flow_restored(){
 check(!esp_radio_calibration_active && !esp_radio_calibration_internal && !esp_radio_calibration_phase && !esp_radio_calibration_step);
 check(!esp_radio_cpu_clock_active && !esp_radio_pll_active && !esp_radio_regi2c_active && ps==flow_ps);
 check(pll_root==flow_root && pll_cpu==flow_cpu && pll_ahb==flow_ahb && pll_rom_ticks==flow_ticks && (pll_power&pcv(11))==(flow_power&pcv(11)) && (pll_ana&12)==(flow_ana&12) && pll_mspi==flow_mspi && clock==pll_master_before);return 0;
}
fn flow_finish(){flow_restored();restoring=1;check(!esp_radio_c6_pmu_abort(1000) && !esp_radio_pmu_active && ps==flow_ps);return 0;}
fn flow_blocked(){
 check(esp_radio_calibration_active && !esp_radio_calibration_internal && esp_radio_calibration_phase==2 && ps==(flow_ps&~8));
 check(esp_radio_c6_pmu_abort(1000)==-16 && esp_radio_c6_pmu_commit()==-16 && esp_radio_c6_clock_restore(1000)==-16 && esp_radio_c6_pll_restore(1000)==-16 && esp_radio_c6_ocode_abort(1000)==-16 && esp_radio_c6_pll_consumer(1)==-16 && esp_radio_c6_pmu_analog(0,1,1000)==-16);
 check(esp_radio_c6_calibration_prepare(1000)==-16 && esp_radio_c6_calibration_abort(0)==-22 && esp_radio_calibration_error==-110);return 0;
}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==3504);pll_meta=cfg+207*8;cal_meta=cfg+2656;memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);pll_consumers=alloc(120);
 let branch=0;while branch<3{let mode=0;while mode<64{flow_reset(mode,branch);let before=fuse_reads;
  check(!esp_radio_c6_calibration_prepare(1000) && esp_radio_ocode_ready && !esp_radio_calibration_error && !esp_radio_calibration_cleanup_error);flow_restored();
  if branch==0{check(esp_radio_calibration_mode==3 && cal_reset_writes==2 && cal_starts==1);}else{check(!cal_reset_writes && !pll_power_writes);if branch==1{check(esp_radio_calibration_mode==1 && esp_radio_ocode_active && load8(memory+0x61*256+6)==fuse_code && (load8(memory+0x61*256+5)&64));}else{check(esp_radio_calibration_mode==2 && fuse_reads==before);}}
  check(esp_radio_c6_calibration_prepare(1000)==-16 && !esp_radio_c6_calibration_abort(1000) && esp_radio_ocode_ready);flow_finish();mode=mode+1;}branch=branch+1;
 }
 // Every policy vector is produced by the actual pinned vendor PMU/OCODE code.
 let policy=h_read(load64(argv+16));check(load64(policy)==32768);flow_reset(16,0);let vector=0;
 while vector<32768{pll_starts=0;pll_issued_writes=0;pll_committed_writes=0;pll_stop_writes=0;let v=policy+8+vector*56;reset_reason=load64(v);fuse_version=load64(v+8)<<27;fuse_code=load64(v+16);let route=load64(v+24);let old=fuse_reads;let resets=cal_reset_writes;
  check(!esp_radio_c6_calibration_prepare(1000) && esp_radio_ocode_ready);let mode=2;if route==1{mode=1;}if route==2{mode=3;}check(esp_radio_calibration_mode==mode);flow_restored();
  if !route{check(fuse_reads==old && cal_reset_writes==resets);}if route==1{check(load8(memory+0x61*256+6)==load64(v+40) && (load8(memory+0x61*256+5)&64));}if route==2{check(cal_reset_writes==resets+2);}
  check(!esp_radio_c6_ocode_abort(1000));vector=vector+1;
 }flow_finish();
 // All five factory commands and23 legacy/preflight/recalibration commands.
 branch=0;while branch<2{let phase=1;let limit=23;if branch{limit=5;}while phase<=limit{
  flow_reset(16+(phase&1),branch);hang=issued+phase;check(esp_radio_c6_calibration_prepare(1000)==-110 && esp_radio_calibration_error==-110);flow_blocked();let count=commands;
  check(esp_radio_c6_calibration_abort(1000)==-110 && commands==count && esp_radio_calibration_cleanup_error==-110 && esp_radio_calibration_error==-110);flow_blocked();release=1;check(!esp_radio_c6_calibration_abort(1000) && esp_radio_calibration_error==-110 && !esp_radio_calibration_cleanup_error && !esp_radio_ocode_ready);flow_finish();phase=phase+1;}branch=branch+1;
 }
 // Cleanup failures after successful calibration never re-run preparation.
 flow_reset(16,0);flow_ignore_restore_root=1;check(esp_radio_c6_calibration_prepare(1000)==-110 && esp_radio_calibration_step==6 && cal_starts==1 && pll_starts==1);flow_blocked();let writes=cal_reset_writes;let coefficients=pll_issued_writes;
 check(esp_radio_c6_calibration_abort(1000)==-110 && esp_radio_calibration_error==-110 && esp_radio_calibration_cleanup_error==-110);flow_ignore_restore_root=0;check(!esp_radio_c6_calibration_abort(1000) && cal_reset_writes==writes && pll_issued_writes==coefficients);flow_finish();
 // A pending OCODE calibration is cancelled before any PLL power-up.
 flow_reset(17,0);cal_flags=0;check(esp_radio_c6_calibration_prepare(400)==-110 && esp_radio_ocode_legacy);flow_blocked();check(esp_radio_c6_calibration_abort(400)==-110 && esp_radio_ocode_legacy);cal_flags=ocv(6);check(!esp_radio_c6_calibration_abort(1000));flow_finish();
 // Invalid policy and unprepared/foreign leases reject without taking ownership.
 flow_reset(16,0);check(esp_radio_c6_calibration_prepare(0)==-22 && esp_radio_c6_calibration_abort(2147483648)==-22 && !esp_radio_calibration_active && ps==flow_ps);
 reset_reason=256;check(esp_radio_c6_calibration_prepare(1000)==-5 && !esp_radio_calibration_active && ps==flow_ps);reset_reason=1;
 esp_radio_pmu_phase=2;check(esp_radio_c6_calibration_prepare(1000)==-16 && !esp_radio_calibration_active);esp_radio_pmu_phase=1;esp_radio_cpu_clock_active=1;check(esp_radio_c6_calibration_prepare(1000)==-16);esp_radio_cpu_clock_active=0;
 ready=0;check(esp_radio_c6_calibration_prepare(1000)==-95 && esp_radio_c6_calibration_abort(1000)==-95 && ps==flow_ps);ready=1;flow_finish();
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
