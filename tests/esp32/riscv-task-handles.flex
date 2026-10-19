import "../../lib/platform/esp32c3-libc.flex";
import "sdk-task-handles-core.flex";
fn libc_pause(a,b,c,d,e,f,g,h){return 0;}
fn sh_runtime_init(){esp32_callback32(libc_pause);return esp_libc_reent_init();}
fn main(){return sh_run(0x3fcb8000);}
