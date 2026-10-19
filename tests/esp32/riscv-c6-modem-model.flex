import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-modem.flex";
// Prepared PMU/calibration are injected here. Their actual transactions run in
// the independent PMU/coordinator suites; this cohort executes real modem code.
global esp_radio_hw_ready=0;
global cfg=0;global bank=0;global before=0;global checks=0;global case_id=0;
global ps=0;global saved_ps=0;global tick=0;global ready=1;global isr=0;
global timer=0;global coex=0;global forced=0;global writes=0;global reads=0;
global fault_step=0;global fault_recovery= -1;global recovering=0;global late=0;
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("modem check ",h_int(checks),h_cat3(" case ",h_int(case_id)," failed\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn check_at(line,ok){if !ok{h_print(2,h_cat3("line ",h_int(line)," failed\n"));}return check(ok);}
fn cv(index){return load64(cfg+index*8);}
fn esp32_state(){if ready{return rv_hal_state;}return 0;}
fn esp32_irq_save(){let old=ps;ps=ps&~8;return old;}
fn esp32_irq_restore(value){if esp_radio_modem_active{check(!(value&8));}ps=value;return 0;}
fn esp32_cycles(){tick=(tick+7)&0xffffffff;return tick;}
fn esp32_call32(a,b,c,d,e,f,g,h,i){check(0);return 0;}
fn row(address){let i=0;while i<5{if address==cv(1+i){return i;}i=i+1;}return -1;}
fn esp32_load32(address){
 check(!(ps&8));reads=reads+1;if address==rv_hal_state+16{return isr;}if address==0x600af004{return timer;}if address==0x600af008{return coex;}if address==0x600af01c{return forced;}
 let i=row(address);check(i>=0);if late{late=late-1;if !late{tick=(tick+100)&0xffffffff;}}return load64(bank+i*8);
}
fn esp32_store32(address,value){
 check(!(ps&8) && esp_radio_modem_active && esp_radio_modem_internal);let i=row(address);check(i>=0);value=value&0xffffffff;check(value!=load64(bank+i*8));writes=writes+1;
 // Wi-Fi's timer is stopped and its old mux disconnected before selecting a
 // shared source. Divisor writes cannot re-enable another source bit.
 if i==2 || i==3{check(!(load64(bank+32)&1));}
 if i==3{check(!(load64(bank+16)&15));}
 if i==2 && !recovering && esp_radio_modem_step==6{check(!(load64(bank+16)&15));}
 if (!recovering && fault_step==esp_radio_modem_step) || (recovering && fault_recovery==esp_radio_modem_recovery){return 0;}
 store64(bank+i*8,value);return 0;
}
fn reset_case(v,mode){
 check(!esp_radio_modem_active);esp_radio_modem_configured=0;esp_radio_modem_internal=0;esp_radio_modem_phase=0;esp_radio_modem_recovery=0;esp_radio_modem_step=0;
 esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_radio_hw_ready=0;esp_radio_pmu_active=1;esp_radio_pmu_phase=1;esp_radio_pmu_analog_count=3;esp_radio_pmu_digital_count=49;esp_radio_pmu_force_count=6;esp_radio_pmu_configured=0;esp_radio_pmu_internal=0;esp_radio_regi2c_active=0;esp_radio_cpu_clock_active=0;esp_radio_pll_active=0;esp_radio_ocode_active=0;esp_radio_ocode_phase=0;esp_radio_ocode_ready=1;esp_radio_calibration_active=0;
 saved_ps=0x1880|(mode*8);ps=saved_ps;ready=1;rv_hal_chip=13;isr=0;timer=0;coex=0;forced=0;writes=0;reads=0;tick=0xfffffff0;fault_step=0;fault_recovery= -1;recovering=0;late=0;
 let i=0;while i<5{let value=load64(v+(2+i)*8);store64(bank+i*8,value);store64(before+i*8,value);i=i+1;}return 0;
}
fn fault_case(v){reset_case(v,1);let i=0;while i<5{store64(bank+i*8,0);i=i+1;}store64(bank+16,0x2222);store64(bank+32,1);i=0;while i<5{store64(before+i*8,load64(bank+i*8));i=i+1;}return 0;}
fn held(){check(esp_radio_modem_active && !esp_radio_modem_internal && ps==(saved_ps&~8) && esp_radio_pmu_active);check(esp_radio_c6_pll_consumer(1)==-16 && !esp_radio_pll_consumers && esp_radio_c6_pmu_abort(1000)==-16 && esp_radio_c6_pmu_commit()==-16 && esp_radio_c6_ocode_abort(1000)==-16 && esp_radio_c6_pmu_analog(0,1,1000)==-16 && esp_radio_c6_modem_stage(0,0,1000)==-16);return 0;}
fn restored(changed){check(!esp_radio_modem_active && !esp_radio_modem_phase && !esp_radio_modem_step && !esp_radio_modem_recovery && !esp_radio_modem_internal && ps==saved_ps && esp_radio_pmu_active && esp_radio_ocode_ready);let i=0;while i<5{let mask=0xffff;if i==0{mask=0xffffff00;}if i==1{mask=0xffff0000;}if i==3{mask=3;}if i==4{mask=1;}check(load64(bank+i*8)==(load64(before+i*8)^(changed&~mask)));i=i+1;}return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(cv(0)==24576);bank=alloc(40);before=alloc(40);let vector=0;
 while vector<cv(0){case_id=vector;let v=cfg+48+vector*96;let mode=0;while mode<2{reset_case(v,mode);check(!esp_radio_c6_modem_stage(load64(v),load64(v+8),1000));check(esp_radio_modem_phase==1 && esp_radio_modem_step==8 && !esp_radio_modem_error);held();let i=0;while i<5{check(load64(bank+i*8)==load64(v+(7+i)*8));i=i+1;}
  // Preserve changes to every uncontrolled bit while restoring owned fields.
  i=0;while i<5{let mask=0xffff;if i==0{mask=0xffffff00;}if i==1{mask=0xffff0000;}if i==3{mask=3;}if i==4{mask=1;}store64(bank+i*8,load64(bank+i*8)^(0xffffffff&~mask));i=i+1;}
  recovering=1;check(!esp_radio_c6_modem_abort(1000));restored(0xffffffff);let count=writes;check(!esp_radio_c6_modem_abort(1000) && writes==count);mode=mode+1;}vector=vector+1;
 }
 let v=cfg+48;
 // Every preparation step can fail without losing the snapshots or IRQ mask.
 let step=1;while step<=8{case_id=30000+step;fault_case(v);fault_step=step;check(esp_radio_c6_modem_stage(3,77,1000)==-110 && esp_radio_modem_error==-110 && esp_radio_modem_phase==2 && esp_radio_modem_step==step);held();check(esp_radio_c6_modem_commit()==-16);recovering=1;check(!esp_radio_c6_modem_abort(1000) && esp_radio_modem_error==-110);restored(0);step=step+1;}
 // Abort resumes at each failed restore step, without replaying earlier stores.
 step=0;while step<7{case_id=31000+step;fault_case(v);check(!esp_radio_c6_modem_stage(3,77,1000));recovering=1;fault_recovery=step;check(esp_radio_c6_modem_abort(1000)==-110 && esp_radio_modem_recovery==step && esp_radio_modem_cleanup_error==-110 && !esp_radio_modem_error);held();check(esp_radio_c6_modem_abort(1000)==-110 && esp_radio_modem_recovery==step);fault_recovery= -1;check(!esp_radio_c6_modem_abort(1000) && !esp_radio_modem_cleanup_error);restored(0);step=step+1;}
 fault_case(v);fault_step=8;check(esp_radio_c6_modem_stage(3,77,1000)==-110);recovering=1;fault_recovery=1;check(esp_radio_c6_modem_abort(1000)==-110 && esp_radio_modem_error==-110 && esp_radio_modem_cleanup_error==-110);fault_recovery= -1;check(!esp_radio_c6_modem_abort(1000) && esp_radio_modem_error==-110);restored(0);
 // A late successful read is still a timeout; cleanup reads back before retry.
 fault_case(v);check(!esp_radio_c6_modem_stage(3,77,1000));esp_radio_modem_internal=1;late=2;check(esp_radio_c6_modem_put(cv(5),1,1,14)==-110);esp_radio_modem_internal=0;recovering=1;check(!esp_radio_c6_modem_abort(1000));restored(0);
 // Shared 32k users and forced/enabled foreign clocks refuse before ownership.
 let which=0;while which<9{fault_case(v);if which==0{timer=8;}if which==1{coex=8;}if which==2{forced=1;}if which==3{forced=2;}if which==4{forced=8;}if which==5{store64(bank+32,3);}if which==6{store64(bank+32,9);}if which==7{esp_radio_ocode_ready=0;}if which==8{isr=1;}check(esp_radio_c6_modem_stage(3,77,1000)==-16 && !esp_radio_modem_active && !writes && ps==saved_ps);which=which+1;}
 fault_case(v);timer=8;coex=8;store64(bank+24,1);store64(before+24,1);check(!esp_radio_c6_modem_stage(3,77,1000));recovering=1;check(!esp_radio_c6_modem_abort(1000));restored(0);
 // Invalid inputs and foreign/partial leases never access the modem MMIO bank.
 fault_case(v);let n=reads;check(esp_radio_c6_modem_stage(-1,0,1000)==-22 && esp_radio_c6_modem_stage(6,0,1000)==-22 && esp_radio_c6_modem_stage(0,-1,1000)==-22 && esp_radio_c6_modem_stage(0,4096,1000)==-22 && esp_radio_c6_modem_stage(0,0,0)==-22 && esp_radio_c6_modem_abort(2147483648)==-22 && reads==n && ps==saved_ps);esp_radio_pmu_phase=2;check(esp_radio_c6_modem_stage(0,0,1000)==-16);esp_radio_pmu_phase=1;esp_radio_cpu_clock_active=1;check(esp_radio_c6_modem_stage(0,0,1000)==-16);esp_radio_cpu_clock_active=0;ready=0;check(esp_radio_c6_modem_stage(0,0,1000)==-95 && !esp_radio_modem_active && ps==saved_ps);ready=1;
 // One atomic commit transfers the PMU and modem leases to platform lifetime.
 let mode=0;while mode<2{fault_case(v);saved_ps=0x1880|(mode*8);ps=saved_ps;esp_radio_ocode_active=1;esp_radio_ocode_phase=1;check(!esp_radio_c6_modem_stage(3,77,1000));esp_radio_phy_refs=1;check(esp_radio_c6_modem_commit()==-16 && esp_radio_modem_active && esp_radio_pmu_active && ps==(saved_ps&~8));esp_radio_phy_refs=0;esp_radio_hw_ready=1;check(esp_radio_c6_modem_commit()==-16 && esp_radio_modem_active && esp_radio_pmu_active && ps==(saved_ps&~8));esp_radio_hw_ready=0;check(!esp_radio_c6_modem_commit() && !esp_radio_modem_active && esp_radio_modem_configured && !esp_radio_pmu_active && esp_radio_pmu_configured && !esp_radio_ocode_active && ps==saved_ps);check(esp_radio_c6_modem_stage(3,77,1000)==-16 && esp_radio_c6_modem_abort(1000)==-16 && esp_radio_c6_modem_commit()==-16);mode=mode+1;}
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
