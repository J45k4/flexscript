import "../../lib/platform/esp32-radio-clock.flex";
fn pw_line(key,value){esp_uart_write(key);esp_uart_hex(value);return 0;}
fn pw_fail(code){pw_line("PENDING FAIL ",code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn main(){let old=esp32_irq_save();esp32_irq_mask(0);if pw_clock()==160{esp_radio_clock_init();esp_radio_cpu160();}
if (esp32_load32(0x3ff44044)&(1<<19)) || esp32_load32(0x3ff44068){pw_fail(4);}
pw_line("PENDING START CLOCK ",pw_clock());pw_line(" SOURCE ",(esp32_load32(0x3ff48070)>>27)&3);pw_line(" PERIOD ",esp32_load32(0x3ff0003c)&3);pw_line(" DIV ",esp32_load32(0x3ff66000)&1023);pw_line(" ROMTICKS ",esp32_load32(0x3ffe01e0));esp_uart_write("\r\n");esp_uart_flush();
let state=alloc(128);let records=alloc(64*128);if state<=0 || records<=0{pw_fail(1);}let row=0;let selector=0;while selector<32{let repeat=0;while repeat<2{let i=0;while i<32{esp32_store32(state+i*4,0);i=i+1;}if esp32_call32(esp32_external("pw_measure"),state,selector,0,0,0,0,0,0){pw_fail(2);}i=0;while i<32{esp32_store32(records+row*128+i*4,esp32_load32(state+i*4));i=i+1;}row=row+1;repeat=repeat+1;}selector=selector+1;}
if esp32_call32(esp32_external("pw_ready"),records,row,0,0,0,0,0,0){pw_fail(3);}row=0;while row<64{let p=records+row*128;pw_line("PENDING SOURCE ",row/8);pw_line(" GATE ",(row/4)%2);pw_line(" ALIGN ",(row/2)%2);pw_line(" REPEAT ",row&1);
pw_line(" SELECTOR ",esp32_load32(p+0));
pw_line(" MASK ",esp32_load32(p+4));
pw_line(" PS ",esp32_load32(p+8));
pw_line(" PENDING ",esp32_load32(p+12));
pw_line(" COUNT ",esp32_load32(p+16));
pw_line(" MARKER ",esp32_load32(p+20));
pw_line(" GATEPC ",esp32_load32(p+24));
pw_line(" STREAMPC ",esp32_load32(p+28));
pw_line(" IRQCC ",esp32_load32(p+32));
pw_line(" IRQPS ",esp32_load32(p+36));
pw_line(" EPS ",esp32_load32(p+40));
pw_line(" EPC ",esp32_load32(p+44));
pw_line(" IRQPENDING ",esp32_load32(p+48));
pw_line(" ACKPENDING ",esp32_load32(p+52));
pw_line(" RETCC ",esp32_load32(p+56));
pw_line(" LEVEL ",esp32_load32(p+60));
pw_line(" T0 ",esp32_load32(p+64));
pw_line(" T1 ",esp32_load32(p+68));
pw_line(" PREPENDING ",esp32_load32(p+72));
pw_line(" ENABLED ",esp32_load32(p+76));
pw_line(" GPIOPRE ",esp32_load32(p+80));
pw_line(" GPIOIRQ ",esp32_load32(p+84));
pw_line(" GPIOACK ",esp32_load32(p+88));
pw_line(" CAUSE0 ",esp32_load32(p+92));
pw_line(" CAUSE1 ",esp32_load32(p+96));
pw_line(" FINALMARKER ",esp32_load32(p+100));
pw_line(" RESETPC ",esp32_load32(p+104));
pw_line(" RESERVED0 ",esp32_load32(p+108));
pw_line(" RESERVED1 ",esp32_load32(p+112));
pw_line(" RESERVED2 ",esp32_load32(p+116));
pw_line(" RESERVED3 ",esp32_load32(p+120));
pw_line(" RESERVED4 ",esp32_load32(p+124));
esp_uart_write("\r\n");row=row+1;}pw_line("PENDING COMPLETE CLOCK ",pw_clock());esp_uart_write("\r\n");esp_uart_flush();esp32_irq_restore(old);return 0;}
