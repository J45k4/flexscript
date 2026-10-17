global pv_context=0;
global pv_callback=0;
global pv_initial_ps=0;
global pv_expected_ps=0;
global pv_rng_count=0;
global pv_rng_fail=0;
global pv_rng_error=0;
global pv_rng_mode=0;
global pv_rng_data=0;
global pv_guard_error=0;
global pv_saved_depth=0;
fn pv_get_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn pv_random(request) {
    pv_rng_count=pv_rng_count+1;let out=load64(request);let size=load64(request+8);
    if request!=pv_context || size!=32 || load64(request+16)!=0x1122334455667788 || !esp_smp_curve_busy || esp_smp_curve_deinit()!=-16 || esp_smp_curve_init(pv_context,64,pv_callback,0)!=-16 || smp_p256_ready(pv_work+16,256)!=-16 || smp_p256_backend(1,pv_work+16,0,0)!=-16 {pv_guard_error=1;return -5;}
    if pv_rng_count>4 {pv_guard_error=2;return -5;}if pv_rng_count==pv_rng_fail {pv_fill(out,32,204);return pv_rng_error;}
    if pv_rng_mode==1 {pv_fill(out,32,204);return 32;}nb_copy(out,pv_rng_data+(pv_rng_count-1)*32,32);if pv_rng_mode==2 {store64(request+8,7);}if pv_rng_mode==3 {esp32_irq_restore(pv_get_ps()|15);}return 0;
}
fn pv_before(row) {
    esp32_irq_restore((pv_initial_ps&~15)|(load64(row+64)&15));pv_expected_ps=pv_get_ps();let ctrl=esp32_external("p256_test_control");nb_zero(ctrl,20);esp32_store32(ctrl+4,load64(row+16));esp32_store32(ctrl+8,load64(row+24));pv_rng_count=0;pv_rng_fail=load64(row+32);pv_rng_error=load64(row+40);pv_rng_mode=load64(row+48);pv_rng_data=row+224;pv_guard_error=0;
    pv_saved_depth=esp32_load32(esp32_state()+16);if pv_mode==1 {esp_smp_curve_context=0;}if pv_mode==2 {esp_smp_curve_busy=1;}if pv_mode==3 {esp32_store32(esp32_state()+16,1);}if pv_mode==4 {esp_smp_curve_context=pv_work+16+192;}if pv_mode==5 {esp_smp_curve_random=0;}return 0;
}
fn pv_after() {esp_smp_curve_context=pv_context;esp_smp_curve_random=pv_callback;esp_smp_curve_busy=0;esp32_store32(esp32_state()+16,pv_saved_depth);return 0;}
fn pv_calls() {return esp32_load32(esp32_external("p256_test_control"));}
fn pv_rng_calls() {return pv_rng_count;}
fn pv_clean() {return !pv_guard_error && !esp_smp_curve_busy && pv_value(pv_context,64,0) && pv_value(pv_context-16,16,165) && pv_value(pv_context+64,16,165) && !esp32_load32(esp32_external("p256_test_control")+12);}
fn pv_ps_clean() {return pv_get_ps()==pv_expected_ps;}
fn pv_report(case_number,op,field,actual,expected) {esp_uart_write("SMP P256 FAIL ");esp_uart_hex(case_number);esp_uart_hex(op);esp_uart_hex(field);esp_uart_hex(actual);esp_uart_hex(expected);esp_uart_write("\r\n");return 0;}
fn pv_init_checks() {
    let raw=alloc(96);pv_fill(raw,96,165);pv_context=raw+16;pv_output=alloc(128);pv_work=alloc(288);pv_callback=esp32_callback(pv_random);pv_initial_ps=pv_get_ps();
    if esp_smp_curve_init(pv_context+1,64,pv_callback,0)!=-22 || esp_smp_curve_init(pv_context,63,pv_callback,0)!=-22 || esp_smp_curve_init(pv_context,64,4294967296,0)!=-22 || !pv_value(raw,96,165) {return 3;}
    if smp_p256_backend(1,pv_work+16,0,0)!=-19 || esp_smp_curve_init(pv_context,64,pv_callback,0x1122334455667788) {return 4;}
    if esp_smp_curve_init(pv_context,64,pv_callback,0)!=-16 || smp_p256_backend(0,pv_work+16,0,0)!=-22 || smp_p256_backend(1,0,0,0)!=-22 || smp_p256_backend(1,pv_context,0,0)!=-22 || smp_p256_backend(1,4294967296,0,0)!=-22 || smp_p256_ready(pv_context,256)!=-22 {return 5;}
    if !pv_value(pv_context,64,0) || pv_get_ps()!=pv_initial_ps {return 6;}return 0;
}
fn main() {let r=pv_init_checks();if r {return r;}let data=esp32_external("smp_p256_cases");r=pv_run(data,esp32_external("smp_p256_cases_size"));esp32_irq_restore(pv_initial_ps);if esp_smp_curve_deinit() || !pv_value(pv_context,64,0) {return 12;}if r {esp_uart_write("SMP P256 RETURN ");esp_uart_hex(r);esp_uart_write("\r\n");esp_uart_flush();return r;}esp_uart_write("PASS: SMP P256 ");esp_uart_hex(pv_checks);esp_uart_write(" independent observations\r\n");esp_uart_flush();return 0;}
