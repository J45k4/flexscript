// RAM-only fault sequence experiment;wrapper provides cs_bus/cs_mode/cs_word.
// Each run reads one invalid entry,then a controlled second access. A host
// timeout is an observed stall,not a successful completion or emulator proof.
import "cache-access-body.flex";
fn cs_state(label){esp_uart_write(label);ci_line(" MMU ",esp32_load32(0x3ff003f0)&1);ci_line(" CTRL ",esp32_load32(0x3ff00040));ci_line(" CFG ",esp32_load32(0x3ff00044));esp_uart_write("\r\n");esp_uart_flush();return 0;}
fn main(){let bus=cs_bus();let mode=cs_mode();ci_line("CACHE SEQ START ",bus);ci_line(" MODE ",mode);esp_uart_write("\r\n");esp_uart_flush();let ps=esp32_irq_save();esp32_irq_mask(0);esp32_store32(0x3ff005a0,0);ci_disable();ci_flush();esp32_call32(0x400095a4,0,0,0,0,0,0,0,0);let pins=esp32_call32(0x40008658,0,0,0,0,0,0,0,0);esp32_call32(0x40062a6c,pins,0,0,0,0,0,0,0);ci_setup();let address=0x3f401234;let entry=0x3ff10000;if bus{address=0x400d1234;entry=0x3ff10134;}ci_check(esp32_load32(address)==cs_word(3),1);ci_disable();esp32_store32(entry,256);esp32_store32(entry+4,1);ci_flush();ci_enable();if mode==6{ci_check(esp32_load32(address+65536)==cs_word(3),2);}cs_state("FIRST READ ARMED");ci_check(esp32_load32(address)==cs_word(0),3);cs_state("FIRST READ DONE");let at=address;let expected=0;if mode==1{at=address+4;expected=1;}if mode==2 || mode==6 || mode==7{at=address+32;expected=2;}
 if mode==3 || mode==4 || mode==5{ci_disable();ci_flush();ci_enable();}
 if mode==4{esp32_store32(0x3ff00044,esp32_load32(0x3ff00044)|8192);esp_delay_cycles(256);}
 if mode==5{let cfg=esp32_load32(0x3ff00044);esp32_store32(0x3ff00044,cfg|8192);esp_delay_cycles(256);esp32_store32(0x3ff00044,cfg&~8192);esp_delay_cycles(256);}
 if mode==6{ci_check(esp32_load32(address+65536)==cs_word(3),4);cs_state("CACHED VALID READ DONE");}
 if mode==7{ci_check(esp32_load32(address+65536+128)==cs_word(4),5);cs_state("FRESH VALID READ DONE");}
 cs_state("SECOND READ ARMED");ci_check(esp32_load32(at)==cs_word(expected),6);cs_state("SECOND READ DONE");ci_disable();esp32_irq_restore(ps);ci_line("CACHE SEQ COMPLETE ",bus);ci_line(" MODE ",mode);esp_uart_write("\r\n");esp_uart_flush();return 0;}
