// Combined final GPIO pull and real I2C FIFO proof; RAM only.
import "../../lib/platform/esp32-i2c.flex";
// Original ESP32: read released RTC-capable pads and verify pulls/open drain.
// No external voltage measurement is claimed. Leaves tested pins as inputs.
fn failed(pin,stage) {esp_uart_write("GPIO FAIL PIN ");esp_uart_hex(pin);esp_uart_write(" STAGE ");esp_uart_hex(stage);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn final_gpio() {esp_uart_write("RTC GPIO PULL PROBE\r\n");let index=0;while index<5 {let pin=25+index;if index>=3 {pin=29+index;}
 if esp_gpio_input(pin,1) {failed(pin,1);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=1 {failed(pin,2);}
 if esp_gpio_pull(pin,2) {failed(pin,3);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=0 {failed(pin,4);}
 if esp_gpio_pull(pin,1) || esp_gpio_write(pin,0) || esp_gpio_open_drain(pin,1) || esp_gpio_output(pin) {failed(pin,5);}esp_delay_cycles(80000);if esp_gpio_read(pin)!=0 {failed(pin,6);}
 esp_gpio_write(pin,1);esp_delay_cycles(80000);if esp_gpio_read(pin)!=1 {failed(pin,7);}esp_gpio_input(pin,0);esp_gpio_open_drain(pin,0);
 esp_uart_write("GPIO PULL PASS ");esp_uart_hex(pin);esp_uart_write("\r\n");index=index+1;
 }esp_uart_write("GPIO STAGE PASS\r\n");esp_uart_flush();return 0;}
// No peer required: generate real open-bus reads with address ACK checking
// deliberately disabled. Exercises hardware FIFO paths, not peer protocols.
fn ck(ok,code) {if !ok {esp_uart_write("FIFO FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn final_fifo() {esp_uart_write("I2C FIFO PROBE\r\n");let bus=0;while bus<2 {ck(esp_i2c_init(bus,21,22,100000)==0,1);let base=esp_i2c_base(bus);let n=1;while n<=32 {
 ei_reset(bus,ei_state(bus));let i=0;while i<16 {esp_i2c_command(base,i,4,0,0);i=i+1;}
 ei_tx_byte(bus,0xa5);ck(((esp32_load32(base+8)>>18)&63)==1,2);let cmd=esp_i2c_command(base,0,0,0,0);cmd=esp_i2c_command(base,cmd,1,1,0);
 if n>1 {cmd=esp_i2c_command(base,cmd,2,n-1,0);}cmd=esp_i2c_command(base,cmd,2,1,1024);esp_i2c_command(base,cmd,3,0,0);esp_reg_update(base+4,32,32);let result=esp_wait_mask(base+32,128,128,16000000);
 if result {esp_uart_write("RAW ");esp_uart_hex(esp32_load32(base+32));esp_uart_write(" STATUS ");esp_uart_hex(esp32_load32(base+8));esp_uart_write("\r\n");}
 ck(result==0,3);ck(((esp32_load32(base+8)>>18)&63)==0,4);ck(((esp32_load32(base+8)>>8)&63)==n,5);ck(esp32_load32(base+88+cmd*4)&0x80000000,6);i=0;while i<n {ck(ei_rx_byte(base)==255,7);i=i+1;}ck(((esp32_load32(base+8)>>8)&63)==0,8);
 esp_uart_write("FIFO PASS BUS ");esp_uart_hex(bus);esp_uart_write(" BYTES ");esp_uart_hex(n);esp_uart_write("\r\n");if n==1 {n=2;}else if n==2 {n=3;}else if n==3 {n=16;}else if n==16 {n=31;}else {n=n+1;}
 }ck(esp_i2c_deinit(bus)==0,9);bus=bus+1;}esp_uart_write("FIFO STAGE PASS\r\n");esp_uart_flush();return 0;}
fn main(){final_gpio();final_fifo();esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;}
