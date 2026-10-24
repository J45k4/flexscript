// Native Pup tensor compiler entry point. Python is not used for kernel lowering.
import "driver.flex";
global cg_repository=0;
global cg_output_root=0;
fn cg_tile(text) {
    let tile=j_array();let start=0;let i=0;let more=1;while more {if !load8(text+i) || load8(text+i)==44 {let part=h_slice(text+start,i-start);h_assert(h_len(part),"empty tile dimension");j_push(tile,j_int(h_number(part)));if !load8(text+i) {more=0;}start=i+1;}i=i+1;}h_assert(j_count(tile)==5,"tile needs TM,TN,TK,RM,RN");let tm=j_value(j_at(tile,0));let tn=j_value(j_at(tile,1));let tk=j_value(j_at(tile,2));let rm=j_value(j_at(tile,3));let rn=j_value(j_at(tile,4));h_assert(cg_power(tm) && cg_power(tn) && cg_power(rm) && cg_power(rn) && tk>0 && (cg_power(tk) || tk%9==0) && tm%rm==0 && tn%rn==0,"invalid tile dimensions");let threads=tm/rm*(tn/rn);h_assert(threads>=32 && threads<=1024 && (cg_pitch(tm,tk,0)+tn)*tk*4<=49152,"tile exceeds device limits");return tile;
}
fn cg_main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;cg_options=cg_default_options();let root=cg_repository;if !root {root=h_real(".");}let output=0;let compiler=0;let inventory=0;let backend="all";let emit_only=0;let generic=0;let residual_body=0;let residual_first=0;let i=1;
    while i<argc {let flag=load64(argv+i*8);let negative=h_starts(flag,"--no-");let name=flag;if negative {name=h_cat("--",flag+5);}let key=0;
        if h_equal(name,"--vector") {key="vector";}if h_equal(name,"--pipeline") {key="pipeline";}if h_equal(name,"--batch-epilogue") {key="batchEpilogue";}if h_equal(name,"--streaming") {key="streaming";}if h_equal(name,"--packed-masks") {key="packedMasks";}if h_equal(name,"--patch-tiles") {key="patchTiles";}if h_equal(name,"--residual-fusion") {key="residualFusion";}if h_equal(name,"--join-views") {key="joinViews";}if h_equal(name,"--shared-placement") {key="sharedPlacement";}if h_equal(name,"--interior-stencil") {key="interiorStencil";}
        if key {j_set(cg_options,key,j_int(!negative));}
        else if h_equal(flag,"--emit-only") {emit_only=1;}
        else if h_equal(flag,"--generic-only") {generic=1;}
        else if h_equal(flag,"--residual-first") {residual_first=1;}
        else if h_equal(flag,"--help") {h_print(1,"pup-codegen GRAPH.bin --compiler FILE [--repo DIR] [--output DIR] [--backend all|sass|cuda|hip] [--emit-only]\n  --operations FILE --packer FILE override operation sources\n  --generic-only builds reusable fallback operations\n  --tile TM,TN,TK,RM,RN --unroll N --staging 0|1|2|4|8\n  --convolution implicit|im2col --residual-fusion --interior-stencil\n  --[no-]vector --[no-]pipeline --[no-]batch-epilogue --no-streaming\n  --[no-]patch-tiles --[no-]packed-masks --[no-]join-views --[no-]shared-placement\n");return 0;}
        else if h_starts(flag,"--") {
            h_assert(i+1<argc,"missing option value");i=i+1;let value=load64(argv+i*8);
            if h_equal(flag,"--residual-body") {residual_body=value;}else if (h_equal(flag,"--repo") || h_equal(flag,"--root")) {root=h_real(value);}else if h_equal(flag,"--operations") {cg_operations=h_real(value);}else if h_equal(flag,"--packer") {cg_packer=h_real(value);}else if h_equal(flag,"--output") {output=h_absolute(value);}else if h_equal(flag,"--compiler") {compiler=h_real(value);}else if h_equal(flag,"--backend") {backend=value;}
            else if h_equal(flag,"--math") {h_assert(h_equal(value,"fp32") || h_equal(value,"fp32-tc"),"invalid math mode");j_set(cg_options,"mathMode",j_string(value));}
            else if h_equal(flag,"--convolution") {h_assert(h_equal(value,"implicit") || h_equal(value,"im2col"),"invalid convolution mode");j_set(cg_options,"convolution",j_string(value));}
            else if h_equal(flag,"--tile") {j_set(cg_options,"tile",cg_tile(value));}
            else if h_equal(flag,"--unroll") {let n=h_number(value);h_assert(n>=0,"negative unroll");j_set(cg_options,"unroll",j_int(n));}
            else if h_equal(flag,"--staging") {let n=h_number(value);h_assert(n==0 || n==1 || n==2 || n==4 || n==8,"invalid staging");j_set(cg_options,"staging",j_int(n));}
            else {h_die(h_cat("unknown option: ",flag));}
        }else {h_assert(!inventory,"multiple graph inventories");inventory=flag;}i=i+1;
    }
    if residual_body {h_print(1,cg_residual(h_read(residual_body),residual_first));return 0;}
    h_assert(compiler || emit_only,"--compiler is required");if !output {output=cg_output_root;if !output {output=h_join(root,"build/pup-kernels");}}if !cg_operations {cg_operations=h_join(root,"libs/ml/pup/gpu/kernels/ops.flex");}if !cg_packer {cg_packer=h_join(root,"libs/ml/pup/gpu/kernels/pack.flex");}let backends=cg_backends(backend);if generic {return cg_generic(root,output,compiler,backends,emit_only);}h_assert(inventory,"graph inventory is required");return cg_generate(root,inventory,output,compiler,backends,emit_only);
}
