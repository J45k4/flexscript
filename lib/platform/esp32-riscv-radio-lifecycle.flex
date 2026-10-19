import "esp32-radio-lifecycle-core.flex";
fn esp_radio_source_count(){return esp_irq_sources();}
fn esp_radio_route(source){return esp_irq_matrix()+source*4;}
