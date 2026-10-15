import "../../lib/storage/nvs.flex";
import "settings-fixture.flex";
fn no_read(p,size) {let at=0;while at<size {let n=syscall(0,0,p+at,size-at,0,0,0);if n<=0 {return -1;}at=at+n;}return 0;}
fn no_write(p,size) {let at=0;while at<size {let n=syscall(1,1,p+at,size-at,0,0,0);if n<=0 {return -1;}at=at+n;}return 0;}
fn no_guard(bytes,live) {let arena=syscall(9,0,bytes+4096,3,34,-1,0);if arena<0 || syscall(10,arena+bytes,4096,0,0,0,0) {return 0;}return arena+bytes-live;}
fn main() {
    let input=no_guard(131072,131072);let work=no_guard(12288,kv_size(4096));let core=no_guard(4096,nv_size(4));let header=alloc(64);if !input || !work || !core || kt_begin(4096) {return 90;}
    while 1 {if no_read(header,4) {return 0;}let size=kv_u32(header);if size<8192 || size>131072 {return 91;}let request=input+131072-size;if no_read(request,size) {return 92;}
        kv_copy(kt_disk,request,8192);kv_init(work,kv_size(4096),4096);kv_fill(work-64,64,165);kv_fill(core-64,64,90);nv_ready=0;nv_next_token=0;let init=kt_reload();if init== -61 {init=kv_create();if !init {init=kt_commit();}}if !init {init=nv_init(core,nv_size(4),4);}kv_put32(header,init);if no_write(header,4) {return 93;}
        let at=8192;while at<size {if size-at<12 {return 94;}let p=request+at;let op=load8(p);let n=load8(p+1);let type=load8(p+2);let mode=load8(p+3);let token=kv_u32(p+4);let length=kv_u32(p+8);at=at+12;if n>size-at || length>size-at-n {return 95;}let key=request+at;let value=key+n;at=at+n+length;let error=0;let opened=0;let got=0;let kind=0;
            if op==1 {error=nv_open(key,n,mode);opened=nv_opened;}
            else if op==2 {error=nv_set(token,key,n,type,value,length);}
            else if op==3 {error=nv_get(token,key,n,type);if !error {got=kv_value_size;kind=kv_value_type;}}
            else if op==4 {error=nv_erase(token,key,n);}
            else if op==5 {error=nv_erase_all(token);}
            else if op==6 {error=nv_close(token);}
            else if op==7 {let handle=nv_handle(token,0);if !handle {error=nv_error;}else if load8(handle+4) {error=kt_commit();if error {nv_fail();}}}
            else if op==8 {nv_ready=0;error=kt_reload();if !error {error=nv_init(core,nv_size(4),4);}}
            else if op==9 {error=nv_fail();}
            else if op==10 {error=nv_init(core,nv_size(4),4);}
            else {return 96;}
            kv_put32(header,error);kv_put32(header+4,opened);kv_put32(header+8,kind);kv_put32(header+12,got);if no_write(header,16) || no_write(kv_value,got) {return 97;}
        }
        let i=0;while i<64 {if load8(work-64+i)!=165 || load8(core-64+i)!=90 {return 98;}i=i+1;}
        kv_put32(header,kv_count);kv_put32(header+4,kv_used);kv_put32(header+8,kv_generation);kv_put32(header+12,nv_ready);kv_put32(header+16,nv_failed);if no_write(header,20) || no_write(kv_stage+32,kv_used) || no_write(kt_disk,8192) {return 99;}
    }return 0;
}
