import "lib/harness.flex";
import "lib/library-package.flex";
fn tl_compile(compiler,source,binary,status) {
    h_compile(compiler,source,binary);h_check(h_run(h_args(binary,0,0,0,0,0)),status,"");t_checks=t_checks+1;return 0;
}
fn suite(compiler) {
    t_init(compiler);let original=h_getenv("FLEXSCRIPT_LIB");
    let root=h_join(t_work,"libraries with spaces");h_mkdir(h_join(root,"probe"));
    h_save(h_join(root,"probe.flex"),"import \"probe/number.flex\"; fn probe(){return number();}");
    h_save(h_join(root,"probe/number.flex"),"fn number(){return 31;}");
    let source=h_join(t_work,"app/main.flex");h_mkdir(h_dir(source));
    // A same-named directory is not an exact local source-file override.
    h_mkdir(h_join(t_work,"app/probe"));
    h_save(source,"import \"probe\"; import \"probe.flex\"; fn main(){return probe();}");
    h_setenv("FLEXSCRIPT_LIB",root);tl_compile(t_compiler,source,t_binary,31);
    h_check(h_run(h_args(t_compiler,"run","--interpret",source,0,0)),31,"");t_checks=t_checks+1;
    h_check(h_run(h_args(t_compiler,"run","--jit",source,0,0)),31,"");t_checks=t_checks+1;
    h_check(h_run(h_args(t_compiler,source,0,0,0,0)),31,"");t_checks=t_checks+1;
    h_save(source,"import \"probe/number.flex\"; fn main(){return number();}");tl_compile(t_compiler,source,t_binary,31);
    // Exact local files take precedence over the configured library directory.
    h_save(h_join(t_work,"app/probe.flex"),"fn probe(){return 7;}");
    h_save(source,"import \"probe.flex\"; fn main(){return probe();}");tl_compile(t_compiler,source,t_binary,7);
    // Explicit relative paths must not fall back to a library with that name.
    h_save(source,"import \"./probe/number.flex\"; fn main(){return number();}");t_reject(source,t_binary,"cannot open source");
    h_setenv("FLEXSCRIPT_LIB",0);
    let installer=h_join(t_work,"install");h_compile(t_compiler,"scripts/install.flex",installer);
    let prefix=h_join(t_work,"installed prefix");h_ok(h_args(installer,"--compiler",t_compiler,"--prefix",prefix,0));
    let installed=h_join(prefix,"bin/flexscript");
    // Only copied app sources and the installed prefix are used from here.
    h_save(source,h_read("examples/monolith/counter.flex"));
    h_compile(installed,source,t_binary);h_elf(t_binary,0);t_checks=t_checks+1;
    h_check(h_run(h_args(installed,"run",source,"--help",0,0)),0,"Usage: app [PORT [STATE-PATH]]\nBinds only 127.0.0.1.\n");t_checks=t_checks+1;
    h_save(source,h_read("examples/monolith/todo.flex"));h_compile(installed,source,t_binary);h_elf(t_binary,0);t_checks=t_checks+1;
    let link=h_join(t_work,"compiler-link");h_assert(syscall(88,installed,link,0,0,0,0)==0,"compiler symlink failed");
    h_compile(link,source,t_binary);h_elf(t_binary,0);t_checks=t_checks+1;
    // Installed libraries and a configured root work without URL downloads.
    h_check(h_run(h_args(installed,"run","--no-url-imports",source,"--help",0)),0,"Usage: app [PORT [STATE-PATH]]\nBinds only 127.0.0.1.\n");t_checks=t_checks+1;
    let bundle=lp_bundle(h_join(t_work,"dist"),b_version());let archive=h_join(h_join(t_work,"dist"),bundle);
    let hash=h_sha(archive);lp_bundle(h_join(t_work,"dist"),b_version());t_assert(h_equal(hash,h_sha(archive)),"library bundle is not reproducible");
    let extracted=h_join(t_work,"extracted bundle");h_mkdir(extracted);h_ok(h_args("tar","-xzf",archive,"-C",extracted,0));
    let bundled_installer=h_join(t_work,"bundle-install");h_compile(t_compiler,h_join(extracted,"scripts/install.flex"),bundled_installer);
    let second=h_join(t_work,"bundle prefix");h_check(h_wait(h_spawn(h_args(bundled_installer,"--compiler",t_compiler,"--prefix",second,0),"",extracted)),0,0);
    h_compile(h_join(second,"bin/flexscript"),source,t_binary);h_elf(t_binary,0);t_checks=t_checks+1;
    h_setenv("FLEXSCRIPT_LIB",original);return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
