// Boot/runtime regression fixture; compile with --target baremetal-x86_64.
global serial_word=0x123456789abcdef0;
fn serial_byte(c) {while !(port_in8(0x3fd)&32) {}port_out8(0x3f8,c);return 0;}
fn serial_text(s) {let i=0;while load8(s+i) {serial_byte(load8(s+i));i=i+1;}return 0;}
fn sum(n) {if !n {return 0;}return n+sum(n-1);}
fn divide(n,d) {return n/d;}
fn main() {
    port_out8(0x3f9,0);port_out8(0x3fb,128);port_out8(0x3f8,1);port_out8(0x3f9,0);
    port_out8(0x3fb,3);port_out8(0x3fa,199);port_out8(0x3fc,11);
    let slot=0;let id=0;while slot<32 && id!=0x11111234 {port_out32(0xcf8,0x80000000|(slot<<11));id=port_in32(0xcfc);if id!=0x11111234 {slot=slot+1;}}
    if slot==32 {serial_text("FAIL: PCI port I/O\n");cpu_halt();}
    port_out32(0xcf8,0x80000010|(slot<<11));let fb=port_in32(0xcfc)&0xfffffff0;
    store64(fb,0x123456789abcdef0);if load64(fb)!=0x123456789abcdef0 {serial_text("FAIL: PCI framebuffer mapping\n");cpu_halt();}
    port_out16(0x1ce,1);port_out16(0x1cf,800);if port_in16(0x1cf)!=800 {serial_text("FAIL: word port I/O\n");cpu_halt();}
    serial_text("PASS: PCI, 16/32-bit port I/O and framebuffer mapping\n");
    store64(0x1000000,serial_word);serial_word=serial_word+1;
    if load64(0x1000000)!=serial_word-1 || sum(10)!=55 || divide(-71,6)!=-11 {
        serial_text("FAIL: bare-metal runtime\n");cpu_halt();
    }
    serial_text("PASS: bare-metal arithmetic/globals/memory/calls\n");
    let count=0;let c=0;
    while c!=10 {while !(port_in8(0x3fd)&1) {}c=port_in8(0x3f8);serial_byte(c);count=count+1;}
    if count==5 {serial_text("PASS: bare-metal serial input\n");}
    else {serial_text("FAIL: serial input\n");}
    // Returning from main tests the backend's default halt path.
    return 0;
}
