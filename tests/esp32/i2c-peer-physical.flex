// Requires one jumper: GPIO21 <-> GPIO19. SCL22 feeds both controllers
// through the input matrix. Exercises actual independent master/slave FIFOs.
import "../../lib/platform/esp32-i2c.flex";
global peer_cases=0;
fn pc(ok,code){if !ok{esp_uart_write("WIRED FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn peer_slave(bus) {
 let base=esp_i2c_base(bus);let bit=7+bus*11;esp_clock_enable(0,bit);esp_reg_update(0x3ff000c4,1<<bit,1<<bit);esp_reg_update(0x3ff000c4,1<<bit,0);
 esp32_store32(base+4,0x103);esp32_store32(base+16,0x52);esp32_store32(base+12,0xfffff);esp32_store32(base+24,3<<12);esp32_store32(base+24,0);esp32_store32(base+40,0);esp32_store32(base+36,65535);esp32_store32(base+48,20);esp32_store32(base+52,20);esp32_store32(base+80,0);esp32_store32(base+84,0);
 let clk=29;let data=30;if bus {clk=95;data=96;}
 esp_gpio_write(19,1);esp_gpio_open_drain(19,1);esp_gpio_pull(19,1);esp_gpio_route_output(19,data);esp32_store32(0x3ff44530+19*4,data);esp_gpio_route_input(22,clk);esp_gpio_route_input(21,data);return 0;
}
fn peer_case(master,tx,rx,tn,rn,seed,cycles,expected) {
 let slave=1-master;let base=esp_i2c_base(slave);peer_slave(slave);let i=0;while i<tn{store8(tx+i,(i*73+seed)&255);i=i+1;}i=0;while i<rn{store8(rx+i,0x55);ei_tx_byte(slave,(i*29+seed+91)&255);i=i+1;}
 let result=esp_i2c_transfer(master,0x52,tx,tn,rx,rn,cycles);if result!=expected {esp_uart_write("RESULT ");esp_uart_hex(result);esp_uart_write(" TN ");esp_uart_hex(tn);esp_uart_write(" RN ");esp_uart_hex(rn);esp_uart_write("\r\n");}pc(result==expected,1);
 if expected>=0 {pc(((esp32_load32(base+8)>>8)&63)==tn,2);i=0;while i<tn{pc(ei_rx_byte(base)==load8(tx+i),3);i=i+1;}i=0;while i<rn{if load8(rx+i)!=((i*29+seed+91)&255){esp_uart_write("RX BYTE ");esp_uart_hex(i);esp_uart_write(" ACTUAL ");esp_uart_hex(load8(rx+i));esp_uart_write("\r\n");}pc(load8(rx+i)==((i*29+seed+91)&255),4);i=i+1;}}
 else {i=0;while i<rn{pc(load8(rx+i)==0x55,5);i=i+1;}}peer_cases=peer_cases+1;return 0;
}
fn main() {
 esp_uart_write("WIRED I2C MATRIX PROBE\r\n");let tx=alloc(64);let rx=alloc(64);let sizes=alloc(40);store64(sizes,0);store64(sizes+8,1);store64(sizes+16,2);store64(sizes+24,29);store64(sizes+32,30);let reads=alloc(40);store64(reads,0);store64(reads+8,1);store64(reads+16,2);store64(reads+24,31);store64(reads+32,32);
 let master=0;while master<2 {let rate=10000;let step=0;while step<3 {peer_slave(1-master);pc(esp_i2c_init(master,21,22,rate)==0,10);
 let a=0;while a<5 {let b=0;while b<5 {let tn=load64(sizes+a*8);let rn=load64(reads+b*8);peer_case(master,tx,rx,tn,rn,master*41+step*23+a*7+b,16000000,tn+rn);b=b+1;}a=a+1;}
 peer_case(master,tx,rx,2,3,171,1,-110);peer_case(master,tx,rx,2,3,172,16000000,5);
 peer_slave(1-master);let i=0;while i<4{store8(rx+i,0x55);i=i+1;}pc(esp_i2c_transfer(master,0x53,0,0,rx,4,16000000)== -6,11);i=0;while i<4{pc(load8(rx+i)==0x55,12);i=i+1;}peer_cases=peer_cases+1;peer_case(master,tx,rx,2,3,173,16000000,5);
 esp_uart_write("I2C MATRIX PASS MASTER ");esp_uart_hex(master);esp_uart_write(" HZ ");esp_uart_hex(rate);esp_uart_write(" CASES ");esp_uart_hex(peer_cases);esp_uart_write("\r\n");pc(esp_i2c_deinit(master)==0,13);let slave=1-master;esp32_store32(esp_i2c_base(slave)+4,0);esp_reg_update(0x3ff000c0,1<<(7+slave*11),0);esp32_store32(0x3ff44530+19*4,1280);esp_gpio_input(19,0);esp_gpio_open_drain(19,0);
 step=step+1;if step==1{rate=100000;}else{rate=400000;}
 }master=master+1;}pc(peer_cases==174,14);esp_uart_write("PEER PASS\r\n");esp_uart_flush();return 0;
}
