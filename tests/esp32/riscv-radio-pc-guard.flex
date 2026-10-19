import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-sdk-sync.flex";
fn never_entered(a,b,c,d,e,f,g,h){return 0;}
fn write_const(code,register,value){
 let lo=((value+2048)&4095)-2048;let hi=((value-lo)>>12)&1048575;
 esp32_store32(code,0x37|(register<<7)|(hi<<12));esp32_store32(code+4,0x13|(register<<7)|(register<<15)|((lo&4095)<<20));return 0;
}
fn main(){
 let guard=alloc(512);let i=0;while i<256{store8(guard+i,165);i=i+1;}let code=guard+256;
 // If the former128KiB IRAM bound is accidentally retained, this buffer's
 // instruction alias publishes DONE99 instead of faulting. It is writable
 // native heap in the explicit64KiB radio profile, outside executable RAM.
 write_const(code,5,esp32_state()+8);esp32_store32(code+8,0x06300313);esp32_store32(code+12,0x0062a023);esp32_store32(code+16,0x0002a223);
 write_const(code+20,5,esp32_state()+4);write_const(code+28,6,0x444f4e45);esp32_store32(code+36,0x0062a023);esp32_store32(code+40,0x0000006f);
 let arena=esp_sdk_heap_min();if esp_sdk_heap_init(arena,esp_sdk_heap_max()-arena)||esp_sdk_task_init(){return 1;}
 let task=esp_sdk_task_create(esp32_callback32(never_entered),0,2048,1);if !task{return 2;}let pc=code;if rv_hal_chip==5{pc=pc+0x700000;}esp32_store32(task+256,pc);esp_sdk_task_unmask();esp_sdk_yield();return 3;
}
