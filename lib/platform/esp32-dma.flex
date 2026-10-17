import "esp32-common.flex";
// Original ESP32 peripheral-local DMA descriptors. There is no S3 GDMA here.
// Official ESP-IDF v5.5.1 esp_rom_lldesc.h:12-byte descriptor,4-byte aligned.
// Reserve16 bytes to match the S3 helper and leave a zero padding word.
// Caller exclusively owns the descriptor and buffer until transfer completion.
fn esp_dma_descriptor(desc,buffer,size,used,next,eof) {
    if !esp_buffer_valid(desc,16) || (desc&3) || !esp_buffer_valid(buffer,size) || (buffer&3) || size<1 || size>4092 || used<0 || used>size || eof<0 || eof>1 {return -22;}
    if desc<buffer+size && buffer<desc+16 {return -22;}
    if next && (!esp_buffer_valid(next,16) || (next&3) || (next<desc+16 && desc<next+16) || (next<buffer+size && buffer<next+16)) {return -22;}
    esp32_store32(desc+4,buffer);esp32_store32(desc+8,next);esp32_store32(desc+12,0);
    // Publish ownership last, after all pointers and the intrinsic's barriers.
    esp32_store32(desc,size|(used<<12)|(eof<<30)|(1<<31));return 0;
}
