import "../../lib/platform/esp32c3-gpio.flex";
fn main() {
 let pin=0;let accepted=0;
 while pin<32 {
  if esp_gpio_valid(pin) {
   let signal=0;while signal<=128 {if esp_gpio_route_output(pin,signal) {return 1;}if signal<128 && esp_gpio_route_input(pin,signal) {return 2;}signal=signal+1;}
   let mode=0;while mode<=5 {if esp_gpio_irq(pin,mode) || esp_gpio_irq_ack(pin) {return 3;}mode=mode+1;}accepted=accepted+1;
  }else {if esp_gpio_route_output(pin,0)!= -22 || esp_gpio_route_input(pin,0)!= -22 || esp_gpio_irq(pin,1)!= -22 || esp_gpio_irq_pending(pin)!= -22 || esp_gpio_irq_ack(pin)!= -22 {return 4;}}
  pin=pin+1;
 }
 if accepted!=15 || esp_gpio_irq_source()!=16 || esp_gpio_route_output(4,129)!= -22 || esp_gpio_route_input(4,128)!= -22 || esp_gpio_route_input(4,-1)!= -22 || esp_gpio_irq(4,6)!= -22 || esp_gpio_irq(1<<32,1)!= -22 || esp_gpio_route_output(1<<32,0)!= -22 {return 5;}
 return 0;
}
