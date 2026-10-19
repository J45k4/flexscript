global force_cfg=0;
fn force_case(seed){
 stage_reset(seed,85);let row=0;while row<6{let value=1<<(row+2);if row==3 || row==5{value=63;}if row==4{value=0x0f000000;}store64(power_bank+row*8,value);store64(power_before+row*8,value);row=row+1;}return 0;
}
fn force_restored(changed,original_ps){
 check(!esp_radio_pmu_active && !esp_radio_pmu_force_count && !esp_radio_pmu_phase && ps==original_ps && !esp_radio_regi2c_active);let row=0;
 while row<6{check(load64(power_bank+row*8)==(load64(power_before+row*8)^(changed&~esp_radio_c6_power_mask(row))));row=row+1;}return 0;
}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==207*8);force_cfg=h_read(load64(argv+16));check(load64(force_cfg)==1536);memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);
 let i=0;while i<1536{let v=force_cfg+8+i*40;let row=load64(v);check(esp_radio_c6_power_address(row)==load64(v+8) && esp_radio_c6_power_mask(row)==load64(v+16));check((load64(v+24)&~esp_radio_c6_power_mask(row))==load64(v+32));esp_radio_c6_power_saved(row,load64(v+24));check(esp_radio_c6_power_saved(row,-1)==load64(v+24));i=i+1;}
 // Execute actual PMU/regulator/force staging for every primary C byte pattern.
 let seed=0;while seed<256{let mode=0;while mode<2{stage_reset(seed,85);let row=0;
  while row<6{let v=force_cfg+8+(seed*6+row)*40;let value=load64(v+24);if row<3{value=value&~35;}if row==4{value=value&~15;}store64(power_bank+row*8,value);store64(power_before+row*8,value);row=row+1;}
  let original_ps=0x1888;if mode{original_ps=0x1880;}ps=original_ps;tick=0xfffffff0;check(!esp_radio_c6_pmu_stage(1000) && esp_radio_pmu_force_count==6 && ps==original_ps);row=0;
  while row<6{let v=force_cfg+8+(seed*6+row)*40;let expected=load64(v+32);if row==4{expected=expected&~15;}check(load64(power_bank+row*8)==expected);store64(power_bank+row*8,load64(power_bank+row*8)^(0xa5000000&~load64(v+16)));row=row+1;}
  restoring=1;check(!esp_radio_c6_pmu_abort(1000));force_restored(0xa5000000,original_ps);mode=mode+1;}seed=seed+1;
 }
 // Every force preparation and restoration may fail with intent retained.
 let row=0;while row<6{force_case(700+row);power_hang=row;check(esp_radio_c6_pmu_stage(1000)==-110 && esp_radio_pmu_phase==2 && esp_radio_pmu_force_count==row+1 && ps==0x1888 && esp_radio_pmu_active);check(esp_radio_c6_pmu_commit()==-16);power_release=1;restoring=1;check(!esp_radio_c6_pmu_abort(1000));force_restored(0,0x1888);row=row+1;}
 row=0;while row<6{force_case(800+row);check(!esp_radio_c6_pmu_stage(1000));power_hang=row;restoring=1;check(esp_radio_c6_pmu_abort(1000)==-110 && esp_radio_pmu_force_count==row+1 && esp_radio_pmu_phase==2 && !esp_radio_pmu_analog_count && !esp_radio_pmu_digital_count);let commands_before=commands;check(esp_radio_c6_pmu_abort(1000)==-110 && commands==commands_before && esp_radio_pmu_force_count==row+1);power_release=1;check(!esp_radio_c6_pmu_abort(1000));force_restored(0,0x1888);row=row+1;}
 // Late observations time out even if the previous write has committed; a
 // readback-confirmed identical value must never issue another force store.
 force_case(901);check(!esp_radio_c6_pmu_stage(1000));let old=power_writes;let irq=esp32_irq_save();check(!esp_radio_c6_power_write(0,0,1000) && power_writes==old);power_late=2;check(esp_radio_c6_power_write(0,0,14)==-110 && power_writes==old);esp32_irq_restore(irq);restoring=1;check(!esp_radio_c6_pmu_abort(1000));force_restored(0,0x1888);
 // Core reset/isolation/power-down and memory isolation preflight is read-only.
 row=0;while row<3{let bit=0;while bit<3{force_case(1000+row*3+bit);let value=1<<bit;if bit==2{value=32;}store64(power_bank+row*8,load64(power_bank+row*8)|value);check(esp_radio_c6_pmu_stage(1000)==-16 && !esp_radio_pmu_active && !total_writes && !commands && ps==0x1888);bit=bit+1;}row=row+1;}
 let bit=0;while bit<4{force_case(1100+bit);store64(power_bank+32,load64(power_bank+32)|(1<<bit));check(esp_radio_c6_pmu_stage(1000)==-16 && !esp_radio_pmu_active && !total_writes);bit=bit+1;}
 force_case(1200);check(!esp_radio_c6_pmu_stage(1000));esp_radio_pmu_force_count=5;check(esp_radio_c6_pmu_commit()==-16 && esp_radio_pmu_active);esp_radio_pmu_force_count=6;restoring=1;check(!esp_radio_c6_pmu_abort(1000));force_restored(0,0x1888);
 force_case(1201);check(!esp_radio_c6_pmu_stage(1000) && !esp_radio_c6_pmu_commit() && !esp_radio_pmu_force_count && esp_radio_pmu_configured && !esp_radio_pmu_active);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
