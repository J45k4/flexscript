import "lib/build.flex";
fn main(argc,argv) {
    h_environment(argc,argv);let compiler=b_option(argc,argv,"--compiler","flexscript");h_mkdir("build/render");
    let names=h_args("custom-vertex","custom-fragment","depth-vertex","depth-fragment",0,0);
    let effects=h_args("water-vertex","water-fragment","atmosphere-vertex","atmosphere-fragment",0,0);
    let targets=h_args("glsl","glsl-es","wgsl",0,0,0);let i=0;
    while i<8 {
        let name=0;let source=0;
        if i>=4 {name=h_at(effects,i-4);source=h_cat3("libs/render/shaders/",name,".seta");}
        else {name=h_at(names,i);source=h_cat3("examples/render/",name,".seta");}
        let j=0;while j<3 {let target=h_at(targets,j);let dest=h_cat3("build/render/",name,h_cat(".",target));
            h_ok(h_args(compiler,"--target",target,source,"-o",dest));j=j+1;
        }i=i+1;
    }
    h_ok(h_args(compiler,"tests/render/core.flex","-o","build/render/test-core",0,0));
    let args=h_args("build/render/test-core",0,0,0,0,0);i=1;while i<argc {if h_equal(load64(argv+i*8),"--gpu") {h_add(args,"--gpu");}i=i+1;}
    h_print(1,h_out(h_ok(args)));h_ok(h_args(compiler,"examples/render/scene.flex","-o","build/render/demo",0,0));return 0;
}
