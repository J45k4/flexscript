// Execute unchanged production drivers against independently supplied C-register
// definitions. Model consumes command/FIFO words and produces wire responses.
import "../../lib/platform/esp32-spi.flex";
import "../../lib/platform/esp32-i2c.flex";
global bm_ref=0;
global bm_regs=0;
global bm_count=0;
global bm_checks=0;
global bm_ticks=0;
global bm_ps=0;
global bm_fault=0;
global bm_preread=0;
global bm_spi_calls=0;
global bm_spi_mode=0;
global bm_spi_bytes=0;
global bm_spi_tx=0;
global bm_spi_rx=0;
global bm_spi_stall=0;
global bm_fifo=0;
global bm_fifo_size=0;
global bm_rx=0;
global bm_rx_size=0;
global bm_rx_at=0;
global bm_i2c_calls=0;
global bm_i2c_error=0;
global bm_tx_size=0;
global bm_expected_rx=0;
global bm_address=0;
global bm_tx=0;
global bm_resets=0;
global bm_scl=22;
global bm_sda=21;
global bm_recovery=0;
global bm_pulses=0;
global bm_release=0;
global bm_output=0xffffffff;
fn br(index) {return load64(bm_ref+16+index*8);}
fn bi(address) {let i=0;while i<bm_count {if load64(bm_regs+i*16)==address {return i;}i=i+1;}store64(bm_regs+i*16,address);bm_count=bm_count+1;return i;}
fn bg(address) {return load64(bm_regs+bi(address)*16+8);}
fn bs(address,value) {store64(bm_regs+bi(address)*16+8,value&4294967295);return 0;}
fn bc(ok,id) {bm_checks=bm_checks+1;if !ok {let p=alloc(24);store64(p,id);store64(p+8,bm_checks);syscall(1,2,p,16,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn esp32_irq_save() {let previous=bm_ps;bm_ps=15;return previous;}
fn esp32_irq_restore(ps) {bm_ps=ps;return 0;}
fn esp32_cycles() {bm_ticks=(bm_ticks+10)&4294967295;return bm_ticks;}
fn bm_spi(base) {
    bm_spi_calls=bm_spi_calls+1;let n=(bg(base+br(4))+1)/8;bc(n>0 && n<=64,100);bc(bg(base+br(5))==n*8-1,101);
    bc(bg(base+br(3))==(br(51+bm_spi_mode)|(1<<27)|(bm_spi_rx<<28)),102);bc(bg(base+br(6))==br(55+bm_spi_mode),103);
    let i=0;while i<n {let word=bg(base+br(8)+(i/4)*4);let actual=(word>>((i&3)*8))&255;let expect=0;if bm_spi_tx {expect=load8(bm_spi_tx+bm_spi_bytes+i);}bc(actual==expect,104);i=i+1;}
    if !bm_spi_stall {i=0;while i<16 {let word=0;let j=0;while j<4 {let at=i*4+j;let value=0;if at<n {let input=0;if bm_spi_tx {input=load8(bm_spi_tx+bm_spi_bytes+at);}value=(input^0xa5)^((bm_spi_bytes+at)&255);}word=word|(value<<(j*8));j=j+1;}bs(base+br(8)+i*4,word);i=i+1;}bs(base+br(7),br(10));bs(base,0);}
    bm_spi_bytes=bm_spi_bytes+n;return 0;
}
fn bm_i2c(base) {
    bm_i2c_calls=bm_i2c_calls+1;let k=0;let used=0;let read=0;let checksum=17;let stop= -1;
    bc(bg(base+br(32))==br(60),200);k=1;
    let first=(bm_address<<1)|!!(!bm_tx_size && bm_expected_rx);bc(load8(bm_fifo)==first,201);used=1;let code=bg(base+br(32)+k*4);bc(code==((br(61)&~255)|(bm_tx_size+1)),202);k=k+1;
    let i=0;while i<bm_tx_size {bc(load8(bm_fifo+used)==load8(bm_tx+i),203);checksum=(checksum*33+load8(bm_fifo+used))&255;used=used+1;i=i+1;}
    if bm_tx_size && bm_expected_rx {bc(bg(base+br(32)+k*4)==br(60),204);k=k+1;bc(bg(base+br(32)+k*4)==((br(61)&~255)|1),205);k=k+1;bc(load8(bm_fifo+used)==((bm_address<<1)|1),206);used=used+1;}
    if bm_expected_rx>1 {bc(bg(base+br(32)+k*4)==((br(62)&~255)|(bm_expected_rx-1)),207);read=bm_expected_rx-1;k=k+1;}
    if bm_expected_rx {bc(bg(base+br(32)+k*4)==br(63),208);read=read+1;k=k+1;}
    bc(read==bm_expected_rx && bm_fifo_size==used,209);bc(bg(base+br(32)+k*4)==br(64),210);stop=k;k=k+1;while k<16 {bc(bg(base+br(32)+k*4)==br(65),211);k=k+1;}
    bm_rx_size=read;bm_rx_at=0;i=0;while i<read {store8(bm_rx+i,(checksum+i*19+bm_address)&255);i=i+1;}
    let status=br(38);if bm_i2c_error==1 {status=br(36);}else if bm_i2c_error==2 {status=br(35);}else if bm_i2c_error==3 {status=br(37);}else if bm_i2c_error==4 {status=0;}
    bs(base+br(20),status);bs(base+br(16),read<<8);if bm_i2c_error!=5 {bs(base+br(32)+stop*4,br(64)|br(68));}if bm_i2c_error==6 {bs(base+br(16),(read+1)<<8);}bs(base+br(15),bg(base+br(15))&~br(34));return 0;
}
fn esp32_load32(address) {
    if address==0x3ff40078 {bc(bm_ps==15,302);bm_preread=1;return 0;}
    let b=0;while b<2 {let base=br(13+b);if address==base+br(19) {bc(bm_ps==15 && bm_preread,303);bm_preread=0;if bm_rx_at>=bm_rx_size {bm_fault=1;return 0;}let byte=load8(bm_rx+bm_rx_at);bm_rx_at=bm_rx_at+1;return byte;}b=b+1;}
    if address==0x3ff4403c {let value=bm_output;if bm_recovery && (bm_recovery==2 || bm_pulses<bm_release) {value=value&~(1<<bm_sda);}if bm_recovery==3 {value=value&~(1<<bm_scl);}return value;}
    return bg(address);
}
fn esp32_store32(address,value) {
    value=value&4294967295;let old=bg(address);bs(address,value);
    if address==0x3ff000c4 && value {bc(bm_ps==15,300);bm_resets=bm_resets+1;let bus=0;while bus<2 {let bit=br(11+bus);if value&bit {let base=br(bus);let i=0;while i<256 {bs(base+i,0);i=i+4;}}bit=br(39+bus);if value&bit {let base=br(13+bus);let i=0;while i<160 {bs(base+i,0);i=i+4;}}bus=bus+1;}}
    if address==0x3ff44008 {if bm_recovery && (value&(1<<bm_scl)) && !(bm_output&(1<<bm_scl)) {bm_pulses=bm_pulses+1;}bm_output=bm_output|value;}
    if address==0x3ff4400c {bm_output=bm_output&~value;}
    let bus=0;while bus<2 {
        let base=br(bus);if address==base && value&br(9) {bm_spi(base);}
        base=br(13+bus);if address==base+br(18) && value&br(33) {bm_fifo_size=0;bm_rx_size=0;bm_rx_at=0;bs(base+br(16),0);}
        if address==br(69+bus) {bc(bm_fifo_size<32,301);store8(bm_fifo+bm_fifo_size,value);bm_fifo_size=bm_fifo_size+1;}
        if address==base+br(21) {bs(base+br(20),bg(base+br(20))&~value);}
        if address==base+br(15) && value&br(34) {bm_i2c(base);}
        bus=bus+1;
    }return 0;
}
fn bm_spi_case(bus,mode,tx,rx,size) {
    let i=0;while i<size {store8(tx+i,(i*31+mode*7)&255);if rx!=tx {store8(rx+i,0x55);}i=i+1;}bm_spi_tx=tx;bm_spi_rx=1;bm_spi_bytes=0;bm_spi_calls=0;bm_spi_mode=mode;
    bc(esp_spi_transfer(bus,tx,rx,size,100000)==size,400);bc(bm_spi_calls==(size+63)/64,401);i=0;while i<size {bc(load8(rx+i)==(((((i*31+mode*7)&255)^0xa5)^(i&255))&255),402);i=i+1;}return 0;
}
fn bm_i2c_case(bus,tx,rx,tn,rn) {
    bm_address=0x52;bm_tx=tx;bm_tx_size=tn;bm_expected_rx=rn;let sum=17;let i=0;while i<tn {store8(tx+i,i*9+3);sum=(sum*33+load8(tx+i))&255;i=i+1;}i=0;while i<rn {store8(rx+i,0x55);i=i+1;}
    let expected=tn+rn;if bm_i2c_error==1 {expected= -6;}if bm_i2c_error==2 {expected= -11;}if bm_i2c_error==3 || bm_i2c_error==4 {expected= -110;}if bm_i2c_error==5 || bm_i2c_error==6 {expected= -5;}
    let resets=bm_resets;bc(esp_i2c_transfer(bus,bm_address,tx,tn,rx,rn,500)==expected,500);i=0;while i<rn {let byte=0x55;if !bm_i2c_error {byte=(sum+i*19+bm_address)&255;}bc(load8(rx+i)==byte,501);i=i+1;}if bm_i2c_error {bc(bm_resets==resets+1,502);}return 0;
}
fn main(argc,argv) {
    if argc!=2 {return 99;}bm_ref=alloc(984);let fd=syscall(2,load64(argv+8),0,0,0,0,0);if fd<0 || syscall(0,fd,bm_ref,984,0,0,0)!=984 {return 98;}syscall(3,fd,0,0,0,0,0);if load64(bm_ref)!=0x4255535245470004 || load64(bm_ref+8)!=121 {return 97;}
    bm_regs=alloc(65536);bm_fifo=alloc(64);bm_rx=alloc(64);let ram=syscall(9,0x3ffb0000,196608,3,0x100022,-1,0);if ram!=0x3ffb0000 {return 96;}let tx=ram+1024;let rx=ram+4096;
    let pad=0;while pad<12 {let at=71+pad*4;let pin=br(at);let address=br(at+1);let up=br(at+2);let down=br(at+3);let original=0x55aa5aa5;bs(address,original);let pull=0;while pull<3 {let expected=original&~(up|down);if pull==1 {expected=expected|up;}if pull==2 {expected=expected|down;}bc(esp_gpio_pull(pin,pull)==0 && bg(address)==expected,6);bc(bm_ps==0,7);pull=pull+1;}pad=pad+1;}
    let input=34;while input<=39 {let address=br(119);if input>=36 {address=br(120);}bs(address,0xf5a55a5f);bc(esp_gpio_pull(input,0)==0 && bg(address)==0xf5a55a5f,8);bc(esp_gpio_pull(input,1)== -22 && esp_gpio_pull(input,2)== -22 && bg(address)==0xf5a55a5f,9);input=input+1;}
    bc(esp_buffer_valid(0x3ffb0010,1) && !esp_buffer_valid(0x3ffb000f,1),1);bc(esp_buffer_valid(0x3ffdfffc,4) && !esp_buffer_valid(0x3ffdfffc,5),2);bc(esp_buffer_valid(0x3ffe0000,0) && !esp_buffer_valid(0x3ffe0000,1) && !esp_buffer_valid(0x7fffffffffffffff,1),3);bc(!esp_buffer_valid(0x3ffb0010,-1),4);
    bc(esp_spi_transfer(2,tx,rx,1,100)== -19 && esp_i2c_transfer(0,0x52,tx,1,rx,1,100)== -19,5);
    let bus=2;while bus<=3 {let mode=0;while mode<4 {
        bm_spi_mode=mode;bc(esp_spi_init(bus,18,23,19,1234567,mode)>0,10);let base=br(bus-2);let clock=bg(base+br(2));let actual=80000000/((((clock>>18)&8191)+1)*(((clock>>12)&63)+1));bc(actual<=1234567,11);bc(bg(base+br(3))==br(51+mode) && bg(base+br(6))==br(55+mode),12);
        bc(bg(0x3ff44530+18*4)==(br(41+(bus-2)*3)|1024) && bg(0x3ff44530+23*4)==(br(42+(bus-2)*3)|1024),13);bc(bg(0x3ff44130+br(43+(bus-2)*3)*4)==(19|128),14);
        bc(esp_spi_init(bus,18,23,19,1000000,0)== -16,15);bm_spi_case(bus,mode,tx,rx,1);bm_spi_case(bus,mode,tx,rx,63);bm_spi_case(bus,mode,tx,rx,64);bm_spi_case(bus,mode,tx,rx,65);bm_spi_case(bus,mode,tx,rx,130);bm_spi_case(bus,mode,0x3ffdf000,0x3ffdfffc,4);
        bm_spi_case(bus,mode,tx,tx,130);bm_spi_tx=0;bm_spi_bytes=0;bm_spi_rx=1;bc(esp_spi_transfer(bus,0,rx,3,1000)==3 && load8(rx)==0xa5 && load8(rx+2)==0xa7,16);bm_spi_tx=tx;bm_spi_bytes=0;bm_spi_rx=0;bc(esp_spi_transfer(bus,tx,0,3,1000)==3,17);
        bm_spi_stall=1;bm_spi_rx=1;bm_spi_bytes=0;bm_ticks=4294967280;let resets=bm_resets;bc(esp_spi_transfer(bus,tx,rx,1,50)== -110 && bm_resets==resets+1,18);bm_spi_stall=0;bm_spi_case(bus,mode,tx,rx,2);
        store64(es_state(bus)+8,1);bc(esp_spi_transfer(bus,tx,rx,1,100)== -16 && esp_spi_deinit(bus)== -16,19);store64(es_state(bus)+8,0);bc(esp_spi_transfer(bus,tx,tx+1,3,100)== -22 && esp_spi_transfer(bus,tx,0x3ffdffff,2,100)== -22,20);
        bc(esp_spi_deinit(bus)==0 && esp_spi_deinit(bus)==0 && !(bg(0x3ff000c0)&br(11+bus-2)),21);mode=mode+1;}bus=bus+1;}
    bc(esp_spi_init(1,18,23,19,1000000,0)== -22 && esp_spi_init(2,34,23,19,1000000,0)== -22 && esp_spi_init(2,18,18,19,1000000,0)== -22,22);bc(esp_spi_init(2,18,-1,-1,1000000,0)== -22 && esp_spi_init(2,18,23,19,1,0)== -22,23);
    bus=0;while bus<2 {bm_sda=21;bm_scl=22;bc(esp_i2c_init(bus,bm_sda,bm_scl,100000)==0,30);let base=br(13+bus);bc(bg(base)==399 && bg(base+br(25))==393 && bg(base+br(23))==200 && bg(base+br(24))==200,31);bc(bg(base+br(28))==400 && bg(base+br(29))==400 && bg(base+br(17))==8000,32);bc(bg(base+br(15))==br(59) && bg(base+br(22))==0,33);bc(bg(0x3ff44130+br(47+bus*2)*4)==(22|128) && bg(0x3ff44130+br(48+bus*2)*4)==(21|128),34);
        bc(esp_i2c_init(bus,21,22,100000)== -16,35);bm_i2c_case(bus,tx,rx,0,0);bm_i2c_case(bus,tx,rx,1,0);bm_i2c_case(bus,tx,rx,30,0);bm_i2c_case(bus,tx,rx,0,1);bm_i2c_case(bus,tx,rx,0,32);bm_i2c_case(bus,tx,rx,30,32);bm_i2c_case(bus,0x3ffdf000,0x3ffdffe0,30,32);
        let error=1;while error<=6 {bm_ticks=4294967280;bm_i2c_error=error;bm_i2c_case(bus,tx,rx,2,3);bm_i2c_error=0;bm_i2c_case(bus,tx,rx,2,3);error=error+1;}
        let calls=bm_i2c_calls;bs(base+br(16),16);bc(esp_i2c_transfer(bus,0x52,tx,2,rx,3,100)== -16 && bm_i2c_calls==calls,36);bs(base+br(16),0);store64(ei_state(bus)+8,1);bc(esp_i2c_transfer(bus,0x52,tx,2,rx,3,100)== -16 && esp_i2c_recover(bus,100)== -16 && esp_i2c_deinit(bus)== -16,37);store64(ei_state(bus)+8,0);
        bm_recovery=1;bm_release=5;bm_pulses=0;bc(esp_i2c_recover(bus,100000)==0 && bm_pulses==6,38);bm_recovery=2;bm_pulses=0;bc(esp_i2c_recover(bus,100000)== -16 && bm_pulses==9,39);bm_recovery=3;bm_pulses=0;bc(esp_i2c_recover(bus,100)== -110 && (bm_output&(1<<22)) && (bm_output&(1<<21)),40);bm_recovery=0;bm_i2c_case(bus,tx,rx,1,1);
        bc(esp_i2c_transfer(bus,128,tx,1,rx,1,100)== -22 && esp_i2c_transfer(bus,0x52,tx,31,rx,1,100)== -22 && esp_i2c_transfer(bus,0x52,tx,1,rx,33,100)== -22,41);
        bc(esp_i2c_deinit(bus)==0 && esp_i2c_deinit(bus)==0 && !(bg(0x3ff000c0)&br(39+bus)),42);bus=bus+1;}
    bc(esp_i2c_init(2,21,22,100000)== -22 && esp_i2c_init(0,21,21,100000)== -22 && esp_i2c_init(0,34,22,100000)== -22,43);bc(!bm_fault && !bm_ps,44);
    let out=alloc(16);store64(out,bm_checks);syscall(1,1,out,8,0,0,0);return 0;
}
