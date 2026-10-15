import "esp32s3-usb.flex";
// Minimal USB CDC ACM device, polled. Call poll frequently in the main loop.
// One buffered 64-byte OUT packet; reads apply backpressure by rearming later.
global esp_cdc_device=0;
global esp_cdc_descriptor=0;
global esp_cdc_product=0;
global esp_cdc_vendor=0;
global esp_cdc_io=0;
global esp_cdc_rx=0;
global esp_cdc_line=0;
global esp_cdc_ready=0;
global esp_cdc_lines=0;
global esp_cdc_received=0;
global esp_cdc_address=0;
global esp_cdc_line_pending=0;
global esp_cdc_control=0;
global esp_cdc_left=0;
global esp_cdc_zero=0;
fn esp_usb_unhex(text,bytes) {
    let n=0;while load8(text+n) {n=n+1;}let i=0;while i<n {let a=load8(text+i);let b=load8(text+i+1);a=a-48;if a>9 {a=a-39;}b=b-48;if b>9 {b=b-39;}store8(bytes+i/2,(a<<4)|b);i=i+2;}return bytes;
}
fn esp_cdc_prepare(vid,pid) {
    if vid<1 || vid>65535 || pid<1 || pid>65535 {return -22;}
    if !esp_cdc_io {
        let memory=alloc(320);if memory<0 {return -12;}esp_cdc_io=memory+192;esp_cdc_rx=memory+256;
        esp_cdc_device=esp_usb_unhex("120100020200004000000000000101020001",memory);
        esp_cdc_descriptor=esp_usb_unhex("090243000201008032090400000102020100052400100105240100010424020205240600010705820308001009040100020a0000000705010240000007058102400000",memory+32);
        esp_cdc_vendor=esp_usb_unhex("160346006c0065007800730063007200690070007400",memory+112);
        esp_cdc_product=esp_usb_unhex("1e0346006c00650078007300630072006900700074002000430044004300",memory+144);
        esp_cdc_line=esp_usb_unhex("00c20100000008",memory+176);
    }
    if esp_cdc_io<0 || esp_cdc_rx<0 {return -12;}
    store8(esp_cdc_device+8,vid);store8(esp_cdc_device+9,vid>>8);store8(esp_cdc_device+10,pid);store8(esp_cdc_device+11,pid>>8);
    esp_cdc_ready=0;esp_cdc_received=0;esp_cdc_address=0;esp_cdc_left=0;esp_cdc_zero=0;esp_cdc_line_pending=0;esp_cdc_lines=0;return 0;
}
fn esp_cdc_init(vid,pid,cycles) {let error=esp_cdc_prepare(vid,pid);if error {return error;}return esp_usb_device_init(cycles);}
fn esp_cdc_next(cycles) {
    let size=esp_cdc_left;if size>64 {size=64;}let error=esp_usb_device_send(0,esp_cdc_control,size,cycles);if error<0 {return error;}
    esp_cdc_control=esp_cdc_control+size;esp_cdc_left=esp_cdc_left-size;return 0;
}
fn esp_cdc_reply(bytes,size,requested,cycles) {
    esp_cdc_left=size;if esp_cdc_left>requested {esp_cdc_left=requested;}esp_cdc_zero=size<requested && !(esp_cdc_left&63);esp_cdc_control=bytes;
    let error=esp_cdc_next(cycles);esp_usb_device_arm(0);return error;
}
fn esp_cdc_reject() {esp_usb_device_stall(0,1);esp_usb_device_stall(0,0);esp_usb_device_arm(0);return -95;}
fn esp_cdc_setup(setup,cycles) {
    let request=load8(setup+1);let kind=load8(setup);let value=load8(setup+2)|(load8(setup+3)<<8);let index=load8(setup+4)|(load8(setup+5)<<8);let length=load8(setup+6)|(load8(setup+7)<<8);
    esp_cdc_left=0;esp_cdc_zero=0;esp_cdc_address=0;esp_cdc_line_pending=0;
    if kind==128 && request==6 {
        let descriptor=0;let size=0;let type=value>>8;
        if type==1 && !(value&255) {descriptor=esp_cdc_device;size=18;}
        else if type==2 && !(value&255) {descriptor=esp_cdc_descriptor;size=67;}
        else if type==3 {
            if !(value&255) {store64(esp_cdc_io,0x04090304);descriptor=esp_cdc_io;size=4;}
            else if (value&255)==1 {descriptor=esp_cdc_vendor;size=load8(descriptor);}
            else if (value&255)==2 {descriptor=esp_cdc_product;size=load8(descriptor);}
        }if descriptor {return esp_cdc_reply(descriptor,size,length,cycles);}return esp_cdc_reject();
    }
    if kind==0 && request==5 && value<=127 && !length && !index {esp_cdc_address=value+1;return esp_cdc_reply(esp_cdc_io,0,0,cycles);}
    if kind==0 && request==9 && value<=1 && !length && !index {
        esp_cdc_ready=value;esp_cdc_received=0;
        if value {esp_usb_endpoint(1,0,2,64);esp_usb_endpoint(1,1,2,64);esp_usb_endpoint(2,1,3,8);esp_usb_device_arm(1);}
        else {esp32_store32(0x60080920,1<<27);esp32_store32(0x60080b20,1<<27);esp32_store32(0x60080940,1<<27);}
        return esp_cdc_reply(esp_cdc_io,0,0,cycles);
    }
    if kind==128 && request==8 && length==1 && !value && !index {store8(esp_cdc_io,esp_cdc_ready);return esp_cdc_reply(esp_cdc_io,1,1,cycles);}
    if (kind==128 || kind==129 || kind==130) && request==0 && length==2 && !value {store64(esp_cdc_io,0);return esp_cdc_reply(esp_cdc_io,2,2,cycles);}
    if kind==129 && request==10 && index<=1 && !value && length==1 {store8(esp_cdc_io,0);return esp_cdc_reply(esp_cdc_io,1,1,cycles);}
    if kind==1 && request==11 && index<=1 && !value && !length {return esp_cdc_reply(esp_cdc_io,0,0,cycles);}
    if kind==2 && request==1 && !value && !length && (index==1 || index==129 || index==130) {
        let base=0x60080b20;if index&128 {base=0x60080900+(index&15)*32;}esp_reg_update(base,(1<<21)|(1<<28),1<<28);return esp_cdc_reply(esp_cdc_io,0,0,cycles);
    }
    if kind==161 && request==33 && !value && !index && length==7 {return esp_cdc_reply(esp_cdc_line,7,7,cycles);}
    if kind==33 && request==32 && !value && !index && length==7 {esp_cdc_line_pending=1;return esp_usb_device_arm(0);}
    if kind==33 && request==34 && !index && !length {esp_cdc_lines=value&3;return esp_cdc_reply(esp_cdc_io,0,0,cycles);}
    if kind==33 && request==35 && !index && !length {return esp_cdc_reply(esp_cdc_io,0,0,cycles);}return esp_cdc_reject();
}
fn esp_cdc_poll(cycles) {
    if esp_usb_mode!=1 || !esp_cdc_io || cycles<1 || cycles>2147483647 {return -22;}
    if esp32_load32(0x60080908)&1 {
        esp32_store32(0x60080908,1);
        if esp_cdc_left {let error=esp_cdc_next(cycles);if error<0 {return error;}}
        else if esp_cdc_zero {esp_cdc_zero=0;let error=esp_usb_device_send(0,esp_cdc_io,0,cycles);if error<0 {return error;}}
        else if esp_cdc_address {esp_usb_device_address(esp_cdc_address-1);esp_cdc_address=0;}
    }
    let packet=esp_usb_device_receive(esp_cdc_io,64);
    if packet== -104 {esp_cdc_ready=0;esp_cdc_received=0;esp_cdc_left=0;esp_cdc_zero=0;esp_cdc_address=0;esp_cdc_line_pending=0;esp_cdc_lines=0;return 0;}
    if packet== -11 {return 0;}if packet<0 {return packet;}let ep=packet&15;let size=(packet>>4)&2047;let status=(packet>>17)&15;
    if status==6 && !ep && size==8 {return esp_cdc_setup(esp_cdc_io,cycles);}
    if status==2 && !ep {
        if esp_cdc_line_pending {if size!=7 {return esp_cdc_reject();}let i=0;while i<7 {store8(esp_cdc_line+i,load8(esp_cdc_io+i));i=i+1;}esp_cdc_line_pending=0;return esp_cdc_reply(esp_cdc_io,0,0,cycles);}
        return esp_usb_device_arm(0);
    }
    if status==2 && ep==1 && esp_cdc_ready {let i=0;while i<size {store8(esp_cdc_rx+i,load8(esp_cdc_io+i));i=i+1;}esp_cdc_received=size;if !size {esp_usb_device_arm(1);}}
    return 0;
}
fn esp_cdc_read(buffer,capacity) {
    if !esp_cdc_ready {return -107;}if capacity<1 || !esp_buffer_valid(buffer,capacity) {return -22;}if !esp_cdc_received {return -11;}
    let count=esp_cdc_received;if count>capacity {count=capacity;}let i=0;while i<count {store8(buffer+i,load8(esp_cdc_rx+i));i=i+1;}
    esp_cdc_received=esp_cdc_received-count;i=0;while i<esp_cdc_received {store8(esp_cdc_rx+i,load8(esp_cdc_rx+count+i));i=i+1;}if !esp_cdc_received {esp_usb_device_arm(1);}return count;
}
fn esp_cdc_write(buffer,size,cycles) {if !esp_cdc_ready {return -107;}return esp_usb_device_send(1,buffer,size,cycles);}
