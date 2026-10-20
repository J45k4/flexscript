// Trusted Linux process boundary. Guest source only enters the last file mount.
import "workspace.flex";
global cw_buffer=0;
global cw_pending=0;
global cw_sent=0;
global cw_reply_size=0;
global cw_calls=0;
global cw_response_bytes=0;

fn cp_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95;}
fn cp_validate(source) {
    let size=h_len(source);
    if !size || !h_len(h_trim(source)) {return "Return a complete Flexscript program.";}
    if size>65536 {return "Source must be at most 64 KiB.";}
    let i=0;
    while i<size {
        let c=load8(source+i);
        if c==47 && i+1<size && load8(source+i+1)==47 {
            while i<size && load8(source+i)!=10 {i=i+1;}
        }else if c==34 {
            i=i+1;let more=1;
            while i<size && more {
                c=load8(source+i);i=i+1;
                if c==92 && i<size {i=i+1;}
                else if c==34 {more=0;}
            }
        }else if cp_letter(c) {
            let start=i;i=i+1;
            while i<size && (cp_letter(load8(source+i)) || c_json_digit(load8(source+i))) {i=i+1;}
            let name=h_slice(source+start,i-start);
            if h_equal(name,"import") || h_equal(name,"extend") {
                return "Imports and compiler extensions are unavailable. Return a self-contained program.";
            }
        }else {
            if c==96 {return "Return raw Flexscript source without Markdown fences.";}
            i=i+1;
        }
    }
    return 0;
}
fn cp_add_library(libraries,path) {
    let i=0;while i<h_count(libraries) {if h_equal(h_at(libraries,i),path) {return 0;}i=i+1;}
    h_add(libraries,path);return 0;
}
fn cp_libraries(compiler) {
    let process=h_run(h_args("ldd",compiler,0,0,0,0));let text=h_out(process);let libraries=h_vec();
    if h_has(text,"statically linked") || h_has(text,"not a dynamic executable") || h_has(h_err(process),"not a dynamic executable") {return libraries;}
    if h_status(process) || h_has(text,"not found") {return 0;}
    let i=0;
    while load8(text+i) {
        if load8(text+i)==47 {
            let start=i;
            while load8(text+i)>32 {i=i+1;}
            cp_add_library(libraries,h_slice(text+start,i-start));
        }else {i=i+1;}
    }
    if !h_count(libraries) {return 0;}
    // Preserve the interpreter path stored in ELF even when ldd canonicalizes
    // /lib64 into /usr/lib64. Both file paths must exist in the isolated root.
    let bytes=h_read(compiler);let size=h_file_size;
    if size<64 || load8(bytes)!=127 || !h_bytes(bytes+1,"ELF",3) || load8(bytes+4)!=2 || load8(bytes+5)!=1 {return 0;}
    let offset=load64(bytes+32);let width=load8(bytes+54)|(load8(bytes+55)<<8);
    let count=load8(bytes+56)|(load8(bytes+57)<<8);i=0;
    if width<56 || offset<64 || offset>size || count>(size-offset)/width {return 0;}
    while i<count {
        let header=bytes+offset+i*width;
        if (load64(header)&0xffffffff)==3 {
            let start=load64(header+8);let length=load64(header+32);
            if start<0 || start>=size || length<2 || length>4096 || length>size-start || load8(bytes+start+length-1)!=0 {return 0;}
            cp_add_library(libraries,h_slice(bytes+start,length-1));
        }
        i=i+1;
    }
    return libraries;
}
fn cp_command(compiler,source_file,libraries,database) {
    let args=h_args("prlimit","--as=1073741824","--cpu=4","--fsize=4194304","--nofile=64","--core=0");
    h_add(args,"--");h_add(args,h_executable("bwrap"));
    h_add(args,"--unshare-all");h_add(args,"--die-with-parent");h_add(args,"--new-session");
    h_add(args,"--cap-drop");h_add(args,"ALL");h_add(args,"--clearenv");
    h_add(args,"--setenv");h_add(args,"LANG");h_add(args,"C");
    h_add(args,"--proc");h_add(args,"/proc");h_add(args,"--dev");h_add(args,"/dev");
    h_add(args,"--tmpfs");h_add(args,"/tmp");h_add(args,"--ro-bind");h_add(args,compiler);h_add(args,"/bin/flex");
    let i=0;while i<h_count(libraries) {
        let library=h_at(libraries,i);h_add(args,"--ro-bind");h_add(args,library);h_add(args,library);i=i+1;
    }
    h_add(args,"--ro-bind");h_add(args,source_file);h_add(args,"/guest/main.flex");
    if database {h_add(args,"--ro-bind");h_add(args,h_join(h_dir(source_file),"sdk.flex"));h_add(args,"/guest/sdk.flex");}
    h_add(args,"--chdir");h_add(args,"/guest");h_add(args,"--");h_add(args,"/bin/flex");
    h_add(args,"run");h_add(args,"--restricted");h_add(args,"--interpret");h_add(args,"--no-url-imports");
    h_add(args,"--fuel=1000000");h_add(args,"--memory=4m");h_add(args,"--timeout-ms=1000");
    if database {h_add(args,"--allow-stdin");}
    h_add(args,"/guest/main.flex");return args;
}
// Capture record: native host child, watchdog/output-limit reason.
fn cw_drain(errors) {
    let s=h_data(cw_buffer);let size=h_size(cw_buffer);let at=0;let active=1;
    while at<size && active {
        let remain=size-at;let match=0;let i=0;let width=remain;if width>8 {width=8;}while i<width && load8(s+at+i)==load8("COLLIEDB"+i) {i=i+1;}match=i==width;
        if match && remain<16 {active=0;}
        else if match {
            let n=load64(s+at+8);if n<16 || n>65536 {return "Invalid database request frame.";}
            if remain<n+16 || cw_pending {active=0;}
            else {cw_calls=cw_calls+1;if cw_calls>1024 {return "Database call limit exceeded.";}
                n=cw_reply(s+at+16,n);if !n {return "Cannot encode database response.";}cw_response_bytes=cw_response_bytes+n+8;if cw_response_bytes>1048576 {return "Database response budget exceeded.";}
                cw_pending=h_take(n+8);store64(cw_pending,n);h_copy(cw_pending+8,db_wire,n);cw_reply_size=n+8;cw_sent=0;at=at+16+load64(s+at+8);active=0;
            }
        }else {h_append(errors,s+at,1);at=at+1;}
    }
    if at {h_copy(s,s+at,size-at);store64(cw_buffer+8,size-at);store8(s+size-at,0);}if h_size(cw_buffer)>131072 {return "Database request buffer exceeded.";}return 0;
}
fn cp_capture(args,timeout) {return cp_capture_run(args,timeout,0,0);}
fn cp_capture_run(args,timeout,config,history) {
    let saved_env=h_env;let clean=h_vec();h_add(clean,"PATH=/usr/bin:/bin");h_add(clean,"LC_ALL=C");
    let database=c_string(config,"workspace_file");cw_db=0;cw_config=config;cw_history=history;if !cw_history {cw_history=j_array();}cw_buffer=h_buffer();cw_pending=0;cw_sent=0;cw_calls=0;cw_response_bytes=0;
    let input="";if database {input=0;}h_env=clean+8;let child=h_spawn(args,input,0);h_env=saved_env;
    let deadline=net_now()+timeout;let scratch=h_take(8192);let status=h_take(8);
    let reason=0;let more=1;let total=0;
    while more && !reason {
        if h_status(child)==-999 {
            let waited=syscall(61,load64(child),status,1,0,0,0);
            if waited==load64(child) {
                let s=load64(status)&0xffff;let code=(s>>8)&255;if s&127 {code=-(s&127);}
                store64(child+8,code);
            }
        }
        let i=0;while i<2 && !reason {
            let at=40+i*8;let fd=load64(child+at);let reading=fd>=0;
            while reading && !reason {
                let n=syscall(0,fd,scratch,8192,0,0,0);
                if n>0 {
                    let keep=n;if keep>1048576-total {keep=1048576-total;}
                    let buffer=load64(child+16+i*8);if database && i==1 {h_append(cw_buffer,scratch,keep);let error=cw_drain(buffer);if error {reason=error;}}else {h_append(buffer,scratch,keep);}total=total+keep;
                    if keep<n {reason="Combined output limit exceeded.";}
                    // Check even while a writer keeps its pipe continuously ready.
                    if net_now()>deadline {reason="Compilation/execution watchdog exceeded.";}
                }else if n!=-4 {
                    reading=0;
                    if n==0 || n==-5 {h_close(fd);store64(child+at,-1);}
                    else if n!=-11 {reason="Cannot read isolated process output.";}
                }
            }
            i=i+1;
        }
        if database && !reason {
            if !cw_pending && h_size(cw_buffer) {reason=cw_drain(load64(child+24));}
            if cw_pending {let n=cw_reply_size-cw_sent;if n>4096 {n=4096;}let sent=syscall(1,load64(child+32),cw_pending+cw_sent,n,0,0,0);if sent>0 {cw_sent=cw_sent+sent;if cw_sent==cw_reply_size {cw_pending=0;}}else if sent!=-4 && sent!=-11 {reason="Database response channel closed.";}}
        }
        more=h_status(child)==-999 || load64(child+40)>=0 || load64(child+48)>=0;
        if more && net_now()>deadline {reason="Compilation/execution watchdog exceeded.";}
        if more && !reason {h_sleep(5);}
    }
    if reason {syscall(62,-load64(child),9,0,0,0,0);h_stop(child);}
    else {h_close(load64(child+32));store64(child+32,-1);}
    if database {if h_size(cw_buffer) {if h_size(cw_buffer)>=8 && h_bytes(h_data(cw_buffer),"COLLIEDB",8) {if !reason {reason="Incomplete database request.";}}else {h_append(load64(child+24),h_data(cw_buffer),h_size(cw_buffer));}}cw_close();}
    let record=h_take(16);store64(record,child);store64(record+8,reason);return record;
}
fn cp_continuation(c) {return c>=128 && c<=191;}
fn cp_text(buffer) {
    let size=h_size(buffer);if size>32768 {size=32768;}
    let bytes=h_data(buffer);let output=h_buffer();let i=0;
    while i<size {
        let c=load8(bytes+i);let width=1;let valid=c<128;
        if c>=194 && c<=223 {width=2;}
        else if c>=224 && c<=239 {width=3;}
        else if c>=240 && c<=244 {width=4;}
        if width>1 && i+width<=size {
            valid=1;let j=1;while j<width {if !cp_continuation(load8(bytes+i+j)) {valid=0;}j=j+1;}
            let next=load8(bytes+i+1);
            if (c==224 && next<160) || (c==237 && next>=160) || (c==240 && next<144) || (c==244 && next>=144) {valid=0;}
        }
        if !c {h_text(output,"\\0");}
        else if valid {h_append(output,bytes+i,width);}
        else {h_text(output,"�");width=1;}
        i=i+width;
    }
    return h_data(output);
}
fn cp_execute(config,source) {return cp_execute_history(config,source,0);}
fn cp_execute_history(config,source,history) {
    let rejected=cp_validate(source);let result=j_object();
    if rejected {
        j_set(result,"executed",j_bool(0));j_set(result,"phase",j_string("source"));
        j_set(result,"state",j_string("rejected"));j_set(result,"exit_code",j_int(-1));
        j_set(result,"stdout",j_string(""));j_set(result,"stderr",j_string(rejected));return result;
    }
    let compiler=j_s(config,"compiler");let libraries=cp_libraries(compiler);
    if !libraries {return c_error("Cannot resolve native compiler runtime libraries.");}
    let database=c_string(config,"workspace_file");let program=source;if database {program=h_cat("import \"sdk.flex\";\n",source);}
    let directory=h_temp();let file=h_join(directory,"main.flex");h_save(file,program);
    let sdk=h_join(directory,"sdk.flex");if database {h_save(sdk,cg_source());}
    let captured=cp_capture_run(cp_command(compiler,file,libraries,database),5000,config,history);
    let child=load64(captured);let reason=load64(captured+8);
    // Only files this worker created are removed, without running a shell.
    syscall(87,file,0,0,0,0,0);if database {syscall(87,sdk,0,0,0,0,0);}syscall(84,directory,0,0,0,0,0);
    if h_starts(h_err(child),"bwrap:") || h_starts(h_err(child),"prlimit:") || h_status(child)==127 {
        return c_error("Cannot start isolated VM. Bubblewrap namespaces and prlimit are required.");
    }
    let state="error";
    if !reason && h_status(child)==42 {state="done";}
    else if !reason && h_status(child)==0 {state="continue";}
    let out=load64(child+16);let err=load64(child+24);
    j_set(result,"state",j_string(state));j_set(result,"exit_code",j_int(h_status(child)));
    j_set(result,"stdout",j_string(cp_text(out)));let error=cp_text(err);
    if reason {error=h_cat3(error,"\n",reason);}
    j_set(result,"stderr",j_string(error));
    j_set(result,"output_truncated",j_bool(h_size(out)>32768 || h_size(err)>32768));return result;
}
