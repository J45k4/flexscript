import "../../lib/platform/esp32c3-irq.flex";
global irq_checks=0;
fn state_irq(source) {if source!=-1 || esp32_load32(esp32_state()+16)!=1 {irq_checks= -100;}else {irq_checks=irq_checks+1;}let a=0x8877665544332211;let b=(a*17)/13;if b==1 {irq_checks= -200;}return 0;}
fn main() {if esp_irq_software(esp32_callback(state_irq)) {return 1;}let n=0;while n<50 {esp32_irq_save();esp32_irq_raise(128);let result=esp32_call32(esp32_external("irq_register_probe"),0,0,0,0,0,0,0,0);if result {return 100+result;}if irq_checks!=n+1 || esp32_load32(esp32_state()+16) {return 2;}n=n+1;}return 0;}
