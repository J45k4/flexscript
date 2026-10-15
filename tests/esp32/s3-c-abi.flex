import "../../lib/platform/esp32s3.flex";
global s3_callbacks=0;
fn s3_callback(a,b,c,d,e,f,g,h) {if a!=11 || b!=22 || c!=33 || d!=44 || e!=55 || f!=66 || g!=0x89abcdef || h!=0xfedcba98 {return 0;}s3_callbacks=s3_callbacks+1;return 0x123456789abcdef0;}
fn main() {
    let alignment=7+esp32_call32(esp32_external("c_stack_alignment"),0,0,0,0,0,0,0,0);if alignment!=7 {return 5;}
    let cb=esp32_callback32(s3_callback);
    if esp32_call32(esp32_external("c_sum8"),1,2,3,4,5,6,7,8)!=454 {return 1;}
    if esp32_call64(esp32_external("c_walk"),80,cb,0,0,0,0,0,0)!=0x123456789abcebe9 {return 2;}
    if esp32_call64(esp32_external("c_call4"),cb,0,0,0,0,0,0,0)!=0x123456789abce0e0 {return 3;}
    if esp32_call64(esp32_external("c_call12"),cb,0,0,0,0,0,0,0)!=0x123456789abce0e0 || s3_callbacks!=3 {return 4;}
    esp_uart_write("PASS: S3 C ABI, eight arguments, deep call4/call8/call12 windows\r\n");esp_uart_flush();return 0;
}
