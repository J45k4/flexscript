global pc_context=0;
global pc_expected_ps=0;
global pc_initial_ps=0;
fn pc_get_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn pc_before(level,fail) {esp32_irq_restore((pc_initial_ps&~15)|(level&15));pc_expected_ps=pc_get_ps();let ctrl=esp32_external("smp_error_control");esp32_store32(ctrl,0);esp32_store32(ctrl+4,fail);esp32_store32(ctrl+8,0);return 0;}
fn pc_calls() {return esp32_load32(esp32_external("smp_error_control"));}
fn pc_backend_clean() {return pc_value(pc_context,256,0) && pc_value(pc_context-16,16,165) && pc_value(pc_context+256,16,165) && !esp_smp_crypto_busy && !esp32_load32(esp32_external("smp_error_control")+8);}
fn pc_ps_clean() {return pc_get_ps()==pc_expected_ps;}
fn pc_report(case_number,step,byte,actual,expected) {esp_uart_write("SMP PRIVACY FAIL ");esp_uart_hex(case_number);esp_uart_hex(step);esp_uart_hex(byte);esp_uart_hex(actual);esp_uart_hex(expected);esp_uart_write("\r\n");return 0;}
fn main() {let raw=alloc(304);pc_fill(raw,304,165);pc_context=(raw+31)&~15;let r=esp_smp_crypto_init(pc_context,256);if r {return r;}pc_initial_ps=pc_get_ps();let data=esp32_external("smp_privacy_cases");r=pc_run(data,esp32_external("smp_privacy_cases_size"));esp32_irq_restore(pc_initial_ps);if esp_smp_crypto_deinit() {return 12;}if r {esp_uart_write("SMP PRIVACY RETURN ");esp_uart_hex(r);esp_uart_write("\r\n");esp_uart_flush();return r;}esp_uart_write("PASS: SMP privacy ");esp_uart_hex(pc_checks);esp_uart_write(" independent observations\r\n");esp_uart_flush();return 0;}
