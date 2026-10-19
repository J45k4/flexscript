import "../../lib/platform/esp32c3-irq.flex";
import "../../lib/platform/esp32c3-uart.flex";
global uart_rx_timeouts=0;global uart_received=0;global uart_buffer=0;global uart_error=0;global uart_tx_done=0;global uart_irq_hits=0;
fn uart_irq(source) {
 if source!=esp_uart_irq_source() || esp32_load32(esp32_state()+16)!=1 {uart_error=1;return 0;}
 let pending=esp_uart_irq_pending();if pending&256 {uart_rx_timeouts=uart_rx_timeouts+1;}if pending&0x1c {uart_error=2;}
 if pending&(1|256) {let byte=esp_uart_try_read();while byte>=0 {if uart_received>=16 {uart_error=3;}else {store8(uart_buffer+uart_received,byte);uart_received=uart_received+1;}byte=esp_uart_try_read();}}
 if pending&(1<<14) {uart_tx_done=uart_tx_done+1;esp_uart_irq_mask(1|256|0x1c);}
 esp_uart_irq_ack(pending);uart_irq_hits=uart_irq_hits+1;return 0;
}
fn main() {
 uart_buffer=alloc(16);if esp_uart_irq_mask(0) || esp_uart_irq_thresholds(1,0) || esp_uart_irq_timeout(0) || esp_uart_irq_ack(0x7ffff) || esp_irq_attach(esp_uart_irq_source(),esp32_callback(uart_irq)) {return 1;}
 // Marker enables the independent peer to send four fragmented binary chunks.
 if esp_uart_irq_mask(1|256|0x1c|(1<<14)) {return 2;}esp_irq_enable();esp_uart_write("FLEXIO01");
 let start=esp32_cycles();while uart_received<16 || !uart_tx_done {if ((esp32_cycles()-start)&4294967295)>500000000 {return 3;}}
 let ps=esp32_irq_save();esp_uart_irq_mask(0);esp_irq_detach(esp_uart_irq_source());esp32_irq_restore(ps);
 if uart_error || uart_irq_hits<4 || esp_uart_try_read()!= -1 {return 4;}
 if load64(uart_buffer)!=0x123456789abcdef0 || load64(uart_buffer+8)!=0x8877665544332211 {return 5;}
 store64(uart_buffer,0x123456789abcdef9);store64(uart_buffer+8,0x778899aabbccddee);let i=0;while i<16 {let sent=esp_uart_try_putc(load8(uart_buffer+i));if !sent {i=i+1;}else if sent!= -11 {return 6;}}esp_uart_flush();return 0;
}
