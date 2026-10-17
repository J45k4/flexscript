import "../../lib/platform/esp32s3-adc.flex";
// Stock QEMU has no S3 analog source. Verify API/deadline state, not values.
fn main() {
    let ps=esp32_irq_save();esp32_irq_restore(ps);
    if esp_adc_read(1,0,100)== -19 && !esp_adc_init(1,0,3) && !esp_adc_init(2,9,2) {
        if esp_adc_read(1,0,5000)!= -110 || esp_adc_read(2,9,5000)!= -110 || esp_adc_busy || s3a_saved_count {return 2;}
        if esp_adc_deinit(1,0) || esp_adc_deinit(2,9) || esp_adc_read(1,0,100)!= -19 {return 3;}
        let after=esp32_irq_save();esp32_irq_restore(after);if after!=ps {return 4;}
        esp_uart_write("PASS: standalone S3 ADC API, both-unit deadlines and cleanup\r\n");esp_uart_flush();return 0;
    }return 1;
}
