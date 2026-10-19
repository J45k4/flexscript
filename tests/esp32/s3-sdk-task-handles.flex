import "../../lib/platform/esp32s3-sdk-task.flex";
import "sdk-task-handles-core.flex";
fn sh_runtime_init(){return 0;}
fn main(){let result=sh_run(0x3fcc8000);if !result{esp_uart_write("PASS: S3 SDK task handles\r\n");esp_uart_flush();}return result;}
