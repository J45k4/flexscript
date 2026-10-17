import "../../lib/platform/esp32-spi.flex";
import "../../lib/platform/esp32-irq.flex";
import "emulator-spi-body.flex";
fn sp_source(bus){return 28+bus;}
fn sp_raw(){return 56;}
fn sp_done(){return 16;}
fn sp_usr(){return 1<<18;}
fn sp_fifo(){return 128;}
fn sp_length(base,length){esp32_store32(base+28,esp32_load32(base+28)|(3<<27));esp32_store32(base+40,length);esp32_store32(base+44,length);return 0;}
fn sp_apply(base){return 0;}
fn sp_arm(base){esp32_store32(base+56,512);return 0;}
fn sp_ack(base){esp32_store32(base+56,512);return 0;}
fn sp_disarm(base){esp32_store32(base+56,0);return 0;}
fn sp_deinit(bus){return esp_spi_deinit(bus);}
