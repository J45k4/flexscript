// Original ECO3 silicon observation;all code/data stays in internalRAM.
// Read-only NOR mapping;no flash program/erase/eFuse command is used.
// A generated wrapper supplies ci_expected():FNV ofbackup[0x11234:0x11274].
// This records behavior rather than embedding the emulator's expected values.
import "../../lib/platform/esp32.flex";
fn ci_check(ok,code){if !ok{esp_uart_write("CACHE ACCESS FAIL ");esp_uart_hex(code);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn ci_flush(){esp32_call32(0x40009a14,0,0,0,0,0,0,0,0);return 0;}
fn ci_enable(){esp32_call32(0x40009a84,0,0,0,0,0,0,0,0);return 0;}
fn ci_disable(){esp32_call32(0x40009ab8,0,0,0,0,0,0,0,0);return 0;}
fn ci_hash(address){let h=2166136261;let i=0;while i<64{let word=esp32_load32(address+i);let byte=0;while byte<4{h=((h^((word>>(byte*8))&255))*16777619)&0xffffffff;byte=byte+1;}i=i+4;}return h;}
fn ci_setup(){ci_disable();ci_flush();esp32_store32(0x3ff10000,1);esp32_store32(0x3ff10134,1);let cfg=esp32_load32(0x3ff00044)&~17;esp32_store32(0x3ff00044,cfg|8192);esp32_store32(0x3ff00044,cfg);ci_enable();return 0;}
fn ci_line(label,value){esp_uart_write(label);esp_uart_hex(value);return 0;}
fn ci_observe(bus,mode,trap){ci_setup();let address=0x3f401234;let entry=0x3ff10000;let mask=16;let enable=1<<14;if bus{address=0x400d1234;entry=0x3ff10134;mask=1;enable=1<<15;}
 esp32_store32(0x3ff005a0,trap*enable);ci_disable();if mode==1{esp32_store32(entry,256);}if mode==2{esp32_store32(0x3ff00044,esp32_load32(0x3ff00044)|mask);}ci_flush();if mode!=3{ci_enable();}
 ci_line("CACHE BEGIN ",bus);ci_line(" MODE ",mode);ci_line(" TRAP ",trap);ci_line(" BEFORE0 ",esp32_load32(0x3ff003f0)&127);ci_line(" BEFORE3 ",esp32_load32(0x3ff003fc)&0xfe00);esp_uart_write("\r\n");esp_uart_flush();
 let value=esp32_load32(address);let debug0=esp32_load32(0x3ff003f0)&127;let debug3=esp32_load32(0x3ff003fc)&0xfe00;let pending=esp32_irq_pending();ci_line("CACHE OBS ",value);ci_line(" DBG0 ",debug0);ci_line(" DBG3 ",debug3);ci_line(" PENDING ",pending);esp_uart_write("\r\n");esp_uart_flush();esp32_store32(0x3ff005a0,0);ci_setup();return 0;}
