import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-timer.flex";
global hits=0;
global timer_id=0;
fn timer_irq(source) {
 if source!=esp_timer_source(timer_id) || esp32_load32(esp32_state()+16)!=1 {hits= -100;}
 else if esp_timer_pending(timer_id) {hits=hits+1;if timer_id {esp_timer_ack(timer_id,1);}else {esp_timer_ack(timer_id,0);esp_timer_alarm(timer_id,esp_timer_read(timer_id)+1000,0);}}return 0;
}
fn main() {
 while timer_id<=2 {
  hits=0;let repeat=0;if timer_id {repeat=1;}
  if esp_timer_init(timer_id,40,1) || esp_timer_set_words(timer_id,4294967295,4194303) || esp_timer_read(timer_id)!=18014398509481983 || esp_timer_set(timer_id,0) {return 1;}
  if esp_irq_attach(esp_timer_source(timer_id),esp32_callback(timer_irq)) || esp_timer_alarm(timer_id,1000,repeat) || esp_timer_start(timer_id) {return 2;}
  esp_irq_enable();let start=esp32_cycles();while hits<10 {if ((esp32_cycles()-start)&4294967295)>100000000 {return 3;}}
  let ps=esp32_irq_save();esp_timer_stop(timer_id);esp_timer_ack(timer_id,0);esp_irq_detach(esp_timer_source(timer_id));esp32_irq_restore(ps);
  if hits!=10 {return 4;}timer_id=timer_id+2;
 }return 0;
}
