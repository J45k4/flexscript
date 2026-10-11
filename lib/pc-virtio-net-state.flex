import "pc-virtio-net.flex";
import "pc-virtio-state.flex";
// Diagnostic network state: modern queues, pending host RX frames, DHCP and
// libslirp's supported migration stream. External connections may disconnect;
// this is explicitly a development recovery path, not lossless VM migration.
fn vns_encode(s,out,capacity) {
    let backend=load64(s+8192);let count=load64(backend+24)-load64(backend+16);if count<0 || count>128 || capacity<8256 || vp_overlap(s,24576,out,capacity) || vp_overlap(load64(s),load64(s+8),out,capacity) {return vn_fail("Invalid network state output buffer.");}
    let scratch=alloc(1048576);if scratch<0 {return vn_fail("Cannot allocate network state stream.");}let n=sn_state_save(backend,scratch,1048576);let bytes=8256+count*2048+n;
    if n<1 || bytes>capacity {syscall(11,scratch,1048576,0,0,0,0);return vn_fail("Cannot encode bounded network state.");}
    kvm_zero(out,8256+count*2048);vps_copy(out,"FLXNET01",8);store64(out+8,bytes);store64(out+16,load64(s+8));store64(out+24,sn_state_version(backend));store64(out+32,n);store64(out+40,count);vps_copy(out+64,s,8192);store64(out+64,0);
    let i=0;while i<count {let source=backend+16384+((load64(backend+16)+i)&127)*2048;let length=load64(source);if length<14 || length>2040 {syscall(11,scratch,1048576,0,0,0,0);return vn_fail("Invalid pending network frame.");}vps_copy(out+8256+i*2048,source,8+length);i=i+1;}
    vps_copy(out+8256+count*2048,scratch,n);syscall(11,scratch,1048576,0,0,0,0);return bytes;
}
fn vns_decode(fresh,input,bytes) {
    if bytes<8257 || bytes>1318976 || load64(input)!=load64("FLXNET01") || load64(input+8)!=bytes || load64(input+16)!=load64(fresh+8) || load64(input+32)<1 || load64(input+32)>1048576 || load64(input+40)<0 || load64(input+40)>128 || load64(input+48) || load64(input+56) {return 0;}
    let n=load64(input+32);let count=load64(input+40);if bytes!=8256+count*2048+n {return 0;}
    // Device MAC and link configuration are immutable in our current model.
    if load64(input+64+512)!=load64(fresh+512) || !vps_load(fresh,input+64) {return 0;}
    let backend=load64(fresh+8192);let i=0;while i<count {let source=input+8256+i*2048;let length=load64(source);if length<14 || length>2040 {return 0;}vps_copy(backend+16384+i*2048,source,8+length);i=i+1;}
    store64(backend+24,count);return sn_state_load(backend,load64(input+24),input+8256+count*2048,n)==1;
}
fn vns_load(s,input,bytes,restricted) {
    if !s || !input || bytes<8257 || vp_overlap(s,24576,input,bytes) {return vn_fail("Invalid network state input buffer.");}
    let fresh=alloc(24576);if fresh<0 {return vn_fail("Cannot allocate restored network device.");}let ok=vn_init(fresh,load64(s),load64(s+8),restricted)>0 && vns_decode(fresh,input,bytes);
    if !ok {vn_close(fresh);syscall(11,fresh,24576,0,0,0,0);return vn_fail("Network state stream failed validation.");}
    vn_close(s);vps_copy(s,fresh,24576);syscall(11,fresh,24576,0,0,0,0);return 1;
}
