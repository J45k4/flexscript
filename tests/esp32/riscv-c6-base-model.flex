global base_cfg=0;global base_sysmap=0;global base_lpmap=0;global base_wifi=0;global base_32k=0;
global base_old_sysmap=0;global base_old_lpmap=0;global base_old_wifi=0;global base_old_32k=0;global base_old_clock=0;global base_old_code=0;global base_old_slp=0;global base_old_live=0;global base_old_ps=0;
global base_requests=0;global base_pending=0;global base_polls=0;global base_hang=0;global base_release=0;global base_inside=0;global base_unrestored=0;global base_ignore_map=0;
fn base_seed(mode,branch){
 check(!esp_radio_base_active);esp_radio_base_configured=0;esp_radio_modem_configured=0;esp_radio_pmu_configured=0;flow_reset(mode,branch);restoring=1;check(!esp_radio_c6_pmu_abort(1000));stage_reset(1500+mode,85);if !branch{fuse_version=0;}if branch==2{reset_reason=2+(mode%254);}
 base_sysmap=((mode+1)*0x1234567)&0xffffffff;base_lpmap=((mode+3)*0x31415927)&0xffffffff;base_wifi=(mode*35)&0xffff;base_32k=mode&3;
 clock=clock&~11;pll_modem0=0;pll_modem1=0;base_old_clock=clock;let code=(load64(pmu_bank+5*8)>>30)&3;let slp=(load64(pmu_bank+6*8)>>26)&1;pll_power=(pll_power&~0xf00000)|(code<<21)|(slp<<23)|((mode&1)<<20);
 base_old_sysmap=base_sysmap;base_old_lpmap=base_lpmap;base_old_wifi=base_wifi;base_old_32k=base_32k;base_old_code=load64(pmu_bank+5*8);base_old_slp=load64(pmu_bank+6*8);base_old_live=pll_power&0xf00000;
 base_old_ps=0x1880|((mode&1)*8);ps=base_old_ps;base_requests=0;base_pending=0;base_polls=0;base_hang=0;base_release=0;base_inside=0;base_unrestored=0;base_ignore_map=0;return 0;
}
fn base_complete(){
 if base_pending==1{pll_power=(pll_power&~0x600000)|(((load64(pmu_bank+5*8)>>30)&3)<<21);}else{pll_power=(pll_power&~0x800000)|(((load64(pmu_bank+6*8)>>26)&1)<<23);}
 base_pending=0;return 0;
}
fn esp32_call64(address,a,b,c,d,e,f,g,h){if address==29{base_inside=1;let result=esp_radio_c6_base_strobe_iram(a,b,c,d,e,f,g,h);base_inside=0;return result;}return base_model_call64(address,a,b,c,d,e,f,g,h);}
fn esp32_load32(address){
 if address==0x600b00dc || address==0x600b00d0{check(0);}
 if address==0x600b0194 && base_pending{if base_requests!=base_hang || base_release{if base_polls{base_polls=base_polls-1;}else{base_complete();}}}
 if address==0x600a980c{return base_sysmap;}if address==0x600af020{return base_lpmap;}if address==0x600af00c{return base_wifi;}if address==0x600af014{return base_32k;}if address==0x600af01c || address==0x600af004 || address==0x600af008{return 0;}if address==0x60096018{return pll_mspi;}
 let result=base_model_load32(address);if address==0x600b0194 && base_unrestored{return result^0x100000;}return result;
}
fn esp32_store32(address,value){
 if address==0x600b00dc || address==0x600b00d0{
  check(base_inside && esp_radio_base_active && esp_radio_base_internal && !(ps&8) && esp_radio_base_issued && !base_pending);base_requests=base_requests+1;
  if address==0x600b00dc{check(value==0x80000000);base_pending=1;}else{check(value==0x10000000);base_pending=2;}
  let mask=0x600000;let target=((load64(pmu_bank+5*8)>>30)&3)<<21;if base_pending==2{mask=0x800000;target=((load64(pmu_bank+6*8)>>26)&1)<<23;}
  if base_requests==base_hang{pll_power=(pll_power&~mask)|(target^mask);}else if (pll_power&mask)==target{base_complete();}base_polls=1;return 0;
 }
 if address==0x600a980c || address==0x600af020 || address==0x600b000c || address==0x600b0024{check(!base_pending);}
 if address==0x600a980c{if !base_ignore_map{base_sysmap=value&0xffffffff;}return 0;}if address==0x600af020{base_lpmap=value&0xffffffff;return 0;}if address==0x600af00c{check(!(clock&1));base_wifi=value&0xffffffff;return 0;}if address==0x600af014{check(!(clock&1));base_32k=value&0xffffffff;return 0;}
 if address==0x600b000c || address==0x600b0024{if esp_radio_base_step==1 || esp_radio_base_recovery{store64(pmu_bank+pmu_row(address)*8,value&0xffffffff);return 0;}}
 if address==pcv(0) && !(esp_radio_cpu_clock_active && esp_radio_pll_active && !(pll_root&0x30000) && !(pll_mspi&pcv(16))){h_print(2,h_cat3("flags ",h_int(esp_radio_cpu_clock_active),h_cat3("/",h_int(esp_radio_pll_active),h_cat3(" root ",h_int(pll_root),h_cat3(" mspi ",h_int(pll_mspi),"\n")))));}
 return base_model_store32(address,value);
}
fn base_restored(){check(!esp_radio_base_active && !esp_radio_base_phase && !esp_radio_pmu_active && !esp_radio_modem_active && !esp_radio_calibration_active && !esp_radio_cpu_clock_active && !esp_radio_pll_active && !base_pending && ps==base_old_ps);check(base_sysmap==base_old_sysmap && base_lpmap==base_old_lpmap && base_wifi==base_old_wifi && base_32k==base_old_32k && clock==base_old_clock);check(load64(pmu_bank+5*8)==base_old_code && load64(pmu_bank+6*8)==base_old_slp && (pll_power&0xf00000)==base_old_live);return 0;}
fn base_blocked(){check(esp_radio_base_active && !esp_radio_base_internal && ps==(base_old_ps&~8));check(esp_radio_c6_pmu_abort(1000)==-16 && esp_radio_c6_regi2c_idle()==-16 && esp_radio_c6_pll_consumer(1)==-16 && esp_radio_c6_base_prepare(0,0,1000)==-16);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));pll_meta=cfg+207*8;cal_meta=cfg+2656;base_cfg=h_read(load64(argv+16));check(load64(base_cfg)==256);memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);pll_consumers=alloc(120);
 // Primary C validates every preinit register and raw WT request, independent
 // of the model's explicitly assumed live-field acknowledgement behavior.
 check(load64(base_cfg+8)==0x600b000c && load64(base_cfg+16)==0x600b0024 && load64(base_cfg+24)==0x600a980c && load64(base_cfg+32)==0x600af020 && load64(base_cfg+40)==0x600b00dc && load64(base_cfg+48)==0x600b00d0);
 let vector=0;while vector<256{let v=base_cfg+56+vector*80;check(load64(v+32)==((load64(v)&~0xc0000000)|0x80000000) && load64(v+40)==load64(v+8) && load64(v+48)==((load64(v+16)&~0xf0000000)|0x40000000) && load64(v+56)==((load64(v+24)&~0xff000000)|0x44000000) && load64(v+64)==0x80000000 && load64(v+72)==0x10000000);vector=vector+1;}
 let branch=0;while branch<3{let mode=0;while mode<64{base_seed(mode,branch);check(!esp_radio_c6_base_prepare(mode%6,mode*61,1000));check(esp_radio_base_step==6 && esp_radio_base_phase==1 && base_requests==4 && esp_radio_pmu_force_count==6 && esp_radio_ocode_ready);let expected_mode=3;if branch==1{expected_mode=1;}if branch==2{expected_mode=2;}check(esp_radio_calibration_mode==expected_mode);base_blocked();restoring=1;check(!esp_radio_c6_base_abort(1000) && base_requests==6);base_restored();mode=mode+1;}branch=branch+1;}
 // Each issued forward command may remain uncertain. Abort must poll that
 // same request before modifying its source registers, and never replay it.
 let command=1;while command<=4{base_seed(9,1);base_hang=command;check(esp_radio_c6_base_prepare(0,0,400)==-110 && esp_radio_base_error==-110 && base_requests==command);base_blocked();restoring=1;check(esp_radio_c6_base_abort(400)==-110 && base_requests==command && esp_radio_base_cleanup_error==-110);base_release=1;check(!esp_radio_c6_base_abort(1000) && esp_radio_base_error==-110);base_restored();command=command+1;}
 command=5;while command<=6{base_seed(9,1);check(!esp_radio_c6_base_prepare(0,0,1000));base_hang=command;restoring=1;check(esp_radio_c6_base_abort(400)==-110 && base_requests==command);base_blocked();check(esp_radio_c6_base_abort(400)==-110 && base_requests==command);base_release=1;check(!esp_radio_c6_base_abort(1000));base_restored();command=command+1;}
 base_seed(9,1);base_ignore_map=1;check(esp_radio_c6_base_prepare(0,0,1000)==-110 && !base_requests);restoring=1;check(!esp_radio_c6_base_abort(1000) && !base_requests);base_restored();
 // Lower-stage failure cleanup composes with the outer snapshots.
 base_seed(9,1);power_hang=0;check(esp_radio_c6_base_prepare(0,0,400)==-110 && esp_radio_base_step==2);base_blocked();check(esp_radio_c6_base_commit()==-16);power_release=1;restoring=1;check(!esp_radio_c6_base_abort(1000) && esp_radio_base_error==-110);base_restored();
 base_seed(9,1);hang=1;check(esp_radio_c6_base_prepare(0,0,400)==-110);release=1;restoring=1;check(!esp_radio_c6_base_abort(1000));base_restored();
 // An un-restored extra monitor bit prevents lease release even when code
 // and PCR/PMU mux fields have returned to their previous values.
 base_seed(9,1);check(!esp_radio_c6_base_prepare(0,0,1000));base_unrestored=1;restoring=1;check(esp_radio_c6_base_abort(400)==-110 && esp_radio_base_active);base_unrestored=0;check(!esp_radio_c6_base_abort(1000));base_restored();
 base_seed(9,1);pll_power=pll_power^0x200000;check(esp_radio_c6_base_prepare(0,0,1000)==-16 && !esp_radio_base_active && !base_requests && ps==base_old_ps);pll_power=pll_power^0x200000;
 check(esp_radio_c6_base_prepare(6,0,1000)==-22 && esp_radio_c6_base_abort(0)==-22 && !esp_radio_base_active);
 // Commit transfers the prepared base/PMU/modem state before PHY ownership.
 base_seed(9,1);check(!esp_radio_c6_base_prepare(0,0,1000));esp_radio_base_step=5;check(esp_radio_c6_base_commit()==-16 && esp_radio_base_active);esp_radio_base_step=6;check(!esp_radio_c6_base_commit() && esp_radio_base_configured && esp_radio_modem_configured && esp_radio_pmu_configured && !esp_radio_base_active && ps==base_old_ps);check(esp_radio_c6_base_abort(1000)==-16);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
