import "../../lib/platform/esp32s3-xip.flex";
import "../../lib/platform/esp32s3.flex";
fn main() {
let p=esp32_external("s3_cache_bytes");let end=esp32_external("s3_cache_bytes_end");let fnc=esp32_external("s3_cache_sum");let iram=esp32_external("s3_cache_iram");let ram=esp32_external("s3_cache_dram");
if p<0x3c400000 || end-p!=131329 || end>0x3c700000 || fnc<0x42010000 || fnc>=0x42300000 || (fnc&65535) || iram<0x40380000 || iram>=0x40398000 || ram<esp32_state()+24 || ram>=0x3fcb0000 {return 1;}
if esp32_call32(0x4000195c,0,0,0,0,0,0,0,0)!=256 || esp32_call32(0x40001968,0,0,0,0,0,0,0,0)!=512 {return 3;}
if load64(ram)!=0x12345678cafebabe || esp32_call32(iram,13,0,0,0,0,0,0,0)!=(13^0xabc12345) {return 2;}
if esp32_call32(fnc,0,1,0,0,0,0,0,0)!=19 {return 10;}
if esp32_call32(fnc,0,65537,0,0,0,0,0,0)!=3210068070 {return 11;}
if esp32_call32(fnc,65519,97,0,0,0,0,0,0)!=602037 {return 12;}
if esp32_call32(fnc,65535,1,0,0,0,0,0,0)!=28 {return 13;}
if esp32_call32(fnc,65535,259,0,0,0,0,0,0)!=4292552 {return 14;}
if esp32_call32(fnc,65536,65537,0,0,0,0,0,0)!=3221274809 {return 15;}
if esp32_call32(fnc,131039,290,0,0,0,0,0,0)!=5426870 {return 16;}
if esp32_call32(fnc,131328,1,0,0,0,0,0,0)!=220 {return 17;}
esp_uart_write("PASS: S3 cached C/code page boundary,3 DROM pages, IRAM and vendor DRAM\r\n");esp_uart_flush();return 0;}
