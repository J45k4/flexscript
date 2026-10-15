import "../lib/platform/esp32s3.flex";
// External LED + series resistor on GPIO4. This is not the board's RGB LED.
fn main() {
    esp_uart_write("Flexscript on ESP32-S3: direct Xtensa, bare metal!\r\n");
    esp_gpio_output(4);
    while 1 {
        esp_gpio_write(4,1);esp_uart_write("LED on\r\n");esp_delay_cycles(10000000);
        esp_gpio_write(4,0);esp_uart_write("LED off\r\n");esp_delay_cycles(10000000);
    }return 0;
}
