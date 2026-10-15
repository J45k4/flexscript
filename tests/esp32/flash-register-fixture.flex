// Independent classic ESP32 register/NOR oracle. The test runner substitutes
// only the target-specific SRAM-placement annotation; production I/O is intact.
import "flash-model-driver.flex";
global fm_regs=0;
global fm_disk=0;
global fm_ps=0x40020;
global fm_cache=1;
global fm_cycles=0;
global fm_wel=0;
global fm_status=0;
global fm_volatile=0;
global fm_status_writes=0;
global fm_nonvolatile_writes=0;
global fm_single_status=0;
global fm_reject_status=0;
global fm_reject_restore=0;
global fm_bad_status=0;
global fm_require_qe=0;
global fm_busy=0;
global fm_stuck=0;
global fm_reject_wel=0;
global fm_protect=0;
global fm_id=0x1640c8;
global fm_image=0x50000;
global fm_pages=1;
global fm_cpu=0;
global fm_crypto=0;
global fm_secure=0;
global fm_commands=0;
global fm_programs=0;
global fm_erases=0;
global fm_rom=0;
global fm_failed=0;
fn fm_check(ok) {if !ok {fm_failed=fm_failed+1;}return 0;}
fn fm_get(address) {return load64(fm_regs+(address-0x3ff42000)*2);}
fn fm_set(address,value) {store64(fm_regs+(address-0x3ff42000)*2,value&4294967295);return 0;}
fn esp32_state() {return 0x3ffb0010;}
fn esp32_cycles() {fm_cycles=(fm_cycles+10)&4294967295;return fm_cycles;}
fn esp32_irq_save() {let old=fm_ps;fm_ps=fm_ps|15;return old;}
fn esp32_irq_restore(ps) {fm_check(fm_cache==1);fm_ps=ps;return 0;}
fn esp32_halt() {fm_check(!fm_cache && (fm_ps&15)==15);syscall(60,80+esp_flash_fatal,0,0,0,0,0);return 0;}
fn fm_equal(a,b) {let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);}
fn esp32_external(name) {if fm_equal(name,"_flex_drom_flash") {return fm_image;}if fm_equal(name,"_flex_drom_pages") {return fm_pages;}fm_failed=fm_failed+1;return 0;}
fn esp32_call32(address,a,b,c,d,e,f,g,h) {
    fm_check(!(a|b|c|d|e|f|g|h) && (fm_ps&15)==15);fm_rom=fm_rom+1;
    if address==0x40009ab8 {fm_check(fm_cache==1);fm_cache=0;if syscall(10,0x3f400000,4096,0,0,0,0) {fm_failed=fm_failed+1;}}
    else if address==0x40009a14 {fm_check(!fm_cache);}
    else if address==0x40009a84 {fm_check(!fm_cache && (!fm_require_qe || (fm_status&0x200)));fm_cache=1;if syscall(10,0x3f400000,4096,1,0,0,0) {fm_failed=fm_failed+1;}}
    else {fm_failed=fm_failed+1;}return 0;
}
fn esp32_load32(address) {
    if address==0x3ff4001c {fm_check(!fm_cache && (fm_ps&15)==15);return 0;}
    if address>=0x3ffb0000 && address<0x3ffc0000 {return load8(address)|(load8(address+1)<<8)|(load8(address+2)<<16)|(load8(address+3)<<24);}
    if address==0x3ff0002c {return 0;}if address==0x3ff00030 {return fm_cpu;}if address==0x3ff00034 {return 0;}
    if address==0x3ff5a000 {return fm_crypto;}if address==0x3ff5a018 {return fm_secure;}
    fm_check(address>=0x3ff42000 && address<0x3ff42100 && !(address&3) && !fm_cache && (fm_ps&15)==15);
    if address==0x3ff42000 && fm_stuck==1 {return 1<<18;}return fm_get(address);
}
fn fm_receive(value,index) {let address=0x3ff42080+(index/4)*4;let shift=(index&3)*8;let old=fm_get(address);fm_set(address,(old&~(255<<shift))|(value<<shift));return 0;}
fn fm_transmit(index) {return (fm_get(0x3ff42080+(index/4)*4)>>((index&3)*8))&255;}
fn fm_command() {
    fm_commands=fm_commands+1;let user=fm_get(0x3ff4201c);let command=fm_get(0x3ff42024);fm_check((command>>28)==7 && !(command&0x0fff0000));command=command&65535;
    fm_check((user&((1<<31)|48))==((1<<31)|48) && !(user&((1<<29)|(1<<25)|(1<<24)|(1<<16)|0xf001)));
    fm_check(fm_get(0x3ff42018)==((3<<12)|(1<<6)|3) && fm_get(0x3ff42034)==6 && !(fm_get(0x3ff42008)&0x07906000));
    let address=fm_get(0x3ff42004)>>8;let n=0;if user&(1<<28) {n=(fm_get(0x3ff4202c)+1)/8;}if user&(1<<27) {n=(fm_get(0x3ff42028)+1)/8;}
    if fm_volatile {fm_check(command==1);}
    if command==5 {fm_check(n==1 && !(user&(1<<30)));let status=(fm_status&252)|fm_wel*2;if fm_busy || fm_stuck==2 {status=status|1;if fm_busy {fm_busy=fm_busy-1;}}fm_receive(status,0);}
    else if command==0x35 {fm_check(n==1 && !(user&(1<<30)));fm_receive((fm_status>>8)&255,0);}
    else if command==6 {fm_check(!(user&((1<<30)|(1<<28)|(1<<27))));if !fm_reject_wel {fm_wel=1;}}
    else if command==4 {fm_wel=0;}
    else if command==0x50 {fm_check(!fm_wel && !n && !(user&(1<<30)));fm_volatile=1;}
    else if command==1 {fm_check((n==1 || n==2) && fm_volatile && !fm_wel && !(user&(1<<30)));if !fm_volatile {fm_nonvolatile_writes=fm_nonvolatile_writes+1;}fm_status_writes=fm_status_writes+1;
        if !fm_reject_status && !(fm_reject_restore && (fm_transmit(0)&0x7c)) && (!fm_single_status || n==1) {let sr=fm_transmit(0);if n==2 {sr=sr|(fm_transmit(1)<<8);}if fm_bad_status {sr=sr&~0x200;if fm_bad_status==1 {fm_bad_status=0;}}fm_status=sr&65532;}fm_volatile=0;
    }
    else if command==0x9f {fm_check(n==3 && !(user&(1<<30)));let i=0;while i<3 {fm_receive((fm_id>>(i*8))&255,i);i=i+1;}}
    else if command==3 || command==2 || command==0x20 {fm_check(user&(1<<30) && fm_get(0x3ff42020)==(23<<26) && !(fm_get(0x3ff42004)&255) && address<0x400000);
        if command==3 {fm_check(n>=1 && n<=64 && address+n<=0x400000);let i=0;while i<n {fm_receive(load8(fm_disk+address+i),i);i=i+1;}}
        else if command==2 {fm_check(fm_wel && n>=1 && n<=64 && (address&255)+n<=256 && address>=1048576 && address+n<=0x3e2000);fm_programs=fm_programs+1;if !fm_protect && !(fm_status&0x407c) {let i=0;while i<n {let byte=fm_transmit(i);fm_check((load8(fm_disk+address+i)&byte)==byte);store8(fm_disk+address+i,load8(fm_disk+address+i)&byte);i=i+1;}}fm_wel=0;fm_busy=2;}
        else {fm_check(fm_wel && !(address&4095) && address>=1048576 && address+4096<=0x3e2000);fm_erases=fm_erases+1;if !fm_protect && !(fm_status&0x407c) {let i=0;while i<4096 {store8(fm_disk+address+i,255);i=i+1;}}fm_wel=0;fm_busy=2;}
    }else {fm_failed=fm_failed+1;}
}
fn esp32_store32(address,value) {
    if address==0x3ff40000 {fm_check(!fm_cache && (fm_ps&15)==15);return 0;}
    fm_check(address>=0x3ff42000 && address<0x3ff42100 && !(address&3) && !fm_cache && (fm_ps&15)==15);fm_set(address,value);
    if address==0x3ff42000 {fm_check(value==(1<<18));fm_command();fm_set(address,0);}return 0;
}
fn fm_restored() {let i=0;while i<8 {let expect=0xa5000000+i;fm_check(fm_get(ef_config_address(i))==expect);i=i+1;}fm_check(fm_cache==1 && fm_ps==0x40020 && !esp_flash_busy);return fm_failed==0;}
fn fm_run(argc,argv) {
    if syscall(9,0x3ffb0000,65536,3,50,-1,0)!=0x3ffb0000 || syscall(9,0x3f400000,4096,3,50,-1,0)!=0x3f400000 {return 1;}esp_flash_scratch=0x3ffb1000;fm_regs=alloc(4096);fm_disk=alloc(4194304);let i=0;while i<4194304 {store8(fm_disk+i,255);i=i+1;}i=0;while i<8 {fm_set(ef_config_address(i),0xa5000000+i);i=i+1;}
    let data=0x3ffb2000;let source=0x3f400000;ef_copy(source,"cached flash source",19);if syscall(10,source,4096,1,0,0,0) {return 2;}let cycles=10000;
    if argc>1 {let mode=load64(argv+8);if load8(mode)==51 {fm_id=0x162085;fm_status=0x021c;fm_require_qe=1;fm_bad_status=2;if esp_flash_region(0x3e0000,8192,cycles) {return 26;}esp_flash_write_access(1,cycles);return 27;}if load8(mode)==49 {fm_stuck=1;}else {fm_stuck=2;}esp_flash_region(0x3e0000,8192,50);return 3;}
    if esp_flash_region(0x3e0000,8192,cycles) || esp_flash_jedec!=fm_id || esp_flash_capacity!=4194304 || !fm_restored() {return 4;}
    if esp_flash_program(4093,source,19,cycles)!=19 || esp_flash_read(4093,data,19,cycles)!=19 {return 5;}i=0;while i<19 {if load8(data+i)!=load8(source+i) {return 6;}i=i+1;}if !fm_restored() {return 7;}
    i=0;while i<513 {store8(data+i,(i*37+11)&255);i=i+1;}if esp_flash_program(239,data,513,cycles)!=513 || !fm_restored() {return 8;}i=0;while i<513 {if load8(fm_disk+0x3e0000+239+i)!=((i*37+11)&255) {return 9;}i=i+1;}
    let writes=fm_programs;i=0;while i<65 {store8(data+i,0);i=i+1;}store8(data+64,255);if esp_flash_program(239,data,65,cycles)!= -30 || fm_programs!=writes || load8(fm_disk+0x3e0000+239)!=11 || !fm_restored() {return 10;}
    fm_reject_wel=1;if esp_flash_program(1000,source,19,cycles)!= -13 || !fm_restored() {return 11;}fm_reject_wel=0;fm_protect=1;if esp_flash_program(1000,source,19,cycles)!= -5 || !fm_restored() || esp_flash_erase(0,4096,cycles)!= -5 || !fm_restored() {return 12;}fm_protect=0;
    fm_cycles=0xfffffff0;if esp_flash_erase(0,8192,cycles)!=8192 || !fm_restored() {return 13;}i=0;while i<8192 {if load8(fm_disk+0x3e0000+i)!=255 {return 14;}i=i+1;}
    fm_image=0x180000;fm_pages=2;if esp_flash_protected_end()!=0x1a0000 || esp_flash_region(0x190000,4096,cycles)!= -22 || esp_flash_region(0x1a0000,4096,cycles) {return 15;}
    let commands=fm_commands;fm_cpu=1;if esp_flash_read(0,data,1,cycles)!= -16 {return 16;}fm_cpu=0;fm_crypto=1<<20;if esp_flash_read(0,data,1,cycles)!= -95 {return 17;}fm_crypto=0;fm_secure=16;if esp_flash_read(0,data,1,cycles)!= -95 {return 18;}fm_secure=0;store8(esp32_state()+16,1);if esp_flash_read(0,data,1,cycles)!= -16 {return 19;}store8(esp32_state()+16,0);esp_flash_busy=1;if esp_flash_read(0,data,1,cycles)!= -16 {return 20;}esp_flash_busy=0;
    if fm_commands!=commands || esp_flash_region(0,4096,cycles)!= -22 || esp_flash_read(4095,data,2,cycles)!= -22 || esp_flash_program(0,esp_flash_scratch,1,cycles)!= -22 || esp_flash_read(0,source,1,cycles)!= -22 || esp_flash_read(0,data,1,0)!= -22 || !fm_restored() {return 21;}
    fm_id=0xffffff;if esp_flash_region(0x3e0000,8192,cycles)!= -19 || esp_flash_start!=0x1a0000 || !fm_restored() {return 22;}
    fm_id=0x1440c8;if esp_flash_region(0x3e0000,8192,cycles)!= -22 || esp_flash_start!=0x1a0000 || !fm_restored() {return 23;}
    if fm_failed {return 25;}if !fm_programs || fm_erases!=3 || fm_rom%3 {return 24;}
    // Actual flash-boot BP bits and a preexisting QE bit must survive the
    // explicit volatile write window; no nonvolatile status writes are allowed.
    fm_id=0x162085;fm_status=0x021c;fm_require_qe=1;if esp_flash_region(0x3e0000,8192,cycles) || esp_flash_status!=0x021c || esp_flash_write_access(1,cycles) || fm_status!=0x0200 || !esp_flash_write_open || !fm_restored() {return 28;}
    let sr_writes=fm_status_writes;if esp_flash_write_access(1,cycles) || fm_status_writes!=sr_writes || esp_flash_region(0x3e0000,8192,cycles)!= -16 || esp_flash_program(1000,source,19,cycles)!=19 || esp_flash_write_access(0,cycles) || fm_status!=0x021c || esp_flash_write_open || !fm_restored() {return 29;}
    if esp_flash_write_access(0,cycles) || esp_flash_write_access(2,cycles)!= -22 || esp_flash_write_access(1,0)!= -22 {return 30;}
    fm_require_qe=0;fm_status=0x1c;fm_single_status=1;sr_writes=fm_status_writes;if esp_flash_write_access(1,cycles) || fm_status || fm_status_writes!=sr_writes+2 || esp_flash_write_access(0,cycles) || fm_status!=0x1c || !fm_restored() {return 31;}
    fm_require_qe=1;fm_status=0x021c;sr_writes=fm_status_writes;if esp_flash_write_access(1,cycles)!= -13 || fm_status_writes!=sr_writes+1 || fm_status!=0x021c || esp_flash_write_open || !fm_restored() {return 32;}fm_single_status=0;
    fm_bad_status=1;if esp_flash_write_access(1,cycles)!= -13 || fm_status!=0x021c || esp_flash_write_open || !fm_restored() {return 33;}
    fm_require_qe=0;fm_status=0x1c;fm_id=0x1640c8;if esp_flash_region(0x3e0000,8192,cycles) || esp_flash_write_access(1,cycles)!= -95 || fm_status!=0x1c || !fm_restored() {return 34;}
    fm_status=0x8000;if esp_flash_write_access(1,cycles)!= -16 || !fm_restored() {return 35;}if fm_nonvolatile_writes || fm_volatile || fm_failed {return 36;}return 0;
}
