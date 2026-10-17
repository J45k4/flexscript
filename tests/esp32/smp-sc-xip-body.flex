global tc_curve_context=0;
global tc_aes_context=0;
global tc_random=0;
global tc_rng_calls=0;
global tc_rng_bad=0;
global tc_ob_ps=0;
fn tc_entropy(request) {
 tc_rng_calls=tc_rng_calls+1;if request!=tc_curve_context || load64(request+8)!=32 || load64(request+16)!=0x1234567812345678 || !esp_smp_curve_busy || sc_tick(0)!=-16 {tc_rng_bad=1;return -5;}if tc_rng_calls!=1 {tc_rng_bad=1;return -5;}tc_lifetime();nb_copy(load64(request),tc_random,32);if tc_mode==300 {return -5;}if tc_mode==301 {return -16;}return 0;
}
fn tc_ob_configure(kind) {if kind<0 || kind>1 {return esp_smp_sc_oob_configure(4294967296,0);}let cb=0;if kind {cb=esp32_callback(tc_ob_cb);}return esp_smp_sc_oob_configure(cb,0x1122334455667788);}
fn tc_ob_change_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps|15);return 0;}
fn tc_ob_ps_clean() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps==tc_ob_ps;}
fn tc_ob_init_alias() {let saved=esp_smp_curve_context;esp_smp_curve_context=tc_ob_pool+32;let r=sc_oob_init(tc_ob_pool,2048,4);esp_smp_curve_context=saved;return r;}
fn tc_before(row) {tc_mode=load64(row+8);if load64(row)>=20 {tc_mode=load64(row+64);}if load64(row)>=39 {tc_mode=load64(row+152);tc_ob_result=load64(row+8);tc_ob_row=row;}let c=esp32_external("p256_test_control");nb_zero(c,20);if tc_mode>100 && tc_mode<200 {esp32_store32(c+4,tc_mode-100);esp32_store32(c+8,-16);}if tc_mode>200 && tc_mode<300 {esp32_store32(c+4,tc_mode-200);esp32_store32(c+8,-32);}c=esp32_external("smp_error_control");nb_zero(c,12);if tc_mode>500 && tc_mode<600 {esp32_store32(c+4,tc_mode-500);}tc_random=row+160;tc_rng_calls=0;tc_rng_bad=0;let ps=esp32_irq_save();if tc_mode>=620 && tc_mode<=635 {ps=(ps&~15)|(tc_mode-620);}esp32_irq_restore(ps);tc_ob_ps=ps;return 0;}
fn tc_report(field,actual,expected) {esp_uart_write("SMP SC FAIL ");esp_uart_hex(tc_case);esp_uart_hex(tc_step);esp_uart_hex(field);esp_uart_hex(actual);esp_uart_hex(expected);esp_uart_write("\r\n");return 0;}
fn main() {
 tc_curve_context=alloc(64);tc_aes_context=alloc(256);let r=esp_smp_curve_init(tc_curve_context,64,esp32_callback(tc_entropy),0x1234567812345678);if r {return r;}r=esp_smp_crypto_init(tc_aes_context,256);if r {return r;}
 r=esp_smp_sc_oob_configure(esp32_callback(tc_ob_cb),0x1122334455667788);if r {return r;}
 r=tc_run(esp32_external("smp_sc_cases"),esp32_external("smp_sc_cases_size"));if r {esp_uart_flush();return r;}if tc_rng_bad || !tc_zero(tc_curve_context,64) || !tc_zero(tc_aes_context,256) {return 9;}esp_uart_write("PASS: SMP SC ");esp_uart_hex(tc_checks);esp_uart_write(" independent observations\r\n");esp_uart_flush();return 0;
}
