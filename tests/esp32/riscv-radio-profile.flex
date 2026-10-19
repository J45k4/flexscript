import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-sdk-sync.flex";
fn main(){
    let state=esp32_state();let expected=0x3fc90000;if rv_hal_chip==13 {expected=0x40810000;}
    if state!=expected || !esp_xip_ready || rv_hal_state!=state || rv_hal_data_size!=32768 || rv_hal_ram_top!=state+229376 {return 1;}
    if esp_sdk_heap_min()!=state+49152 || esp_sdk_heap_max()!=state+180224 || esp32_load32(state+20)!=state+180224 {return 2;}
    if esp_buffer_valid(state+55,1) || !esp_buffer_valid(state+56,1) || !esp_buffer_valid(state+229375,1) || esp_buffer_valid(state+229376,1) || !esp_buffer_valid(state+229376,0) {return 3;}
    // A TLS template/main pair in native heap is outside radio static data.
    let descriptor=state+24;esp32_store32(descriptor,0x31534c54);esp32_store32(descriptor+4,state+32768);esp32_store32(descriptor+8,1);esp32_store32(descriptor+12,16);esp32_store32(descriptor+16,16);esp32_store32(descriptor+20,state+32784);
    if esp_sdk_tls_valid()!=-22 {return 10;}let k=0;while k<32 {esp32_store32(descriptor+k,0);k=k+4;}
    let guard=alloc(16384);if guard!=state+32768 || alloc(8)!=-12 || esp32_load32(state)!=state+49152 {return 4;}
    let i=0;while i<16384 {store8(guard+i,165);i=i+1;}
    if esp_sdk_heap_init(esp_sdk_heap_min(),131072) || esp_sdk_task_init() {return 5;}
    let before=esp_sdk_heap_free();let data=esp_sdk_malloc(120000);if !data {return 6;}
    i=0;while i<120000 {store8(data+i,(i*37+19)&255);i=i+1;}
    i=0;while i<120000 {if load8(data+i)!=((i*37+19)&255) {return 7;}i=i+1;}
    if esp_sdk_free(data) || esp_sdk_heap_free()!=before {return 8;}
    i=0;while i<16384 {if load8(guard+i)!=165 {return 9;}i=i+1;}
    return 0;
}
