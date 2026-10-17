// Collect raw GNU timing records in RAM before dumping them to UART.
import "../../lib/platform/esp32-radio-clock.flex";
fn co_line(key,value){esp_uart_write(key);esp_uart_hex(value);return 0;}
fn co_fail(code){co_line("CCOST FAIL ",code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();return 0;}
fn main(){
 let old=esp32_irq_save();esp32_irq_mask(0);if co_clock()==160{esp_radio_clock_init();esp_radio_cpu160();}
 co_line("CCOST START CLOCK ",co_clock());co_line(" SOURCE ",(esp32_load32(0x3ff48070)>>27)&3);co_line(" PERIOD ",esp32_load32(0x3ff0003c)&3);co_line(" DIV ",esp32_load32(0x3ff66000)&1023);co_line(" ROMTICKS ",esp32_load32(0x3ffe01e0));esp_uart_write("\r\n");esp_uart_flush();
 let state=alloc(64);let records=alloc(672*40);if state<=0 || records<=0{co_fail(1);}let row=0;
 let kind=0;while kind<12{let index=0;while index<7{let count=0;if index{count=1<<(index-1);}let alignment=0;while alignment<4{let mask_index=0;while mask_index<2{
  let mask=mask_index*15;esp32_store32(state+32,0x12345678);let selector=(kind*7+index)*4+alignment;
  if esp32_call32(esp32_external("cc_measure"),state,selector,mask,0,0,0,0,0){co_fail(2);}
  let start=esp32_load32(state);let end=esp32_load32(state+4);let delta=(end-start)&0xffffffff;if !delta || delta>1000000{co_fail(3);}
  let p=records+row*40;esp32_store32(p,esp32_load32(state+16));esp32_store32(p+4,esp32_load32(state+20));esp32_store32(p+8,start);esp32_store32(p+12,end);esp32_store32(p+16,delta);esp32_store32(p+20,esp32_load32(state+8));esp32_store32(p+24,esp32_load32(state+24));esp32_store32(p+28,esp32_load32(state+12));esp32_store32(p+32,esp32_load32(state+32));esp32_store32(p+36,esp32_load32(state+28));
  row=row+1;mask_index=mask_index+1;
 }alignment=alignment+1;}index=index+1;}kind=kind+1;}
 if row!=672 || esp32_call32(esp32_external("cc_ready"),records,row,0,0,0,0,0,0){co_fail(4);}
 row=0;while row<672{let p=records+row*40;let index=(row/8)%7;let count=0;if index{count=1<<(index-1);}co_line("CCOST PATTERN ",row/56);co_line(" COUNT ",count);co_line(" ALIGN ",(row/2)&3);co_line(" MASK ",(row&1)*15);co_line(" BLOCK ",esp32_load32(p));co_line(" STOP ",esp32_load32(p+4));co_line(" START ",esp32_load32(p+8));co_line(" END ",esp32_load32(p+12));co_line(" DELTA ",esp32_load32(p+16));co_line(" PS ",esp32_load32(p+20));co_line(" AFTERPS ",esp32_load32(p+24));co_line(" VALUE ",esp32_load32(p+28));co_line(" MEMORY ",esp32_load32(p+32));co_line(" INTEN ",esp32_load32(p+36));esp_uart_write("\r\n");row=row+1;}
 co_line("CCOST COMPLETE CLOCK ",co_clock());esp_uart_write("\r\n");esp_uart_flush();esp32_irq_restore(old);return 0;
}
