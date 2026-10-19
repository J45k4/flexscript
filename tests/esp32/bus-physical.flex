import "../../lib/platform/esp32-spi.flex";
import "../../lib/platform/esp32-i2c.flex";
fn bp_check(ok,code) {if !ok {esp_uart_write("BUS FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn bp_transfer(bus,tx,rx,n,seed) {let i=0;while i<n {store8(tx+i,(i*31+seed)&255);store8(rx+i,0);i=i+1;}let result=esp_spi_transfer(bus,tx,rx,n,16000000);bp_check(result==n,1000-result);i=0;while i<n {if load8(tx+i)!=load8(rx+i) {esp_uart_write("MISMATCH ");esp_uart_hex(i);esp_uart_write(" TX ");esp_uart_hex(load8(tx+i));esp_uart_write(" RX ");esp_uart_hex(load8(rx+i));esp_uart_write("\r\n");bp_check(0,2000+i);}i=i+1;}return 0;}
fn main() {
    esp_uart_write("ORIGINAL BUS PROBE\r\n");let tx=alloc(256);let rx=alloc(256);bp_check(tx>0 && rx>0,1);let bus=2;let transfers=0;
    while bus<=3 {let mode=0;while mode<4 {let rate=100000;let step=0;while step<3 {
        let actual=esp_spi_init(bus,18,23,19,rate,mode);esp_uart_write("SPI ");esp_uart_hex(bus);esp_uart_write(" MODE ");esp_uart_hex(mode);esp_uart_write(" HZ ");esp_uart_hex(actual);esp_uart_write("\r\n");bp_check(actual>0 && actual<=rate,2);
        let signal=9;if bus==3 {signal=64;}bp_check(esp_gpio_route_input(23,signal)==0,3);bp_transfer(bus,tx,rx,1,mode);bp_transfer(bus,tx,rx,63,mode+9);bp_transfer(bus,tx,rx,64,mode+13);bp_transfer(bus,tx,rx,65,mode+19);bp_transfer(bus,tx,rx,130,mode+29);transfers=transfers+5;
        bp_check(esp_spi_deinit(bus)==0,4);step=step+1;if step==1 {rate=1000000;}else {rate=5000000;}
    }mode=mode+1;}bus=bus+1;}
    esp_uart_write("SPI LOOPBACK TRANSFERS ");esp_uart_hex(transfers);esp_uart_write("\r\n");bus=0;while bus<2 {
        bp_check(esp_i2c_init(bus,21,22,100000)==0,10);let result=esp_i2c_transfer(bus,0x52,0,0,0,0,16000000);esp_uart_write("I2C NO-PEER ");esp_uart_hex(bus);esp_uart_write(" RESULT ");esp_uart_hex(result);esp_uart_write("\r\n");bp_check(result== -6,11);
        bp_check(esp_i2c_recover(bus,16000000)==0,12);result=esp_i2c_transfer(bus,0x52,0,0,0,0,16000000);bp_check(result== -6,13);bp_check(esp_i2c_deinit(bus)==0 && esp_i2c_init(bus,21,22,400000)==0 && esp_i2c_deinit(bus)==0,14);bus=bus+1;
    }
    esp_uart_write("BUS PASS\r\n");esp_uart_flush();return 0;
}
