import "../../lib/platform/esp32c3.flex";
global ctx_main=0;global ctx_worker=0;global ctx_stage=0;global ctx_floor=0;
fn worker(value) {
    if value!=911 || esp32_load32(esp32_state()+20)!=ctx_floor {esp32_store32(esp32_state()+16,1);return 1;}
    let ps=esp32_irq_save();if ps&8 {return 2;}esp32_irq_restore(ps);
    let saved=0x8877665544332211;let i=0;while i<100 {
        ctx_stage=ctx_stage+1;esp32_switch(ctx_worker,ctx_main);if saved!=0x8877665544332211 {return 3;}i=i+1;
    }ctx_stage=101;esp32_switch(ctx_worker,ctx_main);return 4;
}
fn main() {
    let contexts=alloc(1040);contexts=(contexts+15)&~15;ctx_main=contexts;ctx_worker=contexts+512;let stack=alloc(8192);ctx_floor=stack;let top=stack+8192-16;
    store64(top,911);esp32_store32(ctx_worker+8,top);esp32_store32(ctx_worker+256,esp32_callback(worker));esp32_store32(ctx_worker+304,stack);
    let floor=esp32_load32(esp32_state()+20);let ps=esp32_irq_save();esp32_irq_restore(ps|8);let i=0;while i<101 {
        esp32_switch(ctx_main,ctx_worker);if ctx_stage!=i+1 || esp32_load32(esp32_state()+20)!=floor {return 10+i;}
        if !(esp32_irq_save()&8) {return 120;}esp32_irq_restore(ps|8);i=i+1;
    }
    if esp32_switch(ctx_main,ctx_main) {return 121;}esp32_irq_restore(ps);return 0;
}
