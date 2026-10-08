import "lib/build.flex";
fn pk_checks(report,key,count,minimum) {
    let tests=j_need(report,key);
    let results=j_need(tests,"results");
    h_assert(j_count(results)==count,"unexpected bootstrap stage test count");
    let i=0;
    let total=0;
    while i<count {
        let checks=j_n(j_at(results,i),"checks");
        h_assert(checks>=minimum,h_cat("missing test coverage: ",key));
        total=total+checks;
        i=i+1;
    }
    h_assert(total==j_n(tests,"total"),"test report total differs");
    return total;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let build=b_option(argc,argv,"--build-dir","build");
    let dist=b_option(argc,argv,"--dist-dir","dist");
    let report=j_parse(h_read(h_join(build,"bootstrap-report.json")));
    let version=b_version();
    h_assert(b_valid_version(version),"invalid release version");
    h_assert(h_equal(j_s(report,"version"),version),"build version differs");
    h_assert(!h_len(b_git("status","--porcelain",0,0)),"commit the source tree before packaging");
    h_assert(j_n(report,"source_clean"),"rerun bootstrap from the clean committed tree");
    h_assert(h_equal(j_s(report,"source_commit"),b_git("rev-parse","HEAD",0,0)),"build commit differs");
    h_assert(h_equal(j_dump(j_need(report,"source_manifest")),j_dump(b_manifest())),"source files differ from build");
    let binary=h_join(build,"stage2");
    let checksum=h_sha(binary);
    let stages=j_need(report,"stages");
    h_assert(h_equal(checksum,j_s(stages,"stage2")) && h_equal(checksum,j_s(stages,"stage3")),"stage hashes differ");
    let core=h_join(build,"core");
    let core_checksum=h_sha(core);
    let clean=j_need(report,"clean_room");
    h_assert(h_equal(core_checksum,j_s(report,"core_sha256")) && h_equal(core_checksum,j_s(clean,"compiler_sha256")) && h_equal(core_checksum,j_s(clean,"rebuilt_sha256")),"core hashes differ");
    h_assert(j_n(j_need(report,"harness_tests"),"checks")>=27,"missing harness verification");
    pk_checks(report,"tests",3,84);
    pk_checks(report,"import_tests",2,46);
    pk_checks(report,"upgrade_tests",2,88);
    pk_checks(report,"signature_tests",2,37);
    pk_checks(report,"ffi_tests",2,24);
    pk_checks(report,"network_tests",2,38);
    pk_checks(report,"vm_tests",2,335);
    h_assert(j_n(clean,"checks")>=10,"missing clean-room verification");
    h_elf(binary,0);
    h_elf(core,1);
    h_check(h_run(h_args(h_real(binary),"--version",0,0,0,0)),0,h_cat3("flexscript ",version,"\n"));
    h_mkdir(dist);
    let name=h_cat3("flexscript-",version,"-linux-x86_64");
    let core_name=h_cat3("flexscript-core-",version,"-linux-x86_64");
    let data=h_read(binary);
    h_save_bytes(h_join(dist,name),data,h_file_size,493);
    syscall(90,h_join(dist,name),493,0,0,0,0);
    data=h_read(core);
    h_save_bytes(h_join(dist,core_name),data,h_file_size,493);
    syscall(90,h_join(dist,core_name),493,0,0,0,0);
    h_save(h_join(dist,"SHA256SUMS"),h_cat3(h_cat3(checksum,"  ",h_cat(name,"\n")),core_checksum,h_cat3("  ",core_name,"\n")));
    let notes=h_buffer();
    h_text(notes,h_trim(h_read(h_cat3("docs/releases/",version,".md"))));
    h_text(notes,"\n\nVerified build:\n\n");
    h_text(notes,h_cat3("- Source commit: `",j_s(report,"source_commit"),"`.\n"));
    h_text(notes,h_cat3("- Compiler version: `flexscript ",version,"`.\n"));
    h_text(notes,h_cat3("- Bootstrap input: `",j_s(report,"seed_version"),h_cat3("`; SHA-256 `",j_s(report,"seed_sha256"),"`.\n")));
    h_text(notes,"- Stages 2 and 3 are byte-identical native Linux x86-64 compilers.\n");
    let keys=h_args("tests","import_tests","upgrade_tests","signature_tests","ffi_tests","network_tests");
    h_add(keys,"vm_tests");
    let labels=h_args("core","imports","upgrades","Ed25519 and signing","FFI","networking");
    h_add(labels,"interpreter, JIT and capabilities");
    let i=0;
    while i<h_count(keys) {
        h_text(notes,h_cat3("- ",h_int(j_n(j_need(report,h_at(keys,i)),"total")),h_cat3(" checks: ",h_at(labels,i),".\n")));
        i=i+1;
    }
    h_text(notes,h_cat3("- ",h_int(j_n(clean,"checks"))," clean-room checks without a toolchain or libc.\n\n"));
    h_text(notes,"The full compiler requires the Linux x86-64 glibc loader and libc. HTTPS upgrades require OpenSSL 3 and a trusted CA store. Upgrades verify the Ed25519 signature over version-bound checksums before downloading or executing a candidate. The separate static core can rebuild the full compiler without libc.\n\nThe full compiler provides `flex run [options] app.flex` with a restricted interpreter and baseline x86-64 JIT. The core supports `run --interpret`. See `docs/vm.md` and `docs/signing.md`.\n\nBuild orchestration, tests, packaging and signing are written in Flexscript. See `docs/bootstrapping.md` to reproduce the build without Python or Rust using released compiler binaries.\n\n");
    h_text(notes,h_cat3("Compiler SHA-256: `",checksum,"`\n"));
    h_save(h_join(dist,"release-notes.md"),h_data(notes));
    h_print(1,h_cat3("Packaged ",name,h_cat3(": ",checksum,"\n")));
    return 0;
}
