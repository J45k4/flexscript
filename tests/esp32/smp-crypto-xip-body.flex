global sx_context=0;
global sx_expected_ps=0;
global sx_key=0;
global sx_plain=0;
global sx_out=0;
global sx_irq_done=0;
global sx_irq_bad=0;
fn sx_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn st_backend_clean() {return st_zero(sx_context,256) && st_value(sx_context-16,16,165) && st_value(sx_context+256,16,165) && !esp_smp_crypto_busy && sx_ps()==sx_expected_ps;}
fn st_report(index,check) {esp_uart_write("SMP CRYPTO FAIL case=");esp_uart_hex(index);esp_uart_write(" check=");esp_uart_hex(check);esp_uart_write("\r\n");return 0;}
fn sx_soft(source) {
    if smp_aes128(sx_key,sx_plain,sx_out)!= -16 || esp_smp_crypto_init(sx_context,256)!= -16 || esp_smp_crypto_deinit()!= -16 || esp_smp_crypto_context!=sx_context || esp_smp_crypto_busy || !st_zero(sx_context,256) {sx_irq_bad=1;}sx_irq_done=1;return 0;
}
fn sx_run() {
    let records=esp32_external("smp_vectors");let bytes=esp32_external("smp_vectors_size");if !bytes || bytes%832 {return 1;}
    let raw=alloc(304);sx_context=(raw+31)&~15;st_fill(raw,304,165);sx_key=records+32;sx_plain=records+64;sx_out=alloc(32);st_fill(sx_out,32,165);let initial=sx_ps();
    if smp_aes128(sx_key,sx_plain,sx_out)!= -19 || !st_value(sx_out,32,165) || sx_ps()!=initial {return 2;}
    if esp_smp_crypto_init(0x100000000+sx_context,256)!= -22 || esp_smp_crypto_init(sx_context,4294967296)!= -22 || esp_smp_crypto_init(0,256)!= -22 || esp_smp_crypto_init(sx_context,255)!= -22 || esp_smp_crypto_init(sx_context+1,256)!= -22 || !st_value(raw,304,165) || sx_ps()!=initial {return 3;}
    if esp_smp_crypto_init(sx_context,256) || esp_smp_crypto_init(sx_context,256)!= -16 {return 4;}sx_expected_ps=initial;if !st_backend_clean() {return 5;}
    if smp_aes128(sx_key+0x100000000,sx_plain,sx_out)!= -22 || smp_aes128(sx_key,sx_plain+0x100000000,sx_out)!= -22 || smp_aes128(sx_key,sx_plain,sx_out+0x100000000)!= -22 || smp_aes128(0,sx_plain,sx_out)!= -22 || smp_aes128(sx_key,0,sx_out)!= -22 || smp_aes128(sx_key,sx_plain,0)!= -22 || smp_aes128(sx_context,sx_plain,sx_out)!= -22 || smp_aes128(sx_key,sx_context,sx_out)!= -22 || smp_aes128(sx_key,sx_plain,sx_context)!= -22 || !st_value(sx_out,32,165) || !st_backend_clean() {return 6;}
    esp_smp_crypto_busy=1;if smp_aes128(sx_key,sx_plain,sx_out)!= -16 || esp_smp_crypto_deinit()!= -16 || esp_smp_crypto_context!=sx_context || sx_ps()!=initial {return 7;}esp_smp_crypto_busy=0;
    if esp_irq_software(esp32_callback(sx_soft)) {return 8;}esp_irq_enable();sx_expected_ps=sx_ps();esp32_irq_raise(128);let before=esp32_cycles();while !sx_irq_done && ((esp32_cycles()-before)&4294967295)<8000000 {}
    if !sx_irq_done || sx_irq_bad || !st_backend_clean() {return 9;}
    if st_run(records,bytes/832) {return 10;}if st_large(esp32_external("smp_large")) {return 12;}
    if esp_smp_crypto_deinit() || esp_smp_crypto_deinit() || esp_smp_crypto_context || !st_zero(sx_context,256) || sx_ps()!=sx_expected_ps {return 11;}
    esp_uart_write("PASS: SMP Xtensa real vendor AES, ");esp_uart_hex(st_checks);esp_uart_write(" vector/canary/alias checks;context and ISR guards\r\n");esp_uart_flush();return 0;
}

fn main() {let r=sx_run();if r {esp_uart_write("SMP PROVIDER FAIL ");esp_uart_hex(r);esp_uart_write("\r\n");esp_uart_flush();}return r;}
