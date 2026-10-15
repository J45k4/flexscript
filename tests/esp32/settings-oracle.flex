import "settings-fixture.flex";
fn ko_read(p,size) {let at=0;while at<size {let n=syscall(0,0,p+at,size-at,0,0,0);if n<=0 {return -1;}at=at+n;}return 0;}
fn ko_write(p,size) {let at=0;while at<size {let n=syscall(1,1,p+at,size-at,0,0,0);if n<=0 {return -1;}at=at+n;}return 0;}
fn main() {
    // Each request is separately guarded. Multiple framed requests run without
    // retaining mounted state or trusting the previous request's bytes.
    let pages=syscall(9,0,270336,3,34,-1,0);if pages<0 || syscall(10,pages+266240,4096,0,0,0,0) {return 90;}let header=alloc(64);let input=pages;let live=1;
    if kt_begin(4096) {return 91;}let arena=syscall(9,0,16384,3,34,-1,0);if arena<0 || syscall(10,arena+12288,4096,0,0,0,0) {return 92;}let work=arena+12288-kv_size(4096);kt_trace=alloc(262144);if kt_trace<=0 {return 97;}
    while live {if ko_read(header,4) {return 0;}let size=kv_u32(header);if size<8200 || size>266240 {return 93;}input=pages+266240-size;if ko_read(input,size) {return 94;}if kv_u32(input)!=4096 {return 95;}let flags=kv_u32(input+4);kv_copy(kt_disk,input+8,8192);kv_init(work,kv_size(4096),4096);kt_trace_used=0;kt_operations=0;kt_fail_at= -1;kt_corrupt_at= -1;kv_fill(work-64,64,165);let mounted=kt_reload();let result=mounted;if mounted== -61 && (flags&1) {result=kv_create();}let at=8200;
        while !result && at<size {if size-at<8 {result= -74;}else {let op=load8(input+at);let key=load8(input+at+1);let type=load8(input+at+2);let n=kv_u32(input+at+4);at=at+8;if key>size-at || n>size-at-key {result= -74;}else {let kp=input+at;let vp=kp+key;at=at+key+n;if op==1 {result=kv_set(kp,key,type,vp,n);}else if op==2 {result=kv_delete(kp,key);}else if op==3 {result=kt_commit();}else if op==4 {result=kv_rollback();}else {result= -22;}}}}
        let used=0;let count=0;let generation=0;if kv_mounted {used=kv_used;count=kv_count;generation=kv_generation;}let guard=0;while guard<64 {if load8(work-64+guard)!=165 {return 98;}guard=guard+1;}let outsize=28+used+kt_trace_used+8192;kv_put32(header,outsize);kv_put32(header+4,result);kv_put32(header+8,mounted);kv_put32(header+12,generation);kv_put32(header+16,count);kv_put32(header+20,used);kv_put32(header+24,kt_trace_used);kv_put32(header+28,kv_fault);
        if ko_write(header,32) || ko_write(kv_stage+32,used) || ko_write(kt_trace,kt_trace_used) || ko_write(kt_disk,8192) {return 96;}
    }return 0;
}
