import "lib/build.flex";
fn bs_suite(compiler,out,name,seed,first,second) {
    let binary=h_join(out,h_cat("test-",name));
    let source=h_cat3("scripts/test-",name,".flex");
    if h_equal(name,"core") {
        source="scripts/test.flex";
    }
    h_compile(compiler,source,binary);
    let args=h_args(binary,seed,first,second,"--report",h_join(out,h_cat(name,"-tests.json")));
    let timeout=h_timeout;
    // TLS graph-limit fixtures fetch hundreds of modules across both stages.
    if h_equal(name,"url-imports") { h_timeout=300000; }
    h_print(1,h_out(h_ok(args)));
    h_timeout=timeout;
    return j_parse(h_read(h_join(out,h_cat(name,"-tests.json"))));
}
fn bs_first_word(line) {
    let i=0;let n=h_len(line);
    while i<n && (load8(line+i)==32 || load8(line+i)==9) {i=i+1;}
    let start=i;
    let scanning=1;
    while scanning && i<n {
        let c=load8(line+i);
        if (c>=65 && c<=90) || (c>=97 && c<=122) || c==95 {i=i+1;}else {scanning=0;}
    }
    return h_slice(line+start,i-start);
}
fn bs_strip(source) {
    // The published seeds predate the verifier annotation syntax. Contracts
    // erase at compilation, so dropping their lines yields the same program
    // for the seed-built stages; anything else the seeds cannot parse fails
    // loudly instead of being silently altered.
    let words=h_args("requires","ensures","reads","modifies","releases","trusted");
    h_add(words,"terminates");h_add(words,"verify");
    let out=h_buffer();
    let n=h_len(source);
    let i=0;
    let dropping=0;
    while i<n {
        let start=i;
        while i<n && load8(source+i)!=10 {i=i+1;}
        let line=h_slice(source+start,i-start);
        let kept=1;
        if dropping {
            kept=0;
            if h_len(line) && load8(line+h_len(line)-1)==59 {dropping=0;}
        }else {
            let word=bs_first_word(line);
            let k=0;
            while k<h_count(words) {
                if h_equal(word,h_at(words,k)) {
                    kept=0;
                    if !(h_len(line) && load8(line+h_len(line)-1)==59) {dropping=1;}
                    k=h_count(words);
                }
                k=k+1;
            }
        }
        if kept {h_text(out,line);h_text(out,"\n");}
        if i<n {i=i+1;}
    }
    return h_data(out);
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let seed=b_option(argc,argv,"--compiler",0);
    h_assert(seed,"bootstrap requires --compiler PATH to an existing Flexscript compiler; use the published 0.0.1 compiler to reproduce the original bootstrap path");
    let out=h_absolute(b_option(argc,argv,"--out-dir","build"));
    h_mkdir(out);
    let version=b_version();
    let commit=b_git("rev-parse","HEAD",0,0);
    let clean=!h_len(b_git("status","--porcelain",0,0));
    let manifest=j_dump(b_manifest());
    seed=h_real(seed);
    let core_source=h_join(out,"core.flex");
    // The published seeds cannot parse the verifier annotation syntax, so the
    // bootstrap origin builds from the erased flattened source. The stages
    // compile that same erased source, and the clean room re-derives it from
    // the tree to keep the flattened form honest.
    h_save(core_source,bs_strip(b_flatten(1)));
    // Normalize the historical seed before checking the current fixed point.
    let core=h_join(out,"core-seed");
    h_compile(seed,core_source,core);
    h_elf(core,1);
    let rebuilt=h_join(out,"core-rebuilt");
    h_compile(core,core_source,rebuilt);
    // An older seed can emit different instructions after an optimizer change.
    // Require the new emitter to reach a fixed point, independently of the seed.
    let core_seed_sha=h_sha(core);
    let stable=h_join(out,"core");
    h_compile(rebuilt,core_source,stable);
    h_assert(h_equal(h_sha(rebuilt),h_sha(stable)),"core stages 2 and 3 differ");
    core=stable;h_elf(core,1);
    let stages=h_vec();
    let compiler=core;
    let i=1;
    while i<=3 {
        let binary=h_join(out,h_cat("stage",h_int(i)));
        // The bridge core was built from the erased flattened source, which is
        // annotation-capable once compiled, so the stages compile the real
        // annotated tree exactly as the published-seed path always did.
        h_compile(compiler,"compiler/main.flex",binary);
        h_elf(binary,0);
        h_check(h_run(h_args(binary,"--version",0,0,0,0)),0,h_cat3("flexscript ",version,"\n"));
        h_add(stages,binary);
        compiler=binary;
        i=i+1;
    }
    let sha=h_sha(h_at(stages,1));
    h_assert(h_equal(sha,h_sha(h_at(stages,2))),"stages 2 and 3 differ");
    let report=j_object();
    j_set(report,"version",j_string(version));
    j_set(report,"seed_version",j_string(h_trim(h_out(h_ok(h_args(seed,"--version",0,0,0,0))))));
    j_set(report,"seed_sha256",j_string(h_sha(seed)));
    j_set(report,"target",j_string("linux-x86_64"));
    j_set(report,"source_commit",j_string(commit));
    j_set(report,"source_clean",j_bool(clean));
    j_set(report,"source_manifest",j_parse(manifest));
    j_set(report,"compiler_source_sha256",j_string(h_sha("compiler/main.flex")));
    let hashes=j_object();
    i=0;
    while i<3 {
        j_set(hashes,h_cat("stage",h_int(i+1)),j_string(h_sha(h_at(stages,i))));
        i=i+1;
    }
    j_set(report,"stages",hashes);
    j_set(report,"core_sha256",j_string(h_sha(core)));
    j_set(report,"core_seed_sha256",j_string(core_seed_sha));
    let harness=h_join(out,"test-harness");
    h_compile(compiler,"scripts/test-harness.flex",harness);
    h_print(1,h_out(h_ok(h_args(harness,"--report",h_join(out,"harness-tests.json"),0,0,0))));
    j_set(report,"harness_tests",j_parse(h_read(h_join(out,"harness-tests.json"))));
    let result=bs_suite(compiler,out,"core",seed,h_at(stages,0),h_at(stages,1));
    j_set(report,"tests",result);
    j_save(h_join(out,"tests.json"),result);
    let names=h_args("imports","upgrade","signature","ffi","network","vm");
    h_add(names,"url-imports");
    let keys=h_args("import_tests","upgrade_tests","signature_tests","ffi_tests","network_tests","vm_tests");
    h_add(keys,"url_import_tests");
    i=0;
    while i<h_count(names) {
        result=bs_suite(compiler,out,h_at(names,i),0,h_at(stages,0),h_at(stages,1));
        j_set(report,h_at(keys,i),result);
        if i==0 {
            j_save(h_join(out,"import-tests.json"),result);
        }
        i=i+1;
    }
    let tool=h_join(out,"clean-room");
    h_compile(compiler,"scripts/clean-room.flex",tool);
    let args=h_args(tool,core,"--source",core_source,"--out-dir",h_join(out,"clean"));
    h_add(args,"--report");
    h_add(args,h_join(out,"clean-room.json"));
    h_print(1,h_out(h_ok(args)));
    j_set(report,"clean_room",j_parse(h_read(h_join(out,"clean-room.json"))));
    h_assert(h_equal(commit,b_git("rev-parse","HEAD",0,0)),"source commit changed during build");
    h_assert(h_equal(manifest,j_dump(b_manifest())),"source files changed during build");
    h_assert(clean==!h_len(b_git("status","--porcelain",0,0)),"source status changed during build");
    j_save(h_join(out,"bootstrap-report.json"),report);
    h_print(1,h_cat3("Bootstrap passed: ",sha,"\n"));
    return 0;
}
