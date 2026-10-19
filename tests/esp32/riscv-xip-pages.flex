import "../../lib/platform/esp32c3-xip.flex";
import "../../lib/platform/esp32c3-irq.flex";
global xip_irq_seen=0;
fn xip_irq(source){if source==-1 && esp32_load32(esp32_state()+16)==1 {xip_irq_seen=xip_irq_seen+1;}return 0;}
fn xip_ram_leaf(a){return a+9;}
fn xip_ram_callback(a,b,c,d,e,f,g,h){
    let p=esp32_callback(xip_ram_leaf);if p<0x40380000 || p>=0x403a0000 {if p<0x40800000 || p>=0x40820000 {return 0xbad;}}
    return xip_ram_leaf(a)+b+c+d+e+f+g+h;
}
fn xip_native_callback(a,b,c,d,e,f,g,h){return a*b+c*d+e*f+g*h;}
fn main(){
    if !esp_xip_ready || esp_xip_enable()!=-16 {return 1;}
    let target=esp32_callback32(xip_native_callback);if target<0x42000000 || target>=0x42300000 {return 2;}
    if esp32_call32(target,2,3,5,7,11,13,17,19)!=507 {return 3;}
    if esp32_call32(esp32_external("xip_long_code"),71,0,0,0,0,0,0,0)!=100 {return 4;}
    let data=esp32_call32(esp32_external("xip_constant_address"),0,0,0,0,0,0,0,0);let expected=0x3c400000;if esp32_state()==0x40830000 {expected=0x42400000;}if data<expected || data>=expected+0x300000 {return 5;}
    let i=0;while i<143373 {let want=0;if !i {want=17;}else if i==65535 {want=29;}else if i==65536 {want=43;}else if i==131071 {want=61;}else if i==143372 {want=89;}if load8(data+i)!=want {return 6;}i=i+1;}
    if esp32_call32(esp32_external("xip_constant"),65536,0,0,0,0,0,0,0)!=43 {return 7;}
    let ram=esp32_iram_callback32(xip_ram_callback);if ram>=0x42000000 {return 8;}
    if esp32_call32(esp32_external("xip_cache_off"),ram,0,0,0,0,0,0,0)!=159 {return 9;}
    if esp_irq_software(esp32_iram_callback(xip_irq)) || esp_irq_enable() {return 10;}
    if esp32_call32(esp32_external("xip_cache_off"),ram,1,0,0,0,0,0,0)!=159 || xip_irq_seen!=1 {return 11;}
    return 0;
}
