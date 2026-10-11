// i8042 controller with a raw set-2 PS/2 keyboard and standard three-byte mouse.
// 512 bytes, queue of 64 (byte, AUX flag) records at 256. Synchronous commands;
// IRQ1/IRQ12 are edge-raised when a new output-buffer byte becomes visible.
// Translation, active multiplexing, wheel protocols and machine reset are absent.
fn pc_ps2_init(s) {
    let i=0;while i<512 {store8(s+i,0);i=i+1;}
    store64(s+16,0x34);store64(s+24,3);store64(s+64,1);store64(s+72,2);store64(s+88,0x2b);store64(s+104,2);store64(s+112,100);return 0;
}
fn pc_ps2_room(s,n) {return load64(s+8)-load64(s)+n<=64;}
fn pc_ps2_put(s,value,aux) {
    if !pc_ps2_room(s,1) {return -1;}let tail=load64(s+8);let p=s+256+(tail&63)*2;store8(p,value);store8(p+1,aux);store64(s+8,tail+1);store64(s+144+aux*8,value&255);return 1;
}
fn pc_ps2_status(s) {
    let status=16|(load64(s+16)&4)|(load64(s+32)*8);
    if load64(s)!=load64(s+8) {status=status|1;if load8(s+257+(load64(s)&63)*2) {status=status|32;}}
    return status;
}
fn pc_ps2_read(s) {
    let head=load64(s);if head==load64(s+8) {return 255;}let value=load8(s+256+(head&63)*2);store64(s,head+1);store64(s+120,0);return value;
}
fn pc_ps2_irq(s) {
    let irq=0;if load64(s)!=load64(s+8) {let aux=load8(s+257+(load64(s)&63)*2);if load64(s+16)&(1<<aux) {irq=1;if aux {irq=12;}}}
    let previous=load64(s+120);store64(s+120,irq);if irq!=previous {return irq;}return 0;
}
fn pc_ps2_keyboard(s,value) {
    if !pc_ps2_room(s,3) {return -1;}
    let pending=load64(s+48);store64(s+48,0);
    if pending {
        if pending==0xf0 {
            if value==0 {pc_ps2_put(s,0xfa,0);return pc_ps2_put(s,2,0);}
            if value!=2 {return pc_ps2_put(s,0xfe,0);}store64(s+72,2);
        }else if pending==0xed {store64(s+80,value&7);}else if pending==0xf3 {store64(s+88,value&127);}
        return pc_ps2_put(s,0xfa,0);
    }
    if value==0xfe {return pc_ps2_put(s,load64(s+144),0);}
    if value==0xee {return pc_ps2_put(s,0xee,0);}
    if value==0xed || value==0xf0 || value==0xf3 {store64(s+48,value);return pc_ps2_put(s,0xfa,0);}
    if value==0xff {store64(s+64,1);store64(s+72,2);store64(s+80,0);store64(s+88,0x2b);pc_ps2_put(s,0xfa,0);return pc_ps2_put(s,0xaa,0);}
    if value==0xf2 {pc_ps2_put(s,0xfa,0);pc_ps2_put(s,0xab,0);return pc_ps2_put(s,0x83,0);}
    if value==0xf4 || value==0xf5 || value==0xf6 {
        store64(s+64,value==0xf4);if value!=0xf4 {store64(s+72,2);store64(s+80,0);store64(s+88,0x2b);}return pc_ps2_put(s,0xfa,0);
    }
    return pc_ps2_put(s,0xfe,0);
}
fn pc_ps2_mouse(s,value) {
    if !pc_ps2_room(s,4) {return -1;}
    if load64(s+200) && value!=0xec && value!=0xff {return pc_ps2_put(s,value,1);}
    let pending=load64(s+56);store64(s+56,0);
    if pending {if pending==0xf3 {store64(s+112,value);}else {if value>3 {return pc_ps2_put(s,0xfe,1);}store64(s+104,value);}return pc_ps2_put(s,0xfa,1);}
    if value==0xfe {return pc_ps2_put(s,load64(s+152),1);}
    if value==0xf3 || value==0xe8 {store64(s+56,value);return pc_ps2_put(s,0xfa,1);}
    if value==0xff || value==0xf6 {store64(s+96,0);store64(s+104,2);store64(s+112,100);store64(s+160,0);store64(s+168,0);store64(s+176,0);store64(s+184,0);store64(s+192,0);store64(s+200,0);}
    if value==0xff {pc_ps2_put(s,0xfa,1);pc_ps2_put(s,0xaa,1);return pc_ps2_put(s,0,1);}
    if value==0xf2 {pc_ps2_put(s,0xfa,1);return pc_ps2_put(s,0,1);}
    if value==0xe9 {let buttons=load64(s+184);pc_ps2_put(s,0xfa,1);pc_ps2_put(s,(load64(s+96)*32)|(load64(s+160)*64)|(load64(s+192)*16)|((buttons&1)<<2)|((buttons&2)>>1)|((buttons&4)>>1),1);pc_ps2_put(s,load64(s+104),1);return pc_ps2_put(s,load64(s+112),1);}
    if value==0xeb {pc_ps2_put(s,0xfa,1);pc_ps2_packet(s,load64(s+168),load64(s+176),load64(s+184));store64(s+168,0);store64(s+176,0);return 1;}
    if value==0xf4 {store64(s+96,1);}else if value==0xf5 {store64(s+96,0);}else if value==0xf0 {store64(s+160,1);}else if value==0xea {store64(s+160,0);}
    else if value==0xe6 || value==0xe7 {store64(s+192,value==0xe7);}
    else if value==0xee || value==0xec {store64(s+200,value==0xee);}
    else if value!=0xf6 {return pc_ps2_put(s,0xfe,1);}return pc_ps2_put(s,0xfa,1);
}
fn pc_ps2_command(s,value) {
    store64(s+32,1);store64(s+40,0);
    if value==0x20 {return pc_ps2_put(s,load64(s+16),0);}
    if value==0x60 || value==0xd1 || value==0xd2 || value==0xd3 || value==0xd4 {store64(s+40,value);return 1;}
    if value==0xaa {store64(s+16,load64(s+16)|4);return pc_ps2_put(s,0x55,0);}
    if value==0xab || value==0xa9 {return pc_ps2_put(s,0,0);}
    if value==0xa7 {store64(s+16,load64(s+16)|32);return 1;}if value==0xa8 {store64(s+16,load64(s+16)&~32);return 1;}
    if value==0xad {store64(s+16,load64(s+16)|16);return 1;}if value==0xae {store64(s+16,load64(s+16)&~16);return 1;}
    if value==0xd0 {return pc_ps2_put(s,load64(s+24),0);}
    if value==0xc0 {return pc_ps2_put(s,0x80,0);}return -1;
}
fn pc_ps2_data(s,value) {
    store64(s+32,0);let pending=load64(s+40);store64(s+40,0);
    if pending==0x60 {if value&64 {return -1;}store64(s+16,value&63);return 1;}
    if pending==0xd1 {if !(value&1) || !(value&2) {return -1;}store64(s+24,value);return 1;}
    if pending==0xd2 || pending==0xd3 {return pc_ps2_put(s,value,pending==0xd3);}
    if pending==0xd4 {return pc_ps2_mouse(s,value);}return pc_ps2_keyboard(s,value);
}
fn pc_ps2_io(s,port,width,out,data,count) {
    if width!=1 || (port!=0x60 && port!=0x64) {return 0;}let i=0;
    while i<count {if out {let result=0;if port==0x64 {result=pc_ps2_command(s,load8(data+i));}else {result=pc_ps2_data(s,load8(data+i));}if result<0 {return -1;}}
        else {let value=pc_ps2_status(s);if port==0x60 {value=pc_ps2_read(s);}store8(data+i,value);}i=i+1;}
    return 1;
}
// Input integration takes raw set-2 make codes; releases carry F0 prefixes.
fn pc_ps2_key(s,code,extended,down) {
    if code<=0 || code>255 || code==0xe0 || code==0xe1 || code==0xf0 {return 0;}
    if !load64(s+64) || (load64(s+16)&16) {return 0;}let n=1;if extended {n=n+1;}if !down {n=n+1;}if !pc_ps2_room(s,n) {return 0;}
    if extended {pc_ps2_put(s,0xe0,0);}if !down {pc_ps2_put(s,0xf0,0);}pc_ps2_put(s,code,0);return 1;
}
fn pc_ps2_packet(s,dx,dy,buttons) {
    if !pc_ps2_room(s,3) {return 0;}
    let flags=8|(buttons&7);if dx<0 {flags=flags|16;}if dy<0 {flags=flags|32;}
    if dx< -255 || dx>255 {flags=flags|64;}if dy< -255 || dy>255 {flags=flags|128;}
    if dx< -255 {dx=-255;}if dx>255 {dx=255;}if dy< -255 {dy=-255;}if dy>255 {dy=255;}
    pc_ps2_put(s,flags,1);pc_ps2_put(s,dx,1);pc_ps2_put(s,dy,1);return 1;
}
fn pc_ps2_scale(value) {let negative=value<0;if negative {value=-value;}if value==2 {value=1;}else if value==4 {value=6;}else if value==5 {value=9;}else if value>5 {value=value*2;}if negative {value=-value;}return value;}
fn pc_ps2_motion(s,dx,dy,buttons) {
    if (load64(s+16)&32) || load64(s+200) || dx< -32767 || dx>32767 || dy< -32767 || dy>32767 {return 0;}
    if load64(s+160) {store64(s+184,buttons&7);let x=load64(s+168)+dx;let y=load64(s+176)+dy;if x< -32767 {x=-32767;}if x>32767 {x=32767;}if y< -32767 {y=-32767;}if y>32767 {y=32767;}store64(s+168,x);store64(s+176,y);return 1;}
    if !load64(s+96) || !pc_ps2_room(s,3) {return 0;}
    store64(s+184,buttons&7);
    if load64(s+192) {dx=pc_ps2_scale(dx);dy=pc_ps2_scale(dy);}return pc_ps2_packet(s,dx,dy,buttons);
}
