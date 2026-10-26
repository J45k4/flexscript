import "../../../scripts/lib/host.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let bundler=h_has(load64(argv),"bundler");let log=h_getenv("FLEX_GPU_TEST_LOG");let fd=syscall(2,log,0x80441,384,0,0,0);h_assert(fd>=0,"cannot open GPU fixture log");h_write(fd,"x",1);h_close(fd);
    let output=0;let arch=0;let i=1;while i<argc {let arg=load64(argv+i*8);if h_equal(arg,"-o") {i=i+1;output=load64(argv+i*8);}else if h_starts(arg,"--output=") {output=arg+9;}else if h_starts(arg,"--offload-arch=") {arch=arg+15;}else if h_starts(arg,"--targets=") {arch=arg+10;}i=i+1;}
    h_assert(output,"missing GPU fixture output");let failure=h_getenv("FLEX_GPU_TEST_FAILURE");if (h_equal(failure,"hipcc") && !bundler) || (h_equal(failure,"bundler") && bundler) {h_print(2,"synthetic GPU compiler failure\n");return 17;}
    if !bundler {h_assert(h_equal(arch,"gfx90a"),"architecture was not passed to hipcc");h_save(output,"fixture bundle");return 0;}
    h_assert(h_equal(arch,"hipv4-amdgcn-amd-amdhsa--gfx90a"),"architecture was not passed to bundler");if h_equal(failure,"missing") {return 0;}if h_equal(failure,"invalid") {h_save(output,"not ELF");return 0;}
    let image=h_zero(h_take(64),64);store8(image,127);h_copy(image+1,"ELF",3);store8(image+4,2);store8(image+5,1);store8(image+6,1);store8(image+7,64);store8(image+16,3);store8(image+18,224);h_save_bytes(output,image,64,420);return 0;
}
