global se_context=0;
global se_ps=0;
fn se_saved_ps() {let ps=esp32_irq_save();esp32_irq_restore(ps);return ps;}
fn st_backend_clean() {return st_zero(se_context,256) && st_value(se_context-16,16,165) && st_value(se_context+256,16,165) && !esp_smp_crypto_busy && se_saved_ps()==se_ps;}
fn st_report(index,check) {esp_uart_write("SMP ERROR ABI FAIL case=");esp_uart_hex(index);esp_uart_write(" check=");esp_uart_hex(check);esp_uart_write("\r\n");return 0;}
fn se_run() {
 let raw=alloc(304);st_fill(raw,304,165);se_context=(raw+31)&~15;if esp_smp_crypto_init(se_context,256) {return 1;}
 let records=esp32_external("smp_vectors");let ctrl=esp32_external("smp_error_control");let output=alloc(64);let scratch=alloc(544);let initial=se_saved_ps();let level=0;
 while level<16 {esp32_irq_restore((initial&~15)|level);se_ps=se_saved_ps();let i=0;
  while i<14 {let row=records+i*832;st_case=i+1;let used=512;if !load64(row) {used=96;}esp32_store32(ctrl,0);esp32_store32(ctrl+4,0);st_fill(se_context,256,90);
   if !st_check(!st_drive(row,output+16,scratch+16,512) && st_backend_clean()) {return 2;}let calls=esp32_load32(ctrl);let fail=1;
   while fail<=calls {esp32_store32(ctrl,0);esp32_store32(ctrl+4,fail);st_fill(output,64,165);st_fill(scratch,544,165);st_fill(scratch+16,512,90);st_fill(se_context,256,90);
    if !st_check(st_drive(row,output+16,scratch+16,512)== -32 && esp32_load32(ctrl)==fail && !esp32_load32(ctrl+8) && st_outside(output,0) && st_scratch(scratch,used) && st_backend_clean()) {return 3;}fail=fail+1;}
   i=i+1;}level=level+1;}
 esp32_irq_restore(initial);if esp_smp_crypto_deinit() || esp_smp_crypto_context || !st_zero(se_context,256) {return 4;}
 esp_uart_write("PASS: SMP real vendor/C error ABI ");esp_uart_hex(st_checks);esp_uart_write(" checks,16 interrupt levels,unchanged outputs and wiped keys\r\n");esp_uart_flush();return 0;
}

fn main() {let r=se_run();if r {esp_uart_write("SMP PROVIDER ERROR FAIL ");esp_uart_hex(r);esp_uart_write("\r\n");esp_uart_flush();}return r;}
