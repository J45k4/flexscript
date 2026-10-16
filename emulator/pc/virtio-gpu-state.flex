import "virtio-gpu.flex";
import "virtio-state.flex";
// Pointer-free 2D GPU state for local diagnostic recovery. Transport is copied
// with its RAM pointer zeroed; resources carry typed geometry, backing GPAs
// and pixel bytes. Loads build a new device and commit only after validation.
// This codec alone does not save a VM or its network connections.
fn vgs_format(format) {return format==1 || format==2 || format==3 || format==4 || format==67 || format==68 || format==121 || format==134;}
fn vgs_size(s) {
    let bytes=8512;let i=0;while i<256 {let r=s+16384+i*128;if load64(r) {bytes=bytes+64+load64(r+40)+load64(r+56)*16;}i=i+1;}return bytes;
}
fn vgs_encode(s,out,capacity) {
    let bytes=vgs_size(s);if capacity<bytes || bytes>1073741824 || vp_overlap(s,65536,out,bytes) || vp_overlap(load64(s),load64(s+8),out,bytes) {return vg_fail("Invalid GPU state output buffer.");}
    kvm_zero(out,8512);vg_copy(out,"FLXGPU01",8);store64(out+8,bytes);store64(out+24,load64(s+8));vg_copy(out+64,s,8192);store64(out+64,0);vg_copy(out+8256,s+8192,256);store64(out+8256+128,0);
    let at=8512;let count=0;let i=0;while i<256 {let r=s+16384+i*128;if load64(r) {
        let p=out+at;kvm_zero(p,64);vg_copy(p,r,32);store64(p+32,load64(r+40));store64(p+40,load64(r+56));store64(p+48,load64(r+64));at=at+64;
        if load64(r+56) {vg_copy(out+at,load64(r+48),load64(r+56)*16);at=at+load64(r+56)*16;}
        vg_copy(out+at,load64(r+32),load64(r+40));at=at+load64(r+40);count=count+1;
    }i=i+1;}store64(out+16,count);return bytes;
}
fn vgs_decode(fresh,input,bytes) {
    if bytes<8512 || bytes>1073741824 || load64(input)!=load64("FLXGPU01") || load64(input+8)!=bytes || load64(input+16)<0 || load64(input+16)>256 || load64(input+24)!=load64(fresh+8) {return 0;}
    let i=32;while i<64 {if load8(input+i) {return 0;}i=i+1;}
    if !vps_load(fresh,input+64) {return 0;}let metadata=input+8256;if load64(metadata+128) {return 0;}
    i=0;while i<256 {let used=i<40 || (i>=48 && i<56) || (i>=64 && i<104);if !used && load8(metadata+i) {return 0;}i=i+1;}
    vg_copy(fresh+8192,metadata,256);let at=8512;let count=load64(input+16);i=0;
    while i<count {
        if at>bytes-64 {return 0;}let p=input+at;let id=load64(p);let format=load64(p+8);let w=load64(p+16);let h=load64(p+24);let size=load64(p+32);let entries=load64(p+40);let total=load64(p+48);at=at+64;
        if id<1 || id>0xffffffff || vg_find(fresh,id) || !vgs_format(format) || w<1 || w>8192 || h<1 || h>8192 || w*h*4>134217728 || size!=w*h*4 || entries<0 || entries>32768 || total<0 || total>134217728 || load64(p+56) {return 0;}
        if load64(fresh+8320)>536870912-size || entries*16>bytes-at || size>bytes-at-entries*16 {return 0;}
        let sum=0;let j=0;while j<entries {let entry=input+at+j*16;let n=kvm_u32(entry+8);if !n || !vp_range(fresh,load64(entry),n) || sum>134217728-n {return 0;}sum=sum+n;j=j+1;}if sum!=total {return 0;}
        let r=fresh+16384+i*128;vg_copy(r,p,32);store64(r+40,size);let pixels=alloc(size);if pixels<0 {return 0;}store64(r+32,pixels);store64(fresh+8320,load64(fresh+8320)+size);
        if entries {let backing=alloc(entries*16);if backing<0 {return 0;}store64(r+48,backing);store64(r+56,entries);store64(r+64,total);vg_copy(backing,input+at,entries*16);at=at+entries*16;}
        vg_copy(pixels,input+at,size);at=at+size;i=i+1;
    }
    if at!=bytes {return 0;}let scanout=vg_find(fresh,load64(fresh+8192));if load64(fresh+8192) && !scanout {return 0;}
    if scanout {let rect=alloc(16);if rect<0 {return 0;}i=0;while i<4 {let n=load64(fresh+8200+i*8);if n<0 || n>0xffffffff {syscall(11,rect,16,0,0,0,0);return 0;}kvm_put32(rect+i*4,n);i=i+1;}let valid=vg_rect(scanout,rect) && load64(fresh+8216)<=1024 && load64(fresh+8224)<=768;syscall(11,rect,16,0,0,0,0);if !valid {return 0;}}
    let cursor=vg_find(fresh,load64(fresh+8256));if load64(fresh+8256) && (!cursor || load64(cursor+16)!=64 || load64(cursor+24)!=64 || load64(fresh+8280)<0 || load64(fresh+8280)>=64 || load64(fresh+8288)<0 || load64(fresh+8288)>=64) {return 0;}
    if load64(fresh+8264)<0 || load64(fresh+8264)>0xffffffff || load64(fresh+8272)<0 || load64(fresh+8272)>0xffffffff {return 0;}return 1;
}
fn vgs_load(s,input,bytes) {
    if !s || !input || bytes<8512 || vp_overlap(s,65536,input,bytes) {return vg_fail("Invalid GPU state input buffer.");}
    let fresh=alloc(65536);if fresh<0 {return vg_fail("Cannot allocate restored GPU state.");}let ok=vg_init(fresh,load64(s),load64(s+8))>0 && vgs_decode(fresh,input,bytes);
    if !ok {vg_close(fresh);syscall(11,fresh,65536,0,0,0,0);return vg_fail("GPU state stream failed validation.");}
    vg_close(s);vg_copy(s,fresh,65536);syscall(11,fresh,65536,0,0,0,0);return 1;
}
