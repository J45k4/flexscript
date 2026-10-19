import "esp32-riscv-common.flex";
// C6 HP CPU, ROM-configured UART0; GPIO24..30 stay reserved for flash.
global rv_hal_ram_top=0x4085c000;
global rv_hal_data_size=65536;
global rv_hal_chip=13;
global rv_hal_state=0x40830000;
global rv_hal_gpio=0x60091000;
global rv_hal_mux=0x60090000;
global rv_hal_uart_mask=255;
global rv_hal_pin_max=30;
global rv_hal_reserved_start=24;
global rv_hal_reserved_end=30;
