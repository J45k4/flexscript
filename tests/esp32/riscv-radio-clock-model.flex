global rv_hal_chip=0;global esp_radio_hw_ready=0;
global callback_ps=0;global checks=0;global cfg=0;global row=0;
global reads=0;global writes=0;global guard_seen=0;global pending=0;
global first_word=0;global second_word=0;
fn cv(i){return load64(row+i*8);}
fn check(ok){checks=checks+1;if !ok{h_print(2,h_cat3("clock callback check ",h_int(checks)," failed ps="));h_print(2,h_int(callback_ps));h_print(2,h_cat3(" owner=",h_int(esp_radio_owner)," ready="));h_print(2,h_int(esp_radio_hw_ready));h_print(2,h_cat3(" guard=",h_int(guard_seen),"\n"));syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_irq_save(){let old=callback_ps;callback_ps=old&~8;return old;}
fn esp32_irq_restore(ps){callback_ps=ps;if pending && (ps&8) && writes==1{esp_radio_owner=0;}return 0;}
fn esp32_load32(address){check(!(callback_ps&8));reads=reads+1;check(address==cv(4)||address==cv(5));if address==cv(4){return first_word;}return second_word;}
fn esp32_store32(address,value){
 check(!(callback_ps&8)&&guard_seen&&esp_radio_owner==1&&esp_radio_hw_ready);
 check(!esp_radio_base_active&&!esp_radio_regi2c_active&&!esp_radio_pmu_active);
 check(writes<2&&address==cv(4+writes)&&value==cv(8+writes));
 if address==cv(4){first_word=value;}else{second_word=value;}writes=writes+1;
 // A peripheral can change unrelated fields despite CPU IRQ masking.
 if writes==1{if cv(1)==0{first_word=first_word^cv(3);}else{second_word=second_word^cv(3);}}
 return 0;
}
fn esp32_call32(target,a,b,c,d,e,f,g,h){
 check(!target&&!(callback_ps&8)&&!writes&&!reads);
 let result=alloc(16);store64(result,writes);store64(result+8,callback_ps);
 syscall(1,1,result,16,0,0,0);syscall(60,77,0,0,0,0,0);return 0;
}
fn seed(r,irq){
 row=r;rv_hal_chip=5;if cv(0)==6{rv_hal_chip=13;}callback_ps=0x1880|(irq*8);
 esp_radio_owner=1;esp_radio_hw_ready=1;esp_radio_base_active=0;esp_radio_regi2c_active=0;esp_radio_pmu_active=0;
 reads=0;writes=0;guard_seen=0;pending=1;first_word=cv(2);second_word=cv(2)^0xa5a5a5a5;return 0;
}
fn invoke(){if cv(1)==0{return esp_radio_cb_wifi_reset(0,0,0,0,0,0,0,0);}if cv(1)==1{return esp_radio_cb_wifi_clock_on(0,0,0,0,0,0,0,0);}return esp_radio_cb_wifi_clock_off(0,0,0,0,0,0,0,0);}
fn main(argc,argv){
 h_environment(argc,argv);cfg=h_read(load64(argv+8));let count=load64(cfg);check(h_file_size==8+count*80);
 if argc==5{
  let guard=load8(load64(argv+16))-48;let mode=load8(load64(argv+24))-48;let irq=load8(load64(argv+32))-48;
  let i=0;while i<count{row=cfg+8+i*80;if cv(0)==6&&cv(1)==mode{seed(row,irq);i=count;}else{i=i+1;}}
  if guard==1{esp_radio_base_active=1;}else if guard==2{esp_radio_regi2c_active=1;}else if guard==3{esp_radio_pmu_active=1;}else if guard==4{esp_radio_hw_ready=0;}else if guard==5{esp_radio_owner=0;}else{esp_radio_owner=2;}
  invoke();return 99;
 }
 let i=0;while i<count{
  let irq=0;while irq<2{
   seed(cfg+8+i*80,irq);let before=callback_ps;check(!invoke());check(callback_ps==before&&esp_radio_owner==1&&guard_seen==1);
   let expected=0;if cv(4){expected=2;}check(writes==expected&&reads==expected);
   let n=writes;check(esp_radio_wifi_clock(-1)==-22&&esp_radio_wifi_clock(2)==-22&&writes==n&&callback_ps==before);
   irq=irq+1;
  }i=i+1;
 }
 let result=alloc(8);store64(result,checks);return syscall(1,1,result,8,0,0,0)!=8;
}
