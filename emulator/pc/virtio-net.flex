import "virtio-pci.flex";
import "../backends/slirp.flex";
// Modern virtio-net: one RX/TX pair, MAC + STATUS + VERSION_1, IRQ5, slot4.
// No offloads, indirect descriptors, merged RX buffers or control queue.
// State[24576]: transport[8192], slirp pointer at8192, descriptor snapshots
// at8448 (128*24), host packet scratch at16384 (4096). Modern header is12B.
global vn_message=0;
fn vn_fail(text) {vn_message=text;return -1;}
fn vn_close(s) {if s && load64(s+8192) {sn_close(load64(s+8192));store64(s+8192,0);}return 0;}
fn vn_init(s,ram,bytes,restricted) {
    kvm_zero(s,24576);vn_message=0;if vp_init(s,ram,bytes,1,0x020000,4,0x100010020,2)<0 {return vn_fail(vp_message);}
    store8(s+256+60,5);let mac=s+512;store8(mac,0x52);store8(mac+1,0x54);store8(mac+3,0x46);store8(mac+4,0x4c);store8(mac+5,0x58);vp_put16(mac+6,1);
    let backend=sn_create(restricted);if !backend {return vn_fail(sn_message);}store64(s+8192,backend);return 1;
}
fn vn_ready(s,q) {return q && load64(q+8) && (load64(s+72)&15)==15 && !(load64(s+72)&0xc0) && (load64(s+24)&4);}
fn vn_metadata(s,address,bytes) {
    let i=0;while i<2 {let q=vp_queue(s,i);if load64(q+8) {let size=load64(q);if vp_overlap(address,bytes,load64(q+16),size*16) || vp_overlap(address,bytes,load64(q+24),4+size*2) || vp_overlap(address,bytes,load64(q+32),4+size*8) {return 1;}}i=i+1;}return 0;
}
fn vn_chain(s,q,head,write) {
    let at=head;let count=0;let total=0;let more=1;let ram=load64(s);
    while more {
        if at>=load64(q) || count>=load64(q) {return vn_fail("Virtio-net descriptor chain is invalid or cyclic.");}
        let p=ram+load64(q+16)+at*16;let address=load64(p);let bytes=kvm_u32(p+8);let flags=vp_u16(p+12);
        if (flags&~3) || ((flags&2)!=0)!=write || !vp_range(s,address,bytes) {return vn_fail("Virtio-net descriptor flags or DMA bounds are invalid.");}
        if write && vn_metadata(s,address,bytes) {return vn_fail("Virtio-net receive data overlaps queue metadata.");}
        let d=s+8448+count*24;store64(d,address);store64(d+8,bytes);store64(d+16,flags);
        if write {let i=0;while i<count {let old=s+8448+i*24;if vp_overlap(address,bytes,load64(old),load64(old+8)) {return vn_fail("Virtio-net receive segments overlap.");}i=i+1;}}
        total=total+bytes;if total>1048576 {return vn_fail("Virtio-net descriptor chain exceeds its bounded capacity.");}count=count+1;more=(flags&1)!=0;at=vp_u16(p+14);
    }
    store64(s+8200,count);return total;
}
fn vn_copy(s,packet,bytes,write) {
    let copied=0;let i=0;while i<load64(s+8200) && copied<bytes {let d=s+8448+i*24;let size=load64(d+8);if size>bytes-copied {size=bytes-copied;}let guest=load64(s)+load64(d);let j=0;
        while j+8<=size {if write {store64(guest+j,load64(packet+copied+j));}else {store64(packet+copied+j,load64(guest+j));}j=j+8;}
        while j<size {if write {store8(guest+j,load8(packet+copied+j));}else {store8(packet+copied+j,load8(guest+j));}j=j+1;}
        copied=copied+size;i=i+1;
    }return copied==bytes;
}
fn vn_pending(s,q) {let incoming=vp_u16(load64(s)+load64(q+24)+2);let count=(incoming-load64(q+40))&65535;if count>load64(q) {return vn_fail("Virtio-net available ring overrun.");}return count;}
fn vn_complete(s,q,head,bytes) {
    let ram=load64(s);let used=load64(q+48);let entry=ram+load64(q+32)+4+(used&(load64(q)-1))*8;kvm_put32(entry,head);kvm_put32(entry+4,bytes);used=(used+1)&65535;
    store64(q+48,used);vp_put16(ram+load64(q+32)+2,used);store64(q+40,(load64(q+40)+1)&65535);if !(vp_u16(ram+load64(q+24))&1) {store64(s+88,load64(s+88)|1);}return 0;
}
fn vn_tx(s) {
    let q=vp_queue(s,1);if !vn_ready(s,q) {return vn_fail("Virtio-net transmit queue is not ready.");}if vp_validate_queue(s,q)<0 {return vn_fail(vp_message);}
    let pending=vn_pending(s,q);if pending<0 {return -1;}let packet=s+16384;let i=0;
    while i<pending {let head=vp_u16(load64(s)+load64(q+24)+4+(load64(q+40)&(load64(q)-1))*2);let bytes=vn_chain(s,q,head,0);if bytes<0 {return -1;}
        if bytes<26 || bytes>2052 || !vn_copy(s,packet,bytes,0) {return vn_fail("Virtio-net transmit packet has invalid size.");}
        if load8(packet) || load8(packet+1) {return vn_fail("Virtio-net unnegotiated checksum/GSO offload.");}
        if sn_input(load64(s+8192),packet+12,bytes-12)<0 {return vn_fail(sn_message);}vn_complete(s,q,head,0);i=i+1;
    }return 1;
}
fn vn_rx(s) {
    let q=vp_queue(s,0);if !vn_ready(s,q) {return 1;}let backend=load64(s+8192);if !sn_peek(backend) {return 1;}if vp_validate_queue(s,q)<0 {return vn_fail(vp_message);}
    let pending=vn_pending(s,q);if pending<0 {return -1;}let packet=s+16384;let written=0;
    while pending && sn_peek(backend) {let bytes=sn_length(backend)+12;let head=vp_u16(load64(s)+load64(q+24)+4+(load64(q+40)&(load64(q)-1))*2);let capacity=vn_chain(s,q,head,1);if capacity<0 {return -1;}if capacity<bytes {return vn_fail("Virtio-net receive buffer cannot hold the frame.");}
        kvm_zero(packet,12);vp_put16(packet+10,1);let p=sn_peek(backend);let i=12;while i<bytes {store8(packet+i,load8(p+i-12));i=i+1;}if !vn_copy(s,packet,bytes,1) {return vn_fail("Virtio-net receive scatter copy failed.");}
        vn_complete(s,q,head,bytes);sn_pop(backend);pending=pending-1;written=1;
    }return 1+written;
}
fn vn_drain(s,old) {
    if old && !load64(s+72) {let backend=load64(s+8192);store64(backend+16,load64(backend+24));}
    let pending=load64(s+120);store64(s+120,0);if (pending&2) && vn_tx(s)<0 {return -1;}return vn_rx(s);
}
fn vn_tick(s) {if !s {return 1;}if sn_poll(load64(s+8192))<0 {return vn_fail(sn_message);}return vn_rx(s);}
fn vn_io(s,port,width,out,data,count) {if !s {return 0;}let old=load64(s+72);let result=vp_io(s,port,width,out,data,count);if result<0 {return vn_fail(vp_message);}if result && vn_drain(s,old)<0 {return -1;}return result;}
fn vn_pci(s,pci,port,width,out,data,count) {if !s {return 0;}let old=load64(s+72);let result=vp_pci(s,pci,port,width,out,data,count);if result<0 {return vn_fail(vp_message);}if result && vn_drain(s,old)<0 {return -1;}return result;}
