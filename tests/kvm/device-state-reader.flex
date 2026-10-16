import "../../emulator/pc/virtio-gpu-state.flex";
import "../../emulator/pc/virtio-net-state.flex";
fn expect(ok) {if !ok {syscall(1,2,"device dump reader assertion failed\n",36,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn read(path,p,n) {let fd=syscall(2,path,0,0,0,0,0);expect(fd>=0);let at=0;while at<n {let bytes=syscall(0,fd,p+at,n-at,0,0,0);expect(bytes>0);at=at+bytes;}syscall(3,fd,0,0,0,0,0);return 0;}
fn main(argc,argv) {
    expect(argc==4);let ram=alloc(67108864);read(load64(argv+8),ram,67108864);
    let gpu=alloc(65536);let net=alloc(24576);let data=alloc(1318976);expect(vg_init(gpu,ram,67108864)==1 && vn_init(net,ram,67108864,1)==1);
    let fd=syscall(2,load64(argv+16),0,0,0,0,0);expect(fd>=0);let n=syscall(8,fd,0,2,0,0,0);syscall(3,fd,0,0,0,0,0);expect(n==8608);read(load64(argv+16),data,n);expect(vgs_load(gpu,data,n)==1);
    let r=vg_find(gpu,1);expect(r && load64(gpu+8192)==1 && load64(r+16)==2 && load64(r+24)==2 && load64(r+56)==1 && load64(load64(r+48))==0x306000);
    let pixels=alloc(3145728);expect(vg_frame(gpu,pixels,4096,3145728)==1 && kvm_u32(pixels)==0xff0000ff && kvm_u32(pixels+4)==0xff00ff00 && kvm_u32(pixels+4096)==0xffff0000 && kvm_u32(pixels+4100)==0xffffffff);
    let copy=alloc(16);expect(vg_backing_read(gpu,r,0,copy,16) && load64(copy)==load64(ram+0x306000) && load64(copy+8)==load64(ram+0x306008));
    fd=syscall(2,load64(argv+24),0,0,0,0,0);expect(fd>=0);n=syscall(8,fd,0,2,0,0,0);syscall(3,fd,0,0,0,0,0);expect(n>8256 && n<=1318976);read(load64(argv+24),data,n);expect(vns_load(net,data,n,1)==1 && load64(net)==ram && load8(net+512)==0x52);
    vg_close(gpu);vn_close(net);syscall(1,1,"PASS: production dump RAM and GPU/network sections reconstruct fresh devices\n",77,0,0,0);return 0;
}
