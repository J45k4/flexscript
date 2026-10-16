import "boot.flex";
// Fixed boot framebuffer: 1024x768, 32-bit XBGR (RGBA bytes, unused alpha).
// Reserve the top 4 MiB of VM RAM. Pass lnx_fb_usable(bytes) to lnx_load so
// neither E820 usable memory nor the kernel/initramfs can overlap this region.
fn lnx_fb_usable(bytes) {if bytes<134217728 || bytes>3221225472 || (bytes&4095) {return 0;}return bytes-4194304;}
fn lnx_fb_setup(ram,bytes) {
    let usable=lnx_fb_usable(bytes);if !ram || !usable {return kvm_fail("Framebuffer requires page-aligned RAM of 128 MiB to 3 GiB.",-22);}
    let bp=ram+0x90000;let map=bp+0x2d0;
    if load8(bp+0x1e8)!=3 || load64(map+40)!=1048576 || load64(map+48)!=usable-1048576 || kvm_u32(map+56)!=1 {return kvm_fail("Framebuffer requires a boot map that already excludes its reserved RAM.",-22);}
    kvm_zero(bp,64);store8(bp+0x0f,0x23); // Linux VIDEO_TYPE_VLFB, no BIOS calls.
    store8(bp+0x12,0);store8(bp+0x13,4);store8(bp+0x14,0);store8(bp+0x15,3);store8(bp+0x16,32);
    kvm_put32(bp+0x18,usable);kvm_put32(bp+0x1c,64); // VESA lfb_size uses 64-KiB units.
    store8(bp+0x24,0);store8(bp+0x25,16); // 4096-byte pitch
    store8(bp+0x26,8);store8(bp+0x27,0);store8(bp+0x28,8);store8(bp+0x29,8);store8(bp+0x2a,8);store8(bp+0x2b,16);
    kvm_put32(bp+0x36,1); // VIDEO_CAPABILITY_SKIP_QUIRKS
    store64(map+60,usable);store64(map+68,4194304);kvm_put32(map+76,2);store8(bp+0x1e8,4);
    kvm_zero(ram+usable,4194304);return ram+usable;
}
