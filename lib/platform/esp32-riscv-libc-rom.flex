// ESP-IDF5.5.1 ROM syscall table ABI:39 ILP32 function pointers,156 bytes.
// Explicit linked stdio must be initialized before this one-time boot step.
global esp_libc_rom_table=0;
global esp_libc_rom_lock_begin=0;
global esp_libc_rom_lock_end=0;
fn esp_libc_rom_resolve(handle) {if !(handle&3) && handle>=esp_libc_rom_lock_begin && handle<=esp_libc_rom_lock_end-4 {return esp32_load32(handle)==0xbb10c433;}return 0;}
fn esp_libc_rom_syscall_slot() {if rv_hal_chip==5 {return 0x3fcdffe0;}return 0x4087ffd4;}
fn esp_libc_rom_global_slot() {if rv_hal_chip==5 {return 0x3fcdffdc;}return 0x4087ffd0;}
fn esp_libc_rom_common_init() {if rv_hal_chip==5 {return 0x40000350;}return 0x400004a4;}
fn esp_libc_rom_nosys(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);return esp_libc_io_error(a,88);}
fn esp_libc_rom_fstat(a,b,c,d,e,f,g,h) {
    if rv_hal_chip!=5 {return _fstat_r(a,b,c,0,0,0,0,0);}
    // C3 ROM uses time_t32:stat60/alignment4/blksize44. Toolchain stat is88.
    esp_libc_reent_context();esp_libc_reent_pointer(a);if !esp_libc_fd_open(b) {return esp_libc_io_error(a,9);}if (c&3) || !esp_buffer_valid(c,60) {return esp_libc_io_error(a,14);}
    let i=0;while i<60 {store8(c+i,0);i=i+1;}esp32_store32(c+4,8630);esp32_store32(c+44,128);return 0;
}
fn esp_libc_rom_init() {
    esp_libc_lock_context();if esp_libc_rom_table || esp_sdk_current {return -16;}if !esp_libc_stdio_ready {return -19;}
    let ps=esp32_irq_save();if !esp_sdk_irq_blocked(ps) {esp32_irq_restore(ps);return -16;}
    let expected=5;if rv_hal_chip==13 {expected=13;}if esp32_load32(0x40000010)!=expected {esp32_irq_restore(ps);return -95;}
    let slot=esp_libc_rom_syscall_slot();let global_slot=esp_libc_rom_global_slot();if esp32_load32(slot) || esp32_load32(global_slot) || esp_libc_console_fds!=7 {esp32_irq_restore(ps);return -16;}
    let table=esp32_external("flex_rom_syscalls");let i=0;esp32_callback32(esp_libc_rom_nosys);esp32_callback32(esp_libc_rom_fstat);
    // Warm the current toolchain's FILE representation before any C3 ROM
    // formatting, avoiding its documented time_t32 __swsetup_r path. Stdin is
    // read-only; preserve errno across its expected EBADF setup result.
    if expected==5 {let errno=esp32_load32(esp_libc_main_reent);let setup=esp32_external("__swsetup_r");i=4;while i<=12 {let file=esp32_load32(esp_libc_main_reent+i);let old_error=load8(file+12)&64;esp32_call32(setup,esp_libc_main_reent,file,0,0,0,0,0,0);store8(file+12,(load8(file+12)&~64)|old_error);i=i+4;}esp32_store32(esp_libc_main_reent,errno);}
    esp32_call32(esp_libc_rom_common_init(),table+156,table+156,0,0,0,0,0,0);
    esp_libc_rom_lock_begin=0x3fcce710;esp_libc_rom_lock_end=0x3fce0000;if expected==13 {esp_libc_rom_lock_begin=0x4086e610;esp_libc_rom_lock_end=0x40880000;}
    esp_libc_rom_alias=esp32_callback(esp_libc_rom_resolve);esp32_store32(global_slot,esp_libc_main_reent);esp32_store32(slot,table);esp_libc_rom_table=table;esp32_irq_restore(ps);return 0;
}
