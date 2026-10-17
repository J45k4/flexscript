import "esp32s3-irq.flex";
import "esp32s3-sdk-timer.flex";
import "esp32-radio-lifecycle-core.flex";
fn esp_radio_source_count() {return 99;}
fn esp_radio_route(source) {return 0x600c2000+source*4;}
