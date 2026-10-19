// Original ESP32 digital audio over the confirmed GPIO21-to-GPIO25 jumper.
import "../../lib/platform/esp32-i2s.flex";
import "../../lib/platform/esp32-radio-clock.flex";
fn ia_word(label,value) {esp_uart_write(label);esp_uart_hex(value);return 0;}
fn main() {
    esp_gpio_input(25,0);esp_gpio_output(21);esp_gpio_open_drain(21,0);esp_gpio_write(21,0);esp_delay_cycles(1000);ia_word("WIRE LOW ",esp_gpio_read(25));esp_gpio_write(21,1);esp_delay_cycles(1000);ia_word(" HIGH ",esp_gpio_read(25));esp_uart_write("\r\n");
    ia_word("RTC OPTIONS ",esp32_load32(0x3ff48000));ia_word(" CLK CONF ",esp32_load32(0x3ff48070));esp_uart_write("\r\n");esp_radio_clock_init();esp_uart_write("I2S DMA PROBE\r\n");let tx=alloc(256);let rx=alloc(256);let td=alloc(16);let rd=alloc(16);let i=0;while i<64 {esp32_store32(tx+i*4,0x91234567+i*0x10203);esp32_store32(rx+i*4,0x55555555);i=i+1;}
    let rate=esp_i2s_init_duplex(0,22,4,21,25,16000,16);ia_word("RATE ",rate);ia_word(" CONF ",esp32_load32(0x3ff4f008));ia_word(" CLK ",esp32_load32(0x3ff4f0ac));esp_uart_write("\r\n");
    ia_word("RX SUBMIT ",esp_i2s_submit(0,0,rd,rx,256));ia_word(" TX SUBMIT ",esp_i2s_submit(0,1,td,tx,256));esp_uart_write("\r\n");
    esp_delay_cycles(800000);ia_word("LIVE TD ",esp32_load32(td));ia_word(" RD ",esp32_load32(rd));ia_word(" OUTLINK ",esp32_load32(0x3ff4f030));ia_word(" INLINK ",esp32_load32(0x3ff4f034));ia_word(" LC ",esp32_load32(0x3ff4f060));ia_word(" LSTATE ",esp32_load32(0x3ff4f06c));ia_word(" RAW ",esp32_load32(0x3ff4f00c));esp_uart_write("\r\n");
    let result=esp_i2s_wait(0,1,16000000);ia_word("TX WAIT ",result);ia_word(" RAW ",esp32_load32(0x3ff4f00c));ia_word(" STATE ",esp32_load32(0x3ff4f0bc));ia_word(" DESC ",esp32_load32(td));esp_uart_write("\r\n");
    result=esp_i2s_wait(0,0,16000000);ia_word("RX WAIT ",result);ia_word(" RAW ",esp32_load32(0x3ff4f00c));ia_word(" DESC ",esp32_load32(rd));esp_uart_write("\r\n");
    i=0;while i<16 {ia_word("RX ",esp32_load32(rx+i*4));ia_word(" TX ",esp32_load32(tx+i*4));esp_uart_write("\r\n");i=i+1;}
    esp_i2s_deinit(0);esp_uart_write("I2S PROBE DONE\r\n");esp_uart_flush();return 0;
}
