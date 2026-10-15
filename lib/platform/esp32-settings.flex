import "esp32-flash.flex";
import "../storage/settings.flex";
// One store and one flash region, serialized by the application/SDK owner.
// Initialization/reload only read media. Erased media require explicit create.
global esp_settings_start=0;
global esp_settings_bank=0;
global esp_settings_cycles=0;
global esp_settings_status= -107;
global esp_settings_restore_error=0;
global es_write_owned=0;
fn es_region_matches() {return esp_settings_bank && esp_flash_start==esp_settings_start && esp_flash_size==esp_settings_bank*2;}
fn es_restore_window() {if !es_write_owned {return 0;}let result=esp_flash_write_access(0,esp_settings_cycles);esp_settings_restore_error=result;if !result {es_write_owned=0;}return result;}
fn esp_settings_reload() {
    if kv_busy {return -16;}if !es_region_matches() {return -16;}let restored=es_restore_window();if restored {esp_settings_status=restored;return restored;}esp_settings_status= -107;kv_mounted=0;
    let size=esp_settings_bank*2;let result=esp_flash_read(0,kv_bank_buffer(0),size,esp_settings_cycles);if result!=size {if result>=0 {result= -5;}esp_settings_status=result;return result;}
    result=kv_mount();esp_settings_status=result;return result;
}
fn esp_settings_init(start,bank,workspace,capacity,cycles) {
    if kv_busy {return -16;}let size=kv_size(bank);if size<0 || capacity<size || !ef_ram(workspace,size) || !ef_no_alias(workspace,size) || !ef_timeout_valid(cycles) {return -22;}
    let result=esp_flash_region(start,bank*2,cycles);if result {return result;}if !ef_no_alias(workspace,size) {return -22;}result=kv_init(workspace,capacity,bank);if result {return result;}
    esp_settings_start=start;esp_settings_bank=bank;esp_settings_cycles=cycles;return esp_settings_reload();
}
fn esp_settings_commit() {
    if esp_settings_status || !es_region_matches() {return -107;}let result=kv_commit();if result<=0 {return result;}esp_settings_restore_error=0;let owned=!esp_flash_write_open;if owned {result=esp_flash_write_access(1,esp_settings_cycles);if result {kv_io_fail(result);esp_settings_status=result;return result;}es_write_owned=1;}
    let active=1;while active && kv_next_io() {let n=kv_io_size;let kind=kv_io_kind;let done= -22;
        if kind==1 {done=esp_flash_erase(kv_io_offset,n,esp_settings_cycles);}else if kind==2 {done=esp_flash_program(kv_io_offset,kv_io_buffer,n,esp_settings_cycles);}else if kind==3 {done=esp_flash_read(kv_io_offset,kv_io_buffer,n,esp_settings_cycles);}
        result=kv_io_done(done);if result<0 {esp_settings_status=result;active=0;}
    }if owned {let restored=es_restore_window();if restored && result>=0 {result=restored;esp_settings_status=result;}}if result<0 {return result;}return 0;
}
fn esp_settings_create() {if esp_settings_status!= -61 || !es_region_matches() {return -16;}let result=kv_create();if result {return result;}esp_settings_status=0;return esp_settings_commit();}
