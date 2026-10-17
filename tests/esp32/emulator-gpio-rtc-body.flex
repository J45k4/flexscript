// Requires a wire GPIO21->GPIO19. Host model can supply the same connection.
// Uses only those pins and RTC GPIO25(original)/GPIO4(S3); no flash pads.
global eg_seen=0;
fn eg_source(){if eg_s3(){return 16;}return 22;}
fn eg_handler(source){if source==eg_source() && (esp_gpio_pending()&(1<<19)){esp_gpio_ack(1<<19);eg_seen=eg_seen+1;}return 0;}
fn main(){esp_gpio_write(21,0);if esp_gpio_output(21) || esp_gpio_input(19,0) || esp_gpio_interrupt(19,3) || esp_irq_attach(eg_source(),esp32_callback(eg_handler)){return 1;}esp_irq_enable();let i=0;while i<8{esp_gpio_write(21,!(i&1));let start=esp32_cycles();while eg_seen<i+1 && ((esp32_cycles()-start)&0xffffffff)<1000000{}if eg_seen!=i+1 || esp_gpio_read(19)!=!(i&1){return 2;}i=i+1;}esp_gpio_interrupt(19,0);esp_gpio_ack(1<<19);esp_irq_detach(eg_source());
 let pin=25;let pad=0x3ff48484;let mux=1<<17;let ie=1<<11;let rtc=0x3ff48400;let bit=1<<20;let local=1<<29;let force=0;let forcebit=0;if eg_s3(){pin=4;pad=0x60008494;mux=1<<19;ie=1<<13;rtc=0x60008400;bit=1<<14;local=0;force=0x600080d8;forcebit=1<<4;}
 esp_gpio_write(pin,1);if esp_gpio_output(pin){return 3;}let original=esp32_load32(pad);esp32_store32(pad,original|mux|ie);esp32_store32(rtc+4,bit);esp32_store32(rtc+16,bit);if !(esp32_load32(rtc+36)&bit) || esp_gpio_read(pin)!=0{return 4;}
 if local{esp32_store32(pad,esp32_load32(pad)|local);}else{esp32_store32(force,esp32_load32(force)|forcebit);}esp32_store32(rtc+8,bit);esp32_store32(pad,esp32_load32(pad)&~ie);if !(esp32_load32(rtc+36)&bit){return 5;}
 if local{esp32_store32(pad,esp32_load32(pad)&~local);}else{esp32_store32(force,esp32_load32(force)&~forcebit);}if esp32_load32(rtc+36)&bit{return 6;}esp32_store32(rtc+20,bit);esp32_store32(pad,original);if esp_gpio_read(pin)!=1{return 7;}
 esp_gpio_input(pin,0);esp_gpio_input(21,0);esp_gpio_input(19,0);esp_uart_write("PASS: GPIO wire IRQ, RTC ownership and hold\r\n");esp_uart_flush();return 0;
}
