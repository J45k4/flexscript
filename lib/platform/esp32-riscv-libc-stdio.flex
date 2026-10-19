// Pinned newlib4.3 stdio, linked with --newlib-stdio. ROM stubs are separate.
global esp_libc_console_fds=7;
global esp_libc_console_tx=0;
global esp_libc_console_cycles=16000000;
global esp_libc_fclose=0;
fn esp_libc_console_budget(cycles) {esp_libc_reent_context();if cycles<1 || cycles>2147483647 {return -22;}esp_libc_console_cycles=cycles;return 0;}
fn esp_libc_io_error(reent,error) {esp_libc_errno(reent,error);return -1;}
fn esp_libc_fd_open(fd) {return fd>=0 && fd<=2 && (esp_libc_console_fds&(1<<fd));}
fn _write_r(a,b,c,d,e,f,g,h) {
    esp_libc_reent_context();esp_libc_reent_pointer(a);if !esp_libc_fd_open(b) || !b {return esp_libc_io_error(a,9);}if d>2147483647 {return esp_libc_io_error(a,22);}if !d {return 0;}if !esp_buffer_valid(c,d) {return esp_libc_io_error(a,14);}
    if esp_sdk_current && !esp_sdk_mutex_lock(esp_libc_console_tx) {return esp_libc_io_error(a,11);}
    let budget=esp_libc_console_cycles;let start=esp32_cycles();let sent=0;while sent<d && ((esp32_cycles()-start)&4294967295)<budget {if !esp_uart_bus_try_putc(0,load8(c+sent)) {sent=sent+1;}}
    if esp_sdk_current {esp_sdk_mutex_unlock(esp_libc_console_tx);}if !sent {return esp_libc_io_error(a,116);}return sent;
}
fn _read_r(a,b,c,d,e,f,g,h) {
    esp_libc_reent_context();esp_libc_reent_pointer(a);if b || !esp_libc_fd_open(b) {return esp_libc_io_error(a,9);}if d>2147483647 {return esp_libc_io_error(a,22);}if !d {return 0;}if !esp_buffer_valid(c,d) {return esp_libc_io_error(a,14);}
    let count=0;let byte=0;while count<d && byte>=0 {byte=esp_uart_bus_try_read(0);if byte>=0 {store8(c+count,byte);count=count+1;}}if !count {return esp_libc_io_error(a,11);}return count;
}
fn _close_r(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);let ps=esp32_irq_save();if !esp_libc_fd_open(b) {esp32_irq_restore(ps);return esp_libc_io_error(a,9);}esp_libc_console_fds=esp_libc_console_fds&~(1<<b);esp32_irq_restore(ps);return 0;}
fn _lseek_r(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);if !esp_libc_fd_open(b) {return esp_libc_io_error(a,9);}return esp_libc_io_error(a,29);}
fn _isatty_r(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);if !esp_libc_fd_open(b) {esp_libc_errno(a,9);return 0;}return 1;}
fn _fstat_r(a,b,c,d,e,f,g,h) {
    esp_libc_reent_context();esp_libc_reent_pointer(a);if !esp_libc_fd_open(b) {return esp_libc_io_error(a,9);}if (c&7) || !esp_buffer_valid(c,88) {return esp_libc_io_error(a,14);}let i=0;while i<88 {store8(c+i,0);i=i+1;}esp32_store32(c+4,8630);esp32_store32(c+72,128);return 0;
}
fn _open_r(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);return esp_libc_io_error(a,88);}
fn _sbrk_r(a,b,c,d,e,f,g,h) {esp_libc_reent_context();esp_libc_reent_pointer(a);return esp_libc_io_error(a,12);}
fn write(a,b,c,d,e,f,g,h) {return _write_r(esp_libc_getreent(),a,b,c,0,0,0,0);}
fn read(a,b,c,d,e,f,g,h) {return _read_r(esp_libc_getreent(),a,b,c,0,0,0,0);}
fn close(a,b,c,d,e,f,g,h) {return _close_r(esp_libc_getreent(),a,0,0,0,0,0,0);}
fn lseek(a,b,c,d,e,f,g,h) {return _lseek_r(esp_libc_getreent(),a,0,0,0,0,0,0);}
fn isatty(a,b,c,d,e,f,g,h) {return _isatty_r(esp_libc_getreent(),a,0,0,0,0,0,0);}
fn fstat(a,b,c,d,e,f,g,h) {return _fstat_r(esp_libc_getreent(),a,b,0,0,0,0,0);}
fn open(a,b,c,d,e,f,g,h) {return _open_r(esp_libc_getreent(),0,0,0,0,0,0,0);}
fn abort(a,b,c,d,e,f,g,h) {return esp_libc_lock_fault();}
fn esp_libc_file_lock(file,action) {
    esp_libc_lock_context();if !file {return 0;}if (file&3) || !esp_buffer_valid(file,104) {return esp_libc_lock_fault();}if load8(file+13)&2 {return 0;}let lock=esp32_load32(file+88);
    if !action {return esp_libc_lock_acquire(lock,1,1);}if action==1 {return esp_libc_lock_acquire(lock,1,0);}return esp_libc_lock_release(lock,1);
}
fn flockfile(a,b,c,d,e,f,g,h) {return esp_libc_file_lock(a,0);}
fn ftrylockfile(a,b,c,d,e,f,g,h) {return esp_libc_file_lock(a,1);}
fn funlockfile(a,b,c,d,e,f,g,h) {return esp_libc_file_lock(a,2);}
fn esp_libc_stdio_cleanup(a,b,c,d,e,f,g,h) {
    let i=4;let previous1=0;let previous2=0;while i<=12 {let file=esp32_load32(a+i);
        if file && file!=previous1 && file!=previous2 && file!=esp32_load32(esp_libc_main_reent+4) && file!=esp32_load32(esp_libc_main_reent+8) && file!=esp32_load32(esp_libc_main_reent+12) {esp32_call32(esp_libc_fclose,a,file,0,0,0,0,0,0);}
        if i==4 {previous1=file;}else if i==8 {previous2=file;}i=i+4;
    }return 0;
}
fn esp_libc_static_address(index) {
    if index==0 {return esp32_external("__lock___sinit_recursive_mutex");}
    if index==1 {return esp32_external("__lock___malloc_recursive_mutex");}
    if index==2 {return esp32_external("__lock___env_recursive_mutex");}
    if index==3 {return esp32_external("__lock___sfp_recursive_mutex");}
    if index==4 {return esp32_external("__lock___atexit_recursive_mutex");}
    if index==5 {return esp32_external("__lock___at_quick_exit_mutex");}
    if index==6 {return esp32_external("__lock___tz_mutex");}
    if index==7 {return esp32_external("__lock___dd_hash_mutex");}
    return esp32_external("__lock___arc4random_mutex");
}
fn esp_libc_stdio_init() {
    esp_libc_lock_context();if esp_libc_main_reent || esp_sdk_current {return -16;}if !esp_sdk_begin {return -19;}
    let pending=esp_sdk_calloc(6,8);if !pending {return -12;}let i=0;let failed=0;while i<6 && !failed {let recursive=i>0 && i<5;let lock=esp_sdk_mutex_create(recursive);if !lock {failed=1;}else {store64(lock+24,0x4c494243);store64(pending+i*8,lock);i=i+1;}}
    let table=0;if !failed {table=alloc(168);if table<=0 {failed=1;}}
    if failed {let j=0;while j<i {esp_sdk_free(load64(pending+j*8));j=j+1;}esp_sdk_free(pending);return -12;}
    i=0;while i<9 {let kind=1;if i<5 {kind=2;}store64(table+i*16,esp_libc_static_address(i));store64(table+i*16+8,kind);i=i+1;}i=0;while i<3 {store64(table+144+i*8,load64(pending+16+i*8));i=i+1;}
    esp_libc_static_normal=load64(pending);esp_libc_static_recursive=load64(pending+8);esp_libc_console_tx=load64(pending+40);esp_libc_static_locks=table;esp_libc_boot_locks=table+144;esp_libc_boot_used=0;esp_sdk_free(pending);
    let main=esp32_external("_impure_data");esp_libc_reent_bind(main);let files=esp32_external("__sf");i=0;while i<240 {store8(main+i,0);i=i+1;}i=0;while i<3 {esp32_store32(main+4+i*4,files+i*104);i=i+1;}
    esp32_callback32(_write_r);esp32_callback32(_read_r);esp32_callback32(_close_r);esp32_callback32(_lseek_r);esp32_callback32(_isatty_r);esp32_callback32(_fstat_r);esp32_callback32(_open_r);esp32_callback32(_sbrk_r);
    esp32_callback32(abort);
    esp_libc_fclose=esp32_external("_fclose_r");esp32_call32(esp32_external("__sinit"),main,0,0,0,0,0,0,0);if esp_libc_boot_used!=3 {return esp_libc_lock_fault();}esp_libc_boot_locks=0;
    esp32_store32(main+40,esp32_callback32(esp_libc_stdio_cleanup));esp32_store32(main+24,1);esp_libc_stdio_ready=1;return 0;
}

// Optional public POSIX aliases; newlib stdio itself calls the _r bridges.
fn esp_libc_posix_bind(){esp32_callback32(write);esp32_callback32(read);esp32_callback32(close);esp32_callback32(lseek);esp32_callback32(isatty);esp32_callback32(fstat);esp32_callback32(open);esp_libc_file_locks_bind();return 0;}

fn esp_libc_file_locks_bind(){esp32_callback32(flockfile);esp32_callback32(ftrylockfile);esp32_callback32(funlockfile);return 0;}
