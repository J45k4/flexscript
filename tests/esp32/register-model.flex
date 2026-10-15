// Independent host-side bus fixture for unchanged production drivers.
// No device register is accessed on the host. Low mapped RAM preserves the
// driver's actual ESP32 buffer-address validation instead of bypassing it.
import "../../lib/platform/esp32s3-spi.flex";
import "../../lib/platform/esp32s3-i2c.flex";
import "../../lib/platform/esp32s3-pwm.flex";
import "../../lib/platform/esp32s3-adc.flex";
import "../../lib/platform/esp32s3-rmt.flex";
import "../../lib/platform/esp32s3-usb-serial.flex";
import "../../lib/platform/esp32s3-i2s.flex";
import "../../lib/platform/esp32s3-usb-cdc.flex";
global model_usb_sent=0;
global model_usb_count=0;
global model_usb_rx=0;
global model_usb_rx_size=0;
global model_usb_rx_index=0;
global model_regs=0;
global model_count=0;
global model_cycles=0;
global model_stall=0;
global model_i2c_error=0;
global model_i2c_data=0;
global model_i2c_count=0;
global model_rx_at=0;
global model_spi_calls=0;
global model_failed=0;
fn model_index(address) {let i=0;while i<model_count {if load64(model_regs+i*16)==address {return i;}i=i+1;}store64(model_regs+i*16,address);model_count=model_count+1;return i;}
fn model_get(address) {return load64(model_regs+model_index(address)*16+8);}
fn model_set(address,value) {store64(model_regs+model_index(address)*16+8,value&4294967295);return 0;}
fn esp32_cycles() {model_cycles=(model_cycles+10)&4294967295;return model_cycles;}
fn esp32_load32(address) {
    if address>=0x3fcb0000 && address<0x3fcd0000 {return load8(address)|(load8(address+1)<<8)|(load8(address+2)<<16)|(load8(address+3)<<24);}
    if address==0x60081000 && model_usb_rx_index<model_usb_rx_size {let value=load64(model_usb_rx+model_usb_rx_index*4)&4294967295;model_usb_rx_index=model_usb_rx_index+1;if model_usb_rx_index==model_usb_rx_size {model_set(0x60080014,model_get(0x60080014)&~16);}return value;}
    if address==0x6001301c {let v=0x50+model_rx_at;model_rx_at=model_rx_at+1;return v;}return model_get(address);
}
fn esp32_store32(address,value) {
    value=value&4294967295;
    if address>=0x3fcb0000 && address<0x3fcd0000 {let i=0;while i<4 {store8(address+i,value>>(i*8));i=i+1;}return 0;}
    model_set(address,value);
    if address>=0x60081000 && address<=0x60084000 && !(address&4095) {store64(model_usb_sent+model_usb_count*8,value);model_usb_count=model_usb_count+1;}
    if address==0x60080010 && !model_stall {model_set(address,1<<31);}
    if address==0x60080014 {model_set(address,0);}
    if address==0x60080908 {model_set(address,0);}
    if address==0x6000880c && value&(1<<17) && !model_stall {model_set(address,(value&~65535)|65536|2047);}
    if address==0x6001607c {model_set(0x60016070,model_get(0x60016070)&~value);}
    if address==0x60016020 && value&1 && !model_stall {model_set(0x60016070,1);}
    if address==0x6003f080 && value&(1<<21) && !model_stall {model_set(0x6003f068,8);}
    if address==0x6003f074 {model_set(0x6003f068,0);}
    if address==0x60038004 && value&1 {model_set(address,2);}
    if address==0x60024000 && !model_stall {
        model_set(address,0);if value&(1<<24) {model_spi_calls=model_spi_calls+1;let i=0;while i<16 {model_set(0x60024098+i*4,0x44332211);i=i+1;}}
    }
    if address==0x6001301c {store8(model_i2c_data+model_i2c_count,value);model_i2c_count=model_i2c_count+1;}
    if address==0x60013024 {model_set(0x60013020,0);}
    if address==0x60013004 && value&32 {
        let status=128;if model_i2c_error==1 {status=1024;}else if model_i2c_error==2 {status=32;}else if model_i2c_error==3 {status=0;}model_set(0x60013020,status);
    }return 0;
}
fn check(value,id) {if !value && !model_failed {model_failed=id;}return 0;}
fn model_usb_complete() {model_set(0x60080900,model_get(0x60080900)&~(1<<31));model_set(0x60080908,1);return 0;}
fn model_copy(source,dest,size) {let i=0;while i<size {store8(dest+i,load8(source+i));i=i+1;}return dest;}
fn model_setup(buffer,kind,request,value,index,size) {store64(buffer,kind|(request<<8)|(value<<16)|(index<<32)|(size<<48));return 0;}
fn main() {
    model_regs=alloc(65536);model_i2c_data=alloc(64);
    let ram=syscall(9,0x3fcb0000,131072,3,0x100022,-1,0);if ram!=0x3fcb0000 {return 100;}
    let tx=ram+1024;let rx=ram+4096;let i=0;while i<130 {store8(tx+i,i);i=i+1;}
    check(esp_gpio_input(48,1)==0,1);check(model_get(0x600090c4)&256,2);check(model_get(0x60004034)==65536,3);
    model_set(0x60004040,65536);check(esp_gpio_read(48)==1,4);check(esp_gpio_output(22)== -22,5);
    check(esp_gpio_open_drain(4,1)==0 && (model_get(0x60004084)&4),6);check(esp_gpio_interrupt(4,3)==0 && (model_get(0x60004084)&8192),7);
    check(esp_spi_init(2,4,5,6,1000000,0)==1000000,10);check(model_get(0x6002400c)==((39<<12)|(19<<6)|39),11);
    check(esp_spi_transfer(2,tx,rx,130,10000)==130 && model_spi_calls==3,12);
    // Each FIFO word is an externally supplied 11 22 33 44 response pattern.
    i=0;while i<130 {check(load8(rx+i)==17*((i&3)+1),14);i=i+1;}
    model_stall=1;model_cycles=4294967280;check(esp_spi_transfer(2,tx,rx,1,50)== -110,15);model_stall=0;
    check(esp_spi_transfer(0,tx,rx,1,100)== -22 && esp_spi_transfer(2,0,0,1,100)== -22,16);
    check(esp_i2c_init(0,8,9,100000)==0,20);check(model_get(0x60013000)==199 && model_get(0x60013038)==(102|(98<<9)),21);
    store8(tx,0x16);store8(tx+1,0x27);check(esp_i2c_transfer(0,0x50,tx,2,rx,2,1000)==4,22);
    check(model_i2c_count==4 && load8(model_i2c_data)==160 && load8(model_i2c_data+1)==22 && load8(model_i2c_data+2)==39 && load8(model_i2c_data+3)==161,23);
    check(model_get(0x60013058)==0x3000 && model_get(0x6001305c)==0x903 && model_get(0x60013060)==0x3000 && model_get(0x60013064)==0x901,24);
    check(model_get(0x60013068)==0x1801 && model_get(0x6001306c)==0x1c01 && model_get(0x60013070)==0x1000,25);
    check(load8(rx)==80 && load8(rx+1)==81,26);
    model_i2c_error=1;check(esp_i2c_transfer(0,0x50,0,0,0,0,1000)== -6,27);
    model_i2c_error=2;check(esp_i2c_transfer(0,0x50,0,0,0,0,1000)== -11,28);
    model_i2c_error=3;check(esp_i2c_transfer(0,0x50,0,0,0,0,50)== -110,29);
    check(esp_i2c_transfer(0,128,0,0,0,0,100)== -22 && esp_i2c_transfer(0,1,tx,31,0,0,100)== -22,30);
    check(esp_pwm_timer(0,1000,10)==1000,40);check(model_get(0x600190a0)==0x0202710a,41);
    check(esp_pwm_channel(2,0,10)==0 && (model_get(0x6000457c)&511)==75,42);
    check(esp_pwm_duty(2,512)==0 && model_get(0x60019030)==8192,43);
    check(esp_pwm_duty(2,1024)== -22 && esp_pwm_timer(0,20000000,14)== -22,44);
    check(esp_adc_init(1,0,3)==0 && (model_get(0x60008814)&3)==3,45);
    check(esp_adc_read(1,0,100)==2047,46);model_stall=1;model_set(0x6000880c,0);check(esp_adc_read(1,0,20)== -110,47);model_stall=0;
    check(esp_rmt_symbol(1,20,0,30)==0x001e8014 && esp_rmt_symbol(0,0,0,1)== -22,50);
    check(esp_rmt_tx_init(0,11,40,0)==0,51);store64(tx,0x001e8014);
    check(esp_rmt_write(0,tx,1,1000)==1 && model_get(0x60016800)==0x001e8014 && model_get(0x60016804)==0,52);
    model_stall=1;check(esp_rmt_write(0,tx,1,20)== -110,53);model_stall=0;
    let desc=ram+8192;check(esp_dma_descriptor(desc,tx,64,64,0,1)==0,60);
    check(load64(desc)==((tx<<32)|0xc0040040) && load64(desc+8)==0,61);
    check(esp_dma_descriptor(desc,tx,4093,0,0,1)== -22 && esp_dma_descriptor(desc+1,tx,64,64,0,1)== -22,62);
    check(esp_dma_start(0,1,7,desc)==0 && model_get(0x6003f0a8)==7,63);check(esp_dma_wait(0,1,1000)==0,64);
    model_stall=1;check(esp_dma_start(0,1,7,desc)==0 && esp_dma_wait(0,1,20)== -110 && model_get(0x6003f080)==(1<<20),65);model_stall=0;
    check(esp_i2s_init(0,1,4,5,6,48000,16)==48004,70);
    check((model_get(0x6000f02c)&127)==15 && model_get(0x6000f054)==65539,71);
    model_set(0x6000f06c,1);check(esp_i2s_transfer(0,1,0,desc,tx,64,100)==64,72);
    check(esp_i2s_transfer(0,0,0,desc,tx,64,100)== -22 && esp_i2s_transfer(0,1,0,desc,tx,3,100)== -22,73);
    check(esp_usb_serial_init()==0 && (model_get(0x60008120)&(3<<19))==(1<<20),80);
    model_set(0x60038004,2);check(esp_usb_serial_write(tx,65,1000)==65,81);
    model_set(0x60038004,0);check(esp_usb_serial_write(tx,1,20)== -110 && esp_usb_serial_read(rx,1,20)== -110,82);
    model_usb_sent=alloc(1024);model_usb_rx=alloc(64);model_set(0x60080010,1<<31);model_set(0x6008004c,256<<16);model_set(0x60080918,16);
    check(esp_usb_device_init(1000)==0,90);check(model_get(0x60080024)==128 && model_get(0x6008010c)==((16<<16)|176),91);
    check(esp_cdc_prepare(0xcafe,0x4011)==0,92);
    esp_cdc_device=model_copy(esp_cdc_device,ram+16384,18);esp_cdc_descriptor=model_copy(esp_cdc_descriptor,ram+16416,67);
    esp_cdc_vendor=model_copy(esp_cdc_vendor,ram+16512,22);esp_cdc_product=model_copy(esp_cdc_product,ram+16544,30);
    esp_cdc_line=model_copy(esp_cdc_line,ram+16608,7);esp_cdc_io=ram+16640;esp_cdc_rx=ram+16704;
    model_setup(tx,128,6,256,0,18);check(esp_cdc_setup(tx,100)==0,93);
    check((model_get(0x60080900)&0x84000000)==0x84000000 && (model_get(0x60080b00)&0x84000000)==0x84000000,113);
    check(model_usb_count==5 && load64(model_usb_sent)==0x02000112 && load64(model_usb_sent+8)==0x40000002 && load64(model_usb_sent+16)==0x4011cafe,94);
    model_usb_complete();esp_cdc_poll(100);model_usb_count=0;
    model_setup(tx,128,6,512,0,255);check(esp_cdc_setup(tx,100)==0 && esp_cdc_left==3 && model_usb_count==16,95);
    model_usb_complete();check(esp_cdc_poll(100)==0 && esp_cdc_left==0 && model_usb_count==17,96);model_usb_complete();esp_cdc_poll(100);
    model_setup(tx,0,5,7,0,0);check(esp_cdc_setup(tx,100)==0 && !(model_get(0x60080800)&2032),97);
    model_usb_complete();check(esp_cdc_poll(100)==0 && (model_get(0x60080800)&2032)==112,98);
    model_setup(tx,0,9,1,0,0);check(esp_cdc_setup(tx,100)==0 && esp_cdc_ready==1,99);model_usb_complete();esp_cdc_poll(100);
    model_set(0x60080014,16);model_set(0x60080020,(2<<17)|(3<<4)|1);store64(model_usb_rx,0x00636261);model_usb_rx_index=0;model_usb_rx_size=1;
    check(esp_cdc_poll(100)==0 && esp_cdc_received==3,100);check(esp_cdc_read(rx,1)==1 && load8(rx)==97 && esp_cdc_received==2,101);
    check(esp_cdc_read(rx,8)==2 && load8(rx)==98 && load8(rx+1)==99 && esp_cdc_received==0,102);
    model_setup(tx,128,6,0x600,0,10);check(esp_cdc_setup(tx,100)== -95 && (model_get(0x60080900)&(1<<21)),103);
    model_set(0x60080014,1<<12);check(esp_cdc_poll(100)==0 && !esp_cdc_ready,104);
    check(esp_usb_host_init(1000)==0 && esp_usb_mode==2,110);model_set(0x60080440,0);
    check(esp_usb_host_reset(20)== -110 && esp_usb_host_packet(0,0,0,0,3,8,tx,8,20)== -19,111);
    check(esp_usb_host_packet(0,0,0,0,3,7,tx,7,20)== -22,112);
    syscall(11,ram,131072,0,0,0,0);return model_failed;
}
