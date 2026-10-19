// Legacy Xtensa ABI exports; RISC-V uses task-local newlib instead.
fn free(a,b,c,d,e,f,g,h) {return esp_sdk_free(a);
}
fn malloc(a,b,c,d,e,f,g,h) {return esp_sdk_malloc(a);
}
fn calloc(a,b,c,d,e,f,g,h) {return esp_sdk_calloc(a,b);
}
fn realloc(a,b,c,d,e,f,g,h) {return esp_sdk_realloc(a,b);
}
fn puts(a,b,c,d,e,f,g,h) {esp_uart_write(a);esp_uart_write("\r\n");return 0;
}
fn __assert_func(a,b,c,d,e,f,g,h) {esp_uart_write("Vendor assertion ");esp_uart_write(a);esp_uart_hex(b);esp_uart_write(d);return esp_radio_fail(0x4000);
}
fn esp_radio_libc_exports(){
    esp32_callback32(free);
    esp32_callback32(malloc);
    esp32_callback32(calloc);
    esp32_callback32(realloc);
    esp32_callback32(puts);
    esp32_callback32(__assert_func);
    return 0;
}
