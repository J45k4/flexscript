import "../../lib/platform/esp32s3-spi.flex";
import "../../lib/platform/esp32s3-irq.flex";
import "emulator-spi-body.flex";
fn sp_source(bus){return 19+bus;}
fn sp_raw(){return 60;}
fn sp_done(){return 4096;}
fn sp_usr(){return 1<<24;}
fn sp_fifo(){return 152;}
fn sp_length(base,length){esp32_store32(base+28,length);return 0;}
fn sp_apply(base){esp32_store32(base,1<<23);return esp_wait_mask(base,1<<23,0,1000000);}
fn sp_arm(base){esp32_store32(base+56,4096);esp32_store32(base+52,4096);return 0;}
fn sp_ack(base){esp32_store32(base+56,4096);return 0;}
fn sp_disarm(base){esp32_store32(base+52,0);esp32_store32(base+56,4096);return 0;}
fn sp_deinit(bus){esp_gpio_input(18,0);esp_gpio_input(21,0);esp_gpio_input(19,0);esp_reg_update(0x600c0018,1<<(6+(bus-2)*10),0);return 0;}
