import "../../lib/platform/esp32s3-dma.flex";
fn main() {
    esp_uart_write("START: GDMA SHA256\n");let data=alloc(64);let desc=alloc(16);
    store8(data,97);store8(data+1,98);store8(data+2,99);store8(data+3,128);store8(data+63,24);
    if esp_dma_descriptor(desc,data,64,64,0,1) {return 1;}
    esp_clock_enable(1,2);esp_reg_update(0x600c0024,(1<<4)|(1<<5),0);
    esp32_store32(0x6003b000,2);esp32_store32(0x6003b00c,1);
    if esp_dma_start(0,1,7,desc) {return 2;}esp32_store32(0x6003b01c,1);
    let result=esp_dma_wait(0,1,10000000);if result {esp_uart_hex(result);return 3;}
    if esp_wait_mask(0x6003b018,1,0,1000000) {return 4;}
    // FIPS 180-4 SHA-256("abc"), bytes in peripheral digest registers.
    let expected=alloc(32);store64(expected,0xeacf018fbf1678ba);store64(expected+8,0x2322ae5dde404141);store64(expected+16,0x9c7a1796a36103b0);store64(expected+24,0xad1500f261ff10b4);
    let i=0;while i<8 {let word=esp32_load32(0x6003b040+i*4);esp_uart_hex(word);let j=0;while j<4 {if ((word>>(j*8))&255)!=load8(expected+i*4+j) {return 5;}j=j+1;}i=i+1;}
    esp_uart_write("PASS: GDMA transferred SHA256 block and verified digest\n");return 0;
}
