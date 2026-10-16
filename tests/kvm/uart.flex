import "../../emulator/pc/uart.flex";
import "../../emulator/pc/pic.flex";
fn expect(v) {if !v {syscall(60,1,0,0,0,0,0);}return 0;}
fn main() {
    let s=alloc(96);let pic=alloc(256);pc_uart_init(s);pc_pic_init(pic);
    expect(pc_uart_read(s,2)==1 && pc_uart_read(s,5)==0x60);
    // DLAB separates baud divisors from IER and holding registers.
    pc_uart_write(s,3,0x80);pc_uart_write(s,0,12);pc_uart_write(s,1,3);
    expect(pc_uart_read(s,0)==12 && pc_uart_read(s,1)==3 && pc_uart_transmit(s)==-1);
    pc_uart_write(s,3,3);expect(pc_uart_read(s,1)==0);
    pc_uart_write(s,7,0x5a);expect(pc_uart_read(s,7)==0x5a);pc_uart_write(s,7,0xa5);expect(pc_uart_read(s,7)==0xa5);
    pc_uart_write(s,2,1);expect(pc_uart_read(s,2)==1); // no FIFO advertised
    // Loopback is used by the Linux UART probe: no host output, modem mapping.
    pc_uart_write(s,4,0x1e);expect((pc_uart_read(s,6)&0xf0)==0xd0);
    pc_uart_write(s,0,0xae);expect(pc_uart_transmit(s)==-1 && pc_uart_read(s,5)==0x61 && pc_uart_read(s,0)==0xae);
    pc_uart_write(s,4,0x10);expect(pc_uart_read(s,6)==0x0d && pc_uart_read(s,6)==0);
    // RX preserves the first unread byte and reports overrun on a second byte.
    pc_uart_write(s,1,5);expect(pc_uart_receive(s,65));expect(!pc_uart_receive(s,66));expect(pc_uart_read(s,2)==6);
    expect(pc_uart_read(s,5)==0x63 && pc_uart_read(s,2)==4 && pc_uart_read(s,0)==65 && pc_uart_read(s,2)==1);
    // OUT2 gates the PC interrupt pin; THRE IIR read acknowledges its source.
    pc_uart_write(s,1,2);expect(!pc_uart_irq(s));pc_uart_write(s,4,8);expect(pc_uart_irq(s));expect(!pc_uart_irq(s));
    expect(pc_uart_read(s,2)==2 && pc_uart_read(s,2)==1 && !pc_uart_irq(s));
    pc_uart_write(s,0,90);expect(pc_uart_transmit(s)==90 && pc_uart_transmit(s)==-1);expect(pc_uart_irq(s));expect(pc_uart_read(s,2)==2);expect(!pc_uart_irq(s));
    // A serial RX interrupt traverses the same edge-triggered PIC as the PIT.
    store64(pic,0xef);store64(pic+24,32);pc_uart_write(s,1,1);expect(pc_uart_receive(s,88));
    if pc_uart_irq(s) {pc_pic_raise(pic,4);}expect(pc_pic_vector(pic)==36 && pc_pic_take(pic)==36);
    expect(pc_uart_read(s,0)==88 && !pc_uart_irq(s));
    syscall(11,s,96,0,0,0,0);syscall(11,pic,256,0,0,0,0);return 0;
}
