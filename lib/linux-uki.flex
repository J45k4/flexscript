// Extract Linux boot payloads from a PE32+ Unified Kernel Image. This is
// direct Linux boot, not EFI firmware execution. State[48] holds pointers and
// lengths into the caller-owned image: kernel, initramfs and command line.
import "disk-fat.flex";
global uki_message=0;
fn uki_fail(message) {uki_message=message;return 0;}
fn uki_name(p,name) {let n=0;while n<8 && load8(name+n) {if load8(p+n)!=load8(name+n) {return 0;}n=n+1;}while n<8 {if load8(p+n) {return 0;}n=n+1;}return 1;}
fn uki_parse(s,image,bytes) {
    fat_zero(s,48);uki_message=0;if bytes<64 || fat_u16(image)!=0x5a4d {return uki_fail("Expected a PE32+ Unified Kernel Image.");}
    let offset=fat_u32(image+60);if offset<64 || !fat_range(bytes,offset,24) {return uki_fail("UKI PE header exceeds image.");}let p=image+offset;let count=fat_u16(p+6);let optional=fat_u16(p+20);
    if fat_u32(p)!=0x4550 || fat_u16(p+4)!=0x8664 || !count || count>96 || optional<112 || !fat_range(bytes,offset+24,optional+count*40) || fat_u16(p+24)!=0x20b {return uki_fail("Invalid x86-64 UKI PE headers.");}
    let headers=fat_u32(p+24+60);let table=p+24+optional;if headers<offset+24+optional+count*40 || headers>bytes {return uki_fail("Invalid UKI PE header extent.");}
    let i=0;while i<count {let section=table+i*40;let n=fat_u32(section+16);let at=fat_u32(section+20);
        if n && (at<headers || !fat_range(bytes,at,n)) {return uki_fail("UKI section exceeds image or overlaps headers.");}
        let j=0;while j<i {let previous=table+j*40;let pn=fat_u32(previous+16);let pa=fat_u32(previous+20);if n && pn && at<pa+pn && pa<at+n {return uki_fail("UKI raw sections overlap.");}j=j+1;}
        let slot=-1;if uki_name(section,".linux") {slot=0;}else if uki_name(section,".initrd") {slot=16;}else if uki_name(section,".cmdline") {slot=32;}
        if slot>=0 {let size=fat_u32(section+8);if load64(s+slot) || !size || size>n {return uki_fail("UKI boot section is empty, duplicated or truncated.");}store64(s+slot,image+at);store64(s+slot+8,size);}
        i=i+1;
    }
    if !load64(s) || !load64(s+16) || !load64(s+32) || load64(s+40)>4096 {return uki_fail("UKI requires Linux, initramfs and bounded embedded command line.");}
    let n=0;while n<load64(s+40) && load8(load64(s+32)+n) {n=n+1;}if !n || n>=4096 {return uki_fail("Invalid UKI embedded command line.");}store64(s+40,n);return 1;
}
