import "esp32-irq.flex";
import "esp32-sdk-timer.flex";
import "esp32-radio-lifecycle-core.flex";
fn esp_radio_source_count() {return 69;}
fn esp_radio_route(source) {return 0x3ff00104+source*4;}
