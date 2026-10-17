// Uses UART1's internal loopback; no GPIO or external wire is configured.
global eu_rx=0;
global eu_done=0;
global eu_error=0;
fn eu_base(){if eu_chip(){return 0x60010000;}return 0x3ff50000;}
fn eu_source(){if eu_chip(){return 28;}return 35;}
fn eu_interrupt(source){if source!=eu_source(){eu_error=1;return 0;}let base=eu_base();let pending=esp32_load32(base+8);if pending&1{while esp32_load32(base+28)&255{let byte=esp32_load32(base)&255;if byte!=((eu_rx*37+11)&255){eu_error=2;}eu_rx=eu_rx+1;}}if pending&(1<<14){esp32_store32(base+12,esp32_load32(base+12)&~(1<<14));eu_done=eu_done+1;}esp32_store32(base+16,pending);return 0;}
fn main(){let base=eu_base();let reset=0x3ff000c4;let config=0x0800401c;let idle=0x40;if eu_chip(){reset=0x600c0020;config=0x401c;idle=0x48;}
 if esp_clock_enable(0,5){return 1;}esp_reg_update(reset,1<<5,1<<5);esp_reg_update(reset,1<<5,0);if eu_chip(){esp32_store32(base+0x78,0x03500000);}esp32_store32(base+0x20,config);esp32_store32(base+0x14,80);esp32_store32(base+idle,0);esp32_store32(base+0x24,1);esp32_store32(base+0x0c,1|(1<<14));esp32_store32(base+0x10,0xffffffff);
 if esp_irq_attach(eu_source(),esp32_callback(eu_interrupt)){return 2;}esp_irq_enable();let i=0;while i<16{let ps=esp32_irq_save();esp32_store32(base+0x10,0xffffffff);esp32_store32(base+0x0c,1|(1<<14));esp32_store32(base,(i*37+11)&255);esp32_irq_restore(ps);let start=esp32_cycles();while !eu_error && (eu_rx<i+1 || eu_done<i+1) && ((esp32_cycles()-start)&0xffffffff)<1000000{let old=esp32_irq_save();if eu_rx<i+1 || eu_done<i+1{esp32_wait();}esp32_irq_restore(old);}if eu_error || eu_rx!=i+1 || eu_done!=i+1{return 3;}i=i+1;}
 esp32_store32(base+0x0c,0);esp_irq_detach(eu_source());esp_uart_write("PASS: UART1 loopback, RX and TX_DONE interrupts\r\n");esp_uart_flush();return 0;
}
