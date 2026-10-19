import "../../lib/platform/esp32c6.flex";
import "../../lib/platform/esp32c6-radio-pmu-stage.flex";
global esp_radio_hw_ready=0;
fn main(){
 esp_radio_owner=1;let before=esp32_load32(esp32_state());
 let capacity=32768;if esp32_state()==0x40810000{capacity=16384;}let reserve=0;
 if alloc(capacity-reserve)<0{return 1;}
 let rf=esp32_load32(0x600b0154);let clock=esp32_load32(0x600af018);let source=esp32_load32(0x600af010);let select=esp32_load32(0x600af81c);
 let mode=0;while mode<2{
  let ps=esp32_irq_save();if !mode{esp32_irq_restore(ps|8);}
  if esp_radio_c6_ocode_stage(0)!=-22 || esp_radio_c6_ocode_abort(2147483648)!=-22 || esp_radio_c6_ocode_stage(1000)!=-16 || esp_radio_c6_ocode_abort(1000)!=-16{return 6;}
  let attempt=0;while attempt<3{
   if esp_radio_c6_pmu_stage(1000)!=-12{return 2;}
   let actual=esp32_irq_save();if (actual&8)!=(!mode*8){return 3;}esp32_irq_restore(actual);
   if esp_radio_pmu_saved || esp_radio_pmu_active || esp_radio_pmu_phase || esp_radio_pmu_analog_count || esp_radio_pmu_digital_count || esp_radio_pmu_internal || esp_radio_pmu_configured || esp_radio_ocode_active || esp_radio_ocode_ready || esp_radio_ocode_phase || esp_radio_ocode_count || esp_radio_regi2c_active || esp_radio_owner!=1{return 4;}
   if esp32_load32(esp32_state())!=before+capacity-reserve || esp32_load32(0x600b0154)!=rf || esp32_load32(0x600af018)!=clock || esp32_load32(0x600af010)!=source || esp32_load32(0x600af81c)!=select{return 5;}
   attempt=attempt+1;
  }
  esp32_irq_restore(ps);mode=mode+1;
 }
 return 0;
}
