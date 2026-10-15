import "../lib/platform/esp32-irq.flex";
import "../lib/platform/esp32-timer.flex";
// Original ESP32, UART0 via the board's USB bridge; no external GPIO writes.
// APB remains at the ROM's 80 MHz. Three 100 ms timer alarms, then return.
global ticks=0;
fn alarm(source) {if source==14 && esp_timer_pending(0)>0 {esp_timer_ack(0,1);ticks=ticks+1;}return 0;}
fn main() {
    esp_uart_write("Flexscript native ESP32 timer\r\n");
    if esp_timer_init(0,80,0) || esp_irq_attach(14,esp32_callback(alarm)) || esp_timer_alarm(0,100000,1) {return 1;}
    esp_irq_enable();esp_timer_start(0);let previous=0;
    while previous<3 {
        let state=esp32_irq_save();if ticks==previous {esp32_wait();}let current=ticks;esp32_irq_restore(state);
        if current!=previous {esp_uart_write("tick ");esp_uart_hex(current);esp_uart_write("\r\n");previous=current;}
    }
    esp32_irq_save();esp_timer_stop(0);esp_uart_write("PASS: periodic native timer\r\n");esp_uart_flush();return 0;
}
