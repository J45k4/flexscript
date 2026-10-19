import "../../lib/platform/esp32c3.flex";
global ctx_main=0;global ctx_worker=0;global ctx_stage=0;global ctx_result= -1;
fn main_yield(a,b,c,d,e,f,g,h) {if a!=1 || b!=2 || c!=3 || d!=4 || e!=5 || f!=6 || g!=7 || h!=8 {return 1;}esp32_switch(ctx_main,ctx_worker);return 0x123456789abcdef0;}
fn worker_yield(a,b,c,d,e,f,g,h) {if a!=1 || b!=2 || c!=3 || d!=4 || e!=5 || f!=6 || g!=7 || h!=8 {return 2;}ctx_stage=ctx_stage+1;esp32_switch(ctx_worker,ctx_main);return 0x123456789abcdef0;}
fn worker(argument) {
    if argument!=911 {return 3;}ctx_result=esp32_call32(esp32_external("ctx_c_check"),esp32_callback32(worker_yield),24,0x33334444,0,0,0,0,0);
    ctx_stage=4;esp32_switch(ctx_worker,ctx_main);return 4;
}
fn main() {
    let context=alloc(1040);context=(context+15)&~15;ctx_main=context;ctx_worker=context+512;let stack=alloc(8192);let top=stack+8192-16;
    store64(top,911);esp32_store32(ctx_worker+8,top);esp32_store32(ctx_worker+256,esp32_callback(worker));esp32_store32(ctx_worker+304,stack);
    let result=esp32_call32(esp32_external("ctx_c_check"),esp32_callback32(main_yield),24,0x11112222,0,0,0,0,0);
    if result || ctx_stage!=3 {return 10+result;}esp32_switch(ctx_main,ctx_worker);
    if ctx_stage!=4 || ctx_result {return 20+ctx_result;}return 0;
}
