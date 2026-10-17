// PC/AT COM1 with 16450 registers and one-byte receive holding register.
// No FIFO is advertised. Transmission completes synchronously at the host sink.
// 96 bytes: LCR, IER, MCR, SCR, DLL, DLM, RX (-1 empty), LSR errors,
// MSR (including deltas), pending THRE, previous IRQ output, TX (-1 empty).
fn pc_uart_init(s) {let i=0;while i<96 {store8(s+i,0);i=i+1;}store64(s+48,-1);store64(s+64,0xb0);store64(s+88,-1);return 0;}
fn pc_uart_receive(s,value) {
    if load64(s+48)>=0 {store64(s+56,load64(s+56)|2);return 0;}
    store64(s+48,value&255);return 1;
}
fn pc_uart_cause(s) {
    let ier=load64(s+8);
    if (ier&4) && load64(s+56) {return 6;}
    if (ier&1) && load64(s+48)>=0 {return 4;}
    if (ier&2) && load64(s+72) {return 2;}
    if (ier&8) && (load64(s+64)&15) {return 0;}
    return 1;
}
fn pc_uart_irq(s) {
    let level=(load64(s+16)&8)!=0 && pc_uart_cause(s)!=1;let old=load64(s+80);store64(s+80,level);return level && !old;
}
fn pc_uart_modem(s,mcr) {
    let previous=load64(s+64);let lines=0xb0;
    if mcr&16 {lines=((mcr&2)<<3)|((mcr&1)<<5)|((mcr&4)<<4)|((mcr&8)<<4);}
    let changed=(previous^lines)&0xf0;let delta=(changed>>4)&11;
    if (previous&64) && !(lines&64) {delta=delta|4;}
    store64(s+64,lines|(previous&15)|delta);return 0;
}
fn pc_uart_write(s,reg,value) {
    value=value&255;
    if reg==0 {
        if load64(s)&128 {store64(s+32,value);}
        else {if load64(s+16)&16 {pc_uart_receive(s,value);}else {store64(s+88,value);}store64(s+72,1);}
    }
    else if reg==1 {
        if load64(s)&128 {store64(s+40,value);}
        else {if (value&2) && !(load64(s+8)&2) {store64(s+72,1);}store64(s+8,value&15);}
    }
    // FCR writes are ignored, as on the 16450. IIR has no FIFO bits.
    else if reg==3 {store64(s,value);}
    else if reg==4 {store64(s+16,value&31);pc_uart_modem(s,value&31);}
    else if reg==7 {store64(s+24,value);}
    return 0;
}
fn pc_uart_read(s,reg) {
    if reg==0 {if load64(s)&128 {return load64(s+32);}let value=load64(s+48);store64(s+48,-1);if value<0 {return 0;}return value;}
    if reg==1 {if load64(s)&128 {return load64(s+40);}return load64(s+8);}
    if reg==2 {let cause=pc_uart_cause(s);if cause==2 {store64(s+72,0);}return cause;}
    if reg==3 {return load64(s);}
    if reg==4 {return load64(s+16);}
    if reg==5 {let value=0x60|load64(s+56);if load64(s+48)>=0 {value=value|1;}store64(s+56,0);return value;}
    if reg==6 {let value=load64(s+64);store64(s+64,value&0xf0);return value;}
    if reg==7 {return load64(s+24);}return 255;
}
fn pc_uart_transmit(s) {let value=load64(s+88);store64(s+88,-1);return value;}
