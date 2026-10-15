import "../../lib/platform/esp32-irq.flex";
fn forbidden(a,b,c,d,e,f,g,h) {return alloc(8);}
fn interrupt(source) {return esp32_call32(esp32_callback32(forbidden),0,0,0,0,0,0,0,0);}
fn main() {esp_irq_software(esp32_callback(interrupt));esp_irq_enable();esp32_irq_raise(128);while 1 {}return 1;}
