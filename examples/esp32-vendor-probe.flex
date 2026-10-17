// Original ESP32 only; compile --target esp32-xip-elf and link --xip with
// the pinned libwpa_supplicant.a and ESP32 ROM symbol scripts. This exercises
// cached code and the actual vendor archive, without initializing the radio.
import "../lib/platform/esp32.flex";
import "../lib/platform/esp32-xip.flex";
import "../lib/platform/esp32-sdk-sync.flex";
global probe_stage=0;
fn probe_task(a,b,c,d,e,f,g,h) {if a==42 {probe_stage=1;esp_sdk_delay(2);probe_stage=2;}return 0;}
fn main() {
    esp_uart_write("START: native Flexscript vendor/flash probe\r\n");
    if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp32_irq_restore(0);
    let before=esp_sdk_heap_free();let buffer=esp_sdk_malloc(8);if !buffer {return 2;}
    let r=esp32_call32(esp32_external("hexstr2bin"),"deadbeef01234567",buffer,8,0,0,0,0,0);
    if r || load64(buffer)!=0x67452301efbeadde {return 3;}esp_sdk_free(buffer);
    let task=esp_sdk_task_create(esp32_callback32(probe_task),42,8192,1);if !task {return 4;}
    while probe_stage!=2 || load64(task+544)!=2 {esp_sdk_yield();}
    if esp_sdk_task_reap(task) || esp_sdk_heap_free()!=before {return 5;}
    esp_uart_write("PASS: native flash code, linked WPA library and bare-metal C tasks\r\n");esp_uart_flush();return 0;
}
