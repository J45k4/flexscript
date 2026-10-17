import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-wifi.flex";
import "wifi-phy-admission-body.flex";
fn pa_digital() {return 0;}
fn main() {if esp_sdk_heap_init(0x3ffc8000,98304) || esp_sdk_task_init() {return 1;}esp_irq_enable();let r=pa_admission();if r {return r;}esp_uart_write("PASS: original Wi-Fi96 borrowed PHY cases at16 interrupt levels\r\n");esp_uart_flush();return 0;}
