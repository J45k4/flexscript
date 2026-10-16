// Xtensa64-AR register windows. Architectural operations are independent of
// Flexscript encoders. GNU encodings and pinned Espressif QEMU are references.
// AR0..15 retain their original context slots; AR16..63 occupy3072..3455.
fn xt_phys(c,index){index=index&63;if index<16{return c+index*8;}return c+3072+(index-16)*8;}
fn xt_window_live(c){return (xt_sr(c,230)&0x40010)==0x40000;}
fn xt_window_bit(base){return 1<<(base&15);}
fn xt_exception(c,cause,pc){let ps=xt_sr(c,230);let offset=0x300;if ps&32{offset=0x340;}if ps&16{xt_wsr(c,192,pc);offset=0x3c0;}else{xt_wsr(c,177,pc);}xt_wsr(c,232,cause);xt_wsr(c,230,ps|16);store64(c+128,(xt_sr(c,231)+offset)&0xffffffff);store64(c+272,load64(c+272)+1);return 0;}
fn xt_window_fault(c,pc,base,kind,underflow){let old=xt_sr(c,72);xt_wsr(c,72,base);let ps=(xt_sr(c,230)&~0xf00)|(old<<8)|16;xt_wsr(c,230,ps);xt_wsr(c,177,pc);let offset=(kind-1)*128+underflow*64;store64(c+128,(xt_sr(c,231)+offset)&0xffffffff);let count=c+256+underflow*8;store64(count,load64(count)+1);return 1;}
fn xt_window_check(c,pc,group){if !group || !xt_window_live(c){return 0;}let wb=xt_sr(c,72);let ws=xt_sr(c,73);let step=1;while step<=group{let base=(wb+step)&15;if ws&xt_window_bit(base){let kind=1;while kind<3 && !(ws&xt_window_bit(base+kind)){kind=kind+1;}return xt_window_fault(c,pc,base,kind,0);}step=step+1;}return 0;}
fn xt_window_return(c,pc){let ps=xt_sr(c,230);if !xt_window_live(c){xt_exception(c,0,pc);return 1;}let address=xt_reg(c,0);let n=(address>>30)&3;let wb=xt_sr(c,72);let ws=xt_sr(c,73);let nearest=0;let k=1;while k<=3 && !nearest{if ws&xt_window_bit(wb-k){nearest=k;}k=k+1;}
 if !n || (nearest && nearest!=n){xt_exception(c,0,pc);return 1;}let base=(wb-n)&15;if !(ws&xt_window_bit(base)){return xt_window_fault(c,pc,base,n,1);}xt_wsr(c,73,ws&~xt_window_bit(wb));xt_wsr(c,72,base);store64(c+128,(pc&0xc0000000)|(address&0x3fffffff));return 0;
}
fn xt_window_finish(c,underflow){let wb=xt_sr(c,72);let ws=xt_sr(c,73);if underflow{ws=ws|xt_window_bit(wb);}else{ws=ws&~xt_window_bit(wb);}xt_wsr(c,73,ws);let ps=xt_sr(c,230);xt_wsr(c,72,(ps>>8)&15);xt_wsr(c,230,ps&~16);return xt_sr(c,177);}
fn xt_window_max(a,b,d){if b>a{a=b;}if d>a{a=d;}return a/4;}
// Return the highest referenced register group before any instruction state
// changes. Immediate fields must not be mistaken for register operands.
fn xt_window_group(c,op,length){let a=(op>>4)&15;let b=(op>>8)&15;let d=(op>>12)&15;let low=op&15;
 if length==2{if low==8 || low==9{return xt_window_max(a,b,0);}if low==10{return xt_window_max(a,b,d);}if low==11{return xt_window_max(b,d,0);}if low==12{return b/4;}if low==13 && d==0{return xt_window_max(a,b,0);}return 0;}
 if (op&0xff000f)==0xe30000{return d/4;}if (op&0xff000f)==0xf30000{return a/4;}if (op&0xff00ff)==0xfa0040{return d/4;}if (op&0xff00ff)==0xfa0050{return b/4;}
 if (op&255)==0x36{return ((xt_sr(c,230)>>16)&3);}if low==5{return (op>>4)&3;}if low==1{return a/4;}
 if low==2{if d==10{return a/4;}return xt_window_max(a,b,0);}if low==7{if d==6 || d==7 || d==14 || d==15{return b/4;}return xt_window_max(a,b,0);}if (op&255)==0x76 && (d==8 || d==9 || d==10){return b/4;}if low==6 && (a==1 || a==5 || a==9 || a==13 || a==2 || a==6 || a==10 || a==14 || a==11 || a==15){return b/4;}if (op&63)==6{return 0;}
 if (op&0xff000f)==0x030000 || (op&0xff000f)==0x130000 || (op&0xff000f)==0x610000{return a/4;}if (op&0xfff00f)==0x006000{return a/4;}
 if (op&0xfff0cf)==0x0000c0{return xt_window_max(b,((op>>4)&3)*4,0);}if (op&0xfff0ff)==0x0000a0 || (op&0xfff0ff)==0x401000 || (op&0xfff0ff)==0x400000{return b/4;}
 if (op&0xef000f)==0x010000{return xt_window_max(d,b,0);}if (op&0xef000f)==0x210000 || (op&0xff000f)==0x410000 || (op&0x0e000f)==0x040000{return xt_window_max(d,a,0);}
 if (op&0xff000f)==0x090000 || (op&0xff000f)==0x490000 || (op&0xfff00f)==0x001000{return xt_window_max(a,b,0);}
 if (op&0xff000f)==0x230000{return xt_window_max(b,d,0);}
 if low==0{let high=op>>16;if high==0x83 || high==0x93 || high==0xa3 || high==0xb3 || high==0xc2 || high==0xd2 || high==0xe2 || high==0xf2 || high==0x80 || high==0xc0 || high==0x90 || high==0xa0 || high==0xb0 || high==0xd0 || high==0xe0 || high==0xf0 || high==0x10 || high==0x20 || high==0x30 || high==0x81 || high==0x82 || high==0xa2 || high==0x60 || high==0xa1 || high==0x91 || high==0xb1{return xt_window_max(d,a,b);}}return 0;
}
