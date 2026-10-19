global ct_available=0;
global pc_context=0;
global pc_expected_ps=0;
global pc_initial_ps=0;
fn pc_get_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn pc_before(level,fail) {esp32_irq_restore((pc_initial_ps&~15)|(level&15));pc_expected_ps=pc_get_ps();let ctrl=esp32_external("smp_error_control");esp32_store32(ctrl,0);esp32_store32(ctrl+4,fail);esp32_store32(ctrl+8,0);return 0;}
fn pc_calls() {return esp32_load32(esp32_external("smp_error_control"));}
fn pc_backend_clean() {return pc_value(pc_context,256,0) && pc_value(pc_context-16,16,165) && pc_value(pc_context+256,16,165) && !esp_smp_crypto_busy && !esp32_load32(esp32_external("smp_error_control")+8);}
fn pc_ps_clean() {return pc_get_ps()==pc_expected_ps;}
fn pc_report(case_number,step,byte,actual,expected) {esp_uart_write("SMP CHECKPOINT FAIL ");esp_uart_hex(case_number);esp_uart_hex(step);esp_uart_hex(byte);esp_uart_hex(actual);esp_uart_hex(expected);esp_uart_write("\r\n");return 0;}
fn main() {let base=esp_sdk_heap_min();let size=esp_sdk_heap_max()-base;if esp_sdk_heap_init(base,size) {return 1;}ct_available=esp_sdk_heap_free();let raw=alloc(304);pc_fill(raw,304,165);pc_context=(raw+31)&~15;let r=esp_smp_crypto_init(pc_context,256);if r {return r;}pc_initial_ps=pc_get_ps();r=be_run();esp32_irq_restore(pc_initial_ps);if esp_smp_crypto_deinit() {return 12;}if r {esp_uart_write("SMP STORE FAIL ");esp_uart_hex(r);}else {esp_uart_write("PASS: SMP checkpoint-restart ");}esp_uart_hex(ct_checks);esp_uart_write("\r\n");esp_uart_flush();return r;}

fn ct_allocate(n) {return esp_sdk_malloc(n);}
fn ct_release(p) {return esp_sdk_free(p);}
fn ct_arena_clean() {return !esp_sdk_allocated && esp_sdk_heap_free()==ct_available;}
fn ct_diagnostic(mode,code) {esp_uart_write("STORE FAIL case/checkpoint ");esp_uart_hex(mode);esp_uart_hex(code);esp_uart_write("\r\n");return 0;}
