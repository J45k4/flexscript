// Original ESP32: read released RTC-capable pads and verify pulls/open drain.
// No external voltage measurement is claimed. Leaves tested pins as inputs.
import "../../lib/platform/esp32.flex";
fn failed(pin,stage) {esp_uart_write("GPIO FAIL PIN ");esp_uart_hex(pin);esp_uart_write(" STAGE ");esp_uart_hex(stage);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn main() {esp_uart_write("RTC GPIO PULL PROBE\r\n");let index=0;while index<5 {let pin=25+index;if index>=3 {pin=29+index;}
 if esp_gpio_input(pin,1) {failed(pin,1);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=1 {failed(pin,2);}
 if esp_gpio_pull(pin,2) {failed(pin,3);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=0 {failed(pin,4);}
 if esp_gpio_pull(pin,1) || esp_gpio_write(pin,0) || esp_gpio_open_drain(pin,1) || esp_gpio_output(pin) {failed(pin,5);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=0 {failed(pin,6);}
 esp_gpio_write(pin,1);esp_delay_cycles(80000);if esp_gpio_read(pin)!=1 {failed(pin,7);}esp_gpio_input(pin,0);esp_gpio_open_drain(pin,0);
 esp_uart_write("GPIO PULL PASS ");esp_uart_hex(pin);esp_uart_write("\r\n");index=index+1;
 }esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;}
