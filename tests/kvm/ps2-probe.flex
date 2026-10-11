// Controller/device discovery through the monitor's actual guest I/O exits.
fn expect(v) {if !v {port_out8(0x3f8,70);cpu_halt();}return 0;}
fn read(aux,value) {expect((port_in8(0x64)&33)==(1+aux*32));expect(port_in8(0x60)==value);return 0;}
fn mouse(command) {port_out8(0x64,0xd4);port_out8(0x60,command);return 0;}
fn main() {
    expect(!(port_in8(0x64)&3));port_out8(0x64,0xaa);read(0,0x55);
    port_out8(0x64,0x20);read(0,0x34);port_out8(0x64,0x60);port_out8(0x60,7);
    port_out8(0x64,0xa9);read(0,0);port_out8(0x64,0xab);read(0,0);
    port_out8(0x64,0xd3);port_out8(0x60,0xf0);read(1,0xf0);
    port_out8(0x64,0xd3);port_out8(0x60,0x56);read(1,0x56);
    port_out8(0x64,0xd3);port_out8(0x60,0xa4);read(1,0xa4);
    port_out8(0x60,0xf2);read(0,0xfa);read(0,0xab);read(0,0x83);
    port_out8(0x60,0xf0);read(0,0xfa);port_out8(0x60,0);read(0,0xfa);read(0,2);
    mouse(0xff);read(1,0xfa);read(1,0xaa);read(1,0);mouse(0xf4);read(1,0xfa);
    mouse(0xe9);read(1,0xfa);read(1,32);read(1,2);read(1,100);
    let text="PS/2 probe passed\n";let i=0;while load8(text+i) {port_out8(0x3f8,load8(text+i));i=i+1;}cpu_halt();return 0;
}
