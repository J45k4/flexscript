// Xtensa native lifecycle guard; both incoming interrupt levels retain ownership.
fn main(){
 let base=esp_sdk_heap_min();let top=esp_sdk_heap_max();let floor=esp32_load32(esp32_state()+20);if top>floor{top=floor;}if esp_sdk_heap_init(base,top-base) || esp_sdk_task_init(){return 1;}let before=esp_sdk_heap_free();if esp_radio_resources_begin(1){return 2;}
 let p=esp_radio_cb_malloc(48,0,0,0,0,0,0,0);if !p{return 3;}store64(p,0x123456789abcdef0);let free=esp_sdk_heap_free();let original=esp32_irq_save();let mode=0;
 while mode<2{let wanted=original;if !mode{wanted=wanted&~15;}else{wanted=(wanted&~15)|15;}esp32_irq_restore(wanted);esp_radio_base_configured=1;
  if esp_radio_resources_ready() || esp_radio_resources_end(0)!=-16 || esp_radio_owner!=1 || esp_sdk_heap_free()!=free || load64(p)!=0x123456789abcdef0{return 4;}
  esp_radio_owner=0;if esp_radio_resources_begin(1)!=-16 || esp_radio_owner || esp_sdk_heap_free()!=free{return 5;}esp_radio_owner=1;
  let actual=esp32_irq_save();if actual!=wanted{return 6;}esp_radio_base_configured=0;esp32_irq_restore(original);mode=mode+1;
 }
 if esp_radio_resources_end(0) || esp_radio_owner || esp_sdk_heap_free()!=before{return 7;}esp_uart_write("PASS: committed base retains owned heap and IRQ state\r\n");return 0;}
