// Original I2S finite chains. Imported by esp32-i2s.flex; not a second driver.
// State256bytes: existing single-buffer fields retain offsets0..111.
// Per-direction chain count128/136,immutable caller block table144/152.
// Blocks are packed[buffer:u32,bytes:u32],descriptors are16-byte slots.
// Caller owns tables/descriptors/payloads until terminal poll/wait or cancel.
fn eia_status_mask(direction){if direction{return (1<<11)|(1<<12)|(1<<14)|(1<<16);}return (1<<8)|(1<<9)|(1<<10)|(1<<13)|(1<<15);}
fn eia_irq_mask(direction){if direction{return (1<<12)|(1<<14);}return (1<<9)|(1<<10)|(1<<13);}
fn eia_resource_overlap(state,direction,address,size){if eis_active(state,direction){return eis_resource_overlap(state,direction,address,size);}let count=load64(state+128+direction*8);let slots=count;if !slots{slots=1;}let desc=load64(state+64+direction*16);if eia_overlap(address,size,desc,slots*16){return 1;}if !count{return eia_overlap(address,size,load64(state+96+direction*8),load64(state+72+direction*16));}let table=load64(state+144+direction*8);if eia_overlap(address,size,table,count*8){return 1;}let i=0;while i<count{if eia_overlap(address,size,esp32_load32(table+i*8),esp32_load32(table+i*8+4)){return 1;}i=i+1;}return 0;}
fn eia_completion(bus,direction,state){let base=esp_i2s_base(bus);let done=1<<9;let errors=(1<<10)|(1<<13);if direction{done=1<<12;errors=1<<14;}let status=esp32_load32(base+0xc);if status&errors{return -5;}if !((status&done) && (!direction || (esp32_load32(base+0xbc)&1))){return 0;}
 let descriptor=load64(state+64+direction*16);let total=load64(state+72+direction*16);let count=load64(state+128+direction*8);let table=load64(state+144+direction*8);let n=count;if !n{n=1;}let i=0;while i<n{let word=esp32_load32(descriptor+i*16);let size=total;if count{size=esp32_load32(table+i*8+4);}if (word&0x80000000) || (!direction && ((word>>12)&4095)!=size){return -5;}i=i+1;}return total;
}
// 0=pending,positive byte count=complete,negative errno=error. Terminal calls
// stop/reset this direction,ack its status and return every descriptor owner.
fn esp_i2s_poll(bus,direction){if !esp_i2s_base(bus) || direction<0 || direction>1{return -22;}let state=eia_state(bus);if !state || !load64(state){return -19;}let ps=esp32_irq_save();if load64(state+8)&4{esp32_irq_restore(ps);return -16;}if !(load64(state+8)&(1<<direction)){esp32_irq_restore(ps);return -22;}if eis_active(state,direction){esp32_irq_restore(ps);return -16;}let result=eia_completion(bus,direction,state);if result{eia_stop(bus,direction,state);}esp32_irq_restore(ps);return result;}
fn esp_i2s_source(bus){if !esp_i2s_base(bus){return -22;}return 32+bus;}
fn esp_i2s_interrupts(bus,rx,tx){let base=esp_i2s_base(bus);if !base || rx<0 || rx>1 || tx<0 || tx>1{return -22;}let state=eia_state(bus);if !state || !load64(state){return -19;}esp32_store32(base+0x14,rx*eia_irq_mask(0)|tx*eia_irq_mask(1));return 0;}
fn esp_i2s_pending(bus){let base=esp_i2s_base(bus);if !base{return -22;}return esp32_load32(base+0x10);}
fn esp_i2s_ack(bus,mask){let base=esp_i2s_base(bus);if !base || mask<0 || (mask&~0x1ffff){return -22;}esp32_store32(base+0x18,mask);return 0;}
fn eia_chain_validate(state,direction,descriptors,blocks,count){let total=0;let frame=load64(state+24)/4;let peer=1-direction;let busy=load64(state+8);if busy&4 || busy&(1<<direction){return -16;}if !(load64(state+16)&(1<<direction)){return -22;}
 if eis_internal_overlap(descriptors,count*16) || eis_internal_overlap(blocks,count*8){return -22;}if eia_overlap(descriptors,count*16,blocks,count*8){return -22;}if busy&(1<<peer){if eia_resource_overlap(state,peer,descriptors,count*16) || eia_resource_overlap(state,peer,blocks,count*8){return -22;}}
 let i=0;while i<count{let data=esp32_load32(blocks+i*8);let size=esp32_load32(blocks+i*8+4);if eis_internal_overlap(data,size){return -22;}if size<frame || size>4092 || size%frame || (data&3) || !esp_buffer_valid(data,size) || eia_overlap(data,size,descriptors,count*16) || eia_overlap(data,size,blocks,count*8){return -22;}
 if busy&(1<<peer){if eia_resource_overlap(state,peer,data,size){return -22;}}
 // RX blocks must be disjoint. Repeated/overlapping immutable TX blocks are
 // valid because DMA only reads them; cross-direction overlap is rejected.
 if !direction{let j=0;while j<i{if eia_overlap(data,size,esp32_load32(blocks+j*8),esp32_load32(blocks+j*8+4)){return -22;}j=j+1;}}
 total=total+size;i=i+1;}return total;
}
fn esp_i2s_submit_chain(bus,direction,descriptors,blocks,count){let base=esp_i2s_base(bus);if !base || direction<0 || direction>1 || count<1 || count>64 || (descriptors&3) || (blocks&3) || !esp_buffer_valid(descriptors,count*16) || !esp_buffer_valid(blocks,count*8){return -22;}let state=eia_state(bus);if !state || !load64(state){return -19;}let ps=esp32_irq_save();let total=eia_chain_validate(state,direction,descriptors,blocks,count);if total<0{esp32_irq_restore(ps);return total;}
 store64(state+8,load64(state+8)|(1<<direction));store64(state+64+direction*16,descriptors);store64(state+72+direction*16,total);store64(state+96+direction*8,esp32_load32(blocks));store64(state+128+direction*8,count);store64(state+144+direction*8,blocks);
 // Link the whole chain before starting hardware. Owner publication in the
 // common descriptor helper is last for each node; no link is active yet.
 let i=0;while i<count{let data=esp32_load32(blocks+i*8);let size=esp32_load32(blocks+i*8+4);let used=0;if direction{used=size;}let next=0;if i+1<count{next=descriptors+(i+1)*16;}let error=esp_dma_descriptor(descriptors+i*16,data,size,used,next,i+1==count);if error{eia_stop(bus,direction,state);esp32_irq_restore(ps);return error;}i=i+1;}
 let reset=1<<(1-direction);let fifo=1<<(3-direction);esp_reg_update(base+8,reset|fifo,reset|fifo);esp_reg_update(base+8,reset|fifo,0);esp_reg_update(base+0x60,1<<direction,1<<direction);esp_reg_update(base+0x60,1<<direction,0);esp32_store32(base+0x18,eia_status_mask(direction));if !direction{esp32_store32(base+0x24,total/4);}esp32_store32(base+0x34-direction*4,(descriptors&0xfffff)|(1<<29));esp_reg_update(base+8,1<<(5-direction),1<<(5-direction));esp32_irq_restore(ps);return 0;
}
