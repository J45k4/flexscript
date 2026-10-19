import "../../lib/platform/esp32c3-spi.flex";
import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-timer.flex";
global sr_tx=0;global sr_rx=0;global sr_attempts=0;global sr_error=0;
fn sr_irq(source) {
 if esp_timer_pending(0) {esp_timer_ack(0,0);if esp_spi_states && load64(esp_spi_states+8) {if esp_spi_transfer(2,sr_tx,sr_rx,1,1000)!=-16 || esp_spi_deinit(2)!=-16 {sr_error=1;}sr_attempts=sr_attempts+1;}esp_timer_alarm(0,esp_timer_read(0)+1000,0);}return 0;
}
fn main() {
 sr_tx=alloc(64);sr_rx=alloc(64);let i=0;while i<64{store8(sr_tx+i,i);store8(sr_rx+i,165);i=i+1;}
 if esp_spi_init(2,4,5,6,1000000,0)!=1000000 || esp_timer_init(0,40,1) || esp_irq_attach(esp_timer_source(0),esp32_callback(sr_irq)) || esp_timer_alarm(0,1000,0) || esp_timer_start(0) {return 1;}
 esp_irq_enable();let result=esp_spi_transfer(2,sr_tx,sr_rx,64,10000000);let ps=esp32_irq_save();esp_timer_stop(0);esp_irq_detach(esp_timer_source(0));esp32_irq_restore(ps);
 if result!=-110 || !sr_attempts || sr_error || esp_spi_transferred(2) || esp_spi_status(2)!=-110 {return 2;}
 i=0;while i<64{if load8(sr_rx+i)!=165{return 3;}i=i+1;}if esp_spi_deinit(2){return 4;}return 0;
}
