import "esp32s3-common.flex";
// MSPI SPI1, bounded single-wire command transfers. Executes entirely in
// internal SRAM; preserves ROM pin configuration, clock and controller state.
// One owner, no cached flash execution and no interrupt callback use.
fn esp_memory_command(cs,command,address,address_bytes,tx,rx,size,cycles) {
    if cs<0 || cs>1 || command<0 || command>255 || address_bytes<0 || address_bytes>3 || address<0 || address>0xffffff || size<0 || size>64 || (tx && rx) || (size && !tx && !rx) || (tx && !esp_buffer_valid(tx,size)) || (rx && !esp_buffer_valid(rx,size)) || cycles<1 || cycles>2147483647 {return -22;}
    let base=0x60002000;let error=esp_wait_mask(base,0xffffffff,0,cycles);if error {return error;}
    let ctrl=esp32_load32(base+8);let user=esp32_load32(base+24);let user1=esp32_load32(base+28);let user2=esp32_load32(base+32);
    let misc=esp32_load32(base+52);let clk=esp32_load32(base+20);let ddr=esp32_load32(base+224);
    esp32_store32(base+8,ctrl&~0x019063fc);esp32_store32(base+224,0);esp32_store32(base+52,(misc&~3)|(2-cs));
    // Conservative 20 MHz at the ROM's 80 MHz MSPI source (N=4).
    esp32_store32(base+20,(3<<16)|(1<<8)|3);
    let config=1<<31;if address_bytes {config=config|(1<<30);}if tx {config=config|(1<<27);}if rx {config=config|(1<<28);}
    esp32_store32(base+24,config);let addr_bits=0;if address_bytes {addr_bits=(address_bytes*8-1)<<26;}esp32_store32(base+28,addr_bits);esp32_store32(base+32,(7<<28)|command);
    esp32_store32(base+4,address);if size {esp32_store32(base+36,size*8-1);esp32_store32(base+40,size*8-1);}
    let i=0;while i<16 {let word=0;let j=0;while j<4 {if tx && i*4+j<size {word=word|(load8(tx+i*4+j)<<(j*8));}j=j+1;}esp32_store32(base+88+i*4,word);i=i+1;}
    esp32_store32(base,1<<18);error=esp_wait_mask(base,1<<18,0,cycles);
    if !error && rx {i=0;while i<size {let word=esp32_load32(base+88+(i/4)*4);store8(rx+i,word>>((i&3)*8));i=i+1;}}
    esp32_store32(base+8,ctrl);esp32_store32(base+24,user);esp32_store32(base+28,user1);esp32_store32(base+32,user2);esp32_store32(base+52,misc);esp32_store32(base+20,clk);esp32_store32(base+224,ddr);return error;
}
