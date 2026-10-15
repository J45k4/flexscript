import "../../lib/platform/esp32s3.flex";
import "word-vectors.flex";
global runtime_global=-4294967297;
fn recursive(n) {if n<=1 {return 1;}return n*recursive(n-1);}
fn args(a,b,c,d,e,f,g,h) {return a+2*b+3*c+4*d+5*e+6*f+7*g+8*h;}
fn memory_checks() {
    if runtime_global!= -4294967297 {return 1;}runtime_global=0x123456789abcdef;
    if runtime_global!=0x123456789abcdef {return 2;}
    if recursive(10)!=3628800 || args(1,2,3,4,5,6,7,8)!=204 {return 3;}
    let p=alloc(33);if p<0 || p%8 {return 4;}
    let i=0;while i<33 {if load8(p+i) {return 5;}i=i+1;}
    if store64(p+1,-81985529216486896)!= -81985529216486896 || load64(p+1)!= -81985529216486896 {return 6;}
    if store8(p+2,-257)!= -257 || load8(p+2)!=255 {return 7;}
    if !(-4294967296) || !!0 || (-(-4294967296))!=4294967296 {return 8;}
    if ~0!= -1 || ~(-4294967296)!=4294967295 {return 9;}
    if alloc(0)!= -22 || alloc(-1)!= -12 || alloc(32769)!= -12 {return 10;}
    if alloc(32728)<0 || alloc(1)!= -12 {return 11;}
    if esp_gpio_output(-1)!= -22 || esp_gpio_output(22)!= -22 || esp_gpio_write(22,1)!= -22 {return 12;}
    esp_gpio_output(4);esp_gpio_write(4,1);esp_gpio_write(4,0);
    let cycles=esp32_cycles();esp_delay_cycles(1000);if ((esp32_cycles()-cycles)&4294967295)<1000 {return 13;}
    return 0;
}
fn main() {
    esp_uart_write("START: Flexscript ESP32-S3 bare-metal regression\r\n");
    let result=word_vectors();if result {esp_uart_write("FAIL: word vector ");esp_uart_hex(result);esp_uart_write("\r\n");return 1;}
    result=memory_checks();if result {esp_uart_write("FAIL: runtime ");esp_uart_hex(result);esp_uart_write("\r\n");return 2;}
    esp_uart_write("PASS: Xtensa 64-bit words, calls, globals, unaligned memory, allocator, GPIO registers and cycles\r\n");
    esp_uart_write("word_checks=");esp_uart_hex(word_checks);esp_uart_write("\r\n");esp_uart_flush();return 0;
}
