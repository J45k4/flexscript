import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-timer.flex";
global callback_seen=0;
global c_irq_seen=0;
fn callback(a,b,c,d,e,f,g,h) {
    if a!=11 || b!=22 || c!=33 || d!=44 || e!=55 || f!=66 || g!=0x89abcdef || h!=0xfedcba98 {return 0;}
    let length=esp32_call32(0x400014c0,"window callback",0,0,0,0,0,0,0);if length!=15 {return 0;}
    callback_seen=callback_seen+1;return 0x123456789abcdef0;
}
fn c_irq(source) {if source==14 && esp_timer_pending(0)>0 {esp_timer_ack(0,0);esp32_call32(esp32_external("c_set_fpu"),0x3f123456,0,0,0,0,0,0,0);if esp32_call32(0x400014c0,"C IRQ",0,0,0,0,0,0,0)==5 {c_irq_seen=c_irq_seen+1;}}return 0;}
fn main() {
    esp_uart_write("START: C ABI nested windows\r\n");let cb=esp32_callback32(callback);if esp32_call32(esp32_external("c_bss_probe"),0,0,0,0,0,0,0,0)!=0x56789abc {return 6;}
    let alignment=7+esp32_call32(esp32_external("c_stack_alignment"),0,0,0,0,0,0,0,0);if alignment!=7 {esp_uart_hex(alignment);return 7;}
    let nested=1000+esp32_call32(esp32_external("c_sum8"),1,2,3,4,5,6,7,8);if nested!=1454 {return 8;}
    nested=esp32_call32(esp32_external("c_sum8"),10,20,esp32_call32(esp32_external("c_sum8"),1,2,3,4,5,6,7,8),40,50,60,70,80);if nested!=6660 {return 9;}
    let sum=esp32_call32(esp32_external("c_sum8"),1,2,3,4,5,6,7,8);if sum!=454 {esp_uart_hex(sum);return 1;}
    let r=esp32_call64(esp32_external("c_walk"),80,cb,0,0,0,0,0,0);
    if r!=0x123456789abcebe9 || callback_seen!=1 {esp_uart_write("RESULT ");esp_uart_hex(r);esp_uart_hex(callback_seen);return 2;}
    let r4=esp32_call64(esp32_external("c_call4"),cb,0,0,0,0,0,0,0);let r12=esp32_call64(esp32_external("c_call12"),cb,0,0,0,0,0,0,0);
    if r4!=0x123456789abce0e0 || r12!=r4 || callback_seen!=3 {esp_uart_hex(r4);esp_uart_hex(r12);return 3;}
    if esp_timer_init(0,80,0) || esp_irq_attach(14,esp32_callback(c_irq)) || esp_timer_alarm(0,100,0) {return 4;}
    esp32_call32(esp32_external("c_set_fpu"),0x3f654321,0,0,0,0,0,0,0);esp_irq_enable();esp_timer_start(0);let waited=esp32_call32(esp32_external("c_wait"),1000000,0,0,0,0,0,0,0);esp32_irq_save();esp_timer_stop(0);
    if waited!=0x13572468 || c_irq_seen!=1 || esp32_call32(esp32_external("c_read_fpu"),0,0,0,0,0,0,0,0)!=0x3f654321 {esp_uart_hex(waited);esp_uart_hex(c_irq_seen);return 5;}
    esp_uart_write("PASS: C ABI eight arguments, deep windows and reentrant callbacks\r\n");esp_uart_flush();return 0;
}
