import "esp32-dma.flex";
import "esp32-i2s-chain.flex";
import "esp32-i2s-stream.flex";
// Original ESP32 I2S0/1 integrated DMA, stereo Philips PCM,16/32-bit samples.
// Requires an active PLL system clock (for example esp_radio_clock_init).
// PLL_D2=160MHz. init returns actual integer sample rate. RX=0,TX=1.
// SRAM is caller-owned, aligned, little-endian interleaved left/right samples.
// Finite single buffers or chains; submit arms asynchronously,poll/wait reclaim.
// Duplex shares TX master clocks with RX slave; data still passes through GPIO.
// Single core,exclusive peripheral ownership; DMA never touches flash/PSRAM.
global esp_i2s_states=0;
fn esp_i2s_base(bus) {if bus<0 || bus>1 {return 0;}return 0x3ff4f000+bus*122880;}
fn eia_state(bus) {if !esp_i2s_base(bus) || !esp_i2s_states {return 0;}return esp_i2s_states+bus*256;}
fn eia_overlap(a,n,b,m) {return a<b+m && b<a+n;}
fn eia_clock(hz,bits) {
    let unit=hz*bits*8;let n=160000000/unit;let rem=160000000%unit;let best_a=1;let best_b=0;let best_error=rem;let a=1;
    while a<=63 {let b=(rem*a+unit/2)/unit;let error=rem*a-unit*b;if error<0 {error= -error;}
        if error*best_a<best_error*a {best_error=error;best_a=a;best_b=b;}a=a+1;
    }
    if best_b==best_a {n=n+1;best_a=1;best_b=0;}if n<2 || n>255 {return 0;}return (1<<20)|n|(best_b<<8)|(best_a<<14);
}
fn eia_init(bus,mode,bck,ws,dout,din,hz,bits) {
    let base=esp_i2s_base(bus);
    if !base || mode<1 || mode>3 || !esp_gpio_valid(bck) || bck>=34 || !esp_gpio_valid(ws) || ws>=34 || bck==ws || hz<8000 || hz>192000 || (bits!=16 && bits!=32) {return -22;}
    if mode&2 {if !esp_gpio_valid(dout) || dout>=34 || dout==bck || dout==ws {return -22;}}
    if mode&1 {if !esp_gpio_valid(din) || din==bck || din==ws || ((mode&2) && din==dout) {return -22;}}
    // ROM RAM loading may leave the CPU on XTAL with no usable PLL_D2.
    if (esp32_load32(0x3ff48070)&(3<<27))!=(1<<27) {return -19;}
    let clk=eia_clock(hz,bits);if !clk {return -22;}let ps=esp32_irq_save();
    if !esp_i2s_states {let p=alloc(512);if p<=0 {esp32_irq_restore(ps);return -12;}let i=0;while i<512 {store8(p+i,0);i=i+1;}esp_i2s_states=p;}
    let state=eia_state(bus);if load64(state) || load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,4);
    let bit=4;if bus {bit=21;}esp_clock_enable(0,bit);esp_reg_update(0x3ff000c4,1<<bit,1<<bit);esp_reg_update(0x3ff000c4,1<<bit,0);esp32_irq_restore(ps);
    esp32_store32(base+8,15);esp32_store32(base+0x60,15);esp32_store32(base+8,0);esp32_store32(base+0x60,(1<<12)|(1<<8)|(1<<6));
    esp32_store32(base+0x14,0);esp32_store32(base+0x18,0x1ffff);esp32_store32(base+0xa0,(1<<8)|(1<<7)|(1<<3));esp32_store32(base+0xa8,0);esp32_store32(base+0xb4,0);esp32_store32(base+0x1c,0);
    esp32_store32(base+0xac,clk);esp32_store32(base+0xb0,4|(4<<6)|(bits<<12)|(bits<<18));
    let fifo=32|(32<<6)|(1<<12)|(1<<19)|(1<<20);if bits==32 {fifo=fifo|(2<<13)|(2<<16);}esp32_store32(base+0x20,fifo);esp32_store32(base+0x2c,0);
    let conf=(1<<10)|(1<<11);if bits==16 {conf=conf|(1<<16)|(1<<17);}if mode==3 {conf=conf|(1<<18)|(1<<7);}esp32_store32(base+8,conf);
    let clock=23+bus;let word=25+bus;if mode==1 {clock=27;word=28;if bus {clock=164;word=165;}}
    esp_gpio_route_output(bck,clock);esp_gpio_open_drain(bck,0);esp_gpio_route_output(ws,word);esp_gpio_open_drain(ws,0);
    if mode&2 {let signal=163;if bus {signal=189;}esp_gpio_route_output(dout,signal);esp_gpio_open_drain(dout,0);}
    if mode&1 {let signal=155;if bus {signal=181;}esp_gpio_input(din,0);esp_gpio_open_drain(din,0);esp_gpio_route_input(din,signal);}
    store64(state+16,mode);store64(state+24,bits);store64(state+32,bck);store64(state+40,ws);store64(state+48,dout);store64(state+56,din);
    store64(state,1);store64(state+8,0);let a=(clk>>14)&63;let b=(clk>>8)&63;return 160000000*a/(((clk&255)*a+b)*bits*8);
}
fn esp_i2s_init(bus,direction,bck,ws,data,hz,bits) {if direction<0 || direction>1 {return -22;}if direction {return eia_init(bus,2,bck,ws,data,-1,hz,bits);}return eia_init(bus,1,bck,ws,-1,data,hz,bits);}
fn esp_i2s_init_duplex(bus,bck,ws,dout,din,hz,bits) {return eia_init(bus,3,bck,ws,dout,din,hz,bits);}
fn eia_stop(bus,direction,state) {
    let ps=esp32_irq_save();let base=esp_i2s_base(bus);let start=1<<(5-direction);let reset=1<<(1-direction);let fifo=1<<(3-direction);let link=base+0x34-direction*4;
    esp_reg_update(base+8,start,0);esp32_store32(link,1<<28);esp_reg_update(base+0x60,1<<direction,1<<direction);esp_reg_update(base+0x60,1<<direction,0);esp_reg_update(base+8,fifo|reset,fifo|reset);esp_reg_update(base+8,fifo|reset,0);
    let at=64+direction*16;let descriptor=load64(state+at);let count=load64(state+128+direction*8);if !count{count=1;}let i=0;while descriptor && i<count{let node=descriptor+i*16;esp32_store32(node,esp32_load32(node)&0x7fffffff);i=i+1;}esp32_store32(base+0x18,eia_status_mask(direction));store64(state+128+direction*8,0);store64(state+144+direction*8,0);store64(state+at,0);store64(state+at+8,0);store64(state+96+direction*8,0);store64(state+8,load64(state+8)&~(1<<direction));eis_stopped(state,direction);esp32_irq_restore(ps);return 0;
}
fn eia_submit(bus,direction,descriptor,buffer,size,owned) {
    let base=esp_i2s_base(bus);if !base || direction<0 || direction>1 || size<4 || size>4092 || !esp_buffer_valid(descriptor,16) || (descriptor&3) || !esp_buffer_valid(buffer,size) || (buffer&3) || eia_overlap(descriptor,16,buffer,size) {return -22;}
    if eis_internal_overlap(descriptor,16) || eis_internal_overlap(buffer,size){return -22;}let state=eia_state(bus);if !state || !load64(state) {return -19;}if !(load64(state+16)&(1<<direction)) || size%(load64(state+24)/4) {return -22;}
    let ps=esp32_irq_save();let busy=load64(state+8);if busy&((4*!owned)|(1<<direction)) {esp32_irq_restore(ps);return -16;}
    let peer=1-direction;if busy&(1<<peer) {if eia_resource_overlap(state,peer,descriptor,16) || eia_resource_overlap(state,peer,buffer,size) {esp32_irq_restore(ps);return -22;}}
    store64(state+8,busy|(1<<direction));let at=64+direction*16;store64(state+at,descriptor);store64(state+at+8,size);store64(state+96+direction*8,buffer);
    let reset=1<<(1-direction);let fifo=1<<(3-direction);esp_reg_update(base+8,reset|fifo,reset|fifo);esp_reg_update(base+8,reset|fifo,0);esp_reg_update(base+0x60,1<<direction,1<<direction);esp_reg_update(base+0x60,1<<direction,0);
    let used=0;let mask=(1<<8)|(1<<9)|(1<<10)|(1<<13)|(1<<15);if direction {used=size;mask=(1<<11)|(1<<12)|(1<<14)|(1<<16);}esp32_store32(base+0x18,mask);
    let error=esp_dma_descriptor(descriptor,buffer,size,used,0,1);if error {eia_stop(bus,direction,state);esp32_irq_restore(ps);return error;}
    if !direction {esp32_store32(base+0x24,size/4);}esp32_store32(base+0x34-direction*4,(descriptor&0xfffff)|(1<<29));esp_reg_update(base+8,1<<(5-direction),1<<(5-direction));esp32_irq_restore(ps);return 0;
}
fn esp_i2s_submit(bus,direction,descriptor,buffer,size) {return eia_submit(bus,direction,descriptor,buffer,size,0);}
fn eia_wait(bus,direction,cycles,owned) {
    let base=esp_i2s_base(bus);if !base || direction<0 || direction>1 || cycles<1 || cycles>2147483647 {return -22;}let state=eia_state(bus);if !state || !load64(state) {return -19;}if eis_active(state,direction){return -16;}if !owned && (load64(state+8)&4) {return -16;}if !(load64(state+8)&(1<<direction)) {return -22;}
    let start=esp32_cycles();let result=0;while !result{result=eia_completion(bus,direction,state);if !result && ((esp32_cycles()-start)&4294967295)>=cycles{result= -110;}}
    eia_stop(bus,direction,state);return result;
}
fn esp_i2s_wait(bus,direction,cycles) {return eia_wait(bus,direction,cycles,0);}
fn esp_i2s_cancel(bus,direction) {if !esp_i2s_base(bus) || direction<0 || direction>1 {return -22;}let state=eia_state(bus);if !state || !load64(state) {return -19;}let ps=esp32_irq_save();if load64(state+8)&4 {esp32_irq_restore(ps);return -16;}if load64(state+8)&(1<<direction) {eia_stop(bus,direction,state);}esp32_irq_restore(ps);return 0;}
fn esp_i2s_transfer(bus,direction,descriptor,buffer,size,cycles) {if cycles<1 || cycles>2147483647 {return -22;}let error=esp_i2s_submit(bus,direction,descriptor,buffer,size);if error {return error;}return esp_i2s_wait(bus,direction,cycles);}
// Finite duplex exchange. workspace has size+one stereo frame bytes and is
// separate from both descriptors and payloads. A silent first frame lets the
// receiver synchronize to WS; the returned RX buffer begins with TX frame0.
// One time budget begins before copying and is shared by both waits.
fn esp_i2s_exchange(bus,rx_descriptor,rx,tx_descriptor,tx,size,workspace,cycles) {
    if !esp_i2s_base(bus) || cycles<1 || cycles>2147483647 {return -22;}let state=eia_state(bus);if !state || !load64(state) {return -19;}if load64(state+16)!=3 {return -22;}let frame=load64(state+24)/4;
    if size<frame || size>4092-frame || size%frame || !esp_buffer_valid(rx_descriptor,16) || (rx_descriptor&3) || !esp_buffer_valid(tx_descriptor,16) || (tx_descriptor&3) || !esp_buffer_valid(rx,size) || (rx&3) || !esp_buffer_valid(tx,size) || (tx&3) || !esp_buffer_valid(workspace,size+frame) || (workspace&3) {return -22;}
    if eis_internal_overlap(rx_descriptor,16) || eis_internal_overlap(tx_descriptor,16) || eis_internal_overlap(rx,size) || eis_internal_overlap(tx,size) || eis_internal_overlap(workspace,size+frame){return -22;}
    if eia_overlap(rx_descriptor,16,tx_descriptor,16) || eia_overlap(rx_descriptor,16,rx,size) || eia_overlap(rx_descriptor,16,tx,size) || eia_overlap(tx_descriptor,16,rx,size) || eia_overlap(tx_descriptor,16,tx,size) || eia_overlap(rx,size,tx,size) || eia_overlap(workspace,size+frame,rx_descriptor,16) || eia_overlap(workspace,size+frame,tx_descriptor,16) || eia_overlap(workspace,size+frame,rx,size) || eia_overlap(workspace,size+frame,tx,size) {return -22;}
    let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,4);esp32_irq_restore(ps);let start=esp32_cycles();let i=0;while i<frame {store8(workspace+i,0);i=i+1;}i=0;while i<size {store8(workspace+frame+i,load8(tx+i));i=i+1;}
    let result=0;if ((esp32_cycles()-start)&0xffffffff)>=cycles {result= -110;}if !result {result=eia_submit(bus,0,rx_descriptor,rx,size,1);}if !result {result=eia_submit(bus,1,tx_descriptor,workspace,size+frame,1);}
    let direction=0;while direction<2 && !result {let elapsed=(esp32_cycles()-start)&0xffffffff;if elapsed>=cycles {result= -110;}else {let count=eia_wait(bus,direction,cycles-elapsed,1);if count<0 {result=count;}}direction=direction+1;}
    if load64(state+8)&1 {eia_stop(bus,0,state);}if load64(state+8)&2 {eia_stop(bus,1,state);}ps=esp32_irq_save();store64(state+8,0);esp32_irq_restore(ps);if result {return result;}return size;
}
fn esp_i2s_deinit(bus) {
    let base=esp_i2s_base(bus);if !base {return -22;}let state=eia_state(bus);if !state || !load64(state) {return 0;}let ps=esp32_irq_save();if load64(state+8) {esp32_irq_restore(ps);return -16;}store64(state+8,4);esp32_irq_restore(ps);
    esp32_store32(base+8,0);esp32_store32(base+0x14,0);esp32_store32(base+0x18,0x1ffff);esp_gpio_input(load64(state+32),0);esp_gpio_input(load64(state+40),0);let mode=load64(state+16);if mode&2 {esp_gpio_input(load64(state+48),0);}if mode&1 {esp_gpio_input(load64(state+56),0);}
    let bit=4;if bus {bit=21;}ps=esp32_irq_save();esp_reg_update(0x3ff000c0,1<<bit,0);store64(state,0);store64(state+8,0);esp32_irq_restore(ps);return 0;
}
