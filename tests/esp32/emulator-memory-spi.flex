// Read-only SPI0/SPI1/ROM integration. Expected FNV values are host inputs,
//never embedded private flash bytes. WREN/WRDI change only volatile WEL.
import "../../lib/platform/esp32.flex";
global ms_case=0;
fn ms_check(ok,code){if !ok{esp_uart_write("MEMORY SPI FAIL ");esp_uart_hex(code);esp_uart_write(" CASE ");esp_uart_hex(ms_case);esp_uart_write("\r\n");esp_uart_flush();esp32_halt();}return 0;}
fn ms_wait(base){let start=esp32_cycles();while esp32_load32(base){ms_check(((esp32_cycles()-start)&0xffffffff)<1000000,1);}return 0;}
fn ms_hash(base,n){let h=2166136261;let i=0;while i<n{let word=esp32_load32(base+0x80+(i/4)*4);let byte=(word>>((i&3)*8))&255;h=((h^byte)*16777619)&0xffffffff;i=i+1;}return h;}
fn ms_config(base){esp32_store32(base+8,1<<21);esp32_store32(base+0x18,0x3043);esp32_store32(base+0x34,6);return 0;}
fn ms_read(base,at,n,user){ms_wait(base);esp32_store32(base+0x20,23<<26);esp32_store32(base+0x2c,n*8-1);esp32_store32(base+0x1c,(1<<31)|(1<<30)|(1<<28)|48);esp32_store32(base+0x24,(7<<28)|3);if user{esp32_store32(base+4,at<<8);esp32_store32(base,1<<18);}else{esp32_store32(base+0x2c,0);esp32_store32(base+4,at|(n<<24));esp32_store32(base,1<<31);}ms_wait(base);return ms_hash(base,n);}
// A public deterministic source region can be selected by a generated wrapper.
fn main(){esp_uart_write("START: real ROM and NOR commands\r\n");let ps=esp32_irq_save();esp32_call32(0x40009ab8,0,0,0,0,0,0,0,0);let pins=esp32_call32(0x40008658,0,0,0,0,0,0,0,0);esp32_call32(0x40062a6c,pins,0,0,0,0,0,0,0);let base=0x3ff42000;ms_config(base);
 esp32_store32(base,1<<28);ms_wait(base);ms_check((esp32_load32(base+0x80)&0xffffff)==0x162085,2);esp32_store32(base,1<<27);ms_wait(base);let before=esp32_load32(base+0x10)&0xfffc;esp32_store32(base,1<<30);ms_wait(base);esp32_store32(base,1<<27);ms_wait(base);ms_check((esp32_load32(base+0x10)&3)==2,3);esp32_store32(base,1<<29);ms_wait(base);esp32_store32(base,1<<27);ms_wait(base);ms_check((esp32_load32(base+0x10)&65535)==before,4);
 let index=0;while index<8{ms_case=index;let at=ms_at(index);let n=ms_size(index);let expected=ms_expected(index);let got=ms_read(base,at,n,0);if got!=expected{esp_uart_write("READ HASH ");esp_uart_hex(got);esp_uart_write(" EXPECTED ");esp_uart_hex(expected);esp_uart_write("\r\n");}ms_check(got==expected,5);ms_check(ms_read(base,at,n,1)==expected,6);index=index+1;}
 esp32_call32(0x40009a14,0,0,0,0,0,0,0,0);esp32_call32(0x40009a84,0,0,0,0,0,0,0,0);esp32_irq_restore(ps);esp_uart_write("PASS: real ROM,NOR ID/status/WEL and16 exact reads\r\n");esp_uart_flush();return 0;}
