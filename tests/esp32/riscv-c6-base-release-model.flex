// Added to the composed base model by its verifier, after the real helpers.
global lifetime_hardware_entry=0;
fn lifetime_release(cycles){if lifetime_hardware_entry{return esp_radio_c6_hardware_deinit(cycles);}return esp_radio_c6_base_release(cycles);}
fn lifetime_restored(changed){
 base_restored();check(!esp_radio_hw_ready && !esp_radio_base_releasing && !esp_radio_base_configured && !esp_radio_modem_configured && !esp_radio_pmu_configured && !esp_radio_ocode_ready);
 check(!esp_radio_pmu_digital_count && !esp_radio_pmu_analog_count && !esp_radio_pmu_force_count && esp_radio_owner==1);
 let row=0;while row<49{check(load64(pmu_bank+row*8)==(load64(pmu_before+row*8)^(changed&~pv(row,1))));row=row+1;}
 row=0;while row<6{check(load64(power_bank+row*8)==(load64(power_before+row*8)^(changed&~esp_radio_c6_power_mask(row))));row=row+1;}
 row=0;while row<3{check(load8(memory+0x6d*256+av(row,0))==85);row=row+1;}
 check((rf&cv(32))==(rf_old&cv(32)));return 0;
}
fn lifetime_held(){
 check(esp_radio_base_active && esp_radio_base_releasing && esp_radio_base_configured && esp_radio_pmu_configured && esp_radio_modem_configured && ps==(base_old_ps&~8));base_blocked();return 0;
}
fn lifetime_prepare(mode,branch,irq){
 base_seed(mode,branch);check(!esp_radio_c6_base_prepare(4,73,1000));check(!esp_radio_c6_base_commit());
 base_old_ps=0x1880|(irq*8);ps=base_old_ps;esp_radio_hw_ready=lifetime_hardware_entry;return 0;
}
fn base_release_suite(){
 // Close the committed case at the end of the original staging suite.
 restoring=1;check(!lifetime_release(1000));lifetime_restored(0);
 let branch=0;while branch<3{let mode=0;while mode<8{let irq=0;while irq<2{
  lifetime_prepare(mode,branch,irq);let saved=esp_radio_pmu_saved;let trim=load8(memory+0x61*256+tv(6));let force=load8(memory+0x61*256+tv(9));let trim_writes=trim_code_writes+trim_force_writes;
  let changed=0xa5000000;let row=0;while row<49{store64(pmu_bank+row*8,load64(pmu_bank+row*8)^(changed&~pv(row,1)));row=row+1;}
  row=0;while row<6{store64(power_bank+row*8,load64(power_bank+row*8)^(changed&~esp_radio_c6_power_mask(row)));row=row+1;}
  base_old_code=base_old_code^(changed&~pv(5,1));base_old_slp=base_old_slp^(changed&~pv(6,1));
  restoring=1;check(!lifetime_release(1000) && base_requests==6 && esp_radio_pmu_saved==saved);lifetime_restored(changed);
  check(load8(memory+0x61*256+tv(6))==trim && load8(memory+0x61*256+tv(9))==force && trim_code_writes+trim_force_writes==trim_writes);
  let writes=base_stores;let requests=base_requests;check(!lifetime_release(1000) && writes==base_stores && requests==base_requests && ps==base_old_ps);
  // A second preparation owns fresh snapshots and reuses the singleton arena.
  // Reset observer counters only; leave all modeled hardware/trim state intact.
  digital_writes=0;commands=0;pll_starts=0;pll_stop_writes=0;pll_issued_writes=0;pll_committed_writes=0;pll_master_writes=0;cal_starts=0;cal_reads=0;cal_reset_writes=0;
  restoring=0;check(!esp_radio_c6_base_prepare(mode%6,mode*61,1000) && esp_radio_pmu_saved==saved);restoring=1;check(!esp_radio_c6_base_abort(1000));base_restored();
  irq=irq+1;
 }mode=mode+1;}branch=branch+1;}
 // Guard failures keep the lifetime receipt and never issue an MMIO store.
 let irq=0;while irq<2{let fault=0;while fault<34{
  lifetime_prepare(9,1,irq);let saved=esp_radio_pmu_saved;let live=pll_power;let mspi=pll_mspi;
  if fault==0{esp_radio_owner=0;}else if fault==1{esp_radio_owner=2;}else if fault==2{esp_adc_busy=1;}else if fault==3{esp_radio_phy_refs=1;}else if fault==4{esp_radio_phy_clock_refs=1;}else if fault==5{if lifetime_hardware_entry{esp_radio_base_configured=0;}else{esp_radio_hw_ready=1;}}else if fault==6{isr=1;}
  else if fault==7{esp_radio_pmu_active=1;}else if fault==8{esp_radio_modem_active=1;}else if fault==9{esp_radio_calibration_active=1;}else if fault==10{esp_radio_cpu_clock_active=1;}else if fault==11{esp_radio_pll_active=1;}else if fault==12{esp_radio_ocode_active=1;}else if fault==13{esp_radio_regi2c_active=1;}
  else if fault==14{esp_radio_pmu_configured=0;}else if fault==15{esp_radio_modem_configured=0;}else if fault==16{esp_radio_pmu_saved=0;}else if fault==17{esp_radio_ocode_ready=0;}else if fault==18{esp_radio_base_touched=0;}else if fault==19{esp_radio_base_issued=1;}else if fault==20{esp_radio_base_command_step=1;}
  else if fault==21{pll_dma=1;}else if fault==22{pll_regdma=1;}else if fault==23{pll_spi0=1<<18;}else if fault==24{pll_spi1=1<<31;}else if fault==25{pll_modem0=1<<21;}else if fault==26{pll_modem1=1;}else if fault==27{clock=clock|2;}else if fault==28{base_foreign_ble=1;}else if fault==29{pll_mspi=pll_mspi&~3;}else if fault==30{base_foreign_32k=8;}else if fault==31{pll_power=pll_power^0x200000;}else if fault==32{pll_power=pll_power^0x100000;}else{esp_radio_base_releasing=1;}
  // The calibration coordinator owns an IRQ-off interval until recovery.
  if fault==9{ps=ps&~8;base_old_ps=ps;}
  let writes=base_stores;let requests=base_requests;let ready_before=esp_radio_hw_ready;let configured_before=esp_radio_base_configured;check(lifetime_release(1000)==-16 && !esp_radio_base_active && esp_radio_base_configured==configured_before && esp_radio_hw_ready==ready_before && ps==base_old_ps && base_stores==writes && base_requests==requests);
  esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_radio_hw_ready=lifetime_hardware_entry;isr=0;esp_radio_pmu_active=0;esp_radio_modem_active=0;esp_radio_calibration_active=0;esp_radio_cpu_clock_active=0;esp_radio_pll_active=0;esp_radio_ocode_active=0;esp_radio_regi2c_active=0;
  esp_radio_base_configured=1;esp_radio_pmu_configured=1;esp_radio_modem_configured=1;esp_radio_pmu_saved=saved;esp_radio_ocode_ready=1;esp_radio_base_touched=1;esp_radio_base_issued=0;esp_radio_base_command_step=2;esp_radio_base_releasing=0;pll_dma=0;pll_regdma=0;pll_spi0=0;pll_spi1=0;pll_modem0=0;pll_modem1=0;clock=clock&~2;base_foreign_ble=0;base_foreign_32k=0;pll_mspi=mspi;pll_power=live;
  restoring=1;check(!lifetime_release(1000));lifetime_restored(0);fault=fault+1;
 }irq=irq+1;}
 // Repeated timeouts at each reverse write retain the same progress journal.
 let failure=0;while failure<7{lifetime_prepare(9,1,failure&1);restoring=1;
  if failure==0{base_fail_address=0x600af018;}else if failure==1{base_fail_address=0x600af00c;}else if failure==2{base_fail_address=0x600af014;}else if failure==3{base_fail_address=0x600af020;}else if failure==4{base_fail_address=0x600a980c;}else if failure==5{power_hang=5;}else{hang=commands+1;}
  check(lifetime_release(400)==-110);lifetime_held();let requests=base_requests;let step=esp_radio_base_recovery;
  check(lifetime_release(400)==-110 && base_requests==requests && esp_radio_base_recovery==step);lifetime_held();
  base_fail_address=0;power_release=1;release=1;check(!lifetime_release(1000));lifetime_restored(0);failure=failure+1;
 }
 // Inverse WT requests are issued once, including a retry through staging abort.
 let command=5;while command<=6{lifetime_prepare(9,1,command&1);base_hang=command;restoring=1;check(lifetime_release(400)==-110 && base_requests==command);lifetime_held();check(lifetime_release(400)==-110 && base_requests==command);base_release=1;check(!esp_radio_c6_base_abort(1000));lifetime_restored(0);command=command+1;}
 // The final observation keeps lifetime flags until the existing timed check passes.
 lifetime_prepare(9,1,1);base_final_mode=1;base_final_delta=400;restoring=1;check(lifetime_release(400)==-110 && esp_radio_base_recovery==7);lifetime_held();base_final_mode=0;check(!lifetime_release(1000));lifetime_restored(0);
 let writes=base_stores;check(lifetime_release(0)==-22 && lifetime_release(2147483648)==-22 && writes==base_stores && ps==base_old_ps);
 return 0;
}
