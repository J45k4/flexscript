// Independent startup contract from ESP-IDF v5.5.1 bootloader_esp32.c/cache.h.
// Physical ESP32 stalled without mmu_init even though QEMU accepted the image.
import "../../lib/platform/esp32-xip.flex";
global xm_step=0;
global xm_errors=0;
global xm_fail=0;
fn xm_check(ok) {if !ok {xm_errors=xm_errors+1;}return 0;}
fn xm_equal(a,b) {let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);}
fn esp32_external(name) {if xm_equal(name,"_flex_irom_pages") {return 2;}if xm_equal(name,"_flex_irom_flash") {return 0x30000;}if xm_equal(name,"_flex_drom_pages") {return 1;}if xm_equal(name,"_flex_drom_flash") {return 0x50000;}xm_errors=xm_errors+1;return 0;}
fn esp32_irq_save() {xm_check(xm_step==0);xm_step=1;return 15;}
fn esp32_irq_restore(ps) {xm_check(ps==15 && xm_step==10);xm_step=11;return 0;}
fn esp32_load32(address) {xm_check(address==0x3ff00044 && xm_step==8);return 0x8ff;}
fn esp32_store32(address,value) {xm_check(address==0x3ff00044 && value==0x8ee && xm_step==8);xm_step=9;return 0;}
fn esp32_call32(address,a,b,c,d,e,f,g,h) {
    if xm_step==1 {xm_check(address==0x40009ab8 && !a);xm_step=2;}
    else if xm_step==2 {xm_check(address==0x40009a14 && !a);xm_step=3;}
    else if xm_step==3 {xm_check(address==0x400095a4 && !a);xm_step=4;}
    else if xm_step==4 {xm_check(address==0x40008658);xm_step=5;return 0x123456;}
    else if xm_step==5 {xm_check(address==0x40062a6c && a==0x123456 && !b);xm_step=6;}
    else if xm_step==6 {xm_check(address==0x400095e0 && !a && !b && c==0x400d0000 && d==0x30000 && e==64 && f==2);xm_step=7;if xm_fail {xm_step=8;return 1;}}
    else if xm_step==7 {xm_check(address==0x400095e0 && !a && !b && c==0x3f400000 && d==0x50000 && e==64 && f==1);xm_step=8;}
    else if xm_step==9 {xm_check(address==0x40009a84 && !a);xm_step=10;}
    else {xm_errors=xm_errors+1;}return 0;
}
fn main() {if esp_xip_enable() || xm_step!=11 || xm_errors {return 1;}xm_step=0;xm_fail=1;if esp_xip_enable()!=1 || xm_step!=11 || xm_errors {return 2;}return 0;}
