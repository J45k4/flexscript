import "s3-buffer-body.flex";
fn main() {
    let state=esp32_state();let ps=esp32_irq_save();esp32_irq_restore(ps);let floor=esp32_load32(state+20);let depth=esp32_load32(state+16);let heap=esp32_load32(state);
    let result=sb_run(1);if result {esp_uart_write("BUFFER FAIL ");esp_uart_hex(result);return result;}
    let after=esp32_irq_save();esp32_irq_restore(after);if ps!=after || esp32_load32(state)!=heap || esp32_load32(state+16)!=depth || esp32_load32(state+20)!=floor {return 7;}
    let p=alloc(16);if p<=0 || !esp_buffer_valid(p,16) {return 8;}store64(p,0x123456789abcdef0);if load64(p)!=0x123456789abcdef0 {return 9;}
    esp_uart_write("PASS: S3 active-profile buffers exclude control/IRAM aliases and SPI rejects before writes\r\n");esp_uart_flush();return 0;
}
