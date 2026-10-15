import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-timer.flex";
global irq_seen=0;
global timer_seen=0;
fn software(source) {if source== -1 {irq_seen=irq_seen+1;}return 0;}
fn timer(source) {if source==14 && esp_timer_pending(0)>0 {esp_timer_ack(0,0);timer_seen=timer_seen+1;}return 0;}
fn main() {
    esp_uart_write("START: interrupt callbacks\r\n");
    let handler=esp32_callback(software);if handler<=0 || handler>>32 {return 1;}
    if esp32_call(handler,-1)!=0 || irq_seen!=1 {return 2;}
    if esp_irq_software(handler) {return 3;}esp_irq_enable();
    esp32_irq_raise(128);let limit=esp32_cycles();
    while irq_seen<2 && ((esp32_cycles()-limit)&4294967295)<1000000 {}
    esp32_irq_save();if irq_seen!=2 {esp_uart_write("FAIL IRQ ");esp_uart_hex(irq_seen);return 4;}
    if esp_timer_init(0,80,0) || esp_irq_attach(14,esp32_callback(timer)) || esp_timer_alarm(0,100,0) {return 5;}
    esp_irq_enable();esp_timer_start(0);limit=esp32_cycles();
    while !timer_seen && ((esp32_cycles()-limit)&4294967295)<10000000 {let state=esp32_irq_save();if !timer_seen {esp32_wait();}esp32_irq_restore(state);}
    esp32_irq_save();esp_timer_stop(0);let elapsed=esp_timer_read(0);
    if timer_seen!=1 || elapsed<100 {esp_uart_write("FAIL TIMER ");esp_uart_hex(timer_seen);esp_uart_hex(elapsed);return 6;}
    esp_uart_write("PASS: real Xtensa software and timer interrupts, counter and preserved context\r\n");esp_uart_flush();return 0;
}
