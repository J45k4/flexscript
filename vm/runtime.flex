import "jit.flex";
// Trusted execution uses native pointers/syscalls/FFI. Restricted execution
// uses guest offsets and explicitly granted host capabilities.
// Bytecode is compiler-owned: 16-byte records (opcode, operand).
global vm_mode=0;
global vm_restricted=0;
global vm_heap=0;
global vm_heap_limit=16777216;
global vm_heap_used=16;
global vm_stack=0;
global vm_sp=0;
global vm_local_memory=0;
global vm_local_base=0;
global vm_local_top=0;
global vm_frames=0;
global vm_depth=0;
global vm_pc=0;
global vm_acc=0;
global vm_error=0;
global vm_denied_syscall=-1;
global vm_denied_ffi=0;
global vm_finished=0;
global vm_fuel=10000000;
global vm_deadline=0;
global vm_timeout=5000;
global vm_time=0;
global vm_steps=0;
global vm_output_left=1048576;
global vm_stdin=0;
global vm_read_root=-1;
global vm_root_name=0;
global vm_path=0;
global vm_open_how=0;
global vm_poll_records=0;
global vm_file_stat=0;
global vm_fds=0;
global vm_show_stats=0;
global vm_jit_enabled=1;
global vm_jit_threshold=16;
global vm_jit_explicit=0;
global vm_jit_cache=0;
global vm_jit_context=0;
global vm_jit_compilations=0;
global vm_jit_calls=0;
fn vm_emit(op,value) {let at=output_size;emit64(op);emit64(value);return at;}
fn vm_allocate(size) {
    if !size {return -22;}
    if size<0 || size>vm_heap_limit-vm_heap_used {return -12;}
    let rounded=((size+7)/8)*8;if rounded>vm_heap_limit-vm_heap_used {return -12;}
    let address=vm_heap_used;vm_heap_used=vm_heap_used+rounded;
    if !vm_restricted {return vm_heap+address;}return address;
}
fn vm_address(offset,size) {
    if !vm_restricted {
        if !offset || size<0 {vm_error=3;return 0;}
        return offset;
    }
    if offset<16 || offset>vm_heap_used || size<0 || size>vm_heap_used-offset {
        vm_error=3;return 0;
    }
    return vm_heap+offset;
}
fn vm_string_literal() {
    let start=token_start+1;let end=token_start+token_size-1;
    let address=vm_allocate(end-start+1);if address<0 {fail("VM memory limit exceeded by strings");}
    let bytes=vm_address(address,end-start+1);
    let n=0;
    while start<end {
        let c=load8(source+start);start=start+1;
        if c==92 {
            c=load8(source+start);start=start+1;
            if c==110 {c=10;}else if c==114 {c=13;}else if c==116 {c=9;}else if c==48 {c=0;}
        }
        store8(bytes+n,c);n=n+1;
    }
    store8(bytes+n,0);return address;
}
fn vm_ffi_kind(name,size) {
    if equal(name,size,"ffi_open",8) {return 7;}
    if equal(name,size,"ffi_symbol",10) {return 8;}
    if equal(name,size,"ffi_call",8) {return 9;}
    if equal(name,size,"ffi_call_i32",12) {return 10;}
    if equal(name,size,"ffi_call_u32",12) {return 11;}
    return 0;
}
fn vm_resolve() {
    let i=0;
    while i<call_count {
        let site=calls+i*32;let index=find(functions,function_count,load64(site),load64(site+8));
        let at=load64(site+16);
        if index>=0 {
            if load64(functions+index*32+24)!=load64(site+24) {locate_name(load64(site));fail("wrong function argument count");}
            store64(output+at,index);
        }else {
            let kind=vm_ffi_kind(load64(site),load64(site+8));
            if !kind {locate_name(load64(site));fail("undefined function");}
            let arity=7;if kind==7 {arity=1;}else if kind==8 {arity=2;}
            if arity!=load64(site+24) {locate_name(load64(site));fail("wrong FFI argument count");}
            store64(output+at-8,17);store64(output+at,kind);
        }
        i=i+1;
    }
    return 0;
}
fn vm_push(value) {
    if vm_sp>=524288 {vm_error=4;return 0;}
    store64(vm_stack+vm_sp,value);vm_sp=vm_sp+8;return 1;
}
fn vm_pop() {
    let floor=0;if vm_depth {floor=load64(vm_frames+(vm_depth-1)*40+24);}
    if vm_sp<=floor {vm_error=4;return 0;}
    vm_sp=vm_sp-8;return load64(vm_stack+vm_sp);
}
fn vm_enter(index,return_pc) {
    if index<0 || index>=function_count || vm_depth>=256 {vm_error=4;return 0;}
    let entry=functions+index*32;let pc=load64(entry+16);let count=load64(entry+24);
    let slots=load64(output+pc+8);
    if load64(output+pc)!=18 || slots<count || slots>4096 || vm_sp<count*8
        || vm_local_top+slots*8>8388608 {vm_error=9;return 0;}
    let frame=vm_frames+vm_depth*40;
    store64(frame,return_pc);store64(frame+8,vm_local_base);store64(frame+16,vm_local_top);
    store64(frame+24,vm_sp-count*8);store64(frame+32,index);
    vm_local_base=vm_local_top;vm_local_top=vm_local_top+slots*8;
    let i=0;
    while i<slots {
        let value=0;if i<count {value=load64(vm_stack+vm_sp-count*8+i*8);}
        store64(vm_local_memory+vm_local_base+i*8,value);i=i+1;
    }
    vm_sp=vm_sp-count*8;vm_depth=vm_depth+1;vm_pc=pc+16;return 1;
}
fn vm_return() {
    if !vm_depth {vm_error=9;return 0;}
    vm_depth=vm_depth-1;let frame=vm_frames+vm_depth*40;
    vm_pc=load64(frame);vm_local_base=load64(frame+8);vm_local_top=load64(frame+16);
    vm_sp=load64(frame+24);if vm_pc==-1 {vm_finished=1;}return 0;
}
fn vm_binary(op,a,b) {
    if op==43 {return a+b;}if op==45 {return a-b;}if op==42 {return a*b;}
    if op==47 || op==37 {
        if !b || (a==(-9223372036854775807-1) && b==-1) {vm_error=2;return 0;}
        if op==47 {return a/b;}return a%b;
    }
    if op==38 {return a&b;}if op==124 {return a|b;}if op==94 {return a^b;}
    if op==265 {return a<<(b&63);}if op==266 {return a>>(b&63);}
    if op==259 {return a==b;}if op==260 {return a!=b;}
    if op==60 {return a<b;}if op==62 {return a>b;}if op==261 {return a<=b;}if op==262 {return a>=b;}
    vm_error=9;return 0;
}
fn vm_now() {
    if syscall(228,1,vm_time,0,0,0,0)<0 {vm_error=8;return 0;}
    return load64(vm_time)*1000+load64(vm_time+8)/1000000;
}
fn vm_wait(fd,events) {
    let record=vm_open_how;store64(record,fd|(events<<32));
    let left=vm_deadline-vm_now();if left<=0 {vm_error=8;return 0;}
    let result=syscall(7,record,1,left,0,0,0);
    if !result {vm_error=8;return 0;}if result<0 {return 0;}return 1;
}
fn vm_host_fd(fd) {
    if fd<0 || fd>=67 {return -1;}return load64(vm_fds+fd*8);
}
fn vm_guest_path(pointer) {
    let i=0;
    while i<4096 {
        let address=vm_address(pointer+i,1);if !address {return 0;}
        let c=load8(address);store8(vm_path+i,c);if !c {return vm_path;}i=i+1;
    }
    vm_error=5;return 0;
}
fn vm_open_file(pointer,flags) {
    if vm_read_root<0 {vm_error=5;return -1;}
    // Read-only capability. Neither writable opens nor creation are available.
    if flags & ~(2048|524288|131072) {vm_error=5;return -1;}
    let path=vm_guest_path(pointer);if !path {return -1;}
    if load8(path)==47 {
        let n=length(vm_root_name);
        if n==1 && load8(vm_root_name)==47 {path=path+1;}
        else {
            if !equal(path,n,vm_root_name,n) || load8(path+n)!=47 {vm_error=5;return -1;}
            path=path+n+1;
        }
    }
    store64(vm_open_how,flags|524288|131072|2048);store64(vm_open_how+8,0);
    // RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS: kernel-enforced root confinement.
    store64(vm_open_how+16,10);
    let host=syscall(437,vm_read_root,path,vm_open_how,24,0,0);
    if host<0 {return host;}
    // Nonblocking opens and regular-file checks keep FIFO/device opens out of
    // this file capability. Filesystem kernel operations still need OS limits.
    if syscall(5,host,vm_file_stat,0,0,0,0)<0 || (load64(vm_file_stat+24)&61440)!=32768 {
        syscall(3,host,0,0,0,0,0);vm_error=5;return -1;
    }
    let fd=3;while fd<67 && load64(vm_fds+fd*8)>=0 {fd=fd+1;}
    if fd==67 {syscall(3,host,0,0,0,0,0);return -24;}
    store64(vm_fds+fd*8,host);return fd;
}
fn vm_poll_guest(pointer,count,timeout) {
    if count<0 || count>67 || timeout < -1 {return -22;}
    let address=0;if count {address=vm_address(pointer,count*8);if !address {return -1;}}
    let i=0;let invalid=0;
    while i<count {
        let record=load64(address+i*8);let fd=(record<<32)>>32;let events=(record>>32)&65535;
        if events & ~5 {vm_error=5;return -1;}
        let host=vm_host_fd(fd);if fd>=0 && host<0 {invalid=invalid+1;}
        store64(vm_poll_records+i*8,(host&0xffffffff)|(events<<32));i=i+1;
    }
    let left=vm_deadline-vm_now();if left<=0 {vm_error=8;return -1;}
    let wait=timeout;if wait<0 || wait>left {wait=left;}if invalid {wait=0;}
    let result=syscall(7,vm_poll_records,count,wait,0,0,0);
    if result<0 {return result;}
    if !result && !invalid && wait==left {vm_error=8;return -1;}
    i=0;while i<count {
        let record=load64(address+i*8);let fd=(record<<32)>>32;
        let events=(load64(vm_poll_records+i*8)>>48)&65535;
        if fd>=0 && vm_host_fd(fd)<0 {events=32;}
        store64(address+i*8,(record&0xffffffffffff)|(events<<48));i=i+1;
    }
    return result+invalid;
}
fn vm_syscall(number,a,b,c,d,e,f) {
    vm_denied_syscall=number;
    if number==60 {vm_acc=a;vm_finished=1;return a;}
    if !vm_restricted {return syscall(number,a,b,c,d,e,f);}
    if number==2 {return vm_open_file(a,b);}
    if number==7 {return vm_poll_guest(a,b,c);}
    if number==3 {
        let fd=vm_host_fd(a);if fd<0 {return -9;}
        store64(vm_fds+a*8,-1);if a>=3 {return syscall(3,fd,0,0,0,0,0);}return 0;
    }
    if number==228 {
        if a!=1 {vm_error=5;return -1;}let address=vm_address(b,16);if !address {return -1;}
        return syscall(228,1,address,0,0,0,0);
    }
    if number==5 {
        let fd=vm_host_fd(a);if fd<0 {return -9;}
        let address=vm_address(b,144);if !address {return -1;}
        return syscall(5,fd,address,0,0,0,0);
    }
    if number==0 || number==1 {
        let fd=vm_host_fd(a);if fd<0 {if a==0 && !vm_stdin {vm_error=5;}return -9;}
        if number==1 && a!=1 && a!=2 {vm_error=5;return -1;}
        if c<0 {vm_error=3;return -1;}if !c {return 0;}
        let address=vm_address(b,c);if !address {return -1;}
        if number==1 && c>vm_output_left {vm_error=7;return -1;}
        let count=c;if count>4096 {count=4096;}
        let events=1;if number==1 {events=4;}
        if !vm_wait(fd,events) {return -4;}
        let result=syscall(number,fd,address,count,0,0,0);
        if number==1 && result>0 {vm_output_left=vm_output_left-result;}
        return result;
    }
    vm_error=5;return -1;
}
fn vm_builtin(kind) {
    if kind>=7 {
        if vm_restricted {vm_error=5;vm_denied_ffi=kind;vm_denied_syscall=-1;return 0;}
        if kind==7 {return ffi_open(vm_pop());}
        if kind==8 {let name=vm_pop();let library=vm_pop();return ffi_symbol(library,name);}
        let f=vm_pop();let e=vm_pop();let d=vm_pop();let c=vm_pop();let b=vm_pop();let a=vm_pop();let pointer=vm_pop();
        if vm_error {return 0;}
        if kind==9 {return ffi_call(pointer,a,b,c,d,e,f);}
        if kind==10 {return ffi_call_i32(pointer,a,b,c,d,e,f);}
        if kind==11 {return ffi_call_u32(pointer,a,b,c,d,e,f);}
        vm_error=9;return 0;
    }
    if kind==1 || kind==2 {
        let pointer=vm_pop();let size=1;if kind==2 {size=8;}
        let address=vm_address(pointer,size);if !address {return 0;}
        if kind==1 {return load8(address);}return load64(address);
    }
    if kind==3 || kind==4 {
        let value=vm_pop();let pointer=vm_pop();let size=1;if kind==4 {size=8;}
        let address=vm_address(pointer,size);if !address {return 0;}
        if kind==3 {store8(address,value);}else {store64(address,value);}return value;
    }
    if kind==5 {
        let size=vm_pop();let budget=vm_allocate(size);
        if vm_restricted || budget<0 {return budget;}
        // Native mappings preserve alloc/munmap and FFI pointer semantics.
        let pointer=alloc(size);
        if pointer<0 {vm_heap_used=vm_heap_used-((size+7)/8)*8;}
        return pointer;
    }
    if kind==6 {
        let f=vm_pop();let e=vm_pop();let d=vm_pop();let c=vm_pop();let b=vm_pop();let a=vm_pop();let number=vm_pop();
        if vm_error {return 0;}return vm_syscall(number,a,b,c,d,e,f);
    }
    vm_error=9;return 0;
}
fn vm_execute(main_index) {
    if vm_enter(main_index,-1) && vm_jit_enabled {vm_try_jit(main_index);}
    while !vm_finished && !vm_error {
        if vm_fuel<=0 {vm_error=1;}
        else {
            if vm_steps%4096==0 && vm_now()>=vm_deadline {vm_error=8;}
            if !vm_error {
                if vm_pc<0 || vm_pc>output_size-16 || vm_pc%16 {vm_error=9;}
                else {
                    let op=load64(output+vm_pc);let arg=load64(output+vm_pc+8);
                    vm_pc=vm_pc+16;vm_fuel=vm_fuel-1;vm_steps=vm_steps+1;
                    if op==1 {vm_acc=arg;}
                    else if op==2 {vm_push(vm_acc);}
                    else if op==3 || op==4 {
                        let address=vm_local_memory+vm_local_base+arg*8;
                        if arg<0 || arg>4095 || address+8>vm_local_memory+vm_local_top {vm_error=9;}
                        else if op==3 {vm_acc=load64(address);}else {store64(address,vm_acc);}
                    }else if op==5 || op==6 {
                        let address=vm_address(arg,8);
                        if address {if op==5 {vm_acc=load64(address);}else {store64(address,vm_acc);}}
                    }else if op==7 {let a=vm_pop();if !vm_error {vm_acc=vm_binary(arg,a,vm_acc);}}
                    else if op==8 {
                        if vm_enter(arg,vm_pc) && vm_jit_enabled {vm_try_jit(arg);}
                    }else if op==9 {vm_return();}
                    else if op==10 {vm_pc=arg;}
                    else if op==11 {if !vm_acc {vm_pc=arg;}}
                    else if op==12 {if vm_acc {vm_pc=arg;}}
                    else if op==13 {vm_acc=vm_acc!=0;}
                    else if op==14 {vm_acc=-vm_acc;}
                    else if op==15 {vm_acc=!vm_acc;}
                    else if op==16 {vm_acc=~vm_acc;}
                    else if op==17 {vm_acc=vm_builtin(arg);}
                    else {vm_error=9;}
                }
            }
        }
    }
    return vm_acc;
}
fn vm_number(text) {
    let n=0;let i=0;
    while digit(load8(text+i)) {
        if n>1000000000 {return -1;}n=n*10+load8(text+i)-48;i=i+1;
    }
    if !i {return -1;}
    let c=load8(text+i);
    if c==109 || c==77 {n=n*1048576;i=i+1;}
    else if c==107 || c==75 {n=n*1024;i=i+1;}
    if load8(text+i) || n<=0 || n>1000000000 {return -1;}return n;
}
fn vm_prefix(text,prefix) {return equal(text,length(prefix),prefix,length(prefix));}
fn vm_help(fd) {
    print(fd,"Usage: flex run [options] <source.flex> [args...]\n");
    print(fd,"  --interpret          bytecode interpreter only\n  --jit                compile eligible functions on first call\n  --stats              report interpreter/JIT counters\n");
    print(fd,"  --fuel=N             instruction budget (default 10000000)\n  --memory=N           guest heap bytes; k/m suffixes accepted (default 16m)\n  --timeout-ms=N       execution deadline (default 5000)\n");
    print(fd,"  --restricted        use isolated guest memory and capability-limited host calls\n");
    print(fd,"  --allow-read=DIR     grant read-only files in restricted mode\n  --allow-stdin        grant standard input in restricted mode\n  --allow-url-imports  enable source downloads in restricted mode\n  --no-url-imports     disable HTTP/HTTPS source downloads\n");return 0;
}
fn vm_initialize() {
    vm_heap=alloc(vm_heap_limit);vm_stack=alloc(524288);vm_local_memory=alloc(8388608);
    vm_frames=alloc(256*40);vm_time=alloc(16);vm_path=alloc(4096);vm_open_how=alloc(24);
    vm_fds=alloc(67*8);vm_jit_cache=alloc(2048*32);vm_jit_context=alloc(64);
    vm_poll_records=alloc(67*8);
    vm_file_stat=alloc(144);
    if vm_heap<0 || vm_stack<0 || vm_local_memory<0 || vm_frames<0 || vm_time<0
        || vm_path<0 || vm_open_how<0 || vm_fds<0 || vm_jit_cache<0 || vm_jit_context<0
        || vm_poll_records<0 || vm_file_stat<0 {return 0;}
    let i=0;while i<67 {store64(vm_fds+i*8,-1);i=i+1;}
    if vm_stdin {store64(vm_fds,0);}store64(vm_fds+8,1);store64(vm_fds+16,2);
    if vm_jit_enabled && !ffi_open("libc.so.6") {
        vm_jit_enabled=0;if vm_jit_explicit {print(2,"flex vm: JIT requires the full compiler runtime.\n");return 0;}
    }
    return 1;
}
fn vm_copy_arg(text) {
    let n=length(text);let address=vm_allocate(n+1);if address<0 {vm_error=3;return 0;}
    let bytes=vm_address(address,n+1);
    let i=0;while i<=n {store8(bytes+i,load8(text+i));i=i+1;}return address;
}
fn vm_main(argc,argv) {
    let first=2;let root=0;let imports=-1;
    while first<argc && load8(load64(argv+first*8))==45 {
        let arg=load64(argv+first*8);
        if up_text(arg,"--help") {vm_help(1);return 0;}
        if up_text(arg,"--interpret") {vm_jit_enabled=0;}
        else if up_text(arg,"--jit") {vm_jit_enabled=1;vm_jit_explicit=1;vm_jit_threshold=1;}
        else if up_text(arg,"--stats") {vm_show_stats=1;}
        else if up_text(arg,"--restricted") {vm_restricted=1;}
        else if up_text(arg,"--allow-stdin") {vm_stdin=1;}
        else if up_text(arg,"--allow-url-imports") {imports=1;}
        else if up_text(arg,"--no-url-imports") {imports=0;}
        else if vm_prefix(arg,"--allow-read=") {root=arg+13;if !length(root) {vm_help(2);return 1;}}
        else if vm_prefix(arg,"--fuel=") {vm_fuel=vm_number(arg+7);if vm_fuel<0 {vm_help(2);return 1;}}
        else if vm_prefix(arg,"--memory=") {vm_heap_limit=vm_number(arg+9);if vm_heap_limit<4096 {vm_help(2);return 1;}}
        else if vm_prefix(arg,"--timeout-ms=") {vm_timeout=vm_number(arg+13);if vm_timeout<0 {vm_help(2);return 1;}}
        else {vm_help(2);return 1;}
        first=first+1;
    }
    if first>=argc {vm_help(2);return 1;}
    url_import_allowed=!vm_restricted;if imports>=0 {url_import_allowed=imports;}
    if !vm_initialize() {print(2,"flex vm: cannot initialize VM.\n");return 70;}
    if root && vm_restricted {
        vm_read_root=syscall(2,root,0x2b0000,0,0,0,0);
        if vm_read_root<0 {print(2,"flex vm: cannot open read capability directory.\n");return 70;}
        let path=up_join("/proc/self/fd/",up_number(vm_read_root),"");vm_root_name=alloc(4096);
        if !path || vm_root_name<0 {return 70;}
        let n=syscall(89,path,vm_root_name,4095,0,0,0);
        if n<0 {return 70;}store8(vm_root_name+n,0);
    }
    source_path=load64(argv+first*8);vm_mode=1;compiler_initialize();load_module(source_path);
    initialize_output();compile_modules();select_module(0);token_start=source_size;resolve();
    let main_index=find(functions,function_count,"main",4);let count=load64(functions+main_index*32+24);
    if count==2 {
        let guest_argc=argc-first;let guest_argv=vm_allocate((guest_argc+1)*8);
        if guest_argv<0 {vm_error=3;}
        else {
            let bytes=vm_address(guest_argv,(guest_argc+1)*8);
            let i=0;while i<guest_argc {store64(bytes+i*8,vm_copy_arg(load64(argv+(first+i)*8)));i=i+1;}
            vm_push(guest_argc);vm_push(guest_argv);
        }
    }
    vm_deadline=vm_now()+vm_timeout;
    if !vm_error {vm_execute(main_index);}
    let i=3;while i<67 {let fd=load64(vm_fds+i*8);if fd>=0 {syscall(3,fd,0,0,0,0,0);}i=i+1;}
    if vm_read_root>=0 {syscall(3,vm_read_root,0,0,0,0,0);}
    vm_jit_cleanup();
    if vm_show_stats {
        print(2,"VM steps: ");print_number(vm_steps);print(2,"; JIT compilations: ");print_number(vm_jit_compilations);
        print(2,"; JIT calls: ");print_number(vm_jit_calls);print(2,"; fuel remaining: ");print_number(vm_fuel);print(2,"\n");
    }
    if vm_error {
        print(2,"flex vm: ");
        if vm_error==1 {print(2,"instruction budget exhausted");}
        else if vm_error==2 {print(2,"integer division trap");}
        else if vm_error==3 {print(2,"guest memory access out of bounds");}
        else if vm_error==4 {print(2,"VM stack limit exceeded");}
        else if vm_error==5 {
            print(2,"host capability denied");
            if vm_denied_ffi {print(2," (raw FFI)");}
            else if vm_denied_syscall>=0 {print(2," (syscall ");print_number(vm_denied_syscall);print(2,")");}
        }
        else if vm_error==7 {print(2,"output limit exceeded");}
        else if vm_error==8 {print(2,"execution deadline exceeded");}
        else {print(2,"invalid bytecode");}
        print(2,"\n");return 70;
    }
    return vm_acc;
}
