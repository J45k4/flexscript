import "pc-virtio-pci.flex";
// Restore a pointer-free modern transport into a freshly initialized device.
fn vps_copy(to,from,n) {let i=0;while i+8<=n {store64(to+i,load64(from+i));i=i+8;}while i<n {store8(to+i,load8(from+i));i=i+1;}return 0;}
fn vps_load(s,source) {
    if load64(source) || load64(source+8)!=load64(s+8) || load64(source+32)!=load64(s+32) || load64(source+40)!=load64(s+40) || load64(source+112)!=2 {return 0;}
    if load64(source+16)<0 || load64(source+16)>65280 || (load64(source+16)&255) || (load64(source+24)&~5) || (load64(source+48)&~load64(s+40)) || (load64(source+72)&~255) || load64(source+88)>3 || load64(source+96)>1 || load64(source+104)>1 || load64(source+120)>3 || load64(source+128)>255 {return 0;}
    if load64(source+56)<0 || load64(source+56)>0xffffffff || load64(source+64)<0 || load64(source+64)>0xffffffff || load64(source+80)<0 || load64(source+80)>65535 {return 0;}
    if (load64(source+72)&4) && ((load64(source+72)&11)!=11 || !(load64(source+48)&0x100000000)) {return 0;}
    // Only registers writable through our PCI implementation may differ.
    let i=0;while i<256 {let writable=i==4 || i==5 || (i>=16 && i<20) || i==60 || i==0x88 || (i>=0x8c && i<0x94);if !writable && load8(source+256+i)!=load8(s+256+i) {return 0;}i=i+1;}
    if vp_u16(source+260)!=load64(source+24) || kvm_u32(source+272)!=(load64(source+16)|1) {return 0;}
    vps_copy(s+8,source+8,8184);i=0;while i<2 {let q=vp_queue(s,i);let n=load64(q);if n<1 || n>128 || (n&(n-1)) || load64(q+8)<0 || load64(q+8)>1 || load64(q+40)<0 || load64(q+40)>65535 || load64(q+48)<0 || load64(q+48)>65535 || load64(q+56)!=i || load64(q+64)!=65535 {return 0;}
        if load64(q+8) && vp_validate_queue(s,q)<0 {return 0;}i=i+1;
    }return 1;
}
