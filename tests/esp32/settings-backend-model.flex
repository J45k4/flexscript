import "flash-model-settings.flex";
import "flash-register-fixture.flex";
fn main(argc,argv) {
    let checked=fm_run(1,argv);if checked {return checked;}fm_status=0x1c;fm_id=0x162085;fm_bad_status=0;fm_reject_status=0;fm_require_qe=0;
    let cycles=10000;if esp_flash_region(0x3e0000,8192,cycles) || esp_flash_write_access(1,cycles) || esp_flash_erase(0,8192,cycles)!=8192 || esp_flash_write_access(0,cycles) {return 40;}
    let work=0x3ffb4000;if esp_settings_init(0x3e0000,4096,work,8456,cycles)!= -61 || esp_settings_create() || fm_status!=0x1c || esp_flash_write_open {return 41;}
    if kv_set("value",5,1,0x3f400000,19) {return 42;}fm_reject_status=1;if esp_settings_commit()!= -13 || kv_busy || fm_status!=0x1c || esp_flash_write_open {return 43;}fm_reject_status=0;if esp_settings_reload() || kv_get("value",5)!= -2 {return 44;}
    if kv_set("value",5,1,0x3f400000,19) {return 45;}fm_protect=1;if esp_settings_commit()!= -5 || kv_busy || fm_status!=0x1c || esp_flash_write_open {return 46;}fm_protect=0;if esp_settings_reload() || kv_get("value",5)!= -2 {return 47;}
    if kv_set("value",5,1,0x3f400000,19) {return 48;}fm_reject_restore=1;if esp_settings_commit()!= -13 || !esp_flash_write_open || esp_settings_restore_error!= -13 {return 49;}
    // Reload must not publish ready state while this component still owns an
    // unresolved protection change, even though the new settings are durable.
    if esp_settings_reload()!= -13 || esp_settings_status!= -13 || !esp_flash_write_open {return 50;}fm_reject_restore=0;
    if esp_settings_reload() || esp_flash_write_open || fm_status!=0x1c || esp_settings_restore_error || kv_get("value",5) || kv_value_size!=19 || !kv_equal(kv_value,0x3f400000,19) {return 51;}
    // An application-owned window survives commits and reloads unchanged.
    if esp_flash_write_access(1,cycles) || kv_set("more",4,1,0x3f400000,1) || esp_settings_commit() || !esp_flash_write_open || esp_settings_reload() || !esp_flash_write_open || esp_flash_write_access(0,cycles) || fm_status!=0x1c {return 52;}
    if esp_settings_init(0x3e0000,4096,esp_flash_scratch,8456,cycles)!= -22 || esp_settings_init(0x3e0000,4096,work,32,cycles)!= -22 || esp_flash_region(0x1a0000,4096,cycles) || esp_settings_reload()!= -16 || esp_settings_commit()!= -107 || fm_failed || fm_nonvolatile_writes {return 53;}
    return 0;
}
