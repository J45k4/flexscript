import "lib/harness.flex";
fn ti_case(name) {
    let path=h_join(t_work,name);
    h_mkdir(path);
    return path;
}
fn ti_file(dir,name,text) {
    let path=h_join(dir,name);
    h_mkdir(h_dir(path));
    h_save(path,text);
    return 0;
}
fn ti_accept(dir,status,out,source) {
    let bin=h_join(dir,"program");
    h_compile(t_compiler,h_join(dir,source),bin);
    h_elf(bin,0);
    h_check(h_run(h_args(bin,0,0,0,0,0)),status,out);
    t_checks=t_checks+1;
    return h_sha(bin);
}
fn ti_snapshots(dir,result) {
    let names=h_entries(dir);
    let i=0;
    while i<h_count(names) {
        let path=h_join(dir,h_at(names,i));
        if h_isdir(path) {
            ti_snapshots(path,result);
        }else {
            let stat=h_take(144);
            if syscall(4,path,stat,0,0,0,0)==0 && (load64(stat+24)&61440)==32768 {
                let pair=h_take(16);
                store64(pair,path);
                store64(pair+8,h_sha(path));
                h_add(result,pair);
            }
        }
        i=i+1;
    }
    return result;
}
fn ti_reject(dir,message,source,destination) {
    let output=h_join(dir,destination);
    if !h_exists(output) {
        h_save(output,"preserve existing output");
    }
    let snapshots=ti_snapshots(dir,h_vec());
    let p=t_reject(h_join(dir,source),output,message);
    let i=0;
    while i<h_count(snapshots) {
        let pair=h_at(snapshots,i);
        h_assert(h_equal(h_sha(load64(pair)),load64(pair+8)),"compiler changed an imported source on rejection");
        i=i+1;
    }
    return p;
}
fn ti_location(name,text,location,message) {
    let dir=ti_case(name);
    ti_file(dir,"main.flex","import \"bad.flex\"; fn main(){bad();}");
    ti_file(dir,"bad.flex",text);
    let p=ti_reject(dir,message,"main.flex","program");
    h_assert(h_has(h_err(p),h_cat3(dir,"/bad.flex:",location)),h_err(p));
    return 0;
}
fn suite(compiler) {
    t_init(compiler);
    h_compile(t_compiler,"examples/imports/main.flex",t_binary);
    h_check(h_run(h_args(t_binary,0,0,0,0,0)),0,"Hello from imported Flexscript!\n");
    t_checks=t_checks+1;
    let cases=j_parse(h_read("tests/tooling/imports.json"));
    let i=0;
    while i<j_count(cases) {
        let mark=h_mark();
        let item=j_at(cases,i);
        let dir=ti_case(j_s(item,"name"));
        let files=j_value(j_need(item,"files"));
        let k=0;
        while k<h_count(files) {
            let pair=h_at(files,k);
            ti_file(dir,load64(pair),j_value(load64(pair+8)));
            k=k+1;
        }
        let error=j_get(item,"error");
        if error {
            ti_reject(dir,j_value(error),"main.flex","program");
        }else {
            ti_accept(dir,j_n(item,"status"),j_s(item,"stdout"),j_s(item,"source"));
        }
        h_reset(mark);
        i=i+1;
    }
    let dir=ti_case("diamond");
    ti_file(dir,"main.flex","import \"lib/a.flex\"; import \"lib/b.flex\"; fn main(){a();b();return total;}");
    ti_file(dir,"lib/a.flex","import \"shared.flex\"; fn a(){increment();}");
    ti_file(dir,"lib/b.flex","import \"shared.flex\"; fn b(){increment();}");
    ti_file(dir,"lib/shared.flex","global total=0; fn increment(){total=total+1;}");
    let before=ti_accept(dir,2,"","main.flex");
    h_assert(syscall(86,h_join(dir,"lib/shared.flex"),h_join(dir,"hardlink.flex"),0,0,0,0)==0,"hardlink");
    h_assert(syscall(88,"lib/shared.flex",h_join(dir,"symlink.flex"),0,0,0,0)==0,"symlink");
    ti_file(dir,"main.flex",h_cat("import \"./lib/../lib/shared.flex\"; import \"hardlink.flex\"; import \"symlink.flex\";\n",h_read(h_join(dir,"main.flex"))));
    ti_accept(dir,2,"","main.flex");
    ti_file(dir,"main.flex","import \"lib/a.flex\"; import \"lib/b.flex\"; import \"lib/a.flex\"; fn main(){a();b();return total;}");
    h_assert(h_equal(ti_accept(dir,2,"","main.flex"),before),"repeat import changed binary");
    dir=ti_case("absolute");
    ti_file(dir,"library.flex","fn number(){return 13;}");
    ti_file(dir,"main.flex",h_cat3("import \"",h_join(dir,"library.flex"),"\"; fn main(){return number();}"));
    ti_accept(dir,13,"","main.flex");
    dir=ti_case("missing");
    ti_file(dir,"main.flex","// header\nimport \"absent.flex\";\nfn main(){}");
    let p=ti_reject(dir,"cannot open source","main.flex","program");
    h_assert(h_has(h_err(p),h_cat(dir,"/main.flex:2:1: error:")),h_err(p));
    ti_location("syntax-location","fn bad() {\n  return @;\n}\n","2:10: error:","unexpected source byte");
    ti_location("deferred-location","fn bad() {\n    missing();\n}\n","2:5: error:","undefined function");
    ti_location("arity-location","fn bad() {\n    zero(1);\n}\nfn zero(){}","2:5: error:","wrong function argument count");
    dir=ti_case("root-location");
    ti_file(dir,"main.flex","import \"empty.flex\";\nfn main(){\n  missing();\n}");
    ti_file(dir,"empty.flex","");
    p=ti_reject(dir,"undefined function","main.flex","program");
    h_assert(h_has(h_err(p),h_cat(dir,"/main.flex:3:3: error:")),h_err(p));
    dir=ti_case("alias-cycle");
    ti_file(dir,"main.flex","import \"alias.flex\"; fn main(){}");
    syscall(88,"main.flex",h_join(dir,"alias.flex"),0,0,0,0);
    ti_reject(dir,"circular import","main.flex","program");
    dir=ti_case("directory");
    ti_file(dir,"main.flex","import \"library\"; fn main(){}");
    h_mkdir(h_join(dir,"library"));
    ti_reject(dir,"source must be a regular file","main.flex","program");
    dir=ti_case("fifo");
    ti_file(dir,"main.flex","import \"pipe.flex\"; fn main(){}");
    h_assert(syscall(133,h_join(dir,"pipe.flex"),4480,0,0,0,0)==0,"mkfifo");
    ti_reject(dir,"source must be a regular file","main.flex","program");
    dir=ti_case("protect-import");
    ti_file(dir,"main.flex","import \"library.flex\"; fn main(){return value;}");
    ti_file(dir,"library.flex","global value=1;");
    ti_reject(dir,"source and output refer to the same file","main.flex","library.flex");
    syscall(86,h_join(dir,"library.flex"),h_join(dir,"alias.flex"),0,0,0,0);
    ti_reject(dir,"source and output refer to the same file","main.flex","alias.flex");
    syscall(88,"library.flex",h_join(dir,"symlink"),0,0,0,0);
    ti_reject(dir,"cannot open output","main.flex","symlink");
    dir=ti_case("depth");
    ti_file(dir,"main.flex","import \"f1.flex\"; fn main(){}");
    i=1;
    while i<64 {
        let text="";
        if i<63 {
            text=h_cat3("import \"f",h_int(i+1),".flex\";");
        }
        ti_file(dir,h_cat3("f",h_int(i),".flex"),text);
        i=i+1;
    }
    ti_accept(dir,0,"","main.flex");
    ti_file(dir,"f63.flex","import \"f64.flex\";");
    ti_file(dir,"f64.flex","");
    ti_reject(dir,"import nesting exceeds 64","main.flex","program");
    dir=ti_case("file-count");
    let imports=h_buffer();
    i=0;
    while i<256 {
        ti_file(dir,h_cat3("f",h_int(i),".flex"),"");
        if i<255 {
            h_text(imports,h_cat3("import \"f",h_int(i),".flex\";"));
        }
        i=i+1;
    }
    ti_file(dir,"main.flex",h_cat(h_data(imports),"fn main(){}"));
    ti_accept(dir,0,"","main.flex");
    ti_file(dir,"main.flex",h_cat(h_data(imports),"import \"f255.flex\"; fn main(){}"));
    ti_reject(dir,"too many imported files","main.flex","program");
    dir=ti_case("source-limit");
    ti_file(dir,"main.flex","import \"large.flex\"; fn main(){}");
    ti_file(dir,"large.flex",h_repeat(" ",16777216));
    ti_reject(dir,"combined source must be smaller than 16 MiB","main.flex","program");
    return t_done();
}
fn main(argc,argv) {
    return t_entry(argc,argv);
}
