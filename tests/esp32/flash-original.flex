import "flash-original-fixture.flex";
fn main() {let result=fo_run();if esp_flash_write_open {let restored=esp_flash_write_access(0,80000000);if !result {result=restored;}}esp_uart_write("FLASH RESULT ");esp_uart_hex(result);esp_uart_write("\r\n");esp_uart_flush();return result;}
