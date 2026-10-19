import "../../lib/platform/esp32-radio-clock.flex";
fn ex_line(key,value){esp_uart_write(key);esp_uart_hex(value);return 0;}
fn ex_fail(code){ex_line("EXPIRY FAIL ",code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn main(){let old=esp32_irq_save();esp32_irq_mask(0);if ex_clock()==160{esp_radio_clock_init();esp_radio_cpu160();}
ex_line("EXPIRY START CLOCK ",ex_clock());ex_line(" SOURCE ",(esp32_load32(0x3ff48070)>>27)&3);ex_line(" PERIOD ",esp32_load32(0x3ff0003c)&3);ex_line(" DIV ",esp32_load32(0x3ff66000)&1023);ex_line(" ROMTICKS ",esp32_load32(0x3ffe01e0));esp_uart_write("\r\n");esp_uart_flush();
let state=alloc(128);let records=alloc(108*128);if state<=0 || records<=0{ex_fail(1);}let row=0;let selector=0;while selector<54{let repeat=0;while repeat<2{let i=0;while i<32{esp32_store32(state+i*4,0);i=i+1;}if esp32_call32(esp32_external("ex_measure"),state,selector,0,0,0,0,0,0){ex_fail(2);}i=0;while i<32{esp32_store32(records+row*128+i*4,esp32_load32(state+i*4));i=i+1;}row=row+1;repeat=repeat+1;}selector=selector+1;}
if esp32_call32(esp32_external("ex_ready"),records,row,0,0,0,0,0,0){ex_fail(3);}row=0;while row<108{let p=records+row*128;let distance=32;if (row/4)%3==1{distance=64;}if (row/4)%3==2{distance=128;}ex_line("EXPIRY TIMER ",row/36);ex_line(" MODE ",(row/12)%3);ex_line(" DISTANCE ",distance);ex_line(" ALIGN ",(row/2)%2);ex_line(" REPEAT ",row&1);
ex_line(" SELECTOR ",esp32_load32(p+0));
ex_line(" TARGET ",esp32_load32(p+4));
ex_line(" PS ",esp32_load32(p+8));
ex_line(" PENDING ",esp32_load32(p+12));
ex_line(" COUNT ",esp32_load32(p+16));
ex_line(" MARKER ",esp32_load32(p+20));
ex_line(" RESETPC ",esp32_load32(p+24));
ex_line(" STREAMPC ",esp32_load32(p+28));
ex_line(" IRQCC ",esp32_load32(p+32));
ex_line(" IRQPS ",esp32_load32(p+36));
ex_line(" EPS ",esp32_load32(p+40));
ex_line(" EPC ",esp32_load32(p+44));
ex_line(" IRQPENDING ",esp32_load32(p+48));
ex_line(" ACKPENDING ",esp32_load32(p+52));
ex_line(" RETCC ",esp32_load32(p+56));
ex_line(" LEVEL ",esp32_load32(p+60));
ex_line(" T0 ",esp32_load32(p+64));
ex_line(" T1 ",esp32_load32(p+68));
ex_line(" P0 ",esp32_load32(p+72));
ex_line(" P1 ",esp32_load32(p+76));
ex_line(" P2 ",esp32_load32(p+80));
ex_line(" P3 ",esp32_load32(p+84));
ex_line(" P4 ",esp32_load32(p+88));
ex_line(" P5 ",esp32_load32(p+92));
ex_line(" P6 ",esp32_load32(p+96));
ex_line(" P7 ",esp32_load32(p+100));
ex_line(" P8 ",esp32_load32(p+104));
ex_line(" P9 ",esp32_load32(p+108));
ex_line(" P10 ",esp32_load32(p+112));
ex_line(" CAUSE0 ",esp32_load32(p+116));
ex_line(" CAUSE1 ",esp32_load32(p+120));
ex_line(" READBACK ",esp32_load32(p+124));
esp_uart_write("\r\n");row=row+1;}ex_line("EXPIRY COMPLETE CLOCK ",ex_clock());esp_uart_write("\r\n");esp_uart_flush();esp32_irq_restore(old);return 0;}
