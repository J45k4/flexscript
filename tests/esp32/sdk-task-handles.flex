import "../../lib/platform/esp32-sdk-task.flex";
import "sdk-task-handles-core.flex";
fn sh_runtime_init(){return 0;}
fn main(){let result=sh_run(0x3ffc8000);if !result{esp_uart_write("PASS: SDK task handles\r\n");esp_uart_flush();}return result;}
