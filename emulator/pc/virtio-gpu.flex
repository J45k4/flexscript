import "virtio-pci.flex";
// Virtio-gpu 2D protocol. Transport queue execution is separate: vg_command
// accepts a private request snapshot and private response buffer, never live
// descriptor storage. No virgl, blobs, EDID or context features are advertised.
// 65536-byte state: modern PCI transport[8192]; scanout/cursor at 8192;
// 256 resources[128] at 16384. Resource: id, format, width, height, pixels,
// byte size, backing entries/count/total. Host allocations never enter DMA.
global vg_message=0;
fn vg_fail(message) {vg_message=message;return -1;}
fn vg_copy(to,from,n) {let i=0;while i+8<=n {store64(to+i,load64(from+i));i=i+8;}while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn vg_find(s,id) {if !id {return 0;}let i=0;while i<256 {let r=s+16384+i*128;if load64(r)==id {return r;}i=i+1;}return 0;}
fn vg_free_resource(s,r) {
    if load64(r+32) {syscall(11,load64(r+32),load64(r+40),0,0,0,0);store64(s+8320,load64(s+8320)-load64(r+40));}
    if load64(r+48) {syscall(11,load64(r+48),load64(r+56)*16,0,0,0,0);}
    if load64(s+8192)==load64(r) {kvm_zero(s+8192,48);}if load64(s+8256)==load64(r) {store64(s+8256,0);}
    kvm_zero(r,128);return 0;
}
fn vg_clear(s) {let generation=load64(s+8240)+1;let i=0;while i<256 {let r=s+16384+i*128;if load64(r) {vg_free_resource(s,r);}i=i+1;}kvm_zero(s+8192,256);store64(s+8240,generation);return 0;}
fn vg_init(s,ram,bytes) {
    kvm_zero(s,65536);vg_message=0;if vp_init(s,ram,bytes,16,0x038000,3,0x100000000,2)<0 {return vg_fail(vp_message);}
    kvm_put32(s+512+8,1);return 1;
}
fn vg_rect(r,p) {let x=kvm_u32(p);let y=kvm_u32(p+4);let w=kvm_u32(p+8);let h=kvm_u32(p+12);return w && h && x<=load64(r+16) && w<=load64(r+16)-x && y<=load64(r+24) && h<=load64(r+24)-y;}
fn vg_reply(request,output,type) {kvm_zero(output,24);kvm_put32(output,type);if kvm_u32(request+4)&1 {kvm_put32(output+4,1);store64(output+8,load64(request+8));}return 24;}
fn vg_backing_read(s,r,offset,dest,n) {
    let list=load64(r+48);let i=0;while i<load64(r+56) && n {
        let size=kvm_u32(list+i*16+8);if offset>=size {offset=offset-size;}else {
            let part=size-offset;if part>n {part=n;}vg_copy(dest,load64(s)+load64(list+i*16)+offset,part);dest=dest+part;n=n-part;offset=0;
        }i=i+1;
    }return !n;
}
fn vg_cursor(s,request,n) {
    if n<56 {return vg_fail("Truncated virtio-gpu cursor request.");}let type=kvm_u32(request);
    if (type!=0x300 && type!=0x301) || kvm_u32(request+24) || kvm_u32(request+4) || kvm_u32(request+16) {return 0;}
    if type==0x300 {let id=kvm_u32(request+40);let r=vg_find(s,id);let hx=kvm_u32(request+44);let hy=kvm_u32(request+48);
        if id && (!r || load64(r+16)!=64 || load64(r+24)!=64 || hx>=64 || hy>=64) {return 0;}
        store64(s+8256,id);store64(s+8280,hx);store64(s+8288,hy);
    }
    store64(s+8264,kvm_u32(request+28));store64(s+8272,kvm_u32(request+32));store64(s+8240,load64(s+8240)+1);return 0;
}
fn vg_command(s,request,n,output,capacity,queue) {
    if n<24 {return vg_fail("Truncated virtio-gpu command header.");}if queue==1 {return vg_cursor(s,request,n);}if queue!=0 || capacity<24 {return vg_fail("Invalid virtio-gpu command queue or response capacity.");}
    let type=kvm_u32(request);let result=0x1100;
    if kvm_u32(request+16) {return vg_reply(request,output,0x1204);}if kvm_u32(request+4)&~1 {return vg_reply(request,output,0x1205);}
    if type==0x100 {
        if capacity<408 {return vg_fail("Virtio-gpu display response is too small.");}
        kvm_zero(output,408);vg_reply(request,output,0x1101);kvm_put32(output+32,1024);kvm_put32(output+36,768);kvm_put32(output+40,1);return 408;
    }
    if type==0x101 {
        if n<40 {result=0x1205;}else {
            let id=kvm_u32(request+24);let format=kvm_u32(request+28);let w=kvm_u32(request+32);let h=kvm_u32(request+36);
            if !id || vg_find(s,id) || !w || !h || w>8192 || h>8192 || (format!=1 && format!=2 && format!=3 && format!=4 && format!=67 && format!=68 && format!=121 && format!=134) {result=0x1205;}
            else if w*h*4>134217728 || load64(s+8320)>536870912-w*h*4 {result=0x1201;}
            else {let r=0;let i=0;while i<256 && !r {let slot=s+16384+i*128;if !load64(slot) {r=slot;}i=i+1;}
                let pixels=-1;if r {pixels=alloc(w*h*4);}if pixels<0 {result=0x1201;}else {store64(r,id);store64(r+8,format);store64(r+16,w);store64(r+24,h);store64(r+32,pixels);store64(r+40,w*h*4);store64(s+8320,load64(s+8320)+w*h*4);}
            }
        }
    }
    else if type==0x102 || type==0x107 {
        if n<32 {result=0x1205;}else {let r=vg_find(s,kvm_u32(request+24));if !r {result=0x1203;}
            else if type==0x102 {vg_free_resource(s,r);store64(s+8240,load64(s+8240)+1);}
            else {if load64(r+48) {syscall(11,load64(r+48),load64(r+56)*16,0,0,0,0);}store64(r+48,0);store64(r+56,0);store64(r+64,0);}
        }
    }
    else if type==0x106 {
        if n<32 {result=0x1205;}else {let r=vg_find(s,kvm_u32(request+24));let entries=kvm_u32(request+28);
            if !r {result=0x1203;}else if !entries || entries>32768 || entries>(n-32)/16 || load64(r+48) {result=0x1205;}
            else {let i=0;let total=0;while i<entries && result==0x1100 {let e=request+32+i*16;let address=load64(e);let size=kvm_u32(e+8);
                    if !size || !vp_range(s,address,size) || size>134217728-total {result=0x1205;}else {total=total+size;}i=i+1;}
                if result==0x1100 {let backing=alloc(entries*16);if backing<0 {result=0x1201;}else {vg_copy(backing,request+32,entries*16);store64(r+48,backing);store64(r+56,entries);store64(r+64,total);}}
            }
        }
    }
    else if type==0x103 {
        if n<48 {result=0x1205;}else {let id=kvm_u32(request+44);let r=vg_find(s,id);
            if kvm_u32(request+40) {result=0x1202;}
            else if !id {kvm_zero(s+8192,48);store64(s+8240,load64(s+8240)+1);}
            else if !r {result=0x1203;}
            else if !vg_rect(r,request+24) || kvm_u32(request+32)>1024 || kvm_u32(request+36)>768 {result=0x1205;}
            else {store64(s+8192,id);let i=0;while i<4 {store64(s+8200+i*8,kvm_u32(request+24+i*4));i=i+1;}store64(s+8240,load64(s+8240)+1);}
        }
    }
    else if type==0x104 || type==0x105 {
        let required=48;if type==0x105 {required=56;}if n<required {result=0x1205;}else {let at=40;if type==0x105 {at=48;}let id=kvm_u32(request+at);let r=vg_find(s,id);
            if !r {result=0x1203;}else if !vg_rect(r,request+24) {result=0x1205;}
            else if type==0x104 {if load64(s+8192)==id {store64(s+8240,load64(s+8240)+1);}}
            else {let offset=load64(request+40);let x=kvm_u32(request+24);let y=kvm_u32(request+28);let w=kvm_u32(request+32);let h=kvm_u32(request+36);let stride=load64(r+16)*4;let bytes=(h-1)*stride+w*4;
                if !load64(r+48) || offset<0 || offset>load64(r+64) || bytes>load64(r+64)-offset {result=0x1205;}
                else {let row=0;while row<h {if !vg_backing_read(s,r,offset+row*stride,load64(r+32)+(y+row)*stride+x*4,w*4) {return vg_fail("Virtio-gpu backing snapshot is inconsistent.");}row=row+1;}}
            }
        }
    }
    else {result=0x1200;}
    return vg_reply(request,output,result);
}
fn vg_rgba(format,p) {
    let v=kvm_u32(p);let r=0;let g=0;let b=0;let a=255;
    if format==1 || format==2 {b=v&255;g=(v>>8)&255;r=(v>>16)&255;if format==1 {a=(v>>24)&255;}}
    else if format==3 || format==4 {r=(v>>8)&255;g=(v>>16)&255;b=(v>>24)&255;if format==3 {a=v&255;}}
    else if format==67 || format==134 {r=v&255;g=(v>>8)&255;b=(v>>16)&255;if format==67 {a=(v>>24)&255;}}
    else {b=(v>>8)&255;g=(v>>16)&255;r=(v>>24)&255;if format==121 {a=v&255;}}
    return r|(g<<8)|(b<<16)|(a<<24);
}
// Compose into caller-owned RGBA pixels; never modify guest resource/backing
// pages or burn the cursor into the resource. The display is fixed at 1024x768.
fn vg_frame(s,pixels,pitch,bytes) {
    if !pixels || pitch<4096 || pitch>1048576 || bytes<767*pitch+4096 {return vg_fail("Invalid virtio-gpu host frame buffer.");}
    let r=vg_find(s,load64(s+8192));let y=0;while y<768 {let x=0;while x<1024 {let value=0xff000000;
        if r && x<load64(s+8216) && y<load64(s+8224) {let at=(load64(s+8208)+y)*load64(r+16)+load64(s+8200)+x;value=vg_rgba(load64(r+8),load64(r+32)+at*4)|0xff000000;}
        kvm_put32(pixels+y*pitch+x*4,value);x=x+1;}y=y+1;
    }
    let cursor=vg_find(s,load64(s+8256));if cursor {let top=load64(s+8272)-load64(s+8288);let left=load64(s+8264)-load64(s+8280);y=0;
        while y<64 {let x=0;while x<64 {let dx=left+x;let dy=top+y;if dx>=0 && dx<1024 && dy>=0 && dy<768 {let value=vg_rgba(load64(cursor+8),load64(cursor+32)+(y*64+x)*4);let alpha=(value>>24)&255;
            if alpha {let p=pixels+dy*pitch+dx*4;let old=kvm_u32(p);let result=0xff000000;let channel=0;while channel<3 {let c=((value>>(channel*8))&255)+(((old>>(channel*8))&255)*(255-alpha)+127)/255;if c>255 {c=255;}result=result|(c<<(channel*8));channel=channel+1;}kvm_put32(p,result);}
        }x=x+1;}y=y+1;}
    }return 1;
}
fn vg_metadata_overlap(s,address,n) {
    let i=0;while i<load64(s+112) {let q=vp_queue(s,i);if load64(q+8) {let size=load64(q);
        if vp_overlap(address,n,load64(q+16),size*16) || vp_overlap(address,n,load64(q+24),4+size*2) || vp_overlap(address,n,load64(q+32),4+size*8) {return 1;}
    }i=i+1;}return 0;
}
fn vg_request(s,q,head,index) {
    let ram=load64(s);let count=0;let at=head;let done=0;let readable=0;let writable=0;let phase=0;
    while !done {
        if at>=load64(q) || count>=load64(q) {return vg_fail("Virtio-gpu descriptor chain is invalid or cyclic.");}
        let d=ram+load64(q+16)+at*16;let address=load64(d);let size=kvm_u32(d+8);let flags=vp_u16(d+12);let next=vp_u16(d+14);
        if (flags&~3) || !vp_range(s,address,size) {return vg_fail("Virtio-gpu descriptor DMA bounds or flags are invalid.");}
        if flags&2 {phase=1;writable=writable+size;if vg_metadata_overlap(s,address,size) {return vg_fail("Virtio-gpu response overlaps queue metadata.");}}
        else {if phase {return vg_fail("Virtio-gpu readable descriptor follows writable data.");}readable=readable+size;}
        let copy=s+49408+count*24;store64(copy,address);store64(copy+8,size);store64(copy+16,flags);count=count+1;
        if !(flags&1) {done=1;}else {at=next;}
    }
    if readable<24 || (!index && writable<24) {return vg_fail("Virtio-gpu request or response header is truncated.");}
    // Validate every writable segment against every readable segment before
    // executing a command or changing any guest byte.
    let i=0;while i<count {let a=s+49408+i*24;if load64(a+16)&2 {let j=0;while j<count {let b=s+49408+j*24;
        if !(load64(b+16)&2) && vp_overlap(load64(a),load64(a+8),load64(b),load64(b+8)) {return vg_fail("Virtio-gpu response overlaps request data.");}j=j+1;}
    }i=i+1;}
    let input=load64(s+49152);let output=load64(s+49160);
    if !input {input=alloc(2097152);if input<0 {return vg_fail("Cannot allocate virtio-gpu request snapshot.");}store64(s+49152,input);}
    if !output {output=alloc(4096);if output<0 {return vg_fail("Cannot allocate virtio-gpu response scratch.");}store64(s+49160,output);}
    let limit=readable;if limit>2097152 {limit=24;}let copied=0;i=0;
    while i<count && copied<limit {let d=s+49408+i*24;if !(load64(d+16)&2) {let n=load64(d+8);if n>limit-copied {n=limit-copied;}vg_copy(input+copied,ram+load64(d),n);copied=copied+n;}i=i+1;}
    let capacity=writable;if capacity>4096 {capacity=4096;}let written=0;
    if readable>2097152 {if !index {written=vg_reply(input,output,0x1205);}}
    else {written=vg_command(s,input,readable,output,capacity,index);if written<0 {return -1;}}
    copied=0;i=0;while i<count && copied<written {let d=s+49408+i*24;if load64(d+16)&2 {let n=load64(d+8);if n>written-copied {n=written-copied;}vg_copy(ram+load64(d),output+copied,n);copied=copied+n;}i=i+1;}
    return written;
}
fn vg_notify(s,index) {
    let q=vp_queue(s,index);if !q || !load64(q+8) || (load64(s+72)&15)!=15 || (load64(s+72)&0xc0) || !(load64(s+24)&4) {return vg_fail("Virtio-gpu queue is not ready for DMA.");}
    let ram=load64(s);let avail=ram+load64(q+24);let incoming=vp_u16(avail+2);let last=load64(q+40);let pending=(incoming-last)&65535;
    if pending>load64(q) {return vg_fail("Virtio-gpu available ring overrun.");}
    let i=0;while i<pending {let head=vp_u16(avail+4+(last&(load64(q)-1))*2);let written=vg_request(s,q,head,index);if written<0 {return -1;}
        let used=load64(q+48);let entry=ram+load64(q+32)+4+(used&(load64(q)-1))*8;kvm_put32(entry,head);kvm_put32(entry+4,written);
        used=(used+1)&65535;store64(q+48,used);vp_put16(ram+load64(q+32)+2,used);last=(last+1)&65535;store64(q+40,last);i=i+1;
    }
    if pending && !(vp_u16(avail)&1) {store64(s+88,load64(s+88)|1);}return 1;
}
fn vg_drain(s,old_status) {
    if old_status && !load64(s+72) {vg_clear(s);}let pending=load64(s+120);store64(s+120,0);let i=0;
    while i<2 {if (pending&(1<<i)) && vg_notify(s,i)<0 {return -1;}i=i+1;}return 1;
}
fn vg_config_write(s,off,width,value) {
    if off<84 || off+width>88 {return vg_fail("Virtio-gpu configuration register is read-only.");}
    let clear=value<<((off-84)*8);kvm_put32(s+516,clear);kvm_put32(s+512,kvm_u32(s+512)&~clear);return 1;
}
fn vg_io(s,port,width,out,data,count) {
    let old=load64(s+72);let off=port-load64(s+16);
    if (load64(s+24)&1) && off>=80 && off+width<=256 && out && (width==1 || width==2 || width==4) {let i=0;while i<count {let value=0;let j=0;while j<width {value=value|(load8(data+i*width+j)<<(j*8));j=j+1;}if vg_config_write(s,off,width,value)<0 {return -1;}i=i+1;}return 1;}
    let result=vp_io(s,port,width,out,data,count);if result<0 {return vg_fail(vp_message);}if result && vg_drain(s,old)<0 {return -1;}return result;
}
fn vg_pci(s,pci,port,width,out,data,count) {
    let old=load64(s+72);let off=(load64(pci)&252)+port-0xcfc;
    if (load64(pci)&0xffffff00)==load64(s+32) && port>=0xcfc && port+width<=0xd00 && out && off>=0x94 && off+width<=0x98 {
        let cap=s+256+0x84;let at=kvm_u32(cap+8);let n=kvm_u32(cap+12);
        if at>=80 {if load8(cap+4) || off!=0x94 || width!=n || (n!=1 && n!=2 && n!=4) || at>256-n || (at&(n-1)) {return vg_fail("Invalid virtio-gpu PCI configuration access.");}
            let i=0;while i<count {let value=0;let j=0;while j<width {value=value|(load8(data+i*width+j)<<(j*8));j=j+1;}if vg_config_write(s,at,width,value)<0 {return -1;}i=i+1;}return 1;
        }
    }
    let result=vp_pci(s,pci,port,width,out,data,count);if result<0 {return vg_fail(vp_message);}if result && vg_drain(s,old)<0 {return -1;}return result;
}
fn vg_close(s) {vg_clear(s);if load64(s+49152) {syscall(11,load64(s+49152),2097152,0,0,0,0);}if load64(s+49160) {syscall(11,load64(s+49160),4096,0,0,0,0);}store64(s+49152,0);store64(s+49160,0);return 0;}
