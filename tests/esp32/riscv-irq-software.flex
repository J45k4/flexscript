import "../../lib/platform/esp32c3-irq.flex";
global hits=0;
fn irq_callback(source) {if source!=-1 || esp32_load32(esp32_state()+16)!=1 {hits= -100;}else {hits=hits+1;}return 0;}
fn main() {if esp_irq_software(esp32_callback(irq_callback)) {return 1;}esp_irq_enable();esp32_irq_raise(128);let start=esp32_cycles();while !hits {if ((esp32_cycles()-start)&4294967295)>1000000 {return 2;}}return hits-1;}
