// Bundled-only SetaScript import loader. It reuses the compiler's source loader
// (file-identity deduplication, 256 files, the shared 64 MiB SetaScript source
// bound and output-alias protection) and its named-library search. The external
// examples/extensions/seta.flex route has no file access and rejects imports.
global si_seen=0;

fn seta_frontend_modules() {
    select_module(0);seta_begin(source,source_size,1,source_path);
    si_seen=alloc(256*8);if si_seen<0 {s_fail("frontend allocation failed");}
    si_visit(0,0);select_module(0);return seta_finish();
}
// Depth-first, in import statement order. A file is included after its own
// imports. Repeated files and cycle back-edges are skipped: every function is
// visible to every file, so a cycle needs no special ordering.
fn si_visit(module,file) {
    store64(si_seen+module*8,1);
    let count=seta_scan(file);let list=load64(s_files+file*48+32);let i=0;
    while i<count {
        let name=load64(list+i*16);let at=load64(list+i*16+8);
        if source_scheme(name) {s_file(file);ir_error("SetaScript imports must be local files",at);}
        let path=si_resolve(load64(modules+module*64),name);
        if !path {s_file(file);ir_error(up_join("cannot find SetaScript import \"",name,"\""),at);}
        // Loader limits (file count, 64 MiB total) are reported at this import.
        select_module(module);token_start=at;
        let child=load_module(path);
        if !load64(si_seen+child*8) {
            let m=modules+child*64;si_visit(child,seta_add_file(load64(m+8),load64(m+16),load64(m)));
        }
        i=i+1;
    }
    seta_include(file);return 0;
}
// Relative to the importing file first. A missing library name then searches
// FLEXSCRIPT_LIB, else the installed source libraries, for NAME.seta.
fn si_resolve(importer,name) {
    let file=name;
    if load8(name)!=47 {
        let prefix=0;let i=0;while load8(importer+i) {if load8(importer+i)==47 {prefix=i+1;}i=i+1;}
        let directory=alloc(prefix+1);if directory<0 {s_fail("frontend allocation failed");}
        net_copy(directory,importer,prefix);file=up_join(directory,name,"");
    }
    if length(file)<4096 && source_library_regular(file) {return file;}
    let n=length(name);let wanted=name;
    if n<5 || !up_text(name+n-5,".seta") {wanted=up_join(name,".seta","");}
    let library=source_library(wanted);if !library {return 0;}
    n=length(library);if n<5 || !up_text(library+n-5,".seta") {return 0;}
    return library;
}
