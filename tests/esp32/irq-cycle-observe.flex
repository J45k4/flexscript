// Collect GNU IRQ observations before any measurement UART output.
import "../../lib/platform/esp32-radio-clock.flex";
fn qi_line(key,value){esp_uart_write(key);esp_uart_hex(value);return 0;}
fn qi_fail(code){qi_line("IRQC FAIL ",code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn main(){let old=esp32_irq_save();esp32_irq_mask(0);if qi_clock()==160{esp_radio_clock_init();esp_radio_cpu160();}
 qi_line("IRQC START CLOCK ",qi_clock());qi_line(" SOURCE ",(esp32_load32(0x3ff48070)>>27)&3);qi_line(" PERIOD ",esp32_load32(0x3ff0003c)&3);qi_line(" DIV ",esp32_load32(0x3ff66000)&1023);qi_line(" ROMTICKS ",esp32_load32(0x3ffe01e0));esp_uart_write("\r\n");esp_uart_flush();
 let state=alloc(qi_words()*4);let records=alloc(384*qi_words()*4);if state<=0 || records<=0{qi_fail(1);}let row=0;
 let selector=0;while selector<192{let repeat=0;while repeat<2{let i=0;while i<qi_words(){esp32_store32(state+i*4,0);i=i+1;}if esp32_call32(esp32_external("iq_measure"),state,selector,0,0,0,0,0,0){qi_fail(2);}if esp32_load32(state+40)!=1{qi_fail(3);}i=0;while i<qi_words(){esp32_store32(records+row*qi_words()*4+i*4,esp32_load32(state+i*4));i=i+1;}row=row+1;repeat=repeat+1;}selector=selector+1;}
 if row!=384 || esp32_call32(esp32_external("iq_ready"),records,row,0,0,0,0,0,0){qi_fail(4);}
 row=0;while row<384{let p=records+row*qi_words()*4;qi_line("IRQC PROFILE ",row/96);qi_line(" GATE ",(row/32)%3);qi_line(" TALIGN ",(row/8)%4);qi_line(" RALIGN ",(row/2)%4);qi_line(" REPEAT ",row&1);
 qi_line(" START ",esp32_load32(p));qi_line(" IRQCC ",esp32_load32(p+4));qi_line(" RETCC ",esp32_load32(p+8));qi_line(" END ",esp32_load32(p+12));qi_line(" BEFOREPS ",esp32_load32(p+16));qi_line(" IRQPS ",esp32_load32(p+20));qi_line(" EPC ",esp32_load32(p+24));qi_line(" RESUME ",esp32_load32(p+28));qi_line(" INTEN ",esp32_load32(p+32));qi_line(" PENDING ",esp32_load32(p+36));qi_line(" SEEN ",esp32_load32(p+40));qi_line(" VBASE ",esp32_load32(p+44));qi_line(" TRIGGER ",esp32_load32(p+48));qi_line(" AFTERPS ",esp32_load32(p+52));qi_line(" AFTERPENDING ",esp32_load32(p+56));qi_line(" AFTERINTEN ",esp32_load32(p+60));if qi_words()==17{qi_line(" FOLLOWER ",esp32_load32(p+64));}esp_uart_write("\r\n");row=row+1;}
 qi_line("IRQC COMPLETE CLOCK ",qi_clock());esp_uart_write("\r\n");esp_uart_flush();esp32_irq_restore(old);return 0;}
