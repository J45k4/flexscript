// Offline native build orchestration: no Python, LLVM or GPU context required.
import "../libs/os/gpu/build-lib.flex";
fn main(argc,argv) {
 h_environment(argc,argv);h_timeout=300000;h_mkdir("build/gpu-os/tmp");h_setenv("TMPDIR",h_real("build/gpu-os/tmp"));let compiler=h_real(b_option(argc,argv,"--compiler","build/flex"));
 let directory=h_temp();let builder=h_join(directory,"builder");h_compile(compiler,"libs/os/gpu/build.flex",builder);
 let path=h_getenv("PATH");h_setenv("PATH","/no-external-build-tools");let native=gb_build(compiler,h_join(directory,"native output"),"rdna",0,"hip","none");
 h_assert(h_equal(h_trim(h_read(h_cat(native,".target"))),"rdna-greedy"),"native artifact provenance");h_assert(!h_exists(h_cat(native,".fallback")),"pure build prepared a fallback");
 let first=h_sha(native);let stat=h_take(144);h_assert(!syscall(4,native,stat,0,0,0,0),"native stat failed");let seconds=load64(stat+88);let nanos=load64(stat+96);h_sleep(20);
 gb_build(compiler,h_join(directory,"native output"),"rdna",0,"hip","none");h_assert(!syscall(4,native,stat,0,0,0,0) && seconds==load64(stat+88) && nanos==load64(stat+96) && h_equal(first,h_sha(native)),"cached build rewrote artifact");
 let ptx=gb_build(compiler,h_join(directory,"ptx"),"ptx",0,"cuda","none");let old=j_s(j_parse(h_read(h_cat(ptx,".build.json"))),"digest");
 gb_build(compiler,h_join(directory,"ptx"),"ptx",1,"cuda","none");h_assert(!h_equal(old,j_s(j_parse(h_read(h_cat(ptx,".build.json"))),"digest")),"sampling change reused stale cache");
 let args=h_args(builder,"--compiler",compiler,"--target","rdna","--output");h_add(args,h_join(directory,"concurrent"));let a=h_spawn(args,"",0);let b=h_spawn(args,"",0);h_check(h_wait(a),0,0);h_check(h_wait(b),0,0);
 h_assert(h_equal(h_trim(h_out(a)),h_trim(h_out(b))),"concurrent builders published different paths");h_assert(h_equal(first,h_sha(h_trim(h_out(a)))),"concurrent build changed native instructions");
 let rejected=h_run(h_args(builder,"--target","sass","--driver","cuda",0));h_assert(h_status(rejected) && h_has(h_err(rejected),"synchronization is not implemented"),"SASS resident target was accepted");
 rejected=h_run(h_args(builder,"--target","rdna","--driver","cuda",0));h_assert(h_status(rejected) && h_has(h_err(rejected),"incompatible"),"incompatible driver accepted");
 h_setenv("PATH",path);h_print(1,"Flexscript GPU builder: tool-free RDNA/PTX, cache invalidation, concurrent publication and target checks pass\n");return 0;
}
