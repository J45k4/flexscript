import "../backends/kvm.flex";
// Legacy virtio PCI block device, regular-file backing, queue size 128.
// 4096-byte state: fd+1, capacity, RAM/size, BAR, PCI command, PFN, queue select,
// status, guest features, last avail/used, ISR/edge, BAR probe; config at 256;
// snapshotted chain (address,length,flags) at 1024. No indirect/event-index bits.
global vb_message=0;
fn vb_fail(message) {vb_message=message;return -1;}
fn vb_u16(p) {return load8(p)|(load8(p+1)<<8);}
fn vb_put16(p,v) {store8(p,v);store8(p+1,v>>8);return 0;}
fn vb_range(s,address,n) {let bytes=load64(s+24);return address>=0 && n>=0 && address<=bytes && n<=bytes-address;}
fn vb_overlap(a,n,b,m) {return n && m && a<b+m && b<a+n;}
fn vb_reset(s) {let i=48;while i<112 {store64(s+i,0);i=i+8;}return 0;}
fn vb_features(s) {if load64(s+136) {return 518;}return 38;}
fn vb_open_mode(s,path,ram,bytes,writable,slot) {
    kvm_zero(s,4096);vb_message=0;
    if slot!=1 && slot!=2 {return vb_fail("Unsupported virtual block PCI slot.");}
    let flags=0x80000;if writable {flags=0xa0002;}
    let fd=syscall(2,path,flags,0,0,0,0);if fd<0 {return vb_fail("Cannot open virtual block backing file.");}
    // fstat x86-64: reject directories, devices and pipes; never expose host disks.
    let stat=s+256;let r=syscall(5,fd,stat,0,0,0,0);let mode=kvm_u32(stat+24);
    let size=load64(stat+48);
    if r<0 || (mode&0xf000)!=0x8000 || size<512 || (size&511) || size>1099511627776 {
        syscall(3,fd,0,0,0,0,0);return vb_fail("Virtual media must be a regular file of 512-byte sectors, at most 1 TiB.");
    }
    let base=0xc000+(slot-1)*64;let irq=12-slot;
    kvm_zero(stat,256);store64(s,fd+1);store64(s+8,size);store64(s+16,ram);store64(s+24,bytes);store64(s+32,base);store64(s+128,0x80000000+slot*2048);store64(s+136,writable!=0);store64(s+144,irq);
    kvm_put32(stat,0x10011af4);kvm_put32(stat+8,0x01000000);kvm_put32(stat+0x10,base|1);
    kvm_put32(stat+0x2c,0x00021af4);store8(stat+0x3c,irq);store8(stat+0x3d,1);return 1;
}
fn vb_open(s,path,ram,bytes) {return vb_open_mode(s,path,ram,bytes,0,1);}
fn vb_close(s) {if s && load64(s) {syscall(3,load64(s)-1,0,0,0,0,0);store64(s,0);}return 0;}
// Call before pc_pci_io, sharing its configuration-address latch.
fn vb_pci(s,pci,port,width,out,data,count) {
    if !s || !load64(s) || width!=1 && width!=2 && width!=4 {return 0;}
    let address=load64(pci);if (address&0xffffff00)!=load64(s+128) || port<0xcfc || port+width>0xd00 {return 0;}
    let offset=(address&252)+port-0xcfc;let i=0;while i<count {
        let p=data+i*width;
        if out {
            if offset>=0x10 && offset+width<=0x14 {
                let value=kvm_u32(s+256+0x10);let j=0;while j<width {let shift=(offset-0x10+j)*8;value=(value&~(255<<shift))|(load8(p+j)<<shift);j=j+1;}
                store64(s+112,value==0xffffffff);if value!=0xffffffff {store64(s+32,value&0xffc0);kvm_put32(s+256+0x10,(value&0xffc0)|1);}
            }else {let j=0;while j<width {let at=offset+j;if at==4 {store64(s+40,load8(p+j)&5);store8(s+260,load8(p+j)&5);}else if at==0x3c {store8(s+256+at,load8(p+j));}j=j+1;}}
        }else {
            let j=0;while j<width {let at=offset+j;let value=load8(s+256+at);if at>=0x10 && at<0x14 && load64(s+112) {value=0xffffffc1>>((at-0x10)*8);}store8(p+j,value);j=j+1;}
        }i=i+1;
    }return 1;
}
// Validate and snapshot every descriptor before changing guest RAM. Malformed
// DMA stops the device explicitly; ordinary failed requests receive IOERR.
fn vb_request(s,head,queue,used) {
    let ram=load64(s+16);let at=head;let count=0;let total=0;let done=0;
    while !done {
        if at>=128 || count>=128 {return vb_fail("Virtio block descriptor chain is out of range or cyclic.");}
        let d=ram+queue+at*16;let address=load64(d);let length=kvm_u32(d+8);let flags=vb_u16(d+12);let next=vb_u16(d+14);
        if (flags&~3) || !vb_range(s,address,length) {return vb_fail("Virtio block descriptor has unsupported flags or invalid DMA bounds.");}
        let copy=s+1024+count*24;store64(copy,address);store64(copy+8,length);store64(copy+16,flags);
        count=count+1;if !(flags&1) {done=1;}else {at=next;}
    }
    if count<2 || load64(s+1032)<16 || load64(s+1040)!=1 {return vb_fail("Virtio block request header is invalid.");}
    let tail=s+1024+(count-1)*24;let status=load64(tail);
    if load64(tail+8)<1 || load64(tail+16)!=2 {return vb_fail("Virtio block status descriptor is invalid.");}
    let header=load64(s+1024);let type=kvm_u32(ram+header);let sector=load64(ram+header+8);
    let i=1;while i<count-1 {
        let copy=s+1024+i*24;let address=load64(copy);let n=load64(copy+8);let flags=load64(copy+16);
        if (type==0 || type==8) && !(flags&2) {return vb_fail("Virtio block read buffer must be device-writable.");}
        if type==1 && (flags&2) {return vb_fail("Virtio block write buffer must be device-readable.");}
        let maximum=134217728;if load64(s+80)&2 {maximum=65536;}
        if n>maximum || total>134217728-n {return vb_fail("Virtio block request exceeds bounded scatter/gather limits.");}
        if (flags&2) && (vb_overlap(address,n,queue,used+1030-queue) || vb_overlap(address,n,header,load64(s+1032)) || vb_overlap(address,n,status,1)) {return vb_fail("Virtio block writable data overlaps request metadata.");}
        total=total+n;i=i+1;
    }
    if vb_overlap(status,1,queue,used+1030-queue) || vb_overlap(status,1,header,load64(s+1032)) {return vb_fail("Virtio block status overlaps request metadata.");}
    let result=2;let written=0;
    if type==0 || (type==1 && load64(s+136)) {
        result=1;
        if !(total&511) && sector>=0 && sector<=load64(s+8)/512 && total<=load64(s+8)-sector*512 {
            result=0;let offset=sector*512;i=1;
            while i<count-1 && !result {
                let copy=s+1024+i*24;let dest=ram+load64(copy);let n=load64(copy+8);let pos=0;
                let operation=17;if type==1 {operation=18;}
                while pos<n && !result {let r=syscall(operation,load64(s)-1,dest+pos,n-pos,offset+pos,0,0);if r==-4 {}else if r<=0 {result=1;}else {pos=pos+r;if type==0 {written=written+r;}}}
                offset=offset+n;i=i+1;
            }
        }
    }else if type==1 {result=1;} // Read-only even if the driver ignored RO.
    else if type==4 && load64(s+136) {result=1;if !total && !sector {let r=syscall(74,load64(s)-1,0,0,0,0,0);while r==-4 {r=syscall(74,load64(s)-1,0,0,0,0,0);}if !r {result=0;}}}
    else if type==8 {
        if total>=20 {
            let copied=0;i=1;while i<count-1 && copied<20 {
                let copy=s+1024+i*24;if !(load64(copy+16)&2) {return vb_fail("Virtio block ID buffer must be device-writable.");}
                let name="Flexscript ISO media";if load64(s+136) {name="Flexscript VM disk  ";}let n=load64(copy+8);let j=0;while j<n && copied<20 {store8(ram+load64(copy)+j,load8(name+copied));copied=copied+1;j=j+1;}i=i+1;
            }result=0;written=20;
        }else {result=1;}
    }
    store8(ram+status,result);return written+1;
}
fn vb_notify(s) {
    if (load64(s+40)&5)!=5 || !(load64(s+64)) || !(load64(s+72)&4) || (load64(s+72)&0xc0) {return vb_fail("Virtio block queue notified before DMA and DRIVER_OK.");}
    let queue=load64(s+48)*4096;let used=(queue+2048+4+256+4095)&~4095;
    if !queue || !vb_range(s,queue,used+1030-queue) {return vb_fail("Virtio block queue lies outside guest RAM.");}
    let ram=load64(s+16);let avail=ram+queue+2048;let index=vb_u16(avail+2);let last=load64(s+88);let pending=(index-last)&65535;
    if pending>128 {return vb_fail("Virtio block available ring overrun.");}
    let i=0;while i<pending {
        let head=vb_u16(avail+4+(last&127)*2);let written=vb_request(s,head,queue,used);if written<0 {return -1;}
        let finished=load64(s+96);let entry=ram+used+4+(finished&127)*8;kvm_put32(entry,head);kvm_put32(entry+4,written);
        finished=(finished+1)&65535;store64(s+96,finished);vb_put16(ram+used+2,finished);last=(last+1)&65535;store64(s+88,last);i=i+1;
    }
    if pending && !(vb_u16(avail)&1) {store64(s+104,1);}return 1;
}
fn vb_irq(s) {if !s || !load64(s) {return 0;}let high=load64(s+104)!=0;let old=load64(s+120);store64(s+120,high);return high && !old;}
fn vb_io(s,port,width,out,data,count) {
    if !s || !load64(s) || !(load64(s+40)&1) || port<load64(s+32) || port+width>load64(s+32)+64 {return 0;}
    let off=port-load64(s+32);let i=0;while i<count {
        let p=data+i*width;let value=0;let j=0;while j<width {value=value|(load8(p+j)<<(j*8));j=j+1;}
        if out {
            if off==4 && width==4 {if value&~vb_features(s) {return vb_fail("Unsupported virtio block feature negotiation.");}store64(s+80,value);}
            else if off==8 && width==4 {if !load64(s+56) {store64(s+48,value);store64(s+64,value!=0);store64(s+88,0);store64(s+96,0);}}
            else if off==14 && width==2 {store64(s+56,value);}
            else if off==16 && width==2 {if value {return vb_fail("Virtio block has only queue zero.");}if vb_notify(s)<0 {return -1;}}
            else if off==18 && width==1 {if !value {vb_reset(s);store64(s+120,0);}else {store64(s+72,value);}}
            else {return vb_fail("Unsupported virtio block register write.");}
        }else {
            if off==0 && width==4 {value=vb_features(s);}
            else if off==4 && width==4 {value=load64(s+80);}
            else if off==8 && width==4 {value=0;if !load64(s+56) {value=load64(s+48);}}
            else if off==12 && width==2 {value=0;if !load64(s+56) {value=128;}}
            else if off==14 && width==2 {value=load64(s+56);}
            else if off==18 && width==1 {value=load64(s+72);}
            else if off==19 && width==1 {value=load64(s+104);store64(s+104,0);store64(s+120,0);}
            else if off>=20 && off+width<=36 && (width==1 || width==2 || width==4) {
                value=0;let j=0;while j<width {let at=off+j-20;let word=load64(s+8)/512;let shift=at*8;
                    if at>=8 {word=65536;shift=(at-8)*8;}if at>=12 {word=126;shift=(at-12)*8;}
                    value=value|(((word>>shift)&255)<<(j*8));j=j+1;
                }
            }
            else {return vb_fail("Unsupported virtio block register read.");}
            j=0;while j<width {store8(p+j,value>>(j*8));j=j+1;}
        }i=i+1;
    }return 1;
}
