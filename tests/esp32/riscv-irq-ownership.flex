import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-timer.flex";
global irq_owner_hits=0;
fn owner_irq(source) {irq_owner_hits=irq_owner_hits+1;return 0;}
fn removed_irq(source) {esp_irq_detach(source);irq_owner_hits=irq_owner_hits+1;return 0;}
fn main() {
 let callback=esp32_callback(owner_irq);let soft=esp_irq_soft_source();
 if esp_irq_attach(-1,callback)!= -22 || esp_irq_attach(esp_irq_sources(),callback)!= -22 || esp_irq_attach(0,0)!= -22 || esp_irq_attach(0,1<<32)!= -22 || esp_irq_count {return 1;}
 if esp_irq_attach(soft,callback) || esp_irq_software(callback)!= -16 || esp_irq_soft_handler {return 2;}
 if esp_irq_detach(soft) || esp_irq_software(callback) || esp_irq_attach(soft,callback)!= -16 {return 3;}
 let ps=esp32_irq_save();esp32_irq_raise(128);esp32_irq_raise(0);esp32_irq_clear(0);if esp_irq_software(callback) {return 4;}esp32_irq_restore(ps|8);
 if irq_owner_hits!=1 {return 5;}esp32_irq_save();
 let source=0;let owners=0;while owners<32 {if source!=soft {if esp_irq_attach(source,callback) {return 6;}owners=owners+1;}source=source+1;}
 if esp_irq_attach(source,callback)!= -12 || esp_irq_count!=32 {return 7;}
 let route=esp32_load32(esp_irq_matrix()+40*4);esp_irq_detach(40);if esp32_load32(esp_irq_matrix()+40*4)!=route {return 8;}
 let bound=source;source=0;while source<bound {if source!=soft {esp_irq_detach(source);}source=source+1;}
 if esp_irq_count || (esp32_irq_enabled()&2) {return 9;}
 if esp_irq_attach(1,esp32_callback(removed_irq)) || esp_irq_attach(2,esp32_callback(removed_irq)) {return 10;}
 esp_irq_dispatch(2);if esp_irq_count || irq_owner_hits!=3 {return 11;}
 if esp_timer_base(1) || esp_timer_base(3) || esp_timer_init(1,40,1)!= -22 || esp_timer_init(0,1,1)!= -22 || esp_timer_init(0,40,2)!= -22 || esp_timer_set(0,1<<54)!= -22 || esp_timer_set_words(0,0,1<<22)!= -22 || esp_timer_alarm(0,0,0)!= -22 || esp_timer_alarm_words(0,0,1<<22,0)!= -22 || esp_timer_read_words(0,0)!= -22 {return 12;}
 return 0;
}
