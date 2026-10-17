// CS release is measured separately from raw TRANS_DONE and USR completion.
// GPIO22/23 are software event markers captured internally; only21->25 is wired.
// Existing confirmed jumper:GPIO21(MOSI)->GPIO25(RMT input).
// Three independent RMT receivers share one synchronization pulse first,
// then capture SCK(GPIO18), wired MOSI(GPIO25), hardware CS(GPIO4).
// Clock RX reserves blocks0..2; separate RX channels3/4 capture data and CS.
import "../../lib/platform/esp32-spi.flex";
import "../../lib/platform/esp32-rmt.flex";
global sw_case=0;
global sw_donebuf=0;
global sw_busybuf=0;
fn sw_check(ok,code){if !ok{esp_uart_write("WAVE FAIL CASE ");esp_uart_hex(sw_case);esp_uart_write(" CODE ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn sw_print(n){esp_uart_hex(n);esp_uart_putc(32);return 0;}
fn sw_swap32(x){return ((x>>24)&255)|((x>>8)&65280)|((x<<8)&16711680)|((x<<24)&4278190080);}
fn sw_wire(){esp_gpio_write(21,0);sw_check(esp_gpio_output(21)==0 && esp_gpio_input(25,0)==0,1);esp_delay_cycles(80000);sw_check(esp_gpio_read(25)==0,2);esp_gpio_write(21,1);esp_delay_cycles(80000);sw_check(esp_gpio_read(25)==1,3);esp_gpio_write(21,0);return 0;}
fn sw_dump(label,buffer,count){esp_uart_write(label);sw_print(count);let i=0;while i<count{sw_print(esp32_load32(buffer+i*4));i=i+1;}esp_uart_write("\r\n");return 0;}
fn sw_capture(bus,mode,order,profile,clockbuf,databuf,csbuf){
 sw_wire();esp_gpio_write(22,0);esp_gpio_write(23,0);esp_gpio_write(18,0);esp_gpio_output(18);esp_gpio_write(4,0);esp_gpio_output(4);
 sw_check(esp_rmt_rx_init_blocks(0,18,80,30000,0,3)==0 && esp_rmt_rx_init(3,25,80,30000,0)==0 && esp_rmt_rx_init(4,4,80,30000,0)==0 && esp_rmt_rx_init(5,22,80,30000,0)==0 && esp_rmt_rx_init(6,23,80,30000,0)==0,4);esp_gpio_output(22);esp_gpio_output(23);esp_gpio_output(18);esp_gpio_output(4);esp_gpio_write(18,0);esp_gpio_write(4,0);
 esp_gpio_route_input(18,83);esp_gpio_route_input(18,86);esp_gpio_route_input(18,87);esp_gpio_route_input(18,88);esp_gpio_route_input(18,89);sw_check(esp_rmt_rx_start(0)==0 && esp_rmt_rx_start(3)==0 && esp_rmt_rx_start(4)==0 && esp_rmt_rx_start(5)==0 && esp_rmt_rx_start(6)==0,5);
 esp_gpio_write(18,1);esp_delay_cycles(80000);esp_gpio_write(18,0);esp_delay_cycles(80000);esp_gpio_route_input(25,86);esp_gpio_route_input(4,87);esp_gpio_route_input(22,88);esp_gpio_route_input(23,89);
 let rate=esp_spi_init(bus,18,21,-1,100000,mode);sw_check(rate>0 && rate<=100000,6);let base=esp_spi_base(bus);let cs=11;if bus==3{cs=68;}esp_gpio_route_output(4,cs);
 let cmdlen=16;let addrlen=15;let data=17;let dummy=0;let dummyidle=0;
 let packed=0x52+(sw_case&1);let command=sw_swap32(packed)>>(32-cmdlen);let address=0x9a5c371e24b5d0f1;
 let hi=0;let lo=0;if order{hi=sw_swap32(address);lo=sw_swap32(address>>32);}else if addrlen>32{hi=address>>(addrlen-32);lo=address<<(64-addrlen);}else{hi=address<<(32-addrlen);}
 let hold=0;let select=(sw_case/2)&3;if select==1{hold=1;}if select==2{hold=3;}if select==3{hold=15;}let hold_enable=1;let user=(1<<31)|(1<<30)|(1<<27)|32|(hold_enable<<4)|(((mode&1)^(mode>>1))<<7);if dummy{user=user|(1<<29);}if dummyidle{user=user|(1<<26);}
 esp32_store32(base+8,order<<26);esp32_store32(base+20,1|(hold<<4));let n=50;let pre=160;let high=25;esp32_store32(base+24,((pre-1)<<18)|((n-1)<<12)|((high-1)<<6)|(n-1));esp32_store32(base+28,user);esp32_store32(base+32,((addrlen-1)<<26)|(dummy-1)&255);if !dummy{esp32_store32(base+32,(addrlen-1)<<26);}esp32_store32(base+36,((cmdlen-1)<<28)|(packed&65535));esp32_store32(base+4,hi);esp32_store32(base+48,lo);esp32_store32(base+40,data-1);esp32_store32(base+44,0);esp32_store32(base+52,6|((mode>>1)<<29));
 let i=0;while i<16{let word=0;if !i{word=0x963cc35a;}if i==1{word=0xa571e29b;}esp32_store32(base+128+i*4,word);i=i+1;}esp32_store32(base+56,0);esp32_store32(base,1<<18);
 sw_check(esp_wait_mask(base+56,16,16,300000000)==0,10);esp_gpio_write(22,1);
 sw_check(esp_wait_mask(base,1<<18,0,300000000)==0,11);esp_gpio_write(23,1);
 let ndone=esp_rmt_rx_finish(5,sw_donebuf,64,300000000);let nbusy=esp_rmt_rx_finish(6,sw_busybuf,64,300000000);sw_check(ndone>0 && nbusy>0 && esp_gpio_read(22)==1 && esp_gpio_read(23)==1,12);

 let capacity=192;let nclock=esp_rmt_rx_finish(0,clockbuf,capacity,300000000);let spi=esp_wait_mask(base+56,16,16,300000000);let ndata=esp_rmt_rx_finish(3,databuf,64,300000000);let ncs=esp_rmt_rx_finish(4,csbuf,64,300000000);
 if nclock<1 || ndata<1 || ncs<1{esp_uart_write("COUNTS ");sw_print(nclock);sw_print(ndata);sw_print(ncs);esp_uart_write("\r\n");}sw_check(nclock>=1 && nclock<=192 && ndata>=1 && ndata<=64 && ncs>=1 && ncs<=64 && !spi,7);
 esp_uart_write("CR ");sw_print(sw_case);sw_print(esp32_load32(base+36));sw_print(user);sw_print(esp32_load32(base+20));esp_uart_write("\r\n");esp_uart_write("SW ");sw_print(sw_case);sw_print(bus);sw_print(mode);sw_print(order);sw_print(profile);sw_print(cmdlen);sw_print(addrlen);sw_print(data);sw_print(dummy);sw_print(dummyidle);sw_print(command);sw_print(address);sw_print(0x963cc35a);sw_print(0xa571e29b);sw_print(pre);sw_print(n);sw_print(high);sw_print(2);sw_print(hold);sw_print(esp32_load32(base+28));sw_print(esp32_load32(base+20));sw_print(esp_gpio_read(18));sw_print(esp_gpio_read(25));sw_print(esp_gpio_read(4));esp_uart_write("\r\n");sw_dump("R0 ",clockbuf,nclock);sw_dump("R1 ",databuf,ndata);sw_dump("R2 ",csbuf,ncs);sw_dump("R3 ",sw_donebuf,ndone);sw_dump("R4 ",sw_busybuf,nbusy);
 sw_check(esp_spi_deinit(bus)==0,8);sw_check(esp_rmt_deinit(0)==0 && esp_rmt_deinit(3)==0 && esp_rmt_deinit(4)==0 && esp_rmt_deinit(5)==0 && esp_rmt_deinit(6)==0,9);return 0;
}
fn main(){let clockbuf=alloc(768);let databuf=alloc(256);let csbuf=alloc(256);sw_donebuf=alloc(256);sw_busybuf=alloc(256);while sw_case<32{let bus=2+sw_case/16;let mode=(sw_case/8)&1;sw_capture(bus,mode,0,0,clockbuf,databuf,csbuf);sw_case=sw_case+1;}esp_gpio_input(4,0);esp_gpio_input(25,0);esp_gpio_input(22,0);esp_gpio_input(23,0);esp_uart_write("PASS: SPI waveform capture\r\n");esp_uart_flush();return 0;}
