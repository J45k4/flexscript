import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-timer.flex";
// A native adapter configures hardware; the typed application owns its state.
fn physical_tick(source) {if source==14 && esp_timer_pending(0)>0 {esp_timer_ack(0,1);return on_timer(source);}return 0;}
fn esp_platform_init() {
    if esp_timer_init(0,80,0) || esp_irq_attach(14,esp32_callback(physical_tick)) || esp_timer_alarm(0,1000,1) {return -1;}
    esp_timer_start(0);esp_irq_enable();return 0;
}
