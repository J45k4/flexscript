import "esp32-riscv-common.flex";
// C3 CPU0, ROM-configured UART0; GPIO11..17 stay reserved for flash/power.
global rv_hal_ram_top=0x3fccc000;
global rv_hal_data_size=65536;
global rv_hal_chip=5;
global rv_hal_state=0x3fca0000;
global rv_hal_gpio=0x60004000;
global rv_hal_mux=0x60009000;
global rv_hal_uart_mask=1023;
global rv_hal_pin_max=21;
global rv_hal_reserved_start=11;
global rv_hal_reserved_end=17;
