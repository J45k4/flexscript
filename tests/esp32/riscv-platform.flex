import "../../lib/platform/esp32c3.flex";
fn main() {
    if esp_uart_write("RV32 UART ")<0 {return 1;}esp_uart_hex(0x8877665544332211);esp_uart_write("\r\n");esp_uart_flush();
    if esp_gpio_valid(-1) || esp_gpio_valid(11) || esp_gpio_valid(12) || esp_gpio_valid(17) || esp_gpio_valid(22) {return 2;}
    if esp_gpio_output(4) || esp_gpio_write(4,1) || esp_gpio_write(4,0) || esp_gpio_open_drain(4,1) || esp_gpio_pull(4,1) || esp_gpio_input(4,2) {return 3;}
    if esp_delay_cycles(1000) || esp_delay_cycles(-1)!= -22 || esp_delay_cycles(2147483648)!= -22 {return 4;}
    return 0;
}
