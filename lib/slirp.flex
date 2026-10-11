import "ffi.flex";
import "slirp-callbacks.flex";
// Optional userspace Ethernet/NAT backend using standalone libslirp, not QEMU.
// IPv4 10.0.2.0/24: gateway .2, DNS .3, DHCP starts .15. No host forwarding,
// TFTP, legacy emulation or host-loopback access. IPv6 is not enabled.
// Host-owned state[524288]: library, stack, RX head/tail, drops, guest errors,
// poll count/overflow, callbacks at 80, config at 88, code at 96, symbols at
// 104..136. pollfd[1024] at 512; RX[128][length64 + payload2040] at 16384.
global sn_message=0;
fn sn_close(s) {
    if !s {return 0;}if load64(s+8) {ffi_call(load64(s+112),load64(s+8),0,0,0,0,0);}
    if load64(s+80) {syscall(11,load64(s+80),104,0,0,0,0);}if load64(s+88) {syscall(11,load64(s+88),192,0,0,0,0);}if load64(s+96) {syscall(11,load64(s+96),4096,0,0,0,0);}
    if load64(s) {ffi_close(load64(s));}syscall(11,s,524288,0,0,0,0);return 0;
}
fn sn_create(restricted) {
    sn_message=0;let s=alloc(524288);if s<0 {sn_message="Cannot allocate userspace network state.";return 0;}
    let library=ffi_open("libslirp.so.0");if !library {sn_message="User networking requires libslirp.so.0.";sn_close(s);return 0;}store64(s,library);
    store64(s+104,ffi_symbol(library,"slirp_new"));store64(s+112,ffi_symbol(library,"slirp_cleanup"));store64(s+120,ffi_symbol(library,"slirp_input"));store64(s+128,ffi_symbol(library,"slirp_pollfds_fill"));store64(s+136,ffi_symbol(library,"slirp_pollfds_poll"));
    if !load64(s+104) || !load64(s+112) || !load64(s+120) || !load64(s+128) || !load64(s+136) {sn_message="Required libslirp API is unavailable.";sn_close(s);return 0;}
    let cb=alloc(104);let config=alloc(192);let code=alloc(4096);if cb>=0 {store64(s+80,cb);}if config>=0 {store64(s+88,config);}if code>=0 {store64(s+96,code);}
    if cb<0 || config<0 || code<0 || !sn_helpers(code) {sn_message="Cannot allocate/seal network callbacks.";sn_close(s);return 0;}
    store64(cb,code);store64(cb+8,code+400);store64(cb+16,code+256);let i=24;while i<=64 {store64(cb+i,code+384);i=i+8;}
    // SlirpConfig v1, Linux x86-64 layout verified against installed headers.
    store8(config,1);store8(config+4,restricted!=0);store8(config+8,1);
    store8(config+12,10);store8(config+14,2);store8(config+16,255);store8(config+17,255);store8(config+18,255);
    store8(config+20,10);store8(config+22,2);store8(config+23,2);
    store8(config+96,10);store8(config+98,2);store8(config+99,15);store8(config+100,10);store8(config+102,2);store8(config+103,3);
    store64(config+136,1500);store64(config+144,1500);store8(config+152,1);
    let stack=ffi_call(load64(s+104),config,cb,s,0,0,0);if !stack {sn_message="Cannot initialize libslirp IPv4 stack.";sn_close(s);return 0;}store64(s+8,stack);return s;
}
fn sn_input(s,packet,bytes) {
    if !s || bytes<14 || bytes>2040 {sn_message="Ethernet frame exceeds the network backend bounds.";return -1;}
    ffi_call(load64(s+120),load64(s+8),packet,bytes,0,0,0);return 1;
}
fn sn_poll(s) {
    if !s {return 1;}store64(s+48,0);store64(s+56,0);let timeout=s+144;store64(timeout,0);
    let code=load64(s+96);ffi_call(load64(s+128),load64(s+8),timeout,code+512,s,0,0);
    if load64(s+56) {sn_message="Userspace networking exceeded its socket poll limit.";return -1;}
    let result=syscall(7,s+512,load64(s+48),0,0,0,0);if result==-4 {return 1;}
    ffi_call(load64(s+136),load64(s+8),result<0,code+768,s,0,0);if result<0 {sn_message="Network socket polling failed.";return -1;}return 1;
}
fn sn_peek(s) {if !s || load64(s+16)==load64(s+24) {return 0;}return s+16384+(load64(s+16)&127)*2048+8;}
fn sn_length(s) {let p=sn_peek(s);if !p {return 0;}return load64(p-8);}
fn sn_pop(s) {if sn_peek(s) {store64(s+16,load64(s+16)+1);}return 0;}
// The library stream preserves DHCP leases and its migration-supported state.
// External TCP/UDP sockets are not restored by this API. Callers must state
// that limitation explicitly; a successful stream is not a lossless VM save.
fn sn_state_version(s) {let f=ffi_symbol(load64(s),"slirp_state_version");if !f {sn_message="libslirp state API is unavailable.";return -1;}return ffi_call_i32(f,0,0,0,0,0,0);}
fn sn_state_save(s,buffer,capacity) {
    if !s || !buffer || capacity<1 || capacity>1048576 {sn_message="Invalid network state buffer.";return -1;}
    let f=ffi_symbol(load64(s),"slirp_state_save");if !f {sn_message="libslirp save API is unavailable.";return -1;}
    let context=alloc(32);if context<0 {sn_message="Cannot allocate network stream context.";return -1;}store64(context,buffer);store64(context+8,capacity);
    let result=ffi_call_i32(f,load64(s+8),load64(s+96)+1024,context,0,0,0);let bytes=load64(context+16);let error=load64(context+24);syscall(11,context,32,0,0,0,0);
    if result<0 || error {sn_message="Cannot save bounded libslirp state.";return -1;}return bytes;
}
fn sn_state_load(s,version,buffer,bytes) {
    if !s || !buffer || bytes<1 || bytes>1048576 || version!=sn_state_version(s) {sn_message="Invalid network state stream/version.";return -1;}
    let f=ffi_symbol(load64(s),"slirp_state_load");if !f {sn_message="libslirp load API is unavailable.";return -1;}
    let context=alloc(32);if context<0 {sn_message="Cannot allocate network stream context.";return -1;}store64(context,buffer);store64(context+8,bytes);
    let result=ffi_call_i32(f,load64(s+8),version,load64(s+96)+1152,context,0,0);let consumed=load64(context+16);let error=load64(context+24);syscall(11,context,32,0,0,0,0);
    if result<0 || error || consumed!=bytes {sn_message="Cannot load complete bounded libslirp state.";return -1;}return 1;
}
