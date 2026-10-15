import "../../lib/platform/esp32.flex";
// Independent erratum model: a FIFO read while unmasked latches an APB fault.
global uart_model_ps=0;
global uart_model_ready=0;
global uart_model_reads=0;
global uart_model_fault=0;
fn esp32_irq_save() {let old=uart_model_ps;uart_model_ps=15;return old;}
fn esp32_irq_restore(ps) {uart_model_ps=ps;return 0;}
fn esp32_load32(address) {
    if address==0x3ff4001c {return uart_model_ready;}
    if address==0x3ff40000 {uart_model_reads=uart_model_reads+1;if uart_model_ps!=15 {uart_model_fault=1;}return 0x1a5;}
    uart_model_fault=1;return 0;
}
fn esp32_store32(address,value) {uart_model_fault=1;return 0;}
fn esp32_cycles() {return 0;}
fn main() {
    if esp_uart_read()!= -1 || uart_model_reads || uart_model_ps || uart_model_fault {return 1;}
    uart_model_ready=1;if esp_uart_read()!=0xa5 || uart_model_reads!=1 || uart_model_ps || uart_model_fault {return 2;}
    uart_model_ps=5;if esp_uart_read()!=0xa5 || uart_model_reads!=2 || uart_model_ps!=5 || uart_model_fault {return 3;}
    return 0;
}
