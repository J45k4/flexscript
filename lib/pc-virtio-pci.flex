import "kvm.flex";
// Modern virtio PCI transport with an I/O BAR, split rings and INTx. All
// capability structures may use I/O space (virtio 1.2 section 4.1.4). Device
// protocol/DMA execution belongs to the caller; notifications set a bitmask.
// 8192-byte state: RAM/size, BAR, command, PCI address, device/driver features,
// selectors, status, queue selector, ISR/previous IRQ, BAR probe, queue count,
// notification bits; PCI image at 256, device config at 512, two queues at 1024.
// Queue[128]: size, enabled, desc, avail, used, last avail/used, notify off, MSI-X.
global vp_message=0;
fn vp_fail(text) {vp_message=text;return -1;}
fn vp_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn vp_put16(p,v) {store8(p,v);store8(p+1,v>>8);return 0;}
fn vp_queue(s,index) {if index<0 || index>=load64(s+112) {return 0;}return s+1024+index*128;}
fn vp_range(s,address,n) {return address>=0 && n>=0 && address<=load64(s+8) && n<=load64(s+8)-address;}
fn vp_overlap(a,n,b,m) {return n && m && a<b+m && b<a+n;}
fn vp_reset(s) {
    store64(s+48,0);store64(s+56,0);store64(s+64,0);store64(s+72,0);store64(s+80,0);store64(s+88,0);store64(s+96,0);store64(s+120,0);
    let i=0;while i<load64(s+112) {let q=vp_queue(s,i);kvm_zero(q,128);store64(q,128);store64(q+56,i);store64(q+64,65535);i=i+1;}return 0;
}
fn vp_cap(s,at,next,type,offset,length) {
    let p=s+256+at;store8(p,9);store8(p+1,next);store8(p+2,16);store8(p+3,type);kvm_put32(p+8,offset);kvm_put32(p+12,length);return 0;
}
fn vp_init(s,ram,bytes,device,class_code,slot,features,queues) {
    if device<1 || device>63 || slot<3 || slot>7 || queues<1 || queues>2 || bytes<4096 || !(features&0x100000000) || (features&~0x100ffffff) {return vp_fail("Invalid modern virtio PCI device configuration.");}
    kvm_zero(s,8192);vp_message=0;store64(s,ram);store64(s+8,bytes);store64(s+16,0xc100+(slot-3)*256);store64(s+32,0x80000000+slot*2048);store64(s+40,features);store64(s+112,queues);
    let p=s+256;kvm_put32(p,((0x1040+device)<<16)|0x1af4);store8(p+6,16);kvm_put32(p+8,(class_code<<8)|1);kvm_put32(p+16,load64(s+16)|1);kvm_put32(p+44,((0x40+device)<<16)|0x1af4);store8(p+52,0x40);store8(p+60,9);store8(p+61,1);
    vp_cap(s,0x40,0x50,1,0,56);vp_cap(s,0x50,0x64,2,64,4);store8(p+0x52,20);kvm_put32(p+0x60,2);
    vp_cap(s,0x64,0x74,3,68,1);vp_cap(s,0x74,0x84,4,80,176);vp_cap(s,0x84,0,5,0,0);store8(p+0x86,20);
    vp_reset(s);return 1;
}
fn vp_validate_queue(s,q) {
    let n=load64(q);let desc=load64(q+16);let avail=load64(q+24);let used=load64(q+32);let dn=n*16;let an=4+n*2;let un=4+n*8;
    if !n || n>128 || (n&(n-1)) || (desc&15) || (avail&1) || (used&3) || !vp_range(s,desc,dn) || !vp_range(s,avail,an) || !vp_range(s,used,un) {return vp_fail("Modern virtio queue has invalid size, alignment or DMA bounds.");}
    if vp_overlap(desc,dn,avail,an) || vp_overlap(desc,dn,used,un) || vp_overlap(avail,an,used,un) {return vp_fail("Modern virtio queue rings overlap.");}
    let i=0;while i<load64(s+112) {let other=vp_queue(s,i);if other!=q && load64(other+8) {
        let j=0;while j<3 {let address=load64(q+16+j*8);let length=dn;if j==1 {length=an;}else if j==2 {length=un;}
            let k=0;while k<3 {let oa=load64(other+16+k*8);let on=load64(other)*16;if k==1 {on=4+load64(other)*2;}else if k==2 {on=4+load64(other)*8;}
                if vp_overlap(address,length,oa,on) {return vp_fail("Modern virtio queues share ring metadata.");}k=k+1;}j=j+1;}
    }i=i+1;}return 1;
}
fn vp_common_read(s,off,width) {
    let q=vp_queue(s,load64(s+80));let value=0;
    if off==0 && width==4 {return load64(s+56);}
    if off==4 && width==4 {let bank=load64(s+56);if bank<2 {return (load64(s+40)>>(bank*32))&0xffffffff;}return 0;}
    if off==8 && width==4 {return load64(s+64);}
    if off==12 && width==4 {let bank=load64(s+64);if bank<2 {return (load64(s+48)>>(bank*32))&0xffffffff;}return 0;}
    if off==16 && width==2 {return 65535;}if off==18 && width==2 {return load64(s+112);}
    if off==20 && width==1 {return load64(s+72);}if off==21 && width==1 {return load64(s+128);}
    if off==22 && width==2 {return load64(s+80);}if off==26 && width==2 {return 65535;}
    if (off==24 || off==28 || off==30) && width==2 {if q {let at=0;if off==28 {at=8;}else if off==30 {at=56;}value=load64(q+at);}return value;}
    if off>=32 && off<56 && width==4 && !(off&3) {if q {let at=16+(off-32)/8*8;value=(load64(q+at)>>((off&4)*8))&0xffffffff;}return value;}
    return vp_fail("Unsupported modern virtio common-register read.");
}
fn vp_common_write(s,off,width,value) {
    let q=vp_queue(s,load64(s+80));
    if off==0 && width==4 {store64(s+56,value);return 1;}if off==8 && width==4 {store64(s+64,value);return 1;}
    if off==12 && width==4 {
        if load64(s+72)&12 {return vp_fail("Virtio features changed after negotiation.");}
        let bank=load64(s+64);if bank<2 {let shift=bank*32;store64(s+48,(load64(s+48)&~(0xffffffff<<shift))|(value<<shift));}return 1;
    }
    if off==16 && width==2 {return 1;}
    if off==20 && width==1 {
        if !value {vp_reset(s);return 1;}
        if (value&8) && ((load64(s+48)&~load64(s+40)) || !(load64(s+48)&0x100000000)) {value=value&~8;}
        if (value&4) && (value&11)!=11 {return vp_fail("Virtio DRIVER_OK requires acknowledged modern features.");}
        store64(s+72,value);return 1;
    }
    if off==22 && width==2 {store64(s+80,value);return 1;}if off==26 && width==2 {return 1;}
    if (off==24 || off==28 || (off>=32 && off<56 && !(off&3))) {
        let valid_width=width==4;if off<32 {valid_width=width==2;}if !valid_width {return vp_fail("Invalid modern virtio queue-register width.");}if !q {return 1;}
        if load64(q+8) {return vp_fail("Active virtio queue registers are immutable until reset.");}
        if off==24 {if !value || value>128 || (value&(value-1)) {return vp_fail("Unsupported virtio queue size.");}store64(q,value);}
        else if off==28 {if value!=1 || vp_validate_queue(s,q)<0 {return vp_fail("Cannot enable invalid modern virtio queue.");}store64(q+8,1);}
        else {let at=16+(off-32)/8*8;let shift=(off&4)*8;store64(q+at,(load64(q+at)&~(0xffffffff<<shift))|(value<<shift));}return 1;
    }
    return vp_fail("Unsupported modern virtio common-register write.");
}
fn vp_access(s,off,width,out,data,count) {
    if (width!=1 && width!=2 && width!=4) || off<0 || off+width>256 || count<1 {return vp_fail("Invalid modern virtio register access.");}
    let i=0;while i<count {
        let p=data+i*width;let value=0;let j=0;while j<width {value=value|(load8(p+j)<<(j*8));j=j+1;}
        if off<56 {if out {if vp_common_write(s,off,width,value)<0 {return -1;}}else {value=vp_common_read(s,off,width);if value<0 {return -1;}}}
        else if off==64 || off==66 {
            let q=vp_queue(s,value);if !out || width!=2 || !q || off!=64+value*2 || !load64(q+8) || !(load64(s+24)&4) || (load64(s+72)&15)!=15 || (load64(s+72)&0xc0) {return vp_fail("Invalid modern virtio queue notification.");}
            store64(s+120,load64(s+120)|(1<<value));
        }
        else if off==68 && width==1 && !out {value=load64(s+88);store64(s+88,0);store64(s+96,0);}
        else if off>=80 && off+width<=256 {if out {return vp_fail("Device-specific configuration writes require the device handler.");}value=0;j=0;while j<width {value=value|(load8(s+512+off-80+j)<<(j*8));j=j+1;}}
        else {return vp_fail("Unsupported modern virtio I/O register.");}
        if !out {j=0;while j<width {store8(p+j,value>>(j*8));j=j+1;}}i=i+1;
    }return 1;
}
fn vp_io(s,port,width,out,data,count) {
    if !s || !(load64(s+24)&1) || (width!=1 && width!=2 && width!=4) || port<load64(s+16) || port+width>load64(s+16)+256 {return 0;}
    return vp_access(s,port-load64(s+16),width,out,data,count);
}
fn vp_pci(s,pci,port,width,out,data,count) {
    if !s || (width!=1 && width!=2 && width!=4) || port<0xcfc || port+width>0xd00 || (load64(pci)&0xffffff00)!=load64(s+32) {return 0;}
    let off=(load64(pci)&252)+port-0xcfc;let p=s+256;let i=0;
    while i<count {
        let d=data+i*width;
        if off>=0x94 && off+width<=0x98 {
            let cap=p+0x84;let n=kvm_u32(cap+12);let at=kvm_u32(cap+8);
            if load8(cap+4) || off!=0x94 || width!=n || (n!=1 && n!=2 && n!=4) || at>256-n || (at&(n-1)) {return vp_fail("Invalid virtio PCI configuration-access window.");}
            if vp_access(s,at,width,out,d,1)!=1 {return vp_fail("Virtio PCI configuration access failed.");}
        }
        else if out {
            if off>=16 && off+width<=20 {let value=kvm_u32(p+16);let j=0;while j<width {let shift=(off-16+j)*8;value=(value&~(255<<shift))|(load8(d+j)<<shift);j=j+1;}
                store64(s+104,value==0xffffffff);if value!=0xffffffff {store64(s+16,value&0xff00);kvm_put32(p+16,(value&0xff00)|1);}}
            else {let j=0;while j<width {let at=off+j;
                if at==4 {store64(s+24,load8(d+j)&5);store8(p+4,load8(d+j)&5);}
                else if at==5 {store8(p+5,0);}
                else if at==0x3c {store8(p+at,load8(d+j));}
                else if at==0x88 || (at>=0x8c && at<0x94) {store8(p+at,load8(d+j));}
                j=j+1;}}
        }
        else {let j=0;while j<width {let at=off+j;let value=load8(p+at);if at>=16 && at<20 && load64(s+104) {value=0xffffff01>>((at-16)*8);}store8(d+j,value);j=j+1;}}
        i=i+1;
    }return 1;
}
fn vp_irq(s) {let level=load64(s+88)!=0;let previous=load64(s+96);store64(s+96,level);return level && !previous;}
