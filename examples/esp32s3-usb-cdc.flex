import "../lib/platform/esp32s3-usb-cdc.flex";
// Set an authorized VID/PID for your product before distributing hardware.
// These identifiers are example-only. Internal PHY: GPIO19/20 USB connector.
fn main() {
    if esp_cdc_init(0xcafe,0x4011,10000000) {return 1;}let bytes=alloc(64);
    while 1 {esp_cdc_poll(1000000);let count=esp_cdc_read(bytes,64);if count>0 {esp_cdc_write(bytes,count,1000000);}}return 0;
}
