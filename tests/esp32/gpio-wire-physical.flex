// Original ESP32, confirmed external GPIO21--GPIO25 jumper. RAM-only fixture.
// Both pins are released before reversing direction; only one output is active.
import "../../lib/platform/esp32-irq.flex";
global gw_seen=0;
global gw_pin=25;
global gw_event=0;
global gw_sample=0;
global gw_checks=0;
fn gw_release(){esp_gpio_interrupt(21,0);esp_gpio_interrupt(25,0);esp_gpio_input(21,0);esp_gpio_input(25,0);esp_gpio_open_drain(21,0);esp_gpio_open_drain(25,0);esp_gpio_ack((1<<21)|(1<<25));return 0;}
fn gw_fail(stage,tx,rx,step){gw_release();esp_irq_detach(22);esp_uart_write("GPIO WIRE FAIL ");esp_uart_hex(stage);esp_uart_write(" TX ");esp_uart_hex(tx);esp_uart_write(" RX ");esp_uart_hex(rx);esp_uart_write(" STEP ");esp_uart_hex(step);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn gw_read(tx,rx,value,stage,step){esp_delay_cycles(256);if esp_gpio_read(rx)!=value || esp_gpio_read(tx)!=value{gw_fail(stage,tx,rx,step);}gw_checks=gw_checks+1;return 0;}
fn gw_line(stage,tx,rx,mode,count){esp_uart_write("GPIO WIRE ");esp_uart_hex(stage);esp_uart_write(" TX ");esp_uart_hex(tx);esp_uart_write(" RX ");esp_uart_hex(rx);esp_uart_write(" MODE ");esp_uart_hex(mode);esp_uart_write(" COUNT ");esp_uart_hex(count);esp_uart_write("\r\n");return 0;}
fn gw_handler(source){let bit=1<<gw_pin;if source==22 && (esp_gpio_pending()&bit){gw_sample=esp_gpio_read(gw_pin);if gw_event>=4{esp_gpio_interrupt(gw_pin,0);}esp_gpio_ack(bit);gw_seen=gw_seen+1;}return 0;}
fn gw_direction(tx,rx){
 let pull=0;while pull<3{
  gw_release();if esp_gpio_input(rx,pull) || esp_gpio_write(tx,0) || esp_gpio_output(tx){gw_fail(1,tx,rx,pull);}
  let i=0;while i<64{let value=((i*37)^(i>>2))&1;esp_gpio_write(tx,value);gw_read(tx,rx,value,2,i);i=i+1;}
  gw_line(1,tx,rx,pull,64);pull=pull+1;
 }
 pull=1;while pull<3{
  gw_release();if esp_gpio_pull(tx,pull){gw_fail(3,tx,rx,pull);}let value=pull==1;
  let i=0;while i<16{gw_read(tx,rx,value,4,i);i=i+1;}
  gw_line(2,tx,rx,pull,16);pull=pull+1;
 }
 gw_release();if esp_gpio_input(rx,1) || esp_gpio_open_drain(tx,1) || esp_gpio_write(tx,1) || esp_gpio_output(tx){gw_fail(5,tx,rx,0);}
 let i=0;while i<64{let value=i&1;esp_gpio_write(tx,value);gw_read(tx,rx,value,6,i);i=i+1;}
 gw_line(3,tx,rx,1,64);
 let event=1;while event<=5{
  gw_release();gw_pin=rx;gw_event=event;gw_seen=0;gw_sample=2;
  let initial=0;if event==2 || event==4{initial=1;}
  if esp_gpio_input(rx,0) || esp_gpio_write(tx,initial) || esp_gpio_output(tx){gw_fail(7,tx,rx,event);}
  esp_delay_cycles(256);let ps=esp32_irq_save();esp_gpio_ack(1<<rx);esp_gpio_interrupt(rx,event);esp32_irq_restore(ps);
  i=0;while i<16{
   let value=1;if event==2 || event==4{value=0;}if event==3{value=!(i&1);}
   if event>=4 && i{ps=esp32_irq_save();esp_gpio_ack(1<<rx);esp_gpio_interrupt(rx,event);esp32_irq_restore(ps);}
   esp_gpio_write(tx,value);let start=esp32_cycles();while gw_seen<i+1 && ((esp32_cycles()-start)&0xffffffff)<1000000{}
   if gw_seen!=i+1 || gw_sample!=value{gw_fail(8,tx,rx,event*32+i);}
   gw_read(tx,rx,value,9,event*32+i);
   if event!=3{esp_gpio_write(tx,initial);esp_delay_cycles(256);}
   i=i+1;
  }
  esp_gpio_interrupt(rx,0);esp_gpio_ack(1<<rx);gw_line(4,tx,rx,event,gw_seen);event=event+1;
 }
 gw_release();return 0;
}
fn main(){esp_uart_write("GPIO WIRE START 21 25\r\n");gw_release();if esp_irq_attach(22,esp32_callback(gw_handler)){gw_fail(10,21,25,0);}esp_irq_enable();gw_direction(21,25);gw_direction(25,21);gw_release();esp_irq_detach(22);esp_uart_write("GPIO WIRE CHECKS ");esp_uart_hex(gw_checks);esp_uart_write("\r\nPASS: GPIO21--GPIO25 bidirectional drive,pulls,open-drain and5IRQ modes\r\n");esp_uart_flush();return 0;}
