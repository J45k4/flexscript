import "../../lib/platform/esp32.flex";
global ctx_main=0;
global ctx_worker=0;
global ctx_stage=0;
global ctx_result=0;
fn yielding(a,b,c,d,e,f,g,h) {
    if a!=1 || b!=2 || c!=3 || d!=4 || e!=5 || f!=6 || g!=7 || h!=8 {return 0;}
    ctx_stage=ctx_stage+1;esp32_switch(ctx_worker,ctx_main);return 0x98765432;
}
fn worker(argument) {
    if argument!=911 {esp32_halt();}
    esp32_call32(esp32_external("c_set_thread"),0x33334444,0,0,0,0,0,0,0);ctx_result=esp32_call32(esp32_external("c_coop"),30,esp32_callback32(yielding),0x3f123456,0,0,0,0,0);
    if esp32_call32(esp32_external("c_read_thread"),0,0,0,0,0,0,0,0)!=0x33334444 {esp32_halt();}ctx_stage=ctx_stage+1;esp32_switch(ctx_worker,ctx_main);esp32_halt();return 0;
}
fn main() {
    esp_uart_write("START: native task context\r\n");let contexts=alloc(1024);ctx_main=contexts;ctx_worker=contexts+512;let stack=alloc(8192);let sp=stack+8192-16;
    store64(sp,911);esp32_store32(ctx_worker+4,sp);esp32_store32(ctx_worker+256,esp32_callback(worker));esp32_store32(ctx_worker+260,0);esp32_store32(ctx_worker+264,1);esp32_store32(ctx_worker+272,15);esp32_store32(ctx_worker+292,1);esp32_store32(ctx_worker+304,stack);
    esp32_call32(esp32_external("c_set_thread"),0x11112222,0,0,0,0,0,0,0);esp32_call32(esp32_external("c_set_fpu"),0x3f777777,0,0,0,0,0,0,0);
    esp32_switch(ctx_main,ctx_worker);
    if esp32_call32(esp32_external("c_read_thread"),0,0,0,0,0,0,0,0)!=0x11112222 || esp32_call32(esp32_external("c_read_vecbase"),0,0,0,0,0,0,0,0)!=0x40080000 {return 3;}
    if ctx_stage!=1 || esp32_call32(esp32_external("c_read_fpu"),0,0,0,0,0,0,0,0)!=0x3f777777 {esp_uart_hex(ctx_stage);return 1;}
    esp32_call32(esp32_external("c_set_fpu"),0x3f666666,0,0,0,0,0,0,0);
    esp32_switch(ctx_main,ctx_worker);
    if ctx_stage!=2 || ctx_result!=482 || esp32_call32(esp32_external("c_read_fpu"),0,0,0,0,0,0,0,0)!=0x3f666666 {esp_uart_hex(ctx_stage);esp_uart_hex(ctx_result);return 2;}
    esp_uart_write("PASS: task stacks, 64 address registers, deep C windows and FPU context\r\n");esp_uart_flush();return 0;
}
