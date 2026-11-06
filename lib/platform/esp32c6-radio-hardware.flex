import "esp32-riscv-radio-hardware.flex";
import "esp32c6-radio-base.flex";
// C6 cannot use the C3 power/isolation register sequence. The base/PHY startup
// consumer remains gated until its complete hardware contract is verified.
fn esp_radio_hardware_init(){
 if !esp_riscv_ready(){return -95;}let ps=esp32_irq_save();
 if esp_radio_base_active || esp_radio_base_configured || esp_radio_regi2c_active || esp_radio_pmu_active || esp_radio_hw_ready || esp_radio_owner!=1 || esp_adc_busy || esp32_load32(esp32_state()+16){esp32_irq_restore(ps);return -16;}
 esp32_irq_restore(ps);return -95;
}
fn esp_radio_c6_hardware_deinit(cycles){
 if cycles<1 || cycles>2147483647{return -22;}let ps=esp32_irq_save();
 if !esp_riscv_ready() || rv_hal_chip!=13{esp32_irq_restore(ps);return -95;}
 if esp_radio_base_active{
  if !esp_radio_base_releasing{esp32_irq_restore(ps);return -16;}
  return esp_radio_c6_base_release_locked(cycles,ps,1);
 }
 if esp_radio_regi2c_active || esp_radio_pmu_active{esp32_irq_restore(ps);return -16;}
 if !esp_radio_hw_ready && !esp_radio_base_configured{esp32_irq_restore(ps);return 0;}
 if !esp_radio_base_configured{esp32_irq_restore(ps);return -16;}
 return esp_radio_c6_base_release_locked(cycles,ps,1);
}
fn esp_radio_hardware_deinit(){return esp_radio_c6_hardware_deinit(400000);}
