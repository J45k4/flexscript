// From the repository root: flexscript examples/render/run.flex
import "../../scripts/lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=h_executable(b_option(argc,argv,"--compiler","flexscript"));h_assert(compiler,"Flexscript compiler is missing");h_mkdir("build/render");
    let names=h_args("custom-vertex","custom-fragment","depth-vertex","depth-fragment",0,0);let i=0;
    while i<4 {let name=h_at(names,i);h_ok(h_args(compiler,"--target","glsl",h_cat3("examples/render/",name,".seta"),"-o",h_cat3("build/render/",name,".glsl")));i=i+1;}
    let binary="build/render/demo";h_ok(h_args(compiler,"examples/render/scene.flex","-o",binary,0,0));
    let args=h_args(binary,0,0,0,0,0);i=1;while i<argc {h_add(args,load64(argv+i*8));i=i+1;}
    syscall(59,binary,args+8,h_env,0,0,0);h_die("Cannot execute render demo");return 1;
}
