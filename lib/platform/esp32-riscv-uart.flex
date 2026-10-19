import "esp32-riscv-uart-core.flex";
import "esp32-riscv-gpio.flex";
import "esp32-riscv-uart-config.flex";
// Compatibility entrypoints keep using ROM-configured UART0.
fn esp_uart_try_read(){return esp_uart_bus_try_read(0);}
fn esp_uart_try_putc(byte){return esp_uart_bus_try_putc(0,byte);}
fn esp_uart_irq_source(){return esp_uart_bus_irq_source(0);}
fn esp_uart_irq_mask(mask){return esp_uart_bus_irq_mask(0,mask);}
fn esp_uart_irq_pending(){return esp_uart_bus_irq_pending(0);}
fn esp_uart_irq_raw(){return esp_uart_bus_irq_raw(0);}
fn esp_uart_irq_ack(mask){return esp_uart_bus_irq_ack(0,mask);}
fn esp_uart_update(){return esp_uart_bus_update(0);}
fn esp_uart_irq_thresholds(rx_full,tx_empty){return esp_uart_bus_irq_thresholds(0,rx_full,tx_empty);}
fn esp_uart_irq_timeout(bits){return esp_uart_bus_irq_timeout(0,bits);}
