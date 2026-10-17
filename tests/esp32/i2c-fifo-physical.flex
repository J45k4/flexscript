// No peer required: generate real open-bus reads with address ACK checking
// deliberately disabled. Exercises hardware FIFO paths, not peer protocols.
import "../../lib/platform/esp32-i2c.flex";
fn ck(ok,code) {if !ok {esp_uart_write("FIFO FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn main() {esp_uart_write("I2C FIFO PROBE\r\n");let bus=0;while bus<2 {ck(esp_i2c_init(bus,21,22,100000)==0,1);let base=esp_i2c_base(bus);let n=1;while n<=32 {
 ei_reset(bus,ei_state(bus));let i=0;while i<16 {esp_i2c_command(base,i,4,0,0);i=i+1;}
 ei_tx_byte(bus,0xa5);ck(((esp32_load32(base+8)>>18)&63)==1,2);let cmd=esp_i2c_command(base,0,0,0,0);cmd=esp_i2c_command(base,cmd,1,1,0);
 if n>1 {cmd=esp_i2c_command(base,cmd,2,n-1,0);}cmd=esp_i2c_command(base,cmd,2,1,1024);esp_i2c_command(base,cmd,3,0,0);esp_reg_update(base+4,32,32);let result=esp_wait_mask(base+32,128,128,16000000);
 if result {esp_uart_write("RAW ");esp_uart_hex(esp32_load32(base+32));esp_uart_write(" STATUS ");esp_uart_hex(esp32_load32(base+8));esp_uart_write("\r\n");}
 ck(result==0,3);ck(((esp32_load32(base+8)>>18)&63)==0,4);ck(((esp32_load32(base+8)>>8)&63)==n,5);ck(esp32_load32(base+88+cmd*4)&0x80000000,6);i=0;while i<n {ck(ei_rx_byte(base)==255,7);i=i+1;}ck(((esp32_load32(base+8)>>8)&63)==0,8);
 esp_uart_write("FIFO PASS BUS ");esp_uart_hex(bus);esp_uart_write(" BYTES ");esp_uart_hex(n);esp_uart_write("\r\n");if n==1 {n=2;}else if n==2 {n=3;}else if n==3 {n=16;}else if n==16 {n=31;}else {n=n+1;}
 }ck(esp_i2c_deinit(bus)==0,9);bus=bus+1;}esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;}
