// CPU/ABI/IRQ test with an explicit clock and readonly-monitor boundary.
// No PMU, analog or RF accesses are issued by these fixtures.
global esp_radio_hw_ready=0;
global deadline_tick=0;global deadline_start=0;global deadline_calls=0;
global deadline_reads=0;global deadline_mode=0;global deadline_delta=0;
global deadline_budget=400;
fn deadline_cycles(){
 if deadline_mode && esp_radio_base_active && esp_radio_base_recovery==7{
  deadline_calls=deadline_calls+1;if deadline_calls==1{deadline_start=deadline_tick;}
  if deadline_mode==3 && deadline_calls>1{deadline_tick=(deadline_start+deadline_budget)&0xffffffff;}
  return deadline_tick;
 }
 deadline_tick=(deadline_tick+7)&0xffffffff;return deadline_tick;
}
fn deadline_load32(address){
 if address==0x600b0194{
  deadline_reads=deadline_reads+1;if !deadline_mode{return esp_radio_base_live;}
  let elapsed=deadline_delta;if deadline_mode==2 && deadline_reads==1{elapsed=deadline_budget/2;}
  deadline_tick=(deadline_start+elapsed)&0xffffffff;
  if deadline_mode==2 && deadline_reads==1{return esp_radio_base_live^0x100000;}
  return esp_radio_base_live;
 }
 return esp32_load32(address);
}
fn deadline_seed(ps,wrapped){
 esp32_irq_save();esp_radio_owner=1;esp_radio_base_active=1;esp_radio_base_internal=0;
 esp_radio_base_phase=2;esp_radio_base_step=6;esp_radio_base_recovery=7;
 esp_radio_base_command_step=2;esp_radio_base_issued=0;esp_radio_base_live=0xd00000;
 esp_radio_base_ps=ps;esp_radio_base_error=-5;esp_radio_base_cleanup_error=0;
 deadline_tick=0;if wrapped{deadline_tick=0xfffffff0;}
 deadline_calls=0;deadline_reads=0;return 0;
}
fn deadline_case(ps,wrapped,mode,budget,boundary){
 deadline_seed(ps,wrapped);deadline_mode=mode;deadline_budget=budget;deadline_delta=budget-1+boundary;
 let result=esp_radio_c6_base_abort(budget);let reads=deadline_reads;let actual=esp32_irq_save();esp32_irq_restore(actual);
 if !boundary{
  if result{return 1;}if esp_radio_base_active || esp_radio_base_phase || esp_radio_base_recovery || esp_radio_base_cleanup_error || actual!=ps{return 2;}
 }else{
  if result!=-110{return 1;}if !esp_radio_base_active || esp_radio_base_phase!=2 || esp_radio_base_recovery!=7 || esp_radio_base_cleanup_error!=-110 || actual!=(ps&~8){return 3;}
  deadline_mode=0;if esp_radio_c6_base_abort(1000){return 4;}
  actual=esp32_irq_save();esp32_irq_restore(actual);if esp_radio_base_active || esp_radio_base_recovery || esp_radio_base_cleanup_error || actual!=ps{return 5;}
 }
 if reads!=mode || esp_radio_base_error!=-5{return 6;}return 0;
}
fn main(){
 let original=esp32_irq_save();let id=0;let enabled=0;
 while enabled<2{let ps=(original&~8)|(enabled*8);let wrapped=0;while wrapped<2{let mode=1;while mode<=2{let size=0;while size<3{
  let budget=4;if size==1{budget=400;}if size==2{budget=2147483647;}
  let boundary=0;while boundary<3{let r=deadline_case(ps,wrapped,mode,budget,boundary);if r{return 100+id*16+r;}id=id+1;boundary=boundary+1;}
  size=size+1;
 }mode=mode+1;}wrapped=wrapped+1;}enabled=enabled+1;}
 // Expired before the monitor access: retain ownership without another read.
 deadline_seed(original|8,1);deadline_mode=3;deadline_budget=400;deadline_delta=0;
 if esp_radio_c6_base_abort(400)!=-110{return 2501;}
 if deadline_reads || !esp_radio_base_active || esp_radio_base_recovery!=7 || (esp32_irq_save()&8){return 2503;}
 // Invalid budgets must not change the retained receipt or restore IRQs.
 if esp_radio_c6_base_abort(0)!=-22 || esp_radio_c6_base_abort(2147483648)!=-22 || !esp_radio_base_active || esp_radio_base_recovery!=7 || (esp32_irq_save()&8){return 2504;}
 deadline_mode=0;if esp_radio_c6_base_abort(1000){return 2505;}
 let ps=esp32_irq_save();if ps!=(original|8) || esp_radio_base_active || esp_radio_base_cleanup_error || esp_radio_base_error!=-5{return 2506;}
 esp32_irq_restore(original);return 0;
}
