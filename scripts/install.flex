// Install from a source checkout or the release source-library bundle.
import "lib/build.flex";
fn install_copy(source,destination) {
    if h_isdir(source) {
        h_mkdir(destination);let entries=h_entries(source);let i=0;
        while i<h_count(entries) {let name=h_at(entries,i);install_copy(h_join(source,name),h_join(destination,name));i=i+1;}
    }else {
        let bytes=h_read(source);h_save_bytes(destination,bytes,h_file_size,420);
    }return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);
    let compiler=b_option(argc,argv,"--compiler",0);let prefix=b_option(argc,argv,"--prefix",0);
    h_assert(compiler && prefix,"Usage: install --compiler PATH --prefix PREFIX (from checkout or library bundle root)");
    compiler=h_real(compiler);prefix=h_absolute(prefix);
    h_check(h_run(h_args(compiler,"--version",0,0,0,0)),0,0);
    let destination=h_join(prefix,"bin/flexscript");let share=h_join(prefix,"share/flexscript");
    h_assert(!h_equal(compiler,destination),"compiler must be built outside its installation destination");
    h_mkdir(h_dir(destination));h_mkdir(share);
    install_copy("libs",h_join(share,"libs"));install_copy("lib",h_join(share,"lib"));
    install_copy("examples/monolith",h_join(share,"examples/monolith"));
    h_mkdir(h_join(share,"docs"));install_copy("docs/monolith.md",h_join(share,"docs/monolith.md"));
    // Atomic binary replacement. Library sources are copied before publishing
    // the new compiler; existing compiler processes retain their old inode.
    let temporary=h_cat(destination,".install-next");
    h_assert(!h_exists(temporary),"installation staging file already exists");
    let bytes=h_read(compiler);h_save_bytes(temporary,bytes,h_file_size,493);
    h_assert(syscall(90,temporary,493,0,0,0,0)==0,"cannot make installed compiler executable");
    h_assert(syscall(82,temporary,destination,0,0,0,0)==0,"cannot publish installed compiler");
    h_print(1,h_cat3("Installed ",destination," and source libraries.\n"));return 0;
}
