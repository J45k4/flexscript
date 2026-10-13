// Resident source assembly, compiler selection, cache and publication. All
// commands use argument vectors. Direct RDNA calls only the Flexscript compiler.
import "../../../scripts/lib/build.flex";
fn gb_flag(argc,argv,name) {let i=1;while i<argc {if h_equal(load64(argv+i*8),name) {return 1;}i=i+1;}return 0;}
fn gb_identifier(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || (c>=48 && c<=57) || c==95;}
fn gb_model(name,path,native) {
    let source=h_read(path);let stripped=h_buffer();let i=0;let n=h_len(source);
    while i<n {let start=i;while i<n && load8(source+i)!=10 {i=i+1;}let line=h_slice(source+start,i-start);
        if !h_starts(line,"import ") && !h_starts(line,"fn main(") {h_text(stripped,line);h_text(stripped,"\n");}i=i+1;}
    source=h_data(stripped);n=h_len(source);let functions=h_vec();i=0;
    while i<n {if h_starts(source+i,"fn ") {let start=i+3;let end=start;while gb_identifier(load8(source+end)) {end=end+1;}
        if load8(source+end)==40 {h_add(functions,h_slice(source+start,end-start));}i=end;}else {i=i+1;}}
    let result=h_buffer();i=0;
    while i<n {if gb_identifier(load8(source+i)) {let start=i;while i<n && gb_identifier(load8(source+i)) {i=i+1;}let word=h_slice(source+start,i-start);let renamed=0;
        if load8(source+i)==40 {let j=0;while j<h_count(functions) {if h_equal(word,h_at(functions,j)) {renamed=1;}j=j+1;}}
        if renamed {let prefix=h_cat3("os_",name,"_");if h_equal(word,"kernel") {word=h_cat("os_",name);if native && h_equal(name,"gemv") {word="os_gemv_portable";}else if native && h_equal(name,"attention") {word="os_attention_portable";}else if native && h_equal(name,"element") {word="os_element_portable";}else if native && h_equal(name,"rope") {word="os_rope_portable";}}else {word=h_cat(prefix,word);}}
        h_text(result,word);
    }else {h_append(result,source+i,1);i=i+1;}}
    source=h_replace(h_data(result),"(index,input,output,count)","(index,count,step)");
    return h_replace(source,"gpu_launch_word(","os_word(step,");
}
fn gb_compose(target,greedy) {
    let native=h_equal(target,"rdna");let source=h_buffer();
    h_text(source,h_cat3("import \"",h_real("libs/ml/llm/kernels/common-f16.flex"),"\";\n"));
    if native {h_text(source,h_cat3("import \"",h_real("lib/rdna.flex"),"\";\n"));}
    h_text(source,gb_model("gemv","libs/ml/llm/kernels/gemv-wide-rdna.flex",native));
    h_text(source,gb_model("element","libs/ml/llm/kernels/element.flex",native));
    h_text(source,gb_model("rope","libs/ml/llm/kernels/rope.flex",native));
    h_text(source,gb_model("attention","libs/ml/llm/kernels/attention.flex",native));
    if h_equal(target,"hip") {h_text(source,"fn os_sync(work){return gpu_cooperative_barrier();}\n");}
    else if native {h_text(source,"fn os_sync(work){return gpu_rdna_grid_barrier(work);}\n");}
    else {h_text(source,h_read("libs/os/gpu/sync.flex"));}
    if greedy {h_text(source,"fn os_sample(request,work){return os_pick(request,work,-1);}\n");}else {h_text(source,h_read("libs/os/gpu/sampling.flex"));}
    let resident=h_read("libs/os/gpu/resident.flex");
    if native {resident=h_replace(resident,"fn os_stage(","fn os_stage_portable(");resident=h_replace(resident,"fn os_rms_row(","fn os_rms_row_portable(");resident=h_replace(resident,"fn os_rms_head(","fn os_rms_head_portable(");}
    h_text(source,resident);
    if native {h_text(source,"\nfn os_gemv(index,count,step){let n=os_word(step,3)&4294967295;if n && !(n&255) && (index>>5)*n*2<=4294967295 {return gpu_rdna_gemv_stage_f16(index,step);}return os_gemv_portable(index,count,step);}\nfn os_matrix_stage(step){let n=os_word(step,3)&4294967295;if n && !(n&255) && (gpu_load_u64(step+8)>>5)*n*2<=4294967295 {gpu_rdna_gemv_grid_f16(0,step);return 1;}return 0;}\n");}
    else {h_text(source,"\nfn os_matrix_stage(step){return 0;}\n");}
    if native {h_text(source,"\nfn os_rms_head(index,step){return gpu_rdna_rms_head_f16(index,step); }\nfn os_rms_row(row,step){if (os_word(step,3)&4294967295)==2048 {return gpu_rdna_rms_stage_f16(row,step);}return os_rms_row_portable(row,step);}\n");}
    if native {h_text(source,"\nfn os_attention(index,count,step){return gpu_rdna_attention_f32(index,step); }\nfn os_element(index,count,step){return gpu_rdna_element_f32(index,step); }\nfn os_rope(index,count,step){return gpu_rdna_rope_f32(index,step); }\n");}
    if native {h_text(source,"\nfn os_stage(step){let kind=gpu_load_u64(step);let n=os_word(step,3)&4294967295;if kind==5 || kind==28 {if !n || (n&255) || (gpu_load_u64(step+8)>>5)*n*2>4294967295 {return os_stage_portable(step);}}else if kind==6 && n!=128 && n!=2048 {return os_stage_portable(step);}return gpu_rdna_stage(step); }\n");}
    return h_data(source);
}
fn gb_publish(staging,path) {h_assert(syscall(82,staging,path,0,0,0,0)==0,h_cat("cannot publish ",path));return 0;}
fn gb_atomic(path,data,n) {let staging=h_cat(path,".tmp");h_save_bytes(staging,data,n,420);return gb_publish(staging,path);}
fn gb_copy(from,to) {let data=h_read(from);return gb_atomic(to,data,h_file_size);}
fn gb_target(target) {if h_equal(target,"rdna") {return "rdna-gfx1201";}if h_equal(target,"sass") {return "sass-sm75";}return target;}
fn gb_locked(compiler,directory,target,greedy) {
    h_mkdir(directory);directory=h_real(directory);let temporary=h_join(directory,"tmp");h_mkdir(temporary);
    let previous=h_getenv("TMPDIR");h_setenv("TMPDIR",temporary);
    let source=h_join(directory,h_cat3("resident-",target,".flex"));let composed=gb_compose(target,greedy);h_save(source,composed);
    let suffix=".hsaco";if h_equal(target,"ptx") {suffix=".ptx";}else if h_equal(target,"sass") {suffix=".cubin";}
    let output=h_join(directory,h_cat("resident",suffix));let candidate=h_cat(output,".tmp");let metadata=h_cat(output,".target");let stamp=h_cat(output,".build.json");
    let inputs=h_buffer();h_text(inputs,h_sha_bytes(composed,h_len(composed)));h_text(inputs,h_sha(compiler));
    h_text(inputs,h_sha("libs/ml/llm/kernels/common-f16.flex"));h_text(inputs,h_sha("lib/gpu.flex"));h_text(inputs,h_sha("lib/rdna.flex"));h_text(inputs,h_sha("lib/f64.flex"));
    let digest=h_sha_bytes(h_data(inputs),h_size(inputs));let actual=target;if greedy {actual=h_cat(target,"-greedy");}
    if h_exists(output) && h_exists(stamp) && h_exists(metadata) {
        let cached=j_parse(h_read(stamp));
        if h_equal(j_s(cached,"digest"),digest) && h_equal(h_trim(h_read(metadata)),actual) {h_setenv("TMPDIR",previous);return output;}
    }
    if h_equal(target,"hip") {
        let generated=h_join(directory,"resident.hip");h_ok(h_args(compiler,"--target","hip",source,"-o",generated));
        let bundle=h_join(directory,"resident.bundle");let args=h_args("/opt/rocm/bin/hipcc","--genco","--offload-arch=gfx1201","-O3","-ffp-contract=off",generated);h_add(args,"-o");h_add(args,bundle);h_ok(args);
        args=h_args("/opt/rocm/llvm/bin/clang-offload-bundler","--unbundle","--type=o","--targets=hipv4-amdgcn-amd-amdhsa--gfx1201",h_cat("--input=",bundle),h_cat("--output=",candidate));h_ok(args);
    }else {h_ok(h_args(compiler,"--target",gb_target(target),source,"-o",candidate));}
    if !h_equal(target,"ptx") {let object=h_read(candidate);h_assert(h_file_size>=20 && load8(object)==127 && h_bytes(object+1,"ELF",3),"resident worker is not an ELF code object");}
    gb_publish(candidate,output);let value=h_cat(actual,"\n");gb_atomic(metadata,value,h_len(value));
    let record=j_object();j_set(record,"digest",j_string(digest));j_set(record,"target",j_string(target));j_set(record,"greedy",j_bool(greedy));value=j_dump(record);gb_atomic(stamp,value,h_len(value));
    h_setenv("TMPDIR",previous);return output;
}
fn gb_build(compiler,directory,target,greedy,driver,fallback) {
    h_assert(h_equal(target,"auto") || h_equal(target,"hip") || h_equal(target,"rdna") || h_equal(target,"ptx") || h_equal(target,"sass"),"invalid worker target");
    h_assert(h_equal(driver,"hip") || h_equal(driver,"cuda"),"invalid GPU driver");h_assert(h_equal(fallback,"none") || h_equal(fallback,"hip"),"invalid sampling fallback");
    if h_equal(target,"auto") {target="hip";if h_equal(driver,"cuda") {target="ptx";}}
    h_assert(h_equal(driver,"cuda")==!!(h_equal(target,"ptx") || h_equal(target,"sass")),"worker target and host driver are incompatible");
    h_assert(!h_equal(target,"sass"),"native SASS resident synchronization is not implemented; use --target ptx --driver cuda");
    h_mkdir(directory);directory=h_real(directory);compiler=h_real(compiler);
    let lock=syscall(2,h_join(directory,"build.lock"),0x80042,384,0,0,0);h_assert(lock>=0,"cannot open resident build lock");
    let locked=syscall(73,lock,2,0,0,0,0);while locked==-4 {locked=syscall(73,lock,2,0,0,0,0);}h_assert(!locked,"cannot lock resident build");
    if h_equal(target,"rdna") && h_equal(fallback,"hip") {let image=gb_locked(compiler,h_join(directory,"hip-fallback"),"hip",0);gb_copy(image,h_join(directory,"resident.hsaco.fallback"));}
    if h_equal(target,"rdna") {greedy=1;}
    let output=gb_locked(compiler,directory,target,greedy);h_close(lock);return output;
}
fn gb_main(argc,argv) {
    let compiler=b_option(argc,argv,"--compiler","build/flex");let directory=b_option(argc,argv,"--output","build/gpu-os");
    let target=b_option(argc,argv,"--target","auto");let driver=b_option(argc,argv,"--driver","hip");let fallback=b_option(argc,argv,"--fallback","none");let greedy=gb_flag(argc,argv,"--greedy-only");
    h_print(1,h_cat(gb_build(compiler,directory,target,greedy,driver,fallback),"\n"));return 0;
}
