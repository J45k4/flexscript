import "../../lib/platform/esp32c3-i2c.flex";
import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-timer.flex";
global ir_tx=0;global ir_rx=0;global ir_attempts=0;global ir_error=0;
fn ir_irq(source) {
 if esp_timer_pending(0) {esp_timer_ack(0,0);if esp_i2c_states&&load64(esp_i2c_states+8) {if esp_i2c_transfer(0,0x50,ir_tx,1,ir_rx,1,1000)!=-16||esp_i2c_recover(0,1000)!=-16||esp_i2c_deinit(0)!=-16 {ir_error=1;}ir_attempts=ir_attempts+1;}esp_timer_alarm(0,esp_timer_read(0)+1000,0);}return 0;
}
fn main(){
 ir_tx=alloc(32);ir_rx=alloc(32);let i=0;while i<32{store8(ir_tx+i,i);store8(ir_rx+i,165);i=i+1;}
 if esp_i2c_init(0,4,5,100000)||esp_timer_init(0,40,1)||esp_irq_attach(esp_timer_source(0),esp32_callback(ir_irq))||esp_timer_alarm(0,1000,0)||esp_timer_start(0){return 1;}
 esp_irq_enable();let result=esp_i2c_recover(0,10000000);let ps=esp32_irq_save();esp_timer_stop(0);esp_irq_detach(esp_timer_source(0));esp32_irq_restore(ps);
 if result!=-110||!ir_attempts||ir_error||esp_i2c_status(0)!=-110||esp_i2c_transferred(0){return 2;}i=0;while i<32{if load8(ir_rx+i)!=165{return 3;}i=i+1;}if esp_i2c_deinit(0){return 4;}return 0;
}
