fn main() {
    // Print, receive one byte, echo it, then halt. Exercises both exit directions.
    port_out8(0x3fb,3);
    let text="KVM kernel ready\n";let i=0;
    while load8(text+i) {while !(port_in8(0x3fd)&32) {}port_out8(0x3f8,load8(text+i));i=i+1;}
    while !(port_in8(0x3fd)&1) {}
    port_out8(0x3f8,port_in8(0x3f8));port_out8(0x3f8,10);cpu_halt();return 0;
}
