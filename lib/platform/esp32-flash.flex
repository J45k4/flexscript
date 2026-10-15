import "esp32-xip.flex";
// Original ESP32, one active CPU, XIP linker profile. JEDEC single-wire NOR.
// Register/cache contracts: ESP-IDF v5.5.1 esp32 spi_reg.h/cache.h. No
// nonvolatile status writes, flash encryption, secure boot or PSRAM commands.
global esp_flash_start=0;
global esp_flash_size=0;
global esp_flash_capacity=0;
global esp_flash_jedec=0;
global esp_flash_status=0;
global esp_flash_write_open=0;
global esp_flash_saved_status=0;
global esp_flash_scratch=0;
global esp_flash_busy=0;
global esp_flash_fatal=0;
fn ef_copy(out,input,size) {let i=0;while i<size {store8(out+i,load8(input+i));i=i+1;}return 0;}
fn ef_ram(p,size) {return size>=0 && p>=0x3ffb0000 && p<=0x40000000 && size<=0x40000000-p;}
fn ef_input_range(p,size) {return ef_ram(p,size) || (size>=0 && p>=0x3f400000 && p<=0x3f800000 && size<=0x3f800000-p);}
fn ef_no_alias(p,size) {return !size || p+size<=esp_flash_scratch || p>=esp_flash_scratch+320;}
fn ef_timeout_valid(cycles) {return cycles>=1 && cycles<=2147483647;}
fn ef_fault_byte(byte) {while ((esp32_load32(0x3ff4001c)>>16)&255)>=126 {}esp32_store32(0x3ff40000,byte);return 0;}
fn ef_fault(code) {esp_flash_fatal=code;ef_fault_byte(33);ef_fault_byte(70);ef_fault_byte(48+code);ef_fault_byte(13);ef_fault_byte(10);esp32_halt();return -110;}
fn ef_controller(p) {let begin=esp32_cycles();while esp32_load32(0x3ff42000) {if ((esp32_cycles()-begin)&4294967295)>=load64(p+24) {return ef_fault(1);}}return 0;}
// Internal command routine. Every call is made with IRQs masked, cache off and
// internal-RAM arguments. Each command restores the controller configuration
// at the enclosing critical-section boundary; no ROM flash unlock is called.
fn ef_command(p,command,address,has_address,tx,rx,size) {
    if ef_controller(p) {return -110;}let user=(1<<31)|48;if has_address {user=user|(1<<30);}if tx {user=user|(1<<27);}if rx {user=user|(1<<28);}
    esp32_store32(0x3ff4201c,user);let bits=0;if has_address {bits=23<<26;}esp32_store32(0x3ff42020,bits);esp32_store32(0x3ff42024,(7<<28)|command);esp32_store32(0x3ff42004,address<<8);
    if size {esp32_store32(0x3ff42028,size*8-1);esp32_store32(0x3ff4202c,size*8-1);}let i=0;
    while i<16 {let word=0;let j=0;while j<4 {if tx && i*4+j<size {word=word|(load8(tx+i*4+j)<<(j*8));}j=j+1;}esp32_store32(0x3ff42080+i*4,word);i=i+1;}
    esp32_store32(0x3ff42000,1<<18);if ef_controller(p) {return -110;}if rx {i=0;while i<size {let word=esp32_load32(0x3ff42080+(i/4)*4);store8(rx+i,word>>((i&3)*8));i=i+1;}}return 0;
}
fn ef_ready(p) {let begin=esp32_cycles();let busy=1;while busy {if ef_command(p,5,0,0,0,p+192,1) {return -110;}busy=load8(p+192)&1;if busy && ((esp32_cycles()-begin)&4294967295)>=load64(p+24) {return ef_fault(2);}}return 0;}
fn ef_write_enable(p) {let error=ef_ready(p);if error {return error;}error=ef_command(p,6,0,0,0,0,0);if error {return error;}error=ef_command(p,5,0,0,0,p+192,1);if error {return error;}if !(load8(p+192)&2) {return -13;}return 0;}
fn ef_status(p) {let error=ef_ready(p);if error {return error;}store8(p+256,load8(p+192));error=ef_command(p,0x35,0,0,0,p+192,1);if !error {store8(p+257,load8(p+192));}return error;}
fn ef_status_value(p) {return load8(p+256)|(load8(p+257)<<8);}
// Puya P25Q32H, verified JEDEC852016. VWREN50 must immediately precede
// WRSR01; never use WREN06 for a status update. Preserve all unrelated bits.
fn ef_status_put(p,value,bytes) {
    store8(p+272,value);store8(p+273,value>>8);let error=ef_command(p,4,0,0,0,0,0);if error {return error;}error=ef_command(p,0x50,0,0,0,0,0);if error {return error;}error=ef_command(p,1,0,0,p+272,0,bytes);if error {return error;}return ef_status(p);
}
fn ef_status_change(p,value) {
    let error=ef_status(p);if error {return error;}let before=ef_status_value(p);value=value&65532;if before&0x8000 {return -16;}if ((before^value)&0xfffc&~0x407c) {return -22;}
    if !((before^value)&0x7ffc) {return 0;}error=ef_status_put(p,value,2);if error {return error;}let after=ef_status_value(p);
    // Some ordering variants accept SR1-only writes. A one-byte fallback is
    // safe only when the entire old/new SR2 is zero, so QE/locks cannot change.
    if ((after^value)&0x7ffc) && !((before^after)&0x7ffc) && !(before&0xff00) && !(value&0xff00) {error=ef_status_put(p,value,1);if error {return error;}after=ef_status_value(p);}
    if !((after^value)&0x7ffc) {return 0;}if (after^before)&0x7ffc {error=ef_status_put(p,before,2);if error || ((ef_status_value(p)^before)&0x7ffc) {return ef_fault(3);}}return -13;
}
fn ef_config_address(i) {if !i {return 0x3ff42008;}if i==1 {return 0x3ff42018;}if i==2 {return 0x3ff4201c;}if i==3 {return 0x3ff42020;}if i==4 {return 0x3ff42024;}if i==5 {return 0x3ff42028;}if i==6 {return 0x3ff4202c;}return 0x3ff42034;}
fn ef_critical(p) {
    let ps=esp32_irq_save();esp32_call32(0x40009ab8,0,0,0,0,0,0,0,0);let error=ef_controller(p);let i=0;
    while i<8 {store64(p+64+i*8,esp32_load32(ef_config_address(i)));i=i+1;}
    // SPI1 at APB/4, mode0, CS0, single-bit data. SPI0 cache configuration and
    // ROM/eFuse pad routing are untouched. Restore SPI1 before resuming cache.
    esp32_store32(0x3ff42008,load64(p+64)&~0x07906000);esp32_store32(0x3ff42018,(3<<12)|(1<<6)|3);esp32_store32(0x3ff42034,6);
    let op=load64(p);let address=load64(p+8);let size=load64(p+16);
    if !error {error=ef_ready(p);}
    if !error && op==0 {error=ef_status(p);if !error {error=ef_command(p,0x9f,0,0,0,p+192,3);}}
    else if !error && op==1 {error=ef_command(p,3,address,1,0,p+192,size);}
    else if !error && (op==2 || op==3) {
        error=ef_write_enable(p);if !error {let command=2;let tx=p+128;let n=size;if op==3 {command=0x20;tx=0;n=0;}error=ef_command(p,command,address,1,tx,0,n);}
        if !error {error=ef_ready(p);}if !error {error=ef_command(p,4,0,0,0,0,0);}
        if !error && op==2 {error=ef_command(p,3,address,1,0,p+192,size);if !error {i=0;while i<size {if load8(p+128+i)!=load8(p+192+i) {error= -5;}i=i+1;}}}
        if !error && op==3 {let at=0;while at<4096 && !error {error=ef_command(p,3,address+at,1,0,p+192,64);if !error {i=0;while i<64 {if load8(p+192+i)!=255 {error= -5;}i=i+1;}}at=at+64;}}
    }
    else if !error && op==4 {error=ef_status_change(p,size);}
    i=0;while i<8 {esp32_store32(ef_config_address(i),load64(p+64+i*8));i=i+1;}
    esp32_call32(0x40009a14,0,0,0,0,0,0,0,0);esp32_call32(0x40009a84,0,0,0,0,0,0,0,0);esp32_irq_restore(ps);return error;
}
fn ef_mark_iram() {esp32_iram_callback(ef_critical);return 0;}
fn ef_safe_runtime() {
    if esp32_load32(esp32_state()+16) {return -16;}
    if !(esp32_load32(0x3ff0002c)&1) && (esp32_load32(0x3ff00030)&1) && !(esp32_load32(0x3ff00034)&1) {return -16;}
    // Conservatively reject any provisioned encryption count, even an even
    // count with encryption temporarily off; never modify eFuses or locks.
    if (esp32_load32(0x3ff5a000)&0x07f00000) || (esp32_load32(0x3ff5a018)&48) {return -95;}return 0;
}
fn ef_lock() {let error=ef_safe_runtime();if error {return error;}let ps=esp32_irq_save();if esp_flash_busy {esp32_irq_restore(ps);return -16;}esp_flash_busy=1;esp32_irq_restore(ps);return 0;}
fn ef_unlock(result) {esp_flash_busy=0;return result;}
fn ef_run(op,address,size,cycles) {let p=esp_flash_scratch;store64(p,op);store64(p+8,address);store64(p+16,size);store64(p+24,cycles);return ef_critical(p);}
fn esp_flash_protected_end() {let end=esp32_external("_flex_drom_flash")+esp32_external("_flex_drom_pages")*65536;if end<1048576 {end=1048576;}return end;}
fn esp_flash_region(start,size,cycles) {
    if start<1048576 || (start&4095) || size<4096 || (size&4095) || start>16777216 || size>16777216-start || !ef_timeout_valid(cycles) || start<esp_flash_protected_end() {return -22;}
    if esp_flash_write_open {return -16;}let error=ef_lock();if error {return error;}if !esp_flash_scratch {let p=alloc(320);if p<=0 {return ef_unlock(-12);}if !ef_ram(p,320) {return ef_unlock(-12);}esp_flash_scratch=p;}ef_mark_iram();
    error=ef_run(0,0,0,cycles);if error {return ef_unlock(error);}let p=esp_flash_scratch+192;let density=load8(p+2);if !load8(p) || load8(p)==255 || density<20 || density>24 {return ef_unlock(-19);}
    let capacity=1<<density;if start+size>capacity {return ef_unlock(-22);}esp_flash_status=load8(esp_flash_scratch+256)|(load8(esp_flash_scratch+257)<<8);esp_flash_capacity=capacity;esp_flash_jedec=load8(p)|(load8(p+1)<<8)|(density<<16);esp_flash_start=start;esp_flash_size=size;return ef_unlock(0);
}
fn ef_bounds(offset,size,cycles) {return esp_flash_size && offset>=0 && size>=0 && offset<=esp_flash_size && size<=esp_flash_size-offset && ef_timeout_valid(cycles);}
fn esp_flash_read(offset,buffer,size,cycles) {
    if !ef_bounds(offset,size,cycles) || !ef_ram(buffer,size) || !ef_no_alias(buffer,size) {return -22;}let error=ef_lock();if error {return error;}let at=0;while at<size {let n=size-at;if n>64 {n=64;}error=ef_run(1,esp_flash_start+offset+at,n,cycles);if error {return ef_unlock(error);}ef_copy(buffer+at,esp_flash_scratch+192,n);at=at+n;}return ef_unlock(size);
}
fn esp_flash_program(offset,buffer,size,cycles) {
    if !ef_bounds(offset,size,cycles) || !ef_input_range(buffer,size) || !ef_no_alias(buffer,size) {return -22;}let error=ef_lock();if error {return error;}
    // Preflight every byte before issuing any program command. A forbidden
    // zero-to-one transition leaves the entire requested range unchanged.
    let at=0;while at<size {let n=size-at;if n>64 {n=64;}error=ef_run(1,esp_flash_start+offset+at,n,cycles);if error {return ef_unlock(error);}let j=0;while j<n {let value=load8(buffer+at+j);if (load8(esp_flash_scratch+192+j)&value)!=value {return ef_unlock(-30);}j=j+1;}at=at+n;}
    at=0;while at<size {let address=esp_flash_start+offset+at;let n=size-at;if n>64 {n=64;}if n>256-(address&255) {n=256-(address&255);}ef_copy(esp_flash_scratch+128,buffer+at,n);error=ef_run(2,address,n,cycles);if error {return ef_unlock(error);}at=at+n;}return ef_unlock(size);
}
fn esp_flash_erase(offset,size,cycles) {
    if !ef_bounds(offset,size,cycles) || (offset&4095) || size<4096 || (size&4095) {return -22;}let error=ef_lock();if error {return error;}let at=0;while at<size {error=ef_run(3,esp_flash_start+offset+at,0,cycles);if error {return ef_unlock(error);}at=at+4096;}return ef_unlock(size);
}

// Explicit volatile write window. Only the confirmed Puya852016 profile needs
// status changes; already-unprotected NOR parts require no status write.
// Closing restores the original protection bits. Region guards remain active.
fn esp_flash_write_access(enable,cycles) {
    if (enable!=0 && enable!=1) || !ef_timeout_valid(cycles) {return -22;}if !esp_flash_size {return -107;}let error=ef_lock();if error {return error;}
    if (enable && esp_flash_write_open) || (!enable && !esp_flash_write_open) {return ef_unlock(0);}error=ef_run(0,0,0,cycles);if error {return ef_unlock(error);}let before=ef_status_value(esp_flash_scratch);if before&0x8000 {return ef_unlock(-16);}let value=esp_flash_saved_status;if enable {value=before&~0x407f;}
    if ((before^value)&0x7ffc) {if esp_flash_jedec!=0x162085 {return ef_unlock(-95);}error=ef_run(4,0,value,cycles);esp_flash_status=ef_status_value(esp_flash_scratch);if error {return ef_unlock(error);}}
    else {esp_flash_status=before;}if enable {esp_flash_saved_status=before&0x7ffc;esp_flash_write_open=1;}else {esp_flash_write_open=0;}return ef_unlock(0);
}
