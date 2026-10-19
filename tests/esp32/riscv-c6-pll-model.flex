// Appended to the primary PMU/I2C model helpers by the independent verifier.
global pll_master_before=0;global pll_master_writes=0;global pll_master_ignore=0;
global pll_meta=0;global pll_consumers=0;global pll_power=0;global pll_ana=0;global pll_mspi=0;global pll_usb=0;global pll_modem0=0;global pll_modem1=0;
global pll_root=0x28000200;global pll_cpu=0;global pll_ahb=0x300;global pll_apb=0;global pll_query=0x1e014;global pll_rom_ticks=40;
global pll_dma=0;global pll_regdma=0;global pll_spi0=0;global pll_spi1=0;
global pll_power_writes=0;global pll_reg_writes=0;global pll_ignored_write=0;global pll_issued_writes=0;global pll_committed_writes=0;global pll_starts=0;global pll_polls=0;global pll_hang_done=0;global pll_done_tick=0;global pll_preserve_coefficients=1;global pll_case=0;global pll_stop_writes=0;
fn pcv(i){return load64(pll_meta+i*8);}
fn pca(row,column){return load64(pll_meta+280+row*32+column*8);}
fn pcf(row,column){return load64(pll_meta+760+row*40+column*8);}
fn esp32_call64(address,a,b,c,d,e,f,g,h){
 if address==17{return esp_radio_c6_clock_begin_iram(a,b,c,d,e,f,g,h);}if address==19{return esp_radio_c6_clock_restore_iram(a,b,c,d,e,f,g,h);}
 if address==21{return esp_radio_c6_pll_begin_iram(a,b,c,d,e,f,g,h);}check(address==23);return esp_radio_c6_pll_restore_iram(a,b,c,d,e,f,g,h);
}
fn esp32_call32(address,a,b,c,d,e,f,g,h){
 if address==17 || address==19 || address==21 || address==23{return esp32_call64(address,a,b,c,d,e,f,g,h)&0xffffffff;}
 if address==pcv(28){check(!(ps&8)&&!a&&!b&&!c&&!d&&!e&&!f&&!g&&!h);return pll_rom_ticks;}
 if address==pcv(29){check(!(ps&8)&&!b&&!c&&!d&&!e&&!f&&!g&&!h);pll_rom_ticks=a;return 0;}
 return pmu_call32(address,a,b,c,d,e,f,g,h);
}
fn esp32_load32(address){
 check(!(ps&8));if address==pcv(1){return pll_power;}
 if address==pcv(2){if pll_starts && !pll_stop_writes{check((clock&cv(12))==cv(12));}if pll_starts && (pll_ana&pcv(15)) && pll_committed_writes==6 && !pll_hang_done && !(pll_ana&pcv(13)){if pll_polls{pll_polls=pll_polls-1;}else{pll_ana=pll_ana|pcv(13);pll_power=pll_power|pcv(31);pll_done_tick=tick;}}return pll_ana;}
 if address==pcv(3){return pll_mspi;}if address==pcv(4){return pll_usb;}if address==pcv(5){return pll_modem0;}if address==pcv(6){return pll_modem1;}
 if address==pcv(19){return pll_root;}if address==pcv(20){return pll_cpu;}if address==pcv(21){return pll_ahb;}if address==pcv(22){return pll_apb;}if address==pcv(23){return pll_query;}
 if address==pcv(24){return pll_dma;}if address==pcv(25){return pll_regdma;}if address==pcv(26){return pll_spi0;}if address==pcv(27){return pll_spi1;}
 let row=0;while row<15{if address==pca(row,0){return load64(pll_consumers+row*8);}row=row+1;}
 return pmu_load32(address);
}
fn pll_commit(command){
 if !pll_starts{return 0;}check(pll_committed_writes<6);let row=pll_committed_writes;let block=command&255;let reg=(command>>cv(9))&255;let value=(command>>cv(10))&255;
 check(block==pcf(row,0) && reg==pcf(row,1));let mask=((1<<(pcf(row,2)-pcf(row,3)+1))-1)<<pcf(row,3);let before=load8(memory+block*256+reg);
 check((value&mask)==(pcf(row,4)<<pcf(row,3)) && !((value^before)&~mask));pll_committed_writes=row+1;return 0;
}
fn bus_write(address,value){
 if address==cv(5){if (value^clock)&cv(12){pll_master_writes=pll_master_writes+1;if pll_master_writes==pll_master_ignore{return 0;}}if pll_starts && !pll_stop_writes{check((value&cv(12))==cv(12));}}
 if (address==cv(1)||address==cv(2)) && !(value&(1<<cv(11))){check(!esp_radio_regi2c_write_issued);}
 if (address==cv(1)||address==cv(2)) && (value&255)==pcf(0,0) && (value&(1<<cv(11))){check(pll_starts && esp_radio_regi2c_write_issued);pll_issued_writes=pll_issued_writes+1;}
 return pmu_bus_write(address,value);
}
fn esp32_store32(address,value){
 check(!(ps&8));
 if address==pcv(0){
  check(esp_radio_cpu_clock_active && esp_radio_pll_active && !(pll_root&0x30000) && !(pll_mspi&pcv(16)));pll_power_writes=pll_power_writes+1;pll_reg_writes=pll_reg_writes+1;
  if pll_reg_writes==pll_ignored_write{return 0;}
  if value==pcv(7){pll_power=pll_power&~pcv(10);return 0;}
  if value==pcv(8){pll_power=pll_power&~(pcv(9)&~0x10000000);pll_power=pll_power&~pcv(31);if !pll_preserve_coefficients{let row=0;while row<6{let block=pcf(row,0);let reg=pcf(row,1);let mask=((1<<(pcf(row,2)-pcf(row,3)+1))-1)<<pcf(row,3);let p=memory+block*256+reg;store8(p,load8(p)&~mask);row=row+1;}}return 0;}
  if value==pcv(10){pll_power=pll_power|value;return 0;}
  check(value && !(value&~pcv(9)) && value==(pcv(9)&~pll_power));pll_power=pll_power|value;pll_power=pll_power&~pcv(31);return 0;
 }
 if address==pcv(2){
  check(esp_radio_pll_active && esp_radio_cpu_clock_active && !(pll_root&0x30000));check(!((value^pll_ana)&~(pcv(14)|pcv(15))));pll_reg_writes=pll_reg_writes+1;if pll_reg_writes==pll_ignored_write{return 0;}
  let old=pll_ana;pll_ana=(value&~pcv(13))|(old&pcv(13));
  if !(old&pcv(15)) && (value&pcv(15)){check((pll_power&(pcv(9)|pcv(10)))==(pcv(9)|pcv(10)));pll_starts=pll_starts+1;check(pll_starts==1);pll_ana=pll_ana&~pcv(13);pll_power=pll_power&~pcv(31);pll_polls=1;}
  if (old&pcv(15)) && !(value&pcv(15)){check(pll_committed_writes==6 && (clock&cv(12))==cv(12) && ((tick-pll_done_tick)&0xffffffff)>=400);pll_stop_writes=pll_stop_writes+1;pll_ana=pll_ana&~pcv(13);}
  return 0;
 }
 if address==pcv(3){check(esp_radio_pll_active && !((value^pll_mspi)&~pcv(16)));pll_reg_writes=pll_reg_writes+1;if pll_reg_writes!=pll_ignored_write{pll_mspi=value;}return 0;}
 if address==pcv(19){check(!esp_radio_pll_active && esp_radio_cpu_clock_active && !((value^pll_root)&~pcv(34)));pll_root=value;return 0;}
 if address==pcv(20){check(!esp_radio_pll_active && esp_radio_cpu_clock_active && !((value^pll_cpu)&~255));pll_cpu=value;return 0;}
 if address==pcv(21){check(!esp_radio_pll_active && esp_radio_cpu_clock_active && !((value^pll_ahb)&~255));pll_ahb=value;return 0;}
 return pmu_store32(address,value);
}
fn pll_reset(seed,on,gate,mspi,retain,masked){
 check(!esp_radio_pll_active && !esp_radio_cpu_clock_active);stage_reset(seed,85);pll_power=0x84008002;if on{pll_power=pll_power|pcv(9)|pcv(31);if gate{pll_power=pll_power|pcv(10);}}else{if seed&1{pll_power=pll_power|0x10000000;}if seed&2{pll_power=pll_power|pcv(31);}}
 pll_ana=0xa5000004;pll_mspi=0xa5a50001|mspi*pcv(16);pll_usb=0;pll_modem0=0x10800000;pll_modem1=0x30400;pll_root=0x28000200;pll_cpu=0;pll_ahb=0x300;pll_apb=0;pll_query=0x1e014;pll_rom_ticks=40;
 pll_dma=0;pll_regdma=0;pll_spi0=0;pll_spi1=0;pll_power_writes=0;pll_reg_writes=0;pll_ignored_write=0;pll_issued_writes=0;pll_committed_writes=0;pll_starts=0;pll_polls=0;pll_hang_done=0;pll_done_tick=0;pll_preserve_coefficients=retain;pll_stop_writes=0;esp_radio_pll_consumers=0;
 let row=0;while row<15{store64(pll_consumers+row*8,0xa0801234);row=row+1;}
 row=0;while row<6{let p=memory+pcf(row,0)*256+pcf(row,1);let mask=((1<<(pcf(row,2)-pcf(row,3)+1))-1)<<pcf(row,3);store8(p,(load8(p)&~mask)|(pcf(row,4)<<pcf(row,3)));row=row+1;}store8(memory+0x66*256+5,8);store8(memory+0x66*256+9,0xa6);
 check(!esp_radio_c6_pmu_stage(1000));pll_master_before=clock;pll_master_writes=0;pll_master_ignore=0;esp_radio_cpu_clock_active=1;esp_radio_cpu_clock_phase=2;esp_radio_cpu_clock_ps=0x1888;if masked{esp_radio_cpu_clock_ps=0x1880;}
 esp_radio_cpu_clock_root=pll_root;if on && gate{esp_radio_cpu_clock_root=pll_root|0x10000;}esp_radio_cpu_clock_cpu=pll_cpu;esp_radio_cpu_clock_ahb=pll_ahb;esp_radio_cpu_clock_apb=pll_apb;esp_radio_cpu_clock_ticks=40;if on && gate{esp_radio_cpu_clock_ticks=160;}ps=0x1880;return 0;
}
fn esp_radio_c6_pll_bus_recover_test(){let old=esp_radio_pmu_internal;esp_radio_pmu_internal=1;let result=esp_radio_c6_regi2c_recover(1000);esp_radio_pmu_internal=old;return result;}
fn pll_finish(old_power,old_ana,old_mspi){
 check(!esp_radio_c6_pll_restore(1000) && !esp_radio_pll_active && !esp_radio_pll_phase && ps==0x1880);
 check(clock==pll_master_before && !esp_radio_pll_master_clock_owned);
 check((pll_power&pcv(11))==(old_power&pcv(11)) && (pll_ana&12)==(old_ana&12) && pll_mspi==old_mspi);
 check(!esp_radio_c6_clock_restore(1000));let old_ps=ps;restoring=1;check(!esp_radio_c6_pmu_abort(1000) && ps==old_ps && !esp_radio_pmu_active);ps=0x1888;return 0;
}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size==2656);pll_meta=cfg+207*8;memory=alloc(65536);pmu_bank=alloc(392);pmu_before=alloc(392);pll_consumers=alloc(120);
 let mode=0;while mode<64{
  pll_case=mode;let on=mode&1;pll_reset(101+mode,on,(mode>>1)&1,(mode>>2)&1,(mode>>3)&1,(mode>>4)&1);if mode&32{routing=1<<cv(21);}let old=pll_power;let ana=pll_ana;let mspi=pll_mspi;
  check(!esp_radio_c6_pll_begin(1000) && esp_radio_pll_active && esp_radio_pll_phase==2 && !(pll_power&pcv(12)) && !(pll_mspi&pcv(16)) && ps==0x1880);
  check(esp_radio_c6_clock_restore(1000)==-16 && esp_radio_c6_pmu_commit()==-16 && esp_radio_c6_pmu_abort(1000)==-16 && esp_radio_c6_pll_begin(1000)==-16);
  pll_finish(old,ana,mspi);if on{check(pll_issued_writes==6 && pll_committed_writes==6 && pll_starts==1 && pll_stop_writes==1);}else{check(!pll_starts && !pll_power_writes && !pll_issued_writes);}mode=mode+1;
 }
 // Every functional clock selector and enable state is independently classified.
 let row=0;while row<15{let source=0;while source<4{let enabled=0;while enabled<2{
  pll_case=100+row*8+source*2+enabled;pll_reset(201+row,1,1,1,1,0);let word=source<<20;if enabled{word=word|pca(row,1);}store64(pll_consumers+row*8,word);
  let selected=(word&pca(row,2))>>20;let busy=enabled && (pca(row,3)&(1<<selected));let code=esp_radio_c6_pll_begin(1000);
  if busy{check(code==-16 && !esp_radio_pll_active && !pll_power_writes);}else{check(!code);}store64(pll_consumers+row*8,0);let old=0xf6008003;pll_finish(old,0xa5000004,0xa5a50005);
  enabled=enabled+1;}source=source+1;}row=row+1;
 }
 // Explicit users and USB/modem clocks block admission before PLL power writes.
 let item=0;while item<5{pll_case=300+item;pll_reset(311+item,1,1,1,1,0);if item==0{esp_radio_pll_consumers=1;}if item==1{pll_usb=1;}if item==2{pll_modem0=pll_modem0|0x1000000;}if item==3{pll_modem1=pll_modem1|1;}if item==4{store8(memory+0x66*256+5,0x88);}
  check(esp_radio_c6_pll_begin(1000)==-16 && !pll_power_writes);esp_radio_pll_consumers=0;pll_usb=0;pll_modem0=0x10800000;pll_modem1=0x30400;store8(memory+0x66*256+5,8);pll_finish(0xf6008003,0xa5000004,0xa5a50005);item=item+1;
 }
 // Seven preflight reads and nine canonical configuration bus commands can hang.
 let phase=1;while phase<=7{pll_case=400+phase;pll_reset(401+phase,1,1,1,1,0);hang=issued+phase;
  check(esp_radio_c6_pll_begin(21)==-110 && esp_radio_pll_active && !pll_power_writes && ps==0x1880);release=1;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(!pll_starts);phase=phase+1;
 }
 phase=1;while phase<=9{pll_case=500+phase;pll_reset(501+phase,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));hang=issued+phase;
  check(esp_radio_c6_pll_restore(21)==-110 && esp_radio_pll_active && ps==0x1880);let count=commands;check(esp_radio_c6_pll_restore(21)==-110 && commands==count);release=1;pll_finish(0xf6008003,0xa5000004,0xa5a50005);
  check(pll_committed_writes==6 && pll_issued_writes==6 && pll_starts==1);phase=phase+1;
 }
 // Power/control writes, done polling and fixed settling all retain ownership.
 phase=1;while phase<=3{pll_case=600+phase;pll_reset(601+phase,1,1,1,1,0);pll_ignored_write=phase;check(esp_radio_c6_pll_begin(21)==-110 && esp_radio_pll_active);pll_ignored_write=0;pll_finish(0xf6008003,0xa5000004,0xa5a50005);phase=phase+1;}
 pll_case=700;pll_reset(701,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));pll_hang_done=1;check(esp_radio_c6_pll_restore(1000)==-110 && esp_radio_pll_active);let count=pll_issued_writes;pll_hang_done=0;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(pll_issued_writes==count && pll_starts==1);
 pll_case=701;pll_reset(702,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));check(esp_radio_c6_pll_restore(100)==-110 && esp_radio_pll_active);count=pll_issued_writes;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(pll_issued_writes==count);
 // Every restore-side register-write timeout keeps the lease and resumes.
 phase=4;while phase<=10{pll_case=900+phase;pll_reset(901+phase,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));pll_ignored_write=phase;
  check(esp_radio_c6_pll_restore(1000)==-110 && esp_radio_pll_active && ps==0x1880);pll_ignored_write=0;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(pll_issued_writes==6 && pll_starts==1);phase=phase+1;}
 // Initially closed gates are opened for calibration and closed on recovery.
 phase=3;while phase<=10{pll_case=915+phase;pll_reset(916+phase,1,0,1,1,0);check(!esp_radio_c6_pll_begin(1000));pll_ignored_write=phase;
  check(esp_radio_c6_pll_restore(1000)==-110 && esp_radio_pll_active && ps==0x1880);pll_ignored_write=0;pll_finish(0xf4008003,0xa5000004,0xa5a50005);check(pll_issued_writes==6 && pll_starts==1);phase=phase+1;}
 // An uncertain write and the verification read can both time out in sequence.
 pll_case=920;pll_reset(921,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));hang=issued+1;check(esp_radio_c6_pll_restore(1000)==-110);release=1;check(!esp_radio_c6_pll_bus_recover_test());
 release=0;hang=issued+1;check(esp_radio_c6_pll_restore(1000)==-110 && esp_radio_pll_cal_pending==2);release=1;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(pll_issued_writes==6 && pll_starts==1);
 // Noncanonical coefficients are refused before any power change.
 row=0;while row<6{pll_case=940+row;pll_reset(941+row,1,1,1,1,0);let p=memory+pcf(row,0)*256+pcf(row,1);store8(p,load8(p)^(1<<pcf(row,3)));
  check(esp_radio_c6_pll_begin(1000)==-95 && esp_radio_pll_active && !pll_power_writes);pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(!pll_starts);row=row+1;}
 // All modem functional bits use the independent header masks; APB stays usable.
 let bank=0;while bank<2{let bit=0;while bit<32{pll_case=1000+bank*32+bit;pll_reset(1001+bit,1,1,1,1,0);let flag=1<<bit;let mask=pcv(17+bank);if bank{pll_modem1=pll_modem1|flag;}else{pll_modem0=pll_modem0|flag;}
  let result=esp_radio_c6_pll_begin(1000);if flag&mask{check(result==-16 && !pll_power_writes);}else{check(!result);}pll_modem0=0x10800000;pll_modem1=0x30400;pll_finish(0xf6008003,0xa5000004,0xa5a50005);bit=bit+1;}bank=bank+1;}
 // A consumer acquired while the PLL lease is held blocks all restore writes.
 pll_case=1100;pll_reset(1101,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));pll_usb=1;count=pll_reg_writes;
 check(esp_radio_c6_pll_restore(1000)==-16 && esp_radio_pll_active && pll_reg_writes==count && esp_radio_c6_pll_consumer(1)==-16);pll_usb=0;pll_finish(0xf6008003,0xa5000004,0xa5a50005);
 // Settling remains bounded across the32-bit cycle-counter wrap.
 mode=0;while mode<4{pll_case=1120+mode;pll_reset(1121+mode,1,1,1,1,0);check(!esp_radio_c6_pll_begin(1000));tick=0xffffff00+mode*64;pll_finish(0xf6008003,0xa5000004,0xa5a50005);check(pll_starts==1 && pll_stop_writes==1);mode=mode+1;}
 // Outer master-clock enable/restore readback failures retain PLL ownership.
 phase=1;while phase<=2{pll_case=1150+phase;pll_reset(1151+phase,1,1,1,1,0);clock=clock&~cv(12);pll_master_before=clock;pll_master_ignore=phase;
  if phase==1{check(esp_radio_c6_pll_begin(1000)==-110 && esp_radio_pll_active && !pll_power_writes);}else{check(!esp_radio_c6_pll_begin(1000));check(esp_radio_c6_pll_restore(1000)==-110 && esp_radio_pll_active && pll_stop_writes==1);}
  pll_master_ignore=0;pll_finish(0xf6008003,0xa5000004,0xa5a50005);phase=phase+1;}
 // Consumer count errors and invalid budgets preserve state and signed words.
 pll_case=800;pll_reset(801,1,1,1,1,0);check(esp_radio_c6_pll_consumer(2)==-22 && esp_radio_c6_pll_consumer(0)==-22);esp_radio_pll_consumers=9223372036854775807;check(esp_radio_c6_pll_consumer(1)==-75 && esp_radio_pll_consumers==9223372036854775807);esp_radio_pll_consumers=0;check(!esp_radio_c6_pll_consumer(1) && esp_radio_c6_pll_begin(1000)==-16 && !esp_radio_c6_pll_consumer(0));check(esp_radio_c6_pll_begin(0)==-22 && esp_radio_c6_pll_restore(2147483648)==-22 && !pll_power_writes);pll_finish(0xf6008003,0xa5000004,0xa5a50005);
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
