// Explicit serial gate for approved temporary board verification only.
import "flash-original-fixture.flex";
import "settings-flash-fixture.flex";
fn main() {
    esp_uart_write("SETTINGS PROBE READY\r\n");let command= -1;while command<0 {command=esp_uart_read();}
    if command==70 {let raw=fo_run();if esp_flash_write_open {let restored=esp_flash_write_access(0,80000000);if !raw {raw=restored;}}esp_uart_write("FLASH RESULT ");esp_uart_hex(raw);esp_uart_write("\r\n");if raw {esp_uart_flush();return raw;}}
    else if command!=82 {return 21;}let result=sf_run();esp_uart_write("SETTINGS RESULT ");esp_uart_hex(result);esp_uart_write(" protection ");esp_uart_hex(esp_flash_status);esp_uart_write("\r\n");esp_uart_flush();return result;
}
