import "../../lib/platform/esp32c3-libc-stdio.flex";
fn stdio_pause(a,b,c,d,e,f,g,h){return 0;}
fn main(){
 if esp_sdk_heap_init(0x3fcb8000,32768)||esp_libc_stdio_init(){return 1;}esp_libc_posix_bind();esp32_callback32(stdio_pause);
 if esp_libc_console_budget(0)!=-22||esp_libc_console_budget(1<<31)!=-22||esp_libc_console_budget(1){return 2;}
 if esp32_call32(esp32_external("stdio_budget_probe"),0,0,0,0,0,0,0,0){return 3;}let budget=256;let partial=0;
 while budget<=65536&&!partial {esp_libc_console_budget(budget);let result=esp32_call32(esp32_external("stdio_budget_probe"),1,0,0,0,0,0,0,0);if result==1{partial=1;}if result==3{return 4;}budget=budget*2;}
 if !partial{return 5;}if esp_libc_console_budget(16000000){return 6;}return 0;
}
