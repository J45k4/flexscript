global pg_checks=0;
global pg_context=0;
global pg_io=0;
global pg_ps=0;
global pg_callback=0;
global pg_rng_mode=0;
global pg_rng_calls=0;
global pg_rng_bad=0;
fn pg_fill(p,n,v) {let i=0;while i<n {store8(p+i,v);i=i+1;}return 0;}
fn pg_value(p,n,v) {let i=0;while i<n {if load8(p+i)!=v {return 0;}i=i+1;}return 1;}
fn pg_get_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn pg_check(ok,code) {pg_checks=pg_checks+1;if !ok {return code;}return 0;}
fn pg_random(request) {
    pg_rng_calls=pg_rng_calls+1;let out=load64(request);if request!=pg_context || load64(request+8)!=32 || load64(request+16)!=0x1122334455667788 || !esp_smp_curve_busy || esp_smp_curve_deinit()!=-16 || smp_p256_ready(pg_io,256)!=-16 {pg_rng_bad=1;return -5;}
    nb_zero(out,32);store8(out+31,1);if pg_rng_mode==1 {return -5;}if pg_rng_mode==2 {return 32;}if pg_rng_mode==3 {store64(request+8,7);}if pg_rng_mode==4 {esp32_irq_restore(pg_get_ps()|15);}return 0;
}
fn pg_level(level,initial) {
    esp32_irq_restore((initial&~15)|level);pg_ps=pg_get_ps();pg_fill(pg_context,64,165);pg_fill(pg_io,512,165);let r=0;let ctrl=esp32_external("p256_test_control");nb_zero(ctrl,20);
    r=pg_check(smp_p256_ready(pg_io,256)==-19 && smp_p256_backend(1,pg_io,0,0)==-19,1);if r {return r;}
    r=pg_check(esp_smp_curve_init(pg_context+1,64,0,0)==-22 && pg_value(pg_context,64,165),2);if r {return r;}
    r=pg_check(esp_smp_curve_init(pg_context,63,0,0)==-22 && pg_value(pg_context,64,165),3);if r {return r;}
    r=pg_check(esp_smp_curve_init(pg_context,64,4294967296,0)==-22 && pg_value(pg_context,64,165),4);if r {return r;}
    esp32_store32(esp32_state()+16,1);r=pg_check(esp_smp_curve_init(pg_context,64,0,0)==-16,5);if r {return r;}
    r=pg_check(esp_smp_curve_deinit()==-16,6);if r {return r;}esp32_store32(esp32_state()+16,0);
    r=pg_check(esp_smp_curve_init(pg_context,64,0,0)==0 && pg_value(pg_context,64,0),7);if r {return r;}
    esp32_store32(esp32_state()+16,1);r=pg_check(smp_p256_ready(pg_io,256)==-16,8);if r {return r;}
    r=pg_check(smp_p256_backend(1,pg_io,0,0)==-16,9);if r {return r;}esp32_store32(esp32_state()+16,0);
    esp_smp_curve_busy=1;r=pg_check(smp_p256_ready(pg_io,256)==-16,10);if r {return r;}
    r=pg_check(smp_p256_backend(1,pg_io,0,0)==-16 && esp_smp_curve_deinit()==-16,11);if r {return r;}esp_smp_curve_busy=0;
    r=pg_check(smp_p256_ready(pg_context,256)==-22,12);if r {return r;}
    r=pg_check(smp_p256_backend(0,pg_io,0,0)==-22,13);if r {return r;}
    r=pg_check(smp_p256_backend(1,0,0,0)==-22,14);if r {return r;}
    r=pg_check(smp_p256_backend(1,4294967296,0,0)==-22,15);if r {return r;}
    r=pg_check(smp_p256_backend(1,4294967295,0,0)==-22,16);if r {return r;}
    r=pg_check(smp_p256_backend(1,pg_context,0,0)==-22,17);if r {return r;}
    r=pg_check(smp_p256_backend(2,pg_io,pg_context,0)==-22 && smp_p256_backend(2,pg_io,pg_io+16,0)==-22,18);if r {return r;}
    r=pg_check(smp_p256_backend(3,pg_io,pg_io+16,pg_io+128)==-22 && smp_p256_backend(3,pg_io,pg_io+32,pg_context)==-22,19);if r {return r;}
    r=pg_check(smp_p256_backend(4,pg_io,pg_io+16,0)==-22 && smp_p256_backend(4,pg_context,pg_io+32,0)==-22,20);if r {return r;}
    r=pg_check(pg_value(pg_context,64,0) && pg_value(pg_io,256,165) && !esp32_load32(ctrl),21);if r {return r;}
    r=pg_check(p256_public(pg_context,pg_io,pg_io+128,256)==-22 && pg_value(pg_context,64,0) && pg_value(pg_io,512,165) && !esp32_load32(ctrl),37);if r {return r;}
    nb_zero(pg_io,32);store8(pg_io,1);r=pg_check(p256_public(pg_io,pg_context,pg_io+128,256)==-22 && pg_value(pg_context,64,0) && pg_value(pg_io+128,256,165) && !esp32_load32(ctrl),38);if r {return r;}
    r=pg_check(p256_shared(pg_io,pg_context,pg_io+64,pg_io+128,256)==-22 && pg_value(pg_context,64,0) && pg_value(pg_io+128,256,165) && !esp32_load32(ctrl),39);if r {return r;}
    r=pg_check(p256_keypair(pg_context,pg_io+128,256)==-22 && pg_value(pg_context,64,0) && pg_value(pg_io+128,256,165) && !esp32_load32(ctrl),40);if r {return r;}pg_fill(pg_io,512,165);
    r=pg_check(smp_p256_backend(4,pg_io,pg_io+32,0)==-19 && !esp32_load32(ctrl),22);if r {return r;}
    r=pg_check(esp_smp_curve_entropy(pg_io,16,pg_io+128,32)==-19 && pg_value(pg_io,512,165),41);if r {return r;}
    r=pg_check(smp_p256_backend(1,pg_io,0,0)==-2,23);if r {return r;}
    r=pg_check(!esp_smp_curve_busy && pg_value(pg_context,64,0) && pg_get_ps()==pg_ps,24);if r {return r;}
    r=pg_check(esp_smp_curve_deinit()==0 && esp_smp_curve_init(pg_context,64,pg_callback,0x1122334455667788)==0,25);if r {return r;}
    pg_rng_mode=0;while pg_rng_mode<5 {
        pg_rng_calls=0;pg_rng_bad=0;nb_zero(ctrl,20);pg_fill(pg_io,512,165);let result=smp_p256_backend(4,pg_io,pg_io+32,0);let expected=0;if pg_rng_mode==1 {expected=-5;}if pg_rng_mode==2 {expected=-22;}if pg_rng_mode==3 {expected=-116;}
        r=pg_check(result==expected,31);if r {return r;}
        r=pg_check(pg_rng_calls==1 && !pg_rng_bad && esp32_load32(ctrl)==1 && !esp32_load32(ctrl+12),32);if r {return r;}
        r=pg_check(!esp_smp_curve_busy && pg_value(pg_context,64,0) && pg_get_ps()==pg_ps,33);if r {return r;}
        if expected {r=pg_check(pg_value(pg_io,32,0) && pg_value(pg_io+32,64,165),34);}else {r=pg_check(pg_value(pg_io,31,0) && load8(pg_io+31)==1 && smp_p256_backend(1,pg_io+32,0,0)==0,35);}if r {return r;}pg_rng_mode=pg_rng_mode+1;
    }
    r=pg_check(esp_smp_curve_entropy(pg_context,16,pg_io+128,32)==-22 && esp_smp_curve_entropy(pg_io,0,pg_io+128,32)==-22 && esp_smp_curve_entropy(pg_io,33,pg_io+128,32)==-22 && esp_smp_curve_entropy(pg_io,16,pg_io+128,31)==-22 && esp_smp_curve_entropy(pg_io,16,pg_io,32)==-22,42);if r {return r;}
    pg_rng_mode=0;while pg_rng_mode<5 {pg_fill(pg_io,512,165);pg_rng_calls=0;pg_rng_bad=0;let result=esp_smp_curve_entropy(pg_io,16,pg_io+128,32);let expected=0;if pg_rng_mode==1 {expected=-5;}if pg_rng_mode==2 {expected=-22;}if pg_rng_mode==3 {expected=-116;}
        r=pg_check(result==expected && pg_rng_calls==1 && !pg_rng_bad && !esp_smp_curve_busy && pg_value(pg_context,64,0) && pg_get_ps()==pg_ps,43);if r {return r;}
        r=pg_check(pg_value(pg_io+128,32,0) && pg_value(pg_io+16,112,165),44);if r {return r;}if expected {r=pg_check(pg_value(pg_io,16,165),45);}else {r=pg_check(pg_value(pg_io,16,0),46);}if r {return r;}pg_rng_mode=pg_rng_mode+1;
    }
    r=pg_check(esp_smp_curve_deinit()==0 && pg_value(pg_context,64,0) && pg_value(pg_context-16,16,165) && pg_value(pg_context+64,16,165),36);return r;
}
fn main() {
    let raw=alloc(144);pg_fill(raw,144,165);pg_context=raw+16;pg_io=alloc(512);pg_callback=esp32_callback(pg_random);let initial=pg_get_ps();let level=0;let r=0;while level<16 && !r {r=pg_level(level,initial);level=level+1;}esp32_store32(esp32_state()+16,0);esp_smp_curve_busy=0;esp32_irq_restore(initial);
    if r {esp_uart_write("SMP P256 GUARD FAIL ");esp_uart_hex(r);}else {esp_uart_write("PASS: SMP P256 guards ");esp_uart_hex(pg_checks);}esp_uart_write("\r\n");esp_uart_flush();return r;
}
