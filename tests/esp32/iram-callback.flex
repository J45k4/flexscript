import "../../lib/platform/esp32-xip.flex";
import "../../lib/platform/esp32-irq.flex";
global iram_seen=0;
fn iram_helper(n) {return n+7;}
fn iram_c(a,b,c,d,e,f,g,h) {return iram_helper(a)+b+c+d+e+f+g+h;}
fn iram_private(n) {return iram_helper(n);}
fn iram_irq(source) {iram_seen=iram_helper(source);return 0;}
fn iram_cache_cycle(n) {
    esp32_call32(0x40009ab8,0,0,0,0,0,0,0,0);
    let r=iram_helper(n);
    esp32_call32(0x40009a84,0,0,0,0,0,0,0,0);return r;
}
fn iram_cold(n) {return n+9;}
fn main() {
    let c=esp32_iram_callback32(iram_c);let p=esp32_iram_callback(iram_private);let irq=esp32_iram_callback(iram_irq);let cycle=esp32_iram_callback(iram_cache_cycle);
    esp32_iram_callback(esp_irq_dispatch);
    let helper=esp32_callback(iram_helper);let cold=esp32_callback(iram_cold);
    if c<0x40080000 || c>=0x400a0000 || p<0x40080000 || p>=0x400a0000 || helper<0x40080000 || helper>=0x400a0000 || irq<0x40080000 || irq>=0x400a0000 || cycle<0x40080000 || cycle>=0x400a0000 {return 1;}
    if cold<0x400d0000 || c!=esp32_callback32(iram_c) {return 2;}
    if esp32_call32(c,1,2,3,4,5,6,7,8)!=43 || esp32_call(p,35)!=42 || esp32_call(cycle,43)!=50 {return 3;}
    esp_irq_software(irq);esp_irq_enable();esp32_irq_raise(128);while !iram_seen {}if iram_seen!=6 {return 4;}
    if esp32_call(cold,3)!=12 {return 5;}esp_uart_write("PASS: SRAM C/private callbacks, direct helper closure, cache-off execution and software IRQ\r\n");return 0;
}
