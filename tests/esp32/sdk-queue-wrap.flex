import "../../lib/platform/esp32-irq.flex";
import "../../lib/platform/esp32-sdk-sync.flex";
global wrap_queue=0;
global wrap_word=0;
global wrap_irq_result= -1;
fn wrap_message(n) {store64(wrap_word,n);let i=8;while i<12 {store8(wrap_word+i,n+i);i=i+1;}store8(wrap_word+12,0x6d);return 0;}
fn wrap_read(n) {if !esp_sdk_queue_op(wrap_queue,wrap_word,0,0) || load64(wrap_word)!=n || load8(wrap_word+12)!=0x6d {return 0;}let i=8;while i<12 {if load8(wrap_word+i)!=((n+i)&255) {return 0;}i=i+1;}return 1;}
fn wrap_irq(source) {wrap_irq_result=esp_sdk_queue_op(wrap_queue,wrap_word,1000,1);return 0;}
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}
    wrap_queue=esp_sdk_queue_create(3,12);wrap_word=esp_sdk_malloc(16);if !wrap_queue || !wrap_word {return 2;}
    let i=0;while i<64 {
        let a=i*4;wrap_message(a);if !esp_sdk_queue_op(wrap_queue,wrap_word,0,1) {return 3;}
        wrap_message(a+1);if !esp_sdk_queue_op(wrap_queue,wrap_word,0,1) {return 4;}
        wrap_message(a+2);if !esp_sdk_queue_op(wrap_queue,wrap_word,0,1) || esp_sdk_queue_op(wrap_queue,wrap_word,0,1) || !wrap_read(a) {return 5;}
        wrap_message(a+3);if !esp_sdk_queue_op(wrap_queue,wrap_word,0,2) || !wrap_read(a+3) || !wrap_read(a+1) || !wrap_read(a+2) || esp_sdk_queue_op(wrap_queue,wrap_word,0,0) {return 6;}i=i+1;
    }
    if esp_sdk_queue_op(wrap_queue,wrap_word,0,3) {return 7;}
    esp_irq_software(esp32_callback(wrap_irq));esp_irq_enable();wrap_message(999);esp32_irq_raise(128);while wrap_irq_result<0 {}if wrap_irq_result!=1 || !wrap_read(999) {return 8;}
    i=0;while i<3 {wrap_message(i);if !esp_sdk_queue_op(wrap_queue,wrap_word,0,1) {return 9;}i=i+1;}
    wrap_irq_result= -1;wrap_message(888);esp32_irq_raise(128);while wrap_irq_result<0 {}if wrap_irq_result {return 10;}i=0;while i<3 {if !wrap_read(i) {return 11;}i=i+1;}
    if load64(wrap_queue+24) {return 12;}
    esp_sdk_free(wrap_word);esp_sdk_free(wrap_queue);esp_uart_write("PASS: nonpower-of-two queue wrap, byte payloads and nonblocking ISR full/empty\r\n");return 0;
}
