// Real C6 CPU/IRQ admission checks. Only the kernel control block is read;
// successful PMU teardown is tested separately at explicit model boundaries.
fn base_release_native_guards(){
 if esp_radio_c6_base_release(0)!=-22 || esp_radio_c6_base_release(2147483648)!=-22{return 1;}
 let original=esp32_irq_save();let mode=0;while mode<2{
  let wanted=(original&~8)|(mode*8);esp32_irq_restore(wanted);
  if esp_radio_c6_base_release(1000)!=-16{return 2;}
  esp_radio_owner=1;if esp_radio_c6_base_release(1000){return 3;}
  esp_radio_base_configured=1;
  if esp_radio_c6_base_release(1000)!=-16 || !esp_radio_base_configured || esp_radio_base_active{return 4;}
  esp_radio_base_configured=0;esp_radio_base_active=1;
  if esp_radio_c6_base_release(1000)!=-16 || !esp_radio_base_active || esp_radio_base_releasing{return 5;}
  esp_radio_base_active=0;esp_radio_owner=0;let actual=esp32_irq_save();esp32_irq_restore(actual);if actual!=wanted{return 6;}
  mode=mode+1;
 }
 esp32_irq_restore(original);return 0;
}
