// Two cascaded 8259A controllers, fixed priority and edge-triggered PC/AT IRQs.
// 256-byte state; each 128-byte record: IMR, IRR, ISR, vector base, init phase,
// ICW1, read selection, auto-EOI, poll. Unsupported modes fail explicitly.
fn pc_pic_init(s) {let i=0;while i<256 {store8(s+i,0);i=i+1;}store64(s,255);store64(s+128,255);store64(s+24,8);store64(s+152,0x70);return 0;}
fn pc_pic_first(bits) {let i=0;while i<8 {if bits&(1<<i) {return i;}i=i+1;}return -1;}
fn pc_pic_ready(c) {
    if load64(c+32) {return -1;}
    let irq=pc_pic_first(load64(c+8)&~load64(c));let active=pc_pic_first(load64(c+16));
    if active>=0 && irq>=active {return -1;}return irq;
}
fn pc_pic_cascade(s) {if pc_pic_ready(s+128)>=0 {store64(s+8,load64(s+8)|4);}else {store64(s+8,load64(s+8)&~4);}return 0;}
fn pc_pic_raise(s,irq) {if irq<0 || irq>15 || irq==2 {return 0;}let c=s;if irq>=8 {c=s+128;irq=irq-8;}store64(c+8,load64(c+8)|(1<<irq));pc_pic_cascade(s);return 1;}
fn pc_pic_ack(c,irq) {store64(c+8,load64(c+8)&~(1<<irq));if !load64(c+56) {store64(c+16,load64(c+16)|(1<<irq));}return 0;}
fn pc_pic_vector(s) {pc_pic_cascade(s);let irq=pc_pic_ready(s);if irq<0 {return -1;}if irq==2 {let slave=pc_pic_ready(s+128);if slave<0 {return -1;}return load64(s+152)+slave;}return load64(s+24)+irq;}
fn pc_pic_take(s) {
    let vector=pc_pic_vector(s);if vector<0 {return -1;}let irq=pc_pic_ready(s);pc_pic_ack(s,irq);
    if irq==2 {pc_pic_ack(s+128,pc_pic_ready(s+128));}pc_pic_cascade(s);return vector;
}
fn pc_pic_command(c,value) {
    if value&16 {
        if (value&0xea) || !(value&1) {return -1;}
        store64(c,0);store64(c+8,0);store64(c+16,0);store64(c+32,2);store64(c+40,value);store64(c+48,0);store64(c+56,0);store64(c+64,0);return 1;
    }
    if value&8 {
        if value&0xe0 {return -1;}
        if value&2 {store64(c+48,value&1);}if value&4 {store64(c+64,1);}return 1;
    }
    if value&128 {return -1;} // rotating priority is not implemented
    if value&32 {let irq=pc_pic_first(load64(c+16));if value&64 {irq=value&7;}if irq>=0 {store64(c+16,load64(c+16)&~(1<<irq));}return 1;}
    if value&64 {return -1;}return 1;
}
fn pc_pic_io(s,port,width,out,data,count) {
    if width!=1 || (port!=0x20 && port!=0x21 && port!=0xa0 && port!=0xa1) {return 0;}
    let c=s;if port>=0xa0 {c=s+128;}let i=0;while i<count {
        if out {
            let value=load8(data+i);
            if !(port&1) {if pc_pic_command(c,value)<0 {return -1;}}
            else {let phase=load64(c+32);
                if phase==2 {store64(c+24,value&248);store64(c+32,3);}
                else if phase==3 {let expected=4;if c!=s {expected=2;}if value!=expected {return -1;}store64(c+32,4);}
                else if phase==4 {if !(value&1) || (value&0xfc) {return -1;}store64(c+56,(value>>1)&1);store64(c+32,0);}
                else {store64(c,value);}
            }
        }else {
            let value=load64(c);
            if !(port&1) {
                if load64(c+64) {store64(c+64,0);let irq=pc_pic_ready(c);value=0;if irq>=0 {pc_pic_ack(c,irq);value=128|irq;}}
                else {value=load64(c+8);if load64(c+48) {value=load64(c+16);}}
            }store8(data+i,value);
        }pc_pic_cascade(s);i=i+1;
    }return 1;
}
