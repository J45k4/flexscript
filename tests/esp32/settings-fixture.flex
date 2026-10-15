import "../../lib/storage/settings.flex";
global kt_disk=0;
global kt_trace=0;
global kt_trace_used=0;
global kt_operations=0;
global kt_fail_at= -1;
global kt_corrupt_at= -1;
fn kt_begin(bank) {kt_disk=alloc(bank*2);let work=alloc(kv_size(bank));if kt_disk<=0 || work<=0 {return -12;}kv_fill(kt_disk,bank*2,255);if kv_init(work,kv_size(bank),bank) {return -22;}kt_trace=0;kt_trace_used=0;kt_operations=0;kt_fail_at= -1;kt_corrupt_at= -1;return 0;}
fn kt_reload() {kv_copy(kv_bank_buffer(0),kt_disk,kv_bank_size*2);return kv_mount();}
fn kt_commit() {
    let r=kv_commit();if r<=0 {return r;}let steps=0;while kv_next_io() {let kind=kv_io_kind;let at=kv_io_offset;let size=kv_io_size;let p=kv_io_buffer;
        if at<0 || size<=0 || at>kv_bank_size*2 || size>kv_bank_size*2-at || (kind==1 && ((at&4095) || (size&4095))) || (kind==2 && ((at&3) || (size&3))) {return -71;}
        if kv_next_io()!=kind || kv_io_offset!=at || kv_io_size!=size || kv_io_buffer!=p {return -71;}
        if kt_operations==kt_fail_at {return kv_io_done(-5);}kt_operations=kt_operations+1;
        if kind==1 {kv_fill(kt_disk+at,size,255);}else if kind==2 {let i=0;while i<size {let before=load8(kt_disk+at+i);let value=load8(p+i);if (before&value)!=value {return -71;}store8(kt_disk+at+i,value);i=i+1;}}
        else if kind==3 {kv_copy(p,kt_disk+at,size);if kt_operations-1==kt_corrupt_at {store8(p,load8(p)^1);}}else {return -71;}
        if kt_trace {if kt_trace_used+12+size>262144 {return -90;}kv_put32(kt_trace+kt_trace_used,kind);kv_put32(kt_trace+kt_trace_used+4,at);kv_put32(kt_trace+kt_trace_used+8,size);kt_trace_used=kt_trace_used+12;if kind!=1 {kv_copy(kt_trace+kt_trace_used,p,size);kt_trace_used=kt_trace_used+size;}}
        r=kv_io_done(size);if r<0 {return r;}steps=steps+1;if steps>1024 {return -110;}
    }return kv_busy;
}
fn kt_has(key,size,type,value,n) {return kv_get(key,size)==0 && kv_value_type==type && kv_value_size==n && kv_equal(kv_value,value,n);}
