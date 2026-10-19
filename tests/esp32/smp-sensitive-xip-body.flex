fn sk_allocate(n) {return esp_sdk_malloc(n);}
fn sk_report(point) {esp_uart_write("SMP SENSITIVE FAIL ");esp_uart_hex(point);esp_uart_write("\r\n");return 0;}
fn dc_report(a,b,c,d,e) {return 0;}
fn main() {let start=esp_sdk_heap_min();let r=esp_sdk_heap_init(start,esp_sdk_heap_max()-start);if r {return r;}r=sk_run();if r {esp_uart_flush();return r;}esp_uart_write("PASS: SMP sensitive ");esp_uart_hex(sk_checks);esp_uart_write(" independent observations\r\n");esp_uart_flush();return 0;}
