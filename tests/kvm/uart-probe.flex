// Exercise the Linux 8250 existence, loopback and 16450 scratch probes through
// the actual guest IN/OUT exits, including absent legacy serial slots.
fn expect(value) {if !value {port_out8(0x3f8,70);cpu_halt();}return 0;}
fn main() {
    port_out8(0x3fb,0);let ier=port_in8(0x3f9);port_out8(0x3f9,0);expect(port_in8(0x3f9)==0);
    port_out8(0x3f9,15);expect(port_in8(0x3f9)==15);port_out8(0x3f9,ier);
    port_out8(0x3fc,0x1a);expect((port_in8(0x3fe)&0xf0)==0x90);
    port_out8(0x3f8,0xae);expect(port_in8(0x3f8)==0xae);port_out8(0x3fc,0);
    port_out8(0x3fb,0xbf);port_out8(0x3fa,0);port_out8(0x3fb,0);port_out8(0x3fa,1);
    expect((port_in8(0x3fa)&0xc0)==0);
    let scratch=port_in8(0x3ff);port_out8(0x3ff,0xa5);expect(port_in8(0x3ff)==0xa5);
    port_out8(0x3ff,0x5a);expect(port_in8(0x3ff)==0x5a);port_out8(0x3ff,scratch);
    expect(port_in8(0x2f9)==255 && port_in8(0x3e9)==255 && port_in8(0x2e9)==255);
    port_out8(0x2f9,0);expect(port_in8(0x2f9)==255);
    let text="UART probe passed\n";let i=0;while load8(text+i) {port_out8(0x3f8,load8(text+i));i=i+1;}cpu_halt();return 0;
}
