// Exercise the active profile, including rejection before the first arena write.
import "../../lib/platform/esp32-sdk-heap.flex";
fn main() {
    let state=esp32_state();let lower=0x3ffc8000;let upper=0x3ffd0000;let heap=0x3ffc0000;let heap_end=0x3ffc8000;
    if state==0x3fca8000 {lower=0x3fcb2000;upper=0x3fcd0000;heap=0x3fcb0000;heap_end=0x3fcb2000;}
    else if state==0x3fcb0000 {lower=0x3fcc8000;upper=0x3fcd0000;heap=0x3fcc0000;heap_end=0x3fcc8000;}
    else if state==0x3fcc0000 {lower=0x3fcc6000;upper=0x3fcd0000;heap=0x3fcc4000;heap_end=0x3fcc6000;}
    else if state==0x3ffc0000 {upper=0x3ffe0000;heap=0x3ffb6400;heap_end=0x3ffb8000;}
    else if state==0x3ffb0000 {if esp32_load32(state+20)==0x3ffe8000 {upper=0x3ffe0000;}}
    else {return 1;}
    if esp32_load32(state)!=heap || esp32_load32(state+20)<upper {return 2;}
    let native=alloc(heap_end-heap);if native!=heap || esp32_load32(state)!=heap_end {return 3;}
    esp32_store32(lower,0x13572468);esp32_store32(lower+12,0x23456789);
    if esp_sdk_heap_init(lower-16,64)!= -22 || esp_sdk_begin || esp32_load32(lower)!=0x13572468 {return 4;}
    if esp_sdk_heap_init(lower,upper-lower+16)!= -22 || esp_sdk_begin || esp32_load32(lower)!=0x13572468 || esp32_load32(lower+12)!=0x23456789 {return 5;}
    if esp_sdk_heap_init(lower+1,64)!= -22 || esp_sdk_heap_init(lower,63)!= -22 || esp_sdk_heap_init(lower,65)!= -22 || esp_sdk_heap_init(lower,-16)!= -22 || esp_sdk_begin {return 6;}
    if esp_sdk_heap_init(lower,9223372036854775792)!= -22 || esp_sdk_heap_init(9223372036854775792,64)!= -22 || esp_sdk_begin || esp32_load32(lower)!=0x13572468 || esp32_load32(lower+12)!=0x23456789 {return 10;}
    if esp_sdk_heap_init(lower,upper-lower) || esp_sdk_begin!=lower || esp_sdk_end!=upper {return 7;}
    let before=esp_sdk_heap_free();if before!=upper-lower-16 || esp_sdk_heap_init(lower,64)!= -16 || esp_sdk_heap_free()!=before {return 8;}
    if esp_sdk_malloc(-1) || esp_sdk_malloc(9223372036854775807) || esp_sdk_malloc(before) || esp_sdk_calloc(0,1) || esp_sdk_calloc(1,-1) || esp_sdk_calloc(4611686018427387905,4) || esp_sdk_calloc(1,9223372036854775807) || esp_sdk_heap_free()!=before {return 11;}
    let zero=esp_sdk_calloc(1,before-16);if zero!=lower+16 || load8(zero) || load8(zero+before-17) || esp_sdk_free(zero) || esp_sdk_heap_free()!=before {return 12;}
    let all=esp_sdk_malloc(before-16);if all!=lower+16 || esp_sdk_malloc(1) || esp_sdk_free(all) || esp_sdk_heap_free()!=before {return 9;}
    esp_uart_write("PASS: profile heap endpoints, exact capacity and stack-overlap rejection preserve memory\r\n");return 0;
}
