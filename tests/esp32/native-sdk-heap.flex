import "../../lib/platform/esp32-sdk-heap.flex";
// Exercise the real native allocator at the SDK boundary with a live SDK
// allocation/header canary. Exhaustion must return an error without a write.
fn main() {
    if esp_sdk_heap_init(0x3ffc8000,98304) {return 1;}let owned=esp_sdk_malloc(32);if !owned {return 2;}store64(owned,0x123456789abcdef0);
    let before=esp32_load32(0x3ffc8000);let heap=alloc(32768);if heap!=0x3ffc0000 || load8(heap) || load8(heap+32767) {return 3;}
    store8(heap,1);store8(heap+32767,2);if alloc(8)!= -12 || alloc(32769)!= -12 || alloc(0)!= -22 {return 4;}
    if esp32_load32(0x3ffc8000)!=before || load64(owned)!=0x123456789abcdef0 || esp32_load32(0x3ffc800c)!=0x48454150 || esp_sdk_free(owned) || esp_sdk_heap_free()!=98304-16 {return 5;}
    return 0;
}
