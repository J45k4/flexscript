import "../../scripts/lib/build.flex";
import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-clock.flex";
global esp_radio_hw_ready=0;
global cfg=0;global checks=0;global ps=0x1888;global isr=0;global ready=1;
global root_reg=0;global cpu_reg=0;global ahb_reg=0;global apb_reg=0;global query_reg=0;global pll_reg=0x42000001;
global dma_reg=0;global regdma_reg=0;global spi0_reg=0;global spi1_reg=0;global rom_ticks=160;
global writes=0;global ignored_write=0;global ignore_ticks=0;global tick=0;global rom_calls=0;global case_id=0;
fn cv(i){return load64(cfg+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("clock check ",h_int(checks),h_cat3(" case ",h_int(case_id)," failed\n")));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_state(){if ready{return rv_hal_state;}return 0;}
fn esp32_irq_save(){let before=ps;ps=ps&~8;return before;}
fn esp32_irq_restore(value){ps=value;return 0;}
fn esp32_cycles(){tick=(tick+7)&0xffffffff;return tick;}
fn esp32_call64(address,a,b,c,d,e,f,g,h){
 if address==17{return esp_radio_c6_clock_begin_iram(a,b,c,d,e,f,g,h);}
 check(address==19);return esp_radio_c6_clock_restore_iram(a,b,c,d,e,f,g,h);
}
fn esp32_call32(address,a,b,c,d,e,f,g,h){
 // Model the real call32 return convention so unsigned truncation cannot
 // hide a signed-status bug in the callback trampoline.
 if address==17{return esp_radio_c6_clock_begin_iram(a,b,c,d,e,f,g,h)&0xffffffff;}
 if address==19{return esp_radio_c6_clock_restore_iram(a,b,c,d,e,f,g,h)&0xffffffff;}
 check(!(ps&8) && !b && !c && !d && !e && !f && !g && !h);rom_calls=rom_calls+1;
 if address==cv(13){check(!a);return rom_ticks;}check(address==cv(14));check(a>0 && a<=480);if !ignore_ticks{rom_ticks=a;}return 0;
}
fn esp32_load32(address){
 check(!(ps&8));if address==rv_hal_state+16{return isr;}
 if address==cv(0){return root_reg;}if address==cv(1){return cpu_reg;}if address==cv(2){return ahb_reg;}if address==cv(3){return apb_reg;}if address==cv(4){return query_reg;}
 if address==cv(5){return pll_reg;}if address==cv(6){return dma_reg;}if address==cv(7){return regdma_reg;}if address==cv(8){return spi0_reg;}check(address==cv(9));return spi1_reg;
}
fn hw_cpu(){let source=(root_reg>>16)&3;if source==1{if ((cpu_reg>>8)&255)==0 && (cpu_reg&65536){return 120000000;}return 160000000/(((cpu_reg>>8)&255)+1);}let hz=40000000;if source==2{hz=20000000;}return hz/((cpu_reg&255)+1);}
fn hw_ahb(){if ((root_reg>>16)&3)==1{return 160000000/(((ahb_reg>>8)&255)+1);}let hz=40000000;if ((root_reg>>16)&3)==2{hz=20000000;}return hz/((ahb_reg&255)+1);}
fn esp32_store32(address,value){
 check(!(ps&8) && esp_radio_cpu_clock_active);writes=writes+1;
 let old=root_reg;let mask=cv(10);if address==cv(1){old=cpu_reg;mask=cv(11);}else if address==cv(2){old=ahb_reg;mask=cv(12);}else{check(address==cv(0));}
 check(!((old^value)&~mask));if writes==ignored_write{return 0;}
 if address==cv(0){root_reg=value;}else if address==cv(1){cpu_reg=value;}else{ahb_reg=value;}
 check(hw_ahb()<=hw_cpu());return 0;
}
fn reset(root,cpu,ahb,apb,query,ticks){
 check(!esp_radio_cpu_clock_active);if !esp_radio_pmu_saved{esp_radio_pmu_saved=alloc(416);}root_reg=root;cpu_reg=cpu;ahb_reg=ahb;apb_reg=apb;query_reg=query;rom_ticks=ticks;
 pll_reg=cv(17);dma_reg=0;regdma_reg=0;spi0_reg=0;spi1_reg=0;writes=0;ignored_write=0;ignore_ticks=0;tick=0xfffffff0;rom_calls=0;ps=0x1888;
 ready=1;isr=0;rv_hal_chip=13;esp_radio_owner=1;esp_adc_busy=0;esp_radio_phy_refs=0;esp_radio_phy_clock_refs=0;esp_radio_hw_ready=0;
 esp_radio_pmu_active=1;esp_radio_pmu_phase=1;esp_radio_pmu_configured=0;esp_radio_pmu_analog_count=3;esp_radio_pmu_digital_count=49;esp_radio_regi2c_active=0;esp_radio_ocode_active=0;esp_radio_ocode_ready=0;return 0;
}
fn base(){return reset(0x28010200,0x55000003,0x66000307,0,0x1e014,160);}
fn restored(root,cpu,ahb,apb,ticks,saved_ps){check(!esp_radio_cpu_clock_active && !esp_radio_cpu_clock_phase && ps==saved_ps && root_reg==root && cpu_reg==cpu && ahb_reg==ahb && apb_reg==apb && rom_ticks==ticks);return 0;}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));check(h_file_size>=144);let count=cv(15);check(h_file_size==144+count*64);let at=cfg+144;let i=0;
 while i<count{
  let root=load64(at);let cpu=load64(at+8);let ahb=load64(at+16);let apb=load64(at+24);let query=load64(at+32);let cpu_hz=load64(at+40);let ahb_hz=load64(at+48);let apb_hz=load64(at+56);
  let mode=0;while mode<2{
   case_id=i*2+mode;reset(root,cpu,ahb,apb,query,cpu_hz/1000000);if mode{ps=0x1880;}let saved_ps=ps;
   check(esp_radio_c6_clock_frequency(0)==cpu_hz && esp_radio_c6_clock_frequency(1)==ahb_hz && esp_radio_c6_clock_frequency(2)==apb_hz && ps==saved_ps && !writes);
   if cpu_hz<1000000{check(esp_radio_c6_clock_begin(100)==-95 && !esp_radio_cpu_clock_active && !writes && ps==saved_ps);}
   else{
    check(!esp_radio_c6_clock_begin(100) && esp_radio_cpu_clock_active && esp_radio_cpu_clock_phase==2 && ps==(saved_ps&~8) && rom_ticks==40);
    check(esp_radio_c6_clock_frequency(0)==40000000 && esp_radio_c6_clock_frequency(1)==40000000 && esp_radio_c6_clock_frequency(2)==40000000/(((apb>>8)&255)+1));
    let before=writes;check(esp_radio_c6_clock_begin(100)==-16 && writes==before && esp_radio_c6_pmu_commit()==-16 && esp_radio_c6_pmu_abort(100)==-16);
    // Unowned high/reserved bits survive the field-wise restoration.
    cpu_reg=cpu_reg^0x80000000;ahb_reg=ahb_reg^0x80000000;apb_reg=apb_reg^0x80000000;
    check(!esp_radio_c6_clock_restore(100));restored(root,cpu^0x80000000,ahb^0x80000000,apb^0x80000000,cpu_hz/1000000,saved_ps);
    before=writes;check(!esp_radio_c6_clock_restore(100) && writes==before && ps==saved_ps);
   }
   mode=mode+1;
  }at=at+64;i=i+1;
 }
 // Initial hardware/software owners are rejected before writes or ROM changes.
 i=0;while i<14{case_id=10000+i;base();if i==0{ready=0;}if i==1{rv_hal_chip=5;}if i==2{esp_radio_owner=0;}if i==3{esp_adc_busy=1;}if i==4{esp_radio_phy_refs=1;}if i==5{esp_radio_phy_clock_refs=1;}if i==6{esp_radio_hw_ready=1;}if i==7{isr=1;}if i==8{esp_radio_regi2c_active=1;}if i==9{esp_radio_ocode_active=1;}if i==10{dma_reg=1;}if i==11{regdma_reg=1;}if i==12{spi0_reg=1<<18;}if i==13{spi1_reg=1<<31;}
  let expected=-16;if i<2{expected=-95;}check(esp_radio_c6_clock_begin(100)==expected && !esp_radio_cpu_clock_active && !writes && !rom_calls && ps==0x1888);i=i+1;
 }
 // Every primary command/FSM bit is rejected on both SPI controllers;
 // reserved bits are ignored and do not prevent a valid handoff/restore.
 i=0;while i<64{case_id=10500+i;base();let bit=1<<(i%32);if i<32{spi0_reg=bit;}else{spi1_reg=bit;}
  if cv(16)&bit{check(esp_radio_c6_clock_begin(100)==-16 && !esp_radio_cpu_clock_active && !writes && !rom_calls && ps==0x1888);}
  else{check(!esp_radio_c6_clock_begin(100) && !esp_radio_c6_clock_restore(100));}i=i+1;
 }
 base();check(esp_radio_c6_clock_begin(0)==-22 && esp_radio_c6_clock_restore(2147483648)==-22 && !writes && !rom_calls && ps==0x1888);
 // Invalid source/divider encodings never start a transaction.
 i=0;while i<9{case_id=11000+i;base();if i==0{root_reg=root_reg|0x30000;}if i==1{root_reg=root_reg^1;}if i==2{root_reg=root_reg^(1<<24);}if i==3{cpu_reg=cpu_reg|0x200;}if i==4{ahb_reg=(ahb_reg&~0xff00)|0x200;}if i==5{apb_reg=0x200;}if i==6{apb_reg=2;}if i==7{query_reg=0;}if i==8{rom_ticks=0;}
  check(esp_radio_c6_clock_begin(100)==-95 && !esp_radio_cpu_clock_active && !writes && ps==0x1888);i=i+1;
 }
 // Every entry/restore write can be ignored; restore repairs partial state.
 i=1;while i<=3{case_id=12000+i;base();ignored_write=i;check(esp_radio_c6_clock_begin(21)==-110 && esp_radio_cpu_clock_active && ps==0x1880);ignored_write=0;check(!esp_radio_c6_clock_restore(100));restored(0x28010200,0x55000003,0x66000307,0,160,0x1888);i=i+1;}
 i=1;while i<=3{case_id=13000+i;base();check(!esp_radio_c6_clock_begin(100));ignored_write=writes+i;check(esp_radio_c6_clock_restore(21)==-110 && esp_radio_cpu_clock_active && ps==0x1880);ignored_write=0;check(!esp_radio_c6_clock_restore(100));restored(0x28010200,0x55000003,0x66000307,0,160,0x1888);i=i+1;}
 // A later PLL consumer cannot return the CPU to an unstable/off PLL.
 case_id=14000;base();check(!esp_radio_c6_clock_begin(100));pll_reg=0;let before=writes;check(esp_radio_c6_clock_restore(21)==-110 && esp_radio_cpu_clock_active && writes==before && ps==0x1880);pll_reg=0x42000001;check(!esp_radio_c6_clock_restore(100));
 // Test each primary PLL stable/power/global-gate status bit independently.
 i=0;while i<32{if cv(17)&(1<<i){case_id=14500+i;base();check(!esp_radio_c6_clock_begin(100));pll_reg=cv(17)&~(1<<i);before=writes;
  check(esp_radio_c6_clock_restore(21)==-110 && esp_radio_cpu_clock_active && writes==before && ps==0x1880);pll_reg=cv(17);check(!esp_radio_c6_clock_restore(100));}i=i+1;
 }
 // ROM delay calibration failures also retain the mask/lease until repaired.
 case_id=15000;base();ignore_ticks=1;check(esp_radio_c6_clock_begin(100)==-5 && esp_radio_cpu_clock_active && ps==0x1880);ignore_ticks=0;check(!esp_radio_c6_clock_restore(100));
 case_id=15001;base();check(!esp_radio_c6_clock_begin(100));ignore_ticks=1;check(esp_radio_c6_clock_restore(100)==-5 && esp_radio_cpu_clock_active && ps==0x1880);ignore_ticks=0;check(!esp_radio_c6_clock_restore(100));
 // Foreign clock ownership is refused without overwriting its fields.
 i=0;while i<4{case_id=16000+i;base();check(!esp_radio_c6_clock_begin(100));if i==0{root_reg=root_reg|0x20000;}if i==1{cpu_reg=cpu_reg^0x100;}if i==2{ahb_reg=ahb_reg^0x100;}if i==3{apb_reg=0x100;}before=writes;check(esp_radio_c6_clock_restore(100)==-16 && writes==before && esp_radio_cpu_clock_active && ps==0x1880);
  root_reg=0x28000200;cpu_reg=0x55000000;ahb_reg=0x66000300;apb_reg=0;check(!esp_radio_c6_clock_restore(100));i=i+1;
 }
 let out=alloc(8);store64(out,checks);return syscall(1,1,out,8,0,0,0)!=8;
}
