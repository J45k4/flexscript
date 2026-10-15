import "esp32-settings.flex";
import "esp32-radio-os.flex";
import "../storage/nvs.flex";
// Optional OSI-v9 NVS provider. One SDK mutex protects the shared settings
// transaction and handle table. Credentials remain RAM-only in the Wi-Fi facade.
global env_workspace=0;
global env_capacity=0;
global env_core=0;
global env_table=0;
global env_mutex=0;
global env_initialized=0;
global env_active=0;
global esp_nvs_calls=0;
global esp_nvs_commits=0;
global esp_nvs_io_error=0;
fn env_outside(p,size,base,capacity) {return !size || p+size<=base || p>=base+capacity;}
fn env_input(p,size) {if !size && !p {return 1;}return ef_input_range(p,size) && kv_outside(p,size) && env_outside(p,size,env_core,nv_size(16));}
fn env_output(p,size) {return ef_ram(p,size) && kv_outside(p,size) && env_outside(p,size,env_core,nv_size(16)) && ef_no_alias(p,size);}
fn env_name(p) {if !p {return -1;}let i=0;while i<16 {if !env_input(p+i,1) {return -1;}if !load8(p+i) {return i;}i=i+1;}return 16;}
fn env_enter() {if !env_initialized {return 0x1101;}if !esp_sdk_current || esp32_load32(esp32_state()+16) {return 0x103;}if !esp_sdk_mutex_lock(env_mutex) {return 0x103;}env_active=1;esp_nvs_calls=esp_nvs_calls+1;return 0;}
fn env_leave(result) {env_active=0;esp_sdk_mutex_unlock(env_mutex);return result;}
fn esp_nvs_open(name,mode,out) {let error=env_enter();if error {return error;}if !env_output(out,4) {return env_leave(0x102);}let n=env_name(name);if n<0 {return env_leave(0x1106);}error=nv_open(name,n,mode);if !error {kv_put32(out,nv_opened);}return env_leave(error);}
fn esp_nvs_close(handle) {let error=env_enter();if error {return 0;}nv_close(handle);return env_leave(0);}
fn env_set_number(handle,key,value,type,size) {let error=env_enter();if error {return error;}let n=env_name(key);if n<0 {return env_leave(0x1106);}let p=env_core+32;let i=0;while i<size {store8(p+i,value>>(i*8));i=i+1;}return env_leave(nv_set(handle,key,n,type,p,size));}
fn esp_nvs_set_i8(handle,key,value) {if value< -128 || value>127 {return 0x102;}return env_set_number(handle,key,value,17,1);}
fn esp_nvs_set_u8(handle,key,value) {if value<0 || value>255 {return 0x102;}return env_set_number(handle,key,value,1,1);}
fn esp_nvs_set_u16(handle,key,value) {if value<0 || value>65535 {return 0x102;}return env_set_number(handle,key,value,2,2);}
fn env_get_number(handle,key,type,out,size) {let error=env_enter();if error {return error;}let n=env_name(key);if n<0 {return env_leave(0x1106);}error=nv_get(handle,key,n,type);if error {return env_leave(error);}if !env_output(out,size) {return env_leave(0x102);}kv_copy(out,kv_value,size);return env_leave(0);}
fn esp_nvs_get_i8(handle,key,out) {return env_get_number(handle,key,17,out,1);}
fn esp_nvs_get_u8(handle,key,out) {return env_get_number(handle,key,1,out,1);}
fn esp_nvs_get_u16(handle,key,out) {return env_get_number(handle,key,2,out,2);}
fn esp_nvs_set_value(handle,key,type,value,size) {let error=env_enter();if error {return error;}let n=env_name(key);if n<0 {return env_leave(0x1106);}if !env_input(value,size) {return env_leave(0x102);}return env_leave(nv_set(handle,key,n,type,value,size));}
fn esp_nvs_set_blob(handle,key,value,size) {return esp_nvs_set_value(handle,key,66,value,size);}
fn esp_nvs_get_value(handle,key,type,out,length) {
    let error=env_enter();if error {return error;}let n=env_name(key);if n<0 {return env_leave(0x1106);}error=nv_get(handle,key,n,type);if error {return env_leave(error);}if !length {return env_leave(0x110c);}if !env_output(length,4) {return env_leave(0x102);}let needed=kv_value_size;
    if !out {kv_put32(length,needed);return env_leave(0);}let capacity=kv_u32(length);if capacity<needed {kv_put32(length,needed);return env_leave(0x110c);}if !env_output(out,needed) || !env_outside(out,needed,length,4) {return env_leave(0x102);}
    kv_put32(length,needed);kv_copy(out,kv_value,needed);return env_leave(0);
}
fn esp_nvs_get_blob(handle,key,out,length) {return esp_nvs_get_value(handle,key,66,out,length);}
fn esp_nvs_erase_key(handle,key) {let error=env_enter();if error {return error;}let n=env_name(key);if n<0 {return env_leave(0x1106);}return env_leave(nv_erase(handle,key,n));}
fn esp_nvs_erase_all(handle) {let error=env_enter();if error {return error;}return env_leave(nv_erase_all(handle));}
fn esp_nvs_commit(handle) {let error=env_enter();if error {return error;}let p=nv_handle(handle,0);if !p {return env_leave(nv_error);}if !load8(p+4) {return env_leave(0);}error=esp_settings_commit();if error {esp_nvs_io_error=error;nv_fail();return env_leave(-1);}esp_nvs_commits=esp_nvs_commits+1;return env_leave(0);}
fn env_signed32(value) {if value>=2147483648 {return value-4294967296;}return value;}
fn env_cb_set_i8(a,b,c,d,e,f,g,h) {return esp_nvs_set_i8(a,b,env_signed32(c));}
fn env_cb_get_i8(a,b,c,d,e,f,g,h) {return esp_nvs_get_i8(a,b,c);}
fn env_cb_set_u8(a,b,c,d,e,f,g,h) {return esp_nvs_set_u8(a,b,c&255);}
fn env_cb_get_u8(a,b,c,d,e,f,g,h) {return esp_nvs_get_u8(a,b,c);}
fn env_cb_set_u16(a,b,c,d,e,f,g,h) {return esp_nvs_set_u16(a,b,c&65535);}
fn env_cb_get_u16(a,b,c,d,e,f,g,h) {return esp_nvs_get_u16(a,b,c);}
fn env_cb_open(a,b,c,d,e,f,g,h) {return esp_nvs_open(a,b,c);}
fn env_cb_close(a,b,c,d,e,f,g,h) {esp_nvs_close(a);return 0;}
fn env_cb_commit(a,b,c,d,e,f,g,h) {return esp_nvs_commit(a);}
fn env_cb_set_blob(a,b,c,d,e,f,g,h) {return esp_nvs_set_blob(a,b,c,d);}
fn env_cb_get_blob(a,b,c,d,e,f,g,h) {return esp_nvs_get_blob(a,b,c,d);}
fn env_cb_erase(a,b,c,d,e,f,g,h) {return esp_nvs_erase_key(a,b);}
fn env_install() {
    esp32_store32(env_table,esp32_callback32(env_cb_set_i8));esp32_store32(env_table+4,esp32_callback32(env_cb_get_i8));esp32_store32(env_table+8,esp32_callback32(env_cb_set_u8));esp32_store32(env_table+12,esp32_callback32(env_cb_get_u8));esp32_store32(env_table+16,esp32_callback32(env_cb_set_u16));esp32_store32(env_table+20,esp32_callback32(env_cb_get_u16));
    esp32_store32(env_table+24,esp32_callback32(env_cb_open));esp32_store32(env_table+28,esp32_callback32(env_cb_close));esp32_store32(env_table+32,esp32_callback32(env_cb_commit));esp32_store32(env_table+36,esp32_callback32(env_cb_set_blob));esp32_store32(env_table+40,esp32_callback32(env_cb_get_blob));esp32_store32(env_table+44,esp32_callback32(env_cb_erase));
    esp_radio_nvs_table=env_table;esp_radio_nvs_apply();return 0;
}
// Explicit create permits provisioning only when both banks are completely
// erased. Unknown/corrupt media are never formatted. Initialize before radio.
fn esp_nvs_init(start,bank,create) {
    if env_initialized || env_active || esp_radio_osi || !esp_sdk_current {return -16;}if create!=0 && create!=1 {return -22;}let needed=kv_size(bank);if needed<0 {return needed;}
    if env_workspace && needed>env_capacity {return -12;}if !env_workspace {env_workspace=esp_sdk_calloc(1,needed);if !env_workspace {return -12;}env_capacity=needed;}if !env_core {env_core=esp_sdk_calloc(1,nv_size(16));if !env_core {return -12;}}if !env_table {env_table=esp_sdk_calloc(1,48);if !env_table {return -12;}}if !env_mutex {env_mutex=esp_sdk_mutex_create(0);if !env_mutex {return -12;}}
    let error=esp_settings_init(start,bank,env_workspace,env_capacity,80000000);if error== -61 && create {error=esp_settings_create();}if error {esp_nvs_io_error=error;return error;}error=nv_init(env_core,nv_size(16),16);if error {return error;}env_initialized=1;esp_nvs_io_error=0;env_install();return 0;
}
fn esp_nvs_reload() {let error=env_enter();if error {return error;}nv_ready=0;error=esp_settings_reload();if !error {error=nv_init(env_core,nv_size(16),16);}if error {nv_fail();esp_nvs_io_error=error;return env_leave(error);}esp_nvs_io_error=0;return env_leave(0);}
// Release is supported before an OSI table is live. Radio shutdown/restart
// remains a separate lifecycle requirement; do not invalidate a live provider.
fn esp_nvs_release() {
    if !env_workspace && !env_core && !env_table && !env_mutex {return 0;}
    if esp_radio_osi || env_active || esp32_load32(esp32_state()+16) {return -16;}
    if kv_work==env_workspace {let error=es_restore_window();if error {return error;}kv_mounted=0;kv_work=0;esp_settings_status= -107;esp_settings_bank=0;}
    if nv_work==env_core {nv_ready=0;nv_work=0;nv_handles=0;}
    if esp_radio_nvs_table==env_table {esp_radio_nvs_table=0;}env_initialized=0;
    if env_workspace {esp_sdk_free(env_workspace);}if env_core {esp_sdk_free(env_core);}if env_table {esp_sdk_free(env_table);}if env_mutex {esp_sdk_free(env_mutex);}env_workspace=0;env_capacity=0;env_core=0;env_table=0;env_mutex=0;return 0;
}
