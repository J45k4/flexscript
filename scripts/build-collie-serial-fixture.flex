// Test-only x86_64 Android raw-tty endpoint. Production Collie remains ARM64.
import "../apps/collie/lib/state.flex";
fn sf_run(args){return h_check(h_wait(h_spawn(args,"",0)),0,0);}
fn main(argc,argv){
    h_environment(argc,argv);let ndk=0;let out=0;let i=1;
    while i<argc{let key=load64(argv+i*8);i=i+1;h_assert(i<argc,"Missing serial fixture builder value");let value=load64(argv+i*8);if h_equal(key,"--ndk"){ndk=h_real(value);}else if h_equal(key,"--out"){out=h_absolute(value);}else{h_die(h_cat("Unknown serial fixture builder option: ",key));}i=i+1;}
    h_assert(ndk&&out,"Provide --ndk and --out from the repository root");h_mkdir(out);out=h_real(out);let sysroot=h_join(ndk,"toolchains/llvm/prebuilt/linux-x86_64/sysroot");let lib=h_join(sysroot,"usr/lib/x86_64-linux-android/26");let source=h_real("apps/collie/tests/android/serial-gadget-loopback.c");let object=h_join(out,"serial-gadget-loopback.o");let helper=h_join(out,"serial-gadget-loopback");h_assert(h_exists(h_join(lib,"crtbegin_dynamic.o")),"Android26 x86_64 NDK sysroot is required");
    let args=h_args(h_executable("clang"),"--target=x86_64-linux-android26",h_cat("--sysroot=",sysroot),"-fPIE","-fno-stack-protector","-Wall");h_add(args,"-Wextra");h_add(args,"-Werror");h_add(args,"-O2");h_add(args,"-c");h_add(args,source);h_add(args,"-o");h_add(args,object);sf_run(args);
    args=h_args(h_executable("ld.lld"),"-pie","-dynamic-linker","/system/bin/linker64","-z","noexecstack");h_add(args,"-z");h_add(args,"relro");h_add(args,"-z");h_add(args,"now");h_add(args,h_join(lib,"crtbegin_dynamic.o"));h_add(args,object);h_add(args,h_cat("-L",lib));h_add(args,"-lc");h_add(args,h_join(lib,"crtend_android.o"));h_add(args,"-o");h_add(args,helper);sf_run(args);
    let report=j_object();j_set(report,"helper",j_string(helper));j_set(report,"sha256",j_string(h_sha(helper)));j_set(report,"source_sha256",j_string(h_sha(source)));j_set(report,"abi",j_string("x86_64"));j_set(report,"minimum_sdk",j_int(26));j_set(report,"test_only",j_bool(1));j_save(h_join(out,"build.json"),report);h_print(1,h_cat(helper,"\n"));return 0;
}
