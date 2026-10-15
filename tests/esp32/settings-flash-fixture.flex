import "../../lib/platform/esp32-settings.flex";
import "../../lib/platform/esp32.flex";
fn sf_literal(n) {return "settings survive reboot";}
fn sf_run() {
    let cycles=80000000;let size=kv_size(4096);let work=alloc(size);if work<=0 {return 1;}let result=esp_settings_init(0x3e0000,4096,work,size,cycles);let value=alloc(640);if value<=0 {return 2;}
    esp_uart_write("SETTINGS mounted ");esp_uart_hex(result);esp_uart_write("\r\n");
    if result== -61 {if esp_settings_create() || kv_set("message",7,33,sf_literal(0),23) {return 3;}let i=0;while i<600 {store8(value+i,(i*29+17)&255);i=i+1;}if kv_set("payload",7,66,value,600) {return 4;}store8(value,1);if kv_set("count",5,1,value,1) || esp_settings_commit() {return 5;}esp_uart_write("SETTINGS COMMITTED 1\r\n");}
    else if !result {if kv_get("count",5) || kv_value_type!=1 || kv_value_size!=1 {return 6;}let count=load8(kv_value);if count<1 || count>2 || kv_get("message",7) || kv_value_size!=23 || !kv_equal(kv_value,sf_literal(0),23) || kv_get("payload",7) || kv_value_size!=600 {return 7;}let i=0;while i<600 {if load8(kv_value+i)!=((i*29+17+count-1)&255) {return 8;}i=i+1;}
        esp_uart_write("SETTINGS RECOVERED ");esp_uart_hex(count);esp_uart_write("\r\n");
        if count==1 {i=0;while i<600 {store8(value+i,(i*29+18)&255);i=i+1;}if kv_set("payload",7,66,value,600) {return 9;}store8(value,2);if kv_set("count",5,1,value,1) || esp_settings_commit() {return 10;}esp_uart_write("SETTINGS COMMITTED 2\r\n");}
        else {store8(value,3);if kv_set("count",5,1,value,1) || kv_commit()!=1 || esp_flash_write_access(1,cycles) {return 11;}let steps=0;while steps<2 {if !kv_next_io() {return 12;}let done= -22;if kv_io_kind==1 {done=esp_flash_erase(kv_io_offset,kv_io_size,cycles);}else if kv_io_kind==2 {done=esp_flash_program(kv_io_offset,kv_io_buffer,kv_io_size,cycles);}if kv_io_done(done)<0 {return 13;}steps=steps+1;}
            if esp_flash_write_access(0,cycles) {return 15;}esp_uart_write("SETTINGS INTERRUPTED BEFORE MARKER\r\n");
        }
    }else {return 14;}
    esp_uart_flush();return 0;
}
