import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-timer.flex";
global nesting=0;
global reentrant_irq_count=0;
global reentrant_irq_bad=0;
fn reentrant_irq(source) {if esp_timer_pending(0) {esp_timer_ack(0,1);reentrant_irq_count=reentrant_irq_count+1;let pc=esp32_irq_pc();if pc<0x40000000 || pc>=0x400a0000 {reentrant_irq_bad=1;}if esp32_call32(esp32_external("c_sum8"),1,2,3,4,5,6,7,8)!=454 {reentrant_irq_bad=1;}}return 0;}
fn reentrant(a,b,c,d,e,f,g,h) {
    if a!=11 || h!=0xfedcba98 {return 0;}
    if !nesting {nesting=1;let r=esp32_call64(esp32_external("c_walk"),80,esp32_callback32(reentrant),0,0,0,0,0,0);nesting=0;return r;}
    esp32_call32(esp32_external("c_wait"),80000,0,0,0,0,0,0,0);return 4660;
}
fn main() {
    esp_timer_init(0,80,0);esp_irq_attach(esp_timer_source(0),esp32_callback(reentrant_irq));esp_timer_alarm(0,1000,1);esp_timer_start(0);esp_irq_enable();
    let i=0;while i<20 {let r=esp32_call64(esp32_external("c_walk"),80,esp32_callback32(reentrant),0,0,0,0,0,0);if r!=11302 {return 1;}i=i+1;}
    esp_timer_stop(0);if !reentrant_irq_count || reentrant_irq_bad {return 2;}
    esp_uart_write("PASS: nested deep C Flexscript C callback windows\r\n");return 0;
}
