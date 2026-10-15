import "esp32s3-common.flex";
// Fixed-function USB Serial/JTAG controller, not the USB-OTG controller.
// Internal PHY uses GPIO19 D- / GPIO20 D+ and is shared with OTG.
fn esp_usb_serial_init() {esp_clock_enable(1,10);esp_reg_update(0x60008120,3<<19,1<<20);esp_reg_update(0x60038018,(1<<14)|1,1<<14);return 0;}
fn esp_usb_serial_write(bytes,size,cycles) {
    if size<0 || !esp_buffer_valid(bytes,size) || cycles<1 || cycles>2147483647 {return -22;}
    let i=0;while i<size {
        let error=esp_wait_mask(0x60038004,2,2,cycles);if error {return error;}esp32_store32(0x60038000,load8(bytes+i));i=i+1;
        if i%64==0 {esp32_store32(0x60038004,1);}
    }if size%64 {esp32_store32(0x60038004,1);}return size;
}
fn esp_usb_serial_read(bytes,capacity,cycles) {
    if capacity<1 || !esp_buffer_valid(bytes,capacity) || cycles<1 || cycles>2147483647 {return -22;}
    let error=esp_wait_mask(0x60038004,4,4,cycles);if error {return error;}let i=0;
    while i<capacity && (esp32_load32(0x60038004)&4) {store8(bytes+i,esp32_load32(0x60038000));i=i+1;}return i;
}
