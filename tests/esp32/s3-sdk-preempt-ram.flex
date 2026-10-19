// ESP32-S3 CPU-bound task rendezvous using the shared runtime core.
import "../../lib/platform/esp32s3-sdk-preempt.flex";
global pr_rounds=0;
fn pr_busy(a,b,c,d,e,f,g,h) {
    let own=pr_rounds+a*8;let peer=pr_rounds+(1-a)*8;let round=1;
    while round<=12 {while (load64(pr_rounds+16)&1)!=a {}store64(own,round);store64(pr_rounds+16,load64(pr_rounds+16)+1);round=round+1;}return 0;
}
fn main() {
    esp_uart_write("START: RAM preemption\r\n");if esp_sdk_heap_init(0x3fcc8000,32768) || esp_sdk_task_init() {return 1;}
    pr_rounds=alloc(24);let before=esp_sdk_heap_free();let a=esp_sdk_task_create(esp32_callback32(pr_busy),0,8192,5);let b=esp_sdk_task_create(esp32_callback32(pr_busy),1,8192,5);if !a || !b {return 2;}
    let start=esp_sdk_preempt_start(5000);if start {esp_uart_write("START ERROR ");esp_uart_hex(start);esp_uart_write(" cfg=");esp_uart_hex(esp32_load32(esp_timer_base(3)));esp_uart_write(" pending=");esp_uart_hex(esp_timer_pending(3));esp_uart_write("\r\n");return 3;}esp_irq_enable();while load64(a+544)!=2 || load64(b+544)!=2 {esp_sdk_yield();}
    if esp_sdk_preempt_stop() || esp_sdk_task_reap(a) || esp_sdk_task_reap(b) {return 4;}
    if load64(pr_rounds)!=12 || load64(pr_rounds+8)!=12 || esp_sdk_preempt_switches<20 || esp_sdk_preempt_ticks<20 || esp32_load32(esp32_state()+16) || esp_sdk_heap_free()!=before {esp_uart_write("FINAL ERROR ");esp_uart_hex(load64(pr_rounds));esp_uart_hex(load64(pr_rounds+8));esp_uart_hex(esp_sdk_preempt_switches);esp_uart_hex(esp_sdk_preempt_ticks);esp_uart_write("\r\n");return 5;}
    esp_uart_write("PASS: CPU-bound RAM Flex tasks,12 rendezvous each; switches=");esp_uart_hex(esp_sdk_preempt_switches);esp_uart_write(" ticks=");esp_uart_hex(esp_sdk_preempt_ticks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
