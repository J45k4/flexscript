import "json.flex";
global b_seen=0;
global b_globals=0;
global b_functions=0;
fn b_git(a,b,c,d) {
    return h_trim(h_out(h_ok(h_args("git",a,b,c,d,0))));
}
fn b_version() {
    return h_trim(h_read("VERSION"));
}
fn b_compare(a,b) {
    let i=0;
    while load8(a+i) && load8(a+i)==load8(b+i) {
        i=i+1;
    }
    return load8(a+i)-load8(b+i);
}
fn b_manifest() {
    let p=h_ok(h_args("git","ls-files","--cached","--others","--exclude-standard","-z"));
    let size=h_size(load64(p+16));
    let names=h_vec();
    let data=h_out(p);
    let i=0;
    let start=0;
    while i<size {
        if !load8(data+i) {
            if i>start {
                h_add(names,h_slice(data+start,i-start));
            }
            start=i+1;
        }
        i=i+1;
    }
    i=1;
    while i<h_count(names) {
        let value=h_at(names,i);
        let j=i;
        while j>0 && b_compare(h_at(names,j-1),value)>0 {
            store64(names+8+j*8,h_at(names,j-1));
            j=j-1;
        }
        store64(names+8+j*8,value);
        i=i+1;
    }
    let result=j_object();
    i=0;
    while i<h_count(names) {
        let name=h_at(names,i);
        if (i==0 || !h_equal(name,h_at(names,i-1))) && h_exists(name) {
            j_set(result,name,j_string(h_sha(name)));
        }
        i=i+1;
    }
    return result;
}
fn b_visit(path) {
    path=h_real(path);
    let i=0;
    while i<h_count(b_seen) {
        if h_equal(path,h_at(b_seen,i)) {
            return 0;
        }
        i=i+1;
    }
    h_add(b_seen,path);
    let text=h_read(path);
    let stripped=h_buffer();
    let n=h_len(text);
    i=0;
    while i<n {
        let start=i;
        while i<n && load8(text+i)!=10 {
            i=i+1;
        }
        let line=h_slice(text+start,i-start);
        if h_starts(line,"import \"") {
            let end=8;
            while load8(line+end) && load8(line+end)!=34 {
                end=end+1;
            }
            h_assert(load8(line+end)==34,"flatten requires literal import paths");
            b_visit(h_join(h_dir(path),h_slice(line+8,end-8)));
        }else {
            h_text(stripped,line);
            h_text(stripped,"\n");
        }
        if i<n {
            i=i+1;
        }
    }
    let content=h_data(stripped);
    let at=0;
    if !h_starts(content,"fn ") {
        at=h_find(content,"\nfn ");
        h_assert(at>=0,"module has no function definitions");
        at=at+1;
    }
    h_append(b_globals,content,at);
    h_text(b_globals,"\n");
    h_text(b_functions,content+at);
    h_text(b_functions,"\n");
    return 0;
}
fn b_flatten(shims) {
    b_seen=h_vec();
    b_globals=h_buffer();
    b_functions=h_buffer();
    b_visit("compiler/main.flex");
    let text=h_cat(h_data(b_globals),h_data(b_functions));
    if shims {
        text=h_cat(text,"\n// Static bootstrap core: foreign calls are unavailable in this executable.\nfn ffi_open(name){return 0;}\nfn ffi_symbol(handle,name){return 0;}\nfn ffi_call(pointer,a,b,c,d,e,f){return 0;}\nfn ffi_call_i32(pointer,a,b,c,d,e,f){return 0;}\nfn ffi_call_u32(pointer,a,b,c,d,e,f){return 0;}\n");
    }
    return text;
}
fn b_option(argc,argv,name,fallback) {
    let i=1;
    while i<argc {
        if h_equal(load64(argv+i*8),name) {
            h_assert(i+1<argc,h_cat(name," needs a value"));
            return load64(argv+(i+1)*8);
        }
        i=i+1;
    }
    return fallback;
}
fn b_valid_version(s) {
    let i=0;
    let part=0;
    while part<3 {
        let start=i;
        while load8(s+i)>=48 && load8(s+i)<=57 {
            i=i+1;
        }
        if i==start || i-start>9 || (i-start>1 && load8(s+start)==48) {
            return 0;
        }
        part=part+1;
        if part<3 {
            if load8(s+i)!=46 {
                return 0;
            }
            i=i+1;
        }
    }
    return !load8(s+i);
}
