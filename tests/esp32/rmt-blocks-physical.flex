// Original ESP32; existing confirmed jumper GPIO21 -> GPIO25.
// GPIO-generated pulses leave all eight RMT memory blocks available for RX.
// Every legal contiguous reservation crosses each owned block boundary.
import "../../lib/platform/esp32-rmt.flex";
global rb_case=0;
fn rb_require(ok,code){if !ok{esp_uart_write("RMT BLOCK FAIL ");esp_uart_hex(rb_case);esp_uart_putc(32);esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn rb_print(n){esp_uart_hex(n);esp_uart_putc(32);return 0;}
fn rb_wire(){esp_gpio_write(21,0);rb_require(esp_gpio_output(21)==0 && esp_gpio_input(25,0)==0,1);esp_delay_cycles(80000);rb_require(esp_gpio_read(25)==0,2);esp_gpio_write(21,1);esp_delay_cycles(80000);rb_require(esp_gpio_read(25)==1,3);esp_gpio_write(21,0);return 0;}
fn rb_capture(channel,blocks,buffer){
 rb_wire();let capacity=blocks*64;let pulses=capacity-8;
 rb_require(esp_rmt_rx_init_blocks(channel,25,80,2000,0,blocks)==0,4);
 let peer=channel;while peer<channel+blocks{rb_require(esp_rmt_tx_init(peer,18,80,0)== -16,5);if peer!=channel{rb_require(esp_rmt_deinit(peer)==0 && esp_rmt_tx_init(peer,18,80,0)== -16,6);}peer=peer+1;}
 rb_require(esp_rmt_rx_start(channel)==0,7);
 if capacity<512{rb_require(esp_rmt_rx_finish(channel,buffer,capacity+1,1000000)== -22,8);}
 let ps=esp32_irq_save();let i=0;while i<pulses{let high=80+(i&7)*10;let low=120+((i>>3)&7)*10;esp_gpio_write(21,1);esp_delay_cycles(high*80);esp_gpio_write(21,0);esp_delay_cycles(low*80);i=i+1;}esp32_irq_restore(ps);
 let count=esp_rmt_rx_finish(channel,buffer,capacity,80000000);rb_require(count==pulses,9);
 esp_uart_write("RB ");rb_print(rb_case);rb_print(channel);rb_print(blocks);rb_print(pulses);rb_print(count);esp_uart_write("\r\n");esp_uart_write("WORDS ");i=0;while i<count{rb_print(esp32_load32(buffer+i*4));i=i+1;}esp_uart_write("\r\n");
 rb_require(esp_rmt_deinit(channel)==0,10);rb_require(esp_rmt_tx_init(channel,18,80,0)==0 && esp_rmt_deinit(channel)==0,11);rb_case=rb_case+1;return 0;
}
fn main(){let buffer=alloc(2048);let channel=0;while channel<8{let blocks=1;while blocks<=8-channel{rb_capture(channel,blocks,buffer);blocks=blocks+1;}channel=channel+1;}esp_gpio_input(18,0);esp_gpio_input(25,0);esp_uart_write("PASS: RMT block capture,36 reservations\r\n");esp_uart_flush();return 0;}
