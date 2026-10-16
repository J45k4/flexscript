import "../../emulator/pc/virtio-net-state.flex";
fn expect(ok) {if !ok {syscall(1,2,"network state assertion failed\n",31,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn be16(p,n) {store8(p,n>>8);store8(p+1,n);return 0;}
fn setup(q,base) {store64(q+8,1);store64(q+16,base);store64(q+24,base+0x1000);store64(q+32,base+0x2000);return 0;}
fn rejected(target,data,bytes) {let old=load64(target+8192);expect(vns_load(target,data,bytes,1)<0 && load64(target+8192)==old && !sn_peek(old));return 0;}
fn main() {
    let s=alloc(24576);let target=alloc(24576);let ram=alloc(65536);let other=alloc(65536);expect(vn_init(s,ram,65536,1)==1 && vn_init(target,other,65536,1)==1);
    store64(s+24,5);store8(s+260,5);store64(s+48,0x100000000);store64(s+72,15);let tx=vp_queue(s,1);setup(tx,0x1000);
    let p=ram+0x400c;let i=0;while i<6 {store8(p+i,255);store8(p+6+i,load8(s+512+i));store8(p+22+i,load8(s+512+i));i=i+1;}
    be16(p+12,0x806);be16(p+14,1);be16(p+16,0x800);store8(p+18,6);store8(p+19,4);be16(p+20,1);store8(p+28,10);store8(p+30,2);store8(p+31,15);store8(p+38,10);store8(p+40,2);store8(p+41,2);
    store64(ram+0x1000,0x4000);kvm_put32(ram+0x1008,54);vp_put16(ram+0x2002,1);expect(vn_tx(s)==1);let backend=load64(s+8192);expect(sn_peek(backend) && sn_length(backend)>=42);
    let stream=alloc(1318976);let bytes=vns_encode(s,stream,1318976);expect(bytes>10304 && load64(stream+40)==1 && !load64(stream+64));
    rejected(target,stream,bytes-1);let old=load64(stream+24);store64(stream+24,old+1);rejected(target,stream,bytes);store64(stream+24,old);
    old=load64(stream+8256);store64(stream+8256,2041);rejected(target,stream,bytes);store64(stream+8256,old);
    old=load64(stream+64+40);store64(stream+64+40,0);rejected(target,stream,bytes);store64(stream+64+40,old);
    old=load64(stream+64+512);store64(stream+64+512,0);rejected(target,stream,bytes);store64(stream+64+512,old);
    vps_copy(other,ram,65536);let previous=load64(target+8192);expect(vns_load(target,stream,bytes,1)==1 && load64(target)==other && load64(target+8192)!=previous && load64(target+8192)!=backend);
    let restored=load64(target+8192);expect(sn_length(restored)==sn_length(backend));let a=sn_peek(backend);let b=sn_peek(restored);i=0;while i<sn_length(backend) {expect(load8(a+i)==load8(b+i));i=i+1;}
    expect(load64(vp_queue(target,1)+40)==1 && load64(vp_queue(target,1)+48)==1 && vp_irq(target) && !vp_irq(target));
    setup(vp_queue(target,0),0x8000);store64(other+0x8000,0xb000);kvm_put32(other+0x8008,2048);vp_put16(other+0x800c,2);vp_put16(other+0x9002,1);
    expect(vn_rx(target)==2 && vp_u16(other+0xa002)==1 && !sn_peek(restored) && sn_peek(backend) && !load64(ram+0xb000));
    expect(load8(other+0xb000+12)==0x52 && load8(other+0xb000+12+12)==8 && load8(other+0xb000+12+13)==6);
    vn_close(s);vn_close(target);syscall(1,1,"PASS: network state queues, pending ARP, DMA and atomic rejection\n",66,0,0,0);return 0;
}
