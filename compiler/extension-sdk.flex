// Frontend SDK, FIR1 portable word IR. This module has no compiler dependency.
global ir_source=0;
global ir_source_size=0;
global ir_path=0;
global ir_code=0;
global ir_code_size=0;
global ir_functions=0;
global ir_count=0;
global ir_names=0;
global ir_names_size=0;
global ir_current=-1;
global ir_profile=1;
global ir_state=0;
global ir_state_count=0;
fn ir_length(text) {let n=0;while load8(text+n) {n=n+1;}return n;}
fn ir_print(text) {let n=ir_length(text);while n>0 {let k=syscall(1,2,text,n,0,0,0);if k<=0 {return 0;}text=text+k;n=n-k;}return 0;}
fn ir_number(n) {let b=alloc(32);let i=31;while n>=10 {i=i-1;store8(b+i,48+n%10);n=n/10;}i=i-1;store8(b+i,48+n);return ir_print(b+i);}
fn ir_error(message,offset) {
    let line=1;let column=1;let i=0;
    while i<offset && i<ir_source_size {if load8(ir_source+i)==10 {line=line+1;column=1;}else {column=column+1;}i=i+1;}
    ir_print(ir_path);ir_print(":");ir_number(line);ir_print(":");ir_number(column);
    ir_print(": error: ");ir_print(message);ir_print("\n");syscall(60,1,0,0,0,0,0);return 0;
}
fn ir_init(text,size,path,version) {
    ir_source=text;ir_source_size=size;ir_path=path;
    if version!=1 {ir_error("unsupported frontend API version",0);}
    ir_code=alloc(4194304);ir_functions=alloc(2048*64);ir_names=alloc(524288);
    if ir_code<0 || ir_functions<0 || ir_names<0 {ir_error("frontend allocation failed",0);}
    ir_code_size=0;ir_count=0;ir_names_size=0;ir_current=-1;
    ir_profile=1;ir_state=alloc(8388608*8);ir_state_count=0;
    if ir_state<0 {ir_error("frontend allocation failed",0);}return 0;
}
fn ir_state_word(value) {
    if ir_state_count>=8388608 {ir_error("too many IR state words",0);}
    if ir_profile<2 {ir_profile=2;}let index=ir_state_count;store64(ir_state+index*8,value);ir_state_count=index+1;if ir_state_count>2048 && ir_profile<3 {ir_profile=3;}if ir_state_count>262144 && ir_profile<4 {ir_profile=4;}if ir_state_count>1048576 && ir_profile<5 {ir_profile=5;}if ir_state_count>2097152 {ir_profile=6;}return index;
}
fn ir_emit(op,arg) {
    if (op==19 || op==20) && ir_profile<2 {ir_profile=2;}
    if (op==21 || op==22) && ir_profile<3 {ir_profile=3;}
    if ir_code_size>=4194304 {ir_error("frontend IR exceeds 4 MiB",0);}
    let at=ir_code_size;store64(ir_code+at,op);store64(ir_code+at+8,arg);ir_code_size=at+16;if ir_code_size>1048576 {ir_profile=6;}return at;
}
fn ir_patch(at,value) {
    if at<0 || at>=ir_code_size || at%16 {ir_error("invalid IR patch",0);}
    store64(ir_code+at+8,value);return 0;
}
fn ir_begin(name,size,arity) {
    if ir_current>=0 || ir_count>=2048 || size<1 || size>255 || arity<0 || arity>4096 {ir_error("invalid IR function",0);}
    ir_current=ir_count;ir_count=ir_count+1;let f=ir_functions+ir_current*64;
    store64(f,ir_names_size);store64(f+8,size);store64(f+16,ir_code_size);store64(f+24,arity);
    let i=0;while i<size {store8(ir_names+ir_names_size+i,load8(name+i));i=i+1;}
    ir_names_size=ir_names_size+size;ir_emit(18,0);ir_emit(1,0);return ir_current;
}
fn ir_end(slots) {
    if ir_current<0 || slots<load64(ir_functions+ir_current*64+24) || slots>4096 {ir_error("invalid IR local count",0);}
    let f=ir_functions+ir_current*64;store64(f+32,slots);ir_patch(load64(f+16),slots);ir_current=-1;return 0;
}
fn ir_finish() {
    if ir_current>=0 {ir_error("unfinished IR function",0);}
    let code_at=64+ir_count*64;let names_at=code_at+ir_code_size;let total=names_at+ir_names_size+ir_state_count*8;
    if total>4194304 && ir_profile<4 {ir_profile=4;}
    if total>16777216 && ir_profile<5 {ir_profile=5;}
    if total>33554432 {ir_profile=6;}
    if total>134217728 {ir_error("frontend IR exceeds 128 MiB",0);}
    let blob=alloc(total);if blob<0 {ir_error("frontend allocation failed",0);}
    let magic=0x31524946;if ir_profile==2 {magic=0x32524946;}else if ir_profile==3 {magic=0x33524946;}else if ir_profile==4 {magic=0x34524946;}else if ir_profile==5 {magic=0x35524946;}else if ir_profile==6 {magic=0x36524946;}
    store64(blob,magic);store64(blob+8,total);store64(blob+16,ir_count);store64(blob+56,ir_state_count);
    store64(blob+24,code_at);store64(blob+32,ir_code_size);store64(blob+40,names_at);store64(blob+48,ir_names_size);
    let i=0;while i<ir_count*64 {store8(blob+64+i,load8(ir_functions+i));i=i+1;}
    i=0;while i<ir_code_size {store8(blob+code_at+i,load8(ir_code+i));i=i+1;}
    i=0;while i<ir_names_size {store8(blob+names_at+i,load8(ir_names+i));i=i+1;}
    i=0;while i<ir_state_count*8 {store64(blob+names_at+ir_names_size+i,load64(ir_state+i));i=i+8;}
    return blob;
}
