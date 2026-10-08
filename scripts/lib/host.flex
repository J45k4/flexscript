// Native Linux host support for Flexscript's build and test tools.
// Commands are argv vectors passed to execve, never shell interpolation.
import "../../lib/net.flex";
global h_blocks=0;
global h_used=0;
global h_capacity=0;
global h_env=0;
global h_file_size=0;
global h_timeout=30000;
global h_output_limit=33554432;
global h_child_memory=0;
global h_ffi_bridge=0;
fn h_len(s) {
    let n=0;
    if s {
        while load8(s+n) {
            n=n+1;
        }
    }
    return n;
}
fn h_print(fd,s) {
    return h_write(fd,s,h_len(s));
}
fn h_die(s) {
    h_print(2,"Flexscript tool: ");
    h_print(2,s);
    h_print(2,"\n");
    syscall(60,1,0,0,0,0,0);
    return 0;
}
fn h_assert(ok,s) {
    if !ok {
        h_die(s);
    }
    return 0;
}
fn h_take(n) {
    h_assert(n>=0 && n<=134217728,"host allocation limit");
    n=(n+7)/8*8;
    if !h_blocks || n>h_capacity-h_used {
        let size=1048576;
        if size<n+16 {
            size=((n+16+4095)/4096)*4096;
        }
        let p=alloc(size);
        h_assert(p>0,"host allocation failed");
        store64(p,h_blocks);
        store64(p+8,size);
        h_blocks=p;
        h_capacity=size-16;
        h_used=0;
    }
    let p=h_blocks+16+h_used;
    h_used=h_used+n;
    return p;
}
fn h_mark() {
    h_used=h_capacity;
    return h_blocks;
}
fn h_reset(mark) {
    while h_blocks!=mark {
        let old=h_blocks;
        h_blocks=load64(old);
        syscall(11,old,load64(old+8),0,0,0,0);
    }
    if h_blocks {
        h_capacity=load64(h_blocks+8)-16;
    }else {
        h_capacity=0;
    }
    h_used=h_capacity;
    return 0;
}
fn h_copy(to,from,n) {
    let i=0;
    while i<n {
        store8(to+i,load8(from+i));
        i=i+1;
    }
    return to;
}
fn h_zero(p,n) {
    let i=0;
    while i<n {
        store8(p+i,0);
        i=i+1;
    }
    return p;
}
fn h_slice(s,n) {
    let p=h_take(n+1);
    h_copy(p,s,n);
    store8(p+n,0);
    return p;
}
fn h_cat(a,b) {
    let n=h_len(a);
    let m=h_len(b);
    let p=h_take(n+m+1);
    h_copy(p,a,n);
    h_copy(p+n,b,m);
    store8(p+n+m,0);
    return p;
}
fn h_cat3(a,b,c) {
    return h_cat(h_cat(a,b),c);
}
fn h_equal(a,b) {
    if !a || !b {
        return a==b;
    }
    let i=0;
    while load8(a+i) && load8(a+i)==load8(b+i) {
        i=i+1;
    }
    return load8(a+i)==load8(b+i);
}
fn h_bytes(a,b,n) {
    let i=0;
    while i<n {
        if load8(a+i)!=load8(b+i) {
            return 0;
        }
        i=i+1;
    }
    return 1;
}
fn h_starts(a,b) {
    return h_len(a)>=h_len(b) && h_bytes(a,b,h_len(b));
}
fn h_find(s,needle) {
    let n=h_len(s);
    let m=h_len(needle);
    let i=0;
    while i<=n-m {
        if h_bytes(s+i,needle,m) {
            return i;
        }
        i=i+1;
    }
    return -1;
}
fn h_has(s,needle) {
    return h_find(s,needle)>=0;
}
fn h_replace(s,old,new) {
    let b=h_buffer();
    let i=0;
    let n=h_len(old);
    let total=h_len(s);
    h_assert(n>0,"empty replacement pattern");
    while i<total {
        if total-i>=n && h_bytes(s+i,old,n) {
            h_append(b,new,h_len(new));
            i=i+n;
        }else {
            h_append(b,s+i,1);
            i=i+1;
        }
    }
    return h_data(b);
}
fn h_int(n) {
    let p=h_take(32);
    let i=31;
    store8(p+i,0);
    let negative=n<0;
    if !negative {
        n=-n;
    }
    while n<=-10 {
        i=i-1;
        store8(p+i,48-n%10);
        n=n/10;
    }
    i=i-1;
    store8(p+i,48-n);
    if negative {
        i=i-1;
        store8(p+i,45);
    }
    return p+i;
}
fn h_number(s) {
    let n=0;
    let i=0;
    h_assert(load8(s)!=0,"empty integer");
    while load8(s+i) {
        let c=load8(s+i);
        h_assert(c>=48 && c<=57 && n<=(9223372036854775807-(c-48))/10,"invalid integer");
        n=n*10+c-48;
        i=i+1;
    }
    return n;
}
fn h_hex(p,n) {
    let text=h_take(n*2+1);
    let i=0;
    let digits="0123456789abcdef";
    while i<n {
        let c=load8(p+i);
        store8(text+i*2,load8(digits+(c>>4)));
        store8(text+i*2+1,load8(digits+(c&15)));
        i=i+1;
    }
    store8(text+n*2,0);
    return text;
}
fn h_unhex(s) {
    let n=h_len(s);
    h_assert(n%2==0,"invalid hex length");
    let p=h_take(n/2+1);
    let i=0;
    while i<n {
        let c=load8(s+i);
        let v=-1;
        if c>=48 && c<=57 {
            v=c-48;
        }else if c>=97 && c<=102 {
            v=c-87;
        }else if c>=65 && c<=70 {
            v=c-55;
        }
        h_assert(v>=0,"invalid hex byte");
        let at=p+i/2;
        if i%2==0 {
            store8(at,v<<4);
        }else {
            store8(at,load8(at)|v);
        }
        i=i+1;
    }
    store8(p+n/2,0);
    return p;
}
fn h_trim(s) {
    let n=h_len(s);
    while n>0 && load8(s+n-1)<=32 {
        n=n-1;
    }
    while n>0 && load8(s)<=32 {
        s=s+1;
        n=n-1;
    }
    return h_slice(s,n);
}
fn h_repeat(s,n) {
    let m=h_len(s);
    h_assert(n>=0 && n<=67108864/(m+1),"repeat limit");
    let p=h_take(m*n+1);
    let i=0;
    while i<n {
        h_copy(p+i*m,s,m);
        i=i+1;
    }
    store8(p+m*n,0);
    return p;
}
fn h_vec() {
    return h_zero(h_take(32776),32776);
}
fn h_count(v) {
    return load64(v);
}
fn h_at(v,i) {
    h_assert(i>=0 && i<h_count(v),"vector index");
    return load64(v+8+i*8);
}
fn h_add(v,item) {
    let n=h_count(v);
    h_assert(n<4095,"vector capacity");
    store64(v+8+n*8,item);
    store64(v,n+1);
    return v;
}
fn h_args(a,b,c,d,e,f) {
    let v=h_vec();
    if a {
        h_add(v,a);
    }
    if b {
        h_add(v,b);
    }
    if c {
        h_add(v,c);
    }
    if d {
        h_add(v,d);
    }
    if e {
        h_add(v,e);
    }
    if f {
        h_add(v,f);
    }
    return v;
}
fn h_buffer() {
    let p=h_take(24);
    store64(p,0);
    store64(p+8,0);
    store64(p+16,0);
    return p;
}
fn h_append(b,p,n) {
    let size=load64(b+8);
    let cap=load64(b+16);
    h_assert(n>=0 && size<=134217727-n,"buffer limit");
    if size+n+1>cap {
        let next=4096;
        while next<size+n+1 {
            next=next*2;
        }
        let data=h_take(next);
        h_copy(data,load64(b),size);
        store64(b,data);
        store64(b+16,next);
    }
    h_copy(load64(b)+size,p,n);
    store64(b+8,size+n);
    store8(load64(b)+size+n,0);
    return b;
}
fn h_data(b) {
    if !load64(b) {
        h_append(b,"",0);
    }
    return load64(b);
}
fn h_size(b) {
    return load64(b+8);
}
fn h_text(b,s) {
    return h_append(b,s,h_len(s));
}
fn h_write(fd,p,n) {
    let i=0;
    while i<n {
        let k=syscall(1,fd,p+i,n-i,0,0,0);
        if k==-4 {
        }else if k<=0 {
            return -1;
        }else {
            i=i+k;
        }
    }
    return n;
}
fn h_close(fd) {
    if fd>=0 {
        syscall(3,fd,0,0,0,0,0);
    }
    return 0;
}
fn h_read(path) {
    let fd=syscall(2,path,0x80000,0,0,0,0);
    h_assert(fd>=0,h_cat("cannot read ",path));
    let b=h_buffer();
    let scratch=h_take(65536);
    let more=1;
    while more {
        let n=syscall(0,fd,scratch,65536,0,0,0);
        if n>0 {
            h_assert(h_size(b)+n<=67108864,"file exceeds 64 MiB");
            h_append(b,scratch,n);
        }else if n!=-4 {
            h_assert(n==0,"file read failed");
            more=0;
        }
    }
    h_close(fd);
    h_file_size=h_size(b);
    return h_data(b);
}
fn h_save_bytes(path,p,n,mode) {
    let fd=syscall(2,path,0x80241,mode,0,0,0);
    h_assert(fd>=0,h_cat("cannot create ",path));
    h_assert(h_write(fd,p,n)==n,"file write failed");
    h_assert(syscall(3,fd,0,0,0,0,0)==0,"file close failed");
    return 0;
}
fn h_save(path,s) {
    return h_save_bytes(path,s,h_len(s),420);
}
fn h_exists(path) {
    return syscall(21,path,0,0,0,0,0)==0;
}
fn h_isdir(path) {
    let stat=h_take(144);
    if syscall(4,path,stat,0,0,0,0)<0 {
        return 0;
    }
    return (load64(stat+24)&61440)==16384;
}
fn h_mkdir(path) {
    if !h_len(path) || h_isdir(path) {
        return 0;
    }
    let n=h_len(path);
    let i=n-1;
    while i>0 && load8(path+i)!=47 {
        i=i-1;
    }
    if i>0 {
        h_mkdir(h_slice(path,i));
    }
    let r=syscall(83,path,448,0,0,0,0);
    h_assert(r==0 || (r==-17 && h_isdir(path)),h_cat("mkdir failed: ",path));
    return 0;
}
fn h_join(a,b) {
    if load8(b)==47 {
        return b;
    }
    return h_cat3(a,"/",b);
}
fn h_dir(path) {
    let i=h_len(path)-1;
    while i>=0 && load8(path+i)!=47 {
        i=i-1;
    }
    if i<0 {
        return ".";
    }
    if i==0 {
        return "/";
    }
    return h_slice(path,i);
}
fn h_absolute(path) {
    if load8(path)==47 {
        return path;
    }
    let cwd=h_take(4096);
    h_assert(syscall(79,cwd,4096,0,0,0,0)>0,"getcwd failed");
    return h_join(cwd,path);
}
fn h_real(path) {
    let lib=ffi_open("libc.so.6");
    let p=h_take(4096);
    h_assert(ffi_call(ffi_symbol(lib,"realpath"),path,p,0,0,0,0)!=0,h_cat("realpath failed: ",path));
    return p;
}
fn h_temp() {
    let p=h_take(8);
    h_assert(syscall(318,p,8,0,0,0,0)==8,"getrandom failed");
    let path=h_cat("/tmp/flexscript-tools-",h_hex(p,8));
    h_assert(syscall(83,path,448,0,0,0,0)==0,"temporary directory failed");
    return path;
}
fn h_environment(argc,argv) {
    h_env=argv+(argc+1)*8;
    let limits=h_zero(h_take(16),16);
    syscall(160,4,limits,0,0,0,0);
    let action=h_zero(h_take(32),32);
    store64(action,1);
    syscall(13,13,action,0,8,0,0);
    return 0;
}
fn h_restore_sigpipe() {
    // Keep broken-pipe handling private to the harness. Executed programs
    // receive the normal signal disposition, so HTTP crash checks stay valid.
    let action=h_zero(h_take(32),32);
    h_assert(syscall(13,13,action,0,8,0,0)==0,"reset child SIGPIPE failed");
    return 0;
}
fn h_getenv(key) {
    let n=h_len(key);
    let i=0;
    while load64(h_env+i*8) {
        let s=load64(h_env+i*8);
        if h_starts(s,key) && load8(s+n)==61 {
            return s+n+1;
        }
        i=i+1;
    }
    return 0;
}
fn h_setenv(key,value) {
    let v=h_vec();
    let i=0;
    let n=h_len(key);
    while load64(h_env+i*8) {
        let s=load64(h_env+i*8);
        if !(h_starts(s,key) && load8(s+n)==61) {
            h_add(v,s);
        }
        i=i+1;
    }
    if value {
        h_add(v,h_cat3(key,"=",value));
    }
    h_env=v+8;
    store64(h_env+h_count(v)*8,0);
    return 0;
}
fn h_executable(name) {
    if h_has(name,"/") {
        return name;
    }
    let path=h_getenv("PATH");
    if !path {
        path="/usr/bin:/bin";
    }
    let i=0;
    let start=0;
    while 1 {
        if !load8(path+i) || load8(path+i)==58 {
            let part=h_slice(path+start,i-start);
            if !h_len(part) {
                part=".";
            }
            let file=h_join(part,name);
            if syscall(21,file,1,0,0,0,0)==0 {
                return file;
            }
            if !load8(path+i) {
                return name;
            }
            start=i+1;
        }
        i=i+1;
    }
    return name;
}
// Process record: pid, status, stdout buffer, stderr buffer, stdin/stdout/stderr
// fds, input pointer/size/position, start time. Status uses subprocess convention.
fn h_spawn(args,input,cwd) {
    h_assert(h_count(args)>0,"empty command");
    let executable=h_executable(h_at(args,0));
    let a=h_take((h_count(args)+1)*8);
    let i=0;
    while i<h_count(args) {
        store64(a+i*8,h_at(args,i));
        i=i+1;
    }
    store64(a+i*8,0);
    let pipes=h_take(24);
    h_assert(syscall(293,pipes,0x80000,0,0,0,0)==0 && syscall(293,pipes+8,0x80000,0,0,0,0)==0 && syscall(293,pipes+16,0x80000,0,0,0,0)==0,"pipe failed");
    let pid=syscall(57,0,0,0,0,0,0);
    h_assert(pid>=0,"fork failed");
    if pid==0 {
        h_restore_sigpipe();
        syscall(157,1,9,0,0,0,0);
        syscall(109,0,0,0,0,0,0);
        syscall(33,load64(pipes)&0xffffffff,0,0,0,0,0);
        syscall(33,load64(pipes+8)>>32,1,0,0,0,0);
        syscall(33,load64(pipes+16)>>32,2,0,0,0,0);
        i=0;
        while i<6 {
            h_close((load64(pipes+(i/2)*8)>>(32*(i%2)))&0xffffffff);
            i=i+1;
        }
        if cwd && syscall(80,cwd,0,0,0,0,0)<0 {
            syscall(60,126,0,0,0,0,0);
        }
        if h_child_memory {
            let limit=h_take(16);
            store64(limit,h_child_memory);
            store64(limit+8,h_child_memory);
            syscall(160,9,limit,0,0,0,0);
        }
        syscall(59,executable,a,h_env,0,0,0);
        syscall(60,127,0,0,0,0,0);
    }
    h_close(load64(pipes)&0xffffffff);
    h_close(load64(pipes+8)>>32);
    h_close(load64(pipes+16)>>32);
    let p=h_zero(h_take(96),96);
    store64(p,pid);
    store64(p+8,-999);
    store64(p+16,h_buffer());
    store64(p+24,h_buffer());
    store64(p+32,load64(pipes)>>32);
    store64(p+40,load64(pipes+8)&0xffffffff);
    store64(p+48,load64(pipes+16)&0xffffffff);
    store64(p+56,input);
    store64(p+64,h_len(input));
    store64(p+80,net_now());
    i=32;
    while i<=48 {
        syscall(72,load64(p+i),4,2048,0,0,0);
        i=i+8;
    }
    if input && !h_len(input) {
        h_close(load64(p+32));
        store64(p+32,-1);
    }
    return p;
}
fn h_pump(p,ms) {
    let status=h_take(8);
    let waited=syscall(61,load64(p),status,1,0,0,0);
    if waited==load64(p) {
        let s=load64(status)&0xffff;
        let code=(s>>8)&255;
        if s&127 {
            code=-(s&127);
        }
        store64(p+8,code);
    }
    let scratch=h_take(8192);
    let i=0;
    while i<2 {
        let at=40+i*8;
        let fd=load64(p+at);
        if fd>=0 {
            let reading=1;
            while reading {
                let n=syscall(0,fd,scratch,8192,0,0,0);
                if n>0 {
                    let b=load64(p+16+i*8);
                    h_assert(h_size(b)+n<=h_output_limit,"child output exceeds limit");
                    h_append(b,scratch,n);
                }else if n==-4 {
                }else {
                    reading=0;
                    if n==0 || n==-5 {
                        h_close(fd);
                        store64(p+at,-1);
                    }
                }
            }
        }
        i=i+1;
    }
    let fd=load64(p+32);
    if fd>=0 && load64(p+56) {
        let left=load64(p+64)-load64(p+72);
        if left>0 {
            let n=syscall(1,fd,load64(p+56)+load64(p+72),left,0,0,0);
            if n>0 {
                store64(p+72,load64(p+72)+n);
            }else {
                h_assert(n==-11 || n==-4,"child stdin write failed");
            }
        }
        if load64(p+72)==load64(p+64) {
            h_close(fd);
            store64(p+32,-1);
        }
    }
    if ms>0 {
        let poll=h_take(24);
        i=0;
        while i<3 {
            let fd=load64(p+32+i*8);
            let events=1;
            if i==0 {
                events=4;
                if !load64(p+56) {
                    fd=-1;
                }
            }
            store64(poll+i*8,(fd&0xffffffff)|(events<<32));
            i=i+1;
        }
        syscall(7,poll,3,ms,0,0,0);
    }
    return load64(p+8)!=-999;
}
fn h_stop(p) {
    if load64(p+8)==-999 {
        syscall(62,-load64(p),9,0,0,0,0);
        syscall(62,load64(p),9,0,0,0,0);
        let status=h_take(8);
        syscall(61,load64(p),status,0,0,0,0);
        store64(p+8,-9);
    }
    h_close(load64(p+32));
    h_close(load64(p+40));
    h_close(load64(p+48));
    store64(p+32,-1);
    store64(p+40,-1);
    store64(p+48,-1);
    return 0;
}
fn h_wait(p) {
    while load64(p+8)==-999 || load64(p+40)>=0 || load64(p+48)>=0 {
        h_pump(p,10);
        if net_now()-load64(p+80)>h_timeout {
            h_stop(p);
            h_die("child process timed out");
        }
    }
    h_close(load64(p+32));
    store64(p+32,-1);
    return p;
}
fn h_run(args) {
    return h_wait(h_spawn(args,"",0));
}
fn h_out(p) {
    return h_data(load64(p+16));
}
fn h_err(p) {
    return h_data(load64(p+24));
}
fn h_status(p) {
    return load64(p+8);
}
fn h_check(p,status,out) {
    if h_status(p)!=status {
        h_print(2,h_err(p));
        h_die(h_cat3("exit ",h_int(h_status(p)),h_cat(" expected ",h_int(status))));
    }
    if out {
        h_assert(h_size(load64(p+16))==h_len(out) && h_bytes(h_out(p),out,h_len(out)),h_cat("unexpected stdout: ",h_out(p)));
    }
    return p;
}
fn h_ok(args) {
    return h_check(h_run(args),0,0);
}
fn h_compile(compiler,source,binary) {
    let p=h_ok(h_args(compiler,source,"-o",binary,0,0));
    h_assert(h_equal(h_err(p),""),h_err(p));
    return 0;
}
fn h_send(p,text) {
    h_assert(load64(p+32)>=0,"closed child stdin");
    store64(p+56,text);
    store64(p+64,h_len(text));
    store64(p+72,0);
    return 0;
}
fn h_until(p,text,ms) {
    let end=net_now()+ms;
    while !h_has(h_out(p),text) {
        h_pump(p,5);
        h_assert(h_status(p)==-999 || h_has(h_out(p),text),h_cat("child exited: ",h_err(p)));
        h_assert(net_now()<end,h_cat("missing child output: ",text));
    }
    return 0;
}
fn h_sleep(ms) {
    let time=h_take(16);
    store64(time,ms/1000);
    store64(time+8,(ms%1000)*1000000);
    return syscall(35,time,0,0,0,0,0);
}
fn h_remove(path) {
    if h_exists(path) {
        h_ok(h_args("rm","-rf","--",path,0,0));
    }
    return 0;
}
fn h_sha_bytes(data,size) {
    let lib=ffi_open("libcrypto.so.3");
    h_assert(lib,"OpenSSL 3 libcrypto is required");
    let digest=h_take(32);
    h_assert(ffi_call(ffi_symbol(lib,"SHA256"),data,size,digest,0,0,0)==digest,"SHA256 failed");
    return h_hex(digest,32);
}
fn h_sha(path) {
    let data=h_read(path);
    return h_sha_bytes(data,h_file_size);
}
fn h_elf(path,standalone) {
    let p=h_read(path);
    let n=h_file_size;
    h_assert(n>=120 && load8(p)==127 && h_bytes(p+1,"ELF",3) && load8(p+4)==2 && load8(p+5)==1 && load8(p+6)==1 && ((load8(p+19)<<8)|load8(p+18))==62,"expected Linux x86-64 ELF");
    let offset=load64(p+32);
    let size=load8(p+54)|(load8(p+55)<<8);
    let count=load8(p+56)|(load8(p+57)<<8);
    h_assert(count==1 || (!standalone && count==4),"unexpected ELF program headers");
    let i=0;
    while i<count {
        h_assert(offset+i*size+4<=n,"ELF header out of bounds");
        let expected=1;
        if count==4 {
            if i==0 {
                expected=6;
            }else if i==1 {
                expected=3;
            }else if i==3 {
                expected=2;
            }
        }
        h_assert((load64(p+offset+i*size)&0xffffffff)==expected,"unexpected ELF segment");
        i=i+1;
    }
    return 0;
}
fn h_entries(path) {
    let fd=syscall(2,path,0x90000,0,0,0,0);
    h_assert(fd>=0,"directory open failed");
    let result=h_vec();
    let data=h_take(32768);
    let more=1;
    while more {
        let n=syscall(217,fd,data,32768,0,0,0);
        h_assert(n>=0,"getdents failed");
        if !n {
            more=0;
        }
        let i=0;
        while i<n {
            let size=load8(data+i+16)|(load8(data+i+17)<<8);
            h_assert(size>=20 && size<=n-i,"invalid directory entry");
            let name=data+i+19;
            if !h_equal(name,".") && !h_equal(name,"..") {
                h_add(result,h_slice(name,h_len(name)));
            }
            i=i+size;
        }
    }
    h_close(fd);
    return result;
}
fn h_trigger(process,text) {
    let n=h_write(load64(process+32),text,h_len(text));
    h_assert(n==h_len(text),"interactive input failed");
    return 0;
}
// Trusted tooling adapter for APIs with eight integer/pointer parameters.
// The language's six-argument FFI intrinsic remains unchanged.
fn h_ffi8(pointer,a,b,c,d,e,f,g,h) {
    if !h_ffi_bridge {
        let code=h_unhex("4989fa4883ec18498b423848890424498b42404889442408498b7a08498b7210498b5218498b4a204d8b42284d8b4a30498b02ffd04883c418c3");
        h_ffi_bridge=alloc(4096);
        h_assert(h_ffi_bridge>0,"FFI adapter allocation");
        h_copy(h_ffi_bridge,code,58);
        h_assert(syscall(10,h_ffi_bridge,4096,5,0,0,0)==0,"FFI adapter mprotect");
    }
    let args=h_take(72);
    store64(args,pointer);
    store64(args+8,a);
    store64(args+16,b);
    store64(args+24,c);
    store64(args+32,d);
    store64(args+40,e);
    store64(args+48,f);
    store64(args+56,g);
    store64(args+64,h);
    return ffi_call(h_ffi_bridge,args,0,0,0,0,0);
}
