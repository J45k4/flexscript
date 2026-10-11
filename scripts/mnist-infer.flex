// MNIST IDX + named F32 safetensors -> Pup frontend -> PTX or direct SASS.
import "lib/build.flex";
import "../libs/ml/pup/lower.flex";
import "../libs/ml/pup/runtime.flex";
global mi_clock=0;
fn mi_now() {if !mi_clock {mi_clock=alloc(16);}h_assert(syscall(228,1,mi_clock,0,0,0,0)==0,"clock unavailable");return load64(mi_clock)*1000+load64(mi_clock+8)/1000000;}
fn mi_int(s) {let n=0;let i=0;while load8(s+i) {let c=load8(s+i);h_assert(c>=48 && c<=57 && i<6,"invalid integer option");n=n*10+c-48;i=i+1;}h_assert(i>0,"empty integer option");return n;}
fn mi_u32(p) {return load8(p)|(load8(p+1)<<8)|(load8(p+2)<<16)|(load8(p+3)<<24);}
fn mi_be32(p) {return (load8(p)<<24)|(load8(p+1)<<16)|(load8(p+2)<<8)|load8(p+3);}
fn mi_checkpoint(path,memory,run) {
    let data=h_read(path);let size=h_file_size;h_assert(size>=10,"truncated safetensors file");let header=load64(data);
    h_assert(header>=2 && header<=1048576 && header<=size-8,"invalid safetensors header length");
    let fields=j_parse(h_slice(data+8,header));let i=0;
    while i<pg_param_count {
        let v=load64(pg_params+i*8);let name=load64(v+80);
        if !h_equal(name,"images") {
            let item=j_need(fields,name);h_assert(h_equal(j_s(item,"dtype"),"F32"),"checkpoint tensor must be F32");
            let shape=j_need(item,"shape");h_assert(j_count(shape)==pg_rank(v),"checkpoint tensor rank mismatch");let axis=0;
            while axis<pg_rank(v) {h_assert(j_kind(j_at(shape,axis))==1 && j_value(j_at(shape,axis))==pg_dim(v,axis),"checkpoint tensor shape mismatch");axis=axis+1;}
            let offsets=j_need(item,"data_offsets");h_assert(j_count(offsets)==2,"invalid checkpoint offsets");
            let begin=j_value(j_at(offsets,0));let end=j_value(j_at(offsets,1));
            h_assert(j_kind(j_at(offsets,0))==1 && j_kind(j_at(offsets,1))==1 && begin>=0 && end>=begin && end<=size-8-header && end-begin==pg_size(v)*4,"checkpoint tensor exceeds file bounds");
            let destination=memory+load64(v+64)*8;let k=0;while k<pg_size(v) {store64(destination+k*8,mi_u32(data+8+header+begin+k*4));k=k+1;}
            pup_gpu_bind(run,v,destination,pg_size(v));
        }i=i+1;
    }return 0;
}
fn mi_plan(model,artifact,target) {
    let report=j_object();j_set(report,"source_sha256",j_string(h_sha(model)));j_set(report,"artifact_sha256",j_string(h_sha(artifact)));j_set(report,"target",j_string(target));
    j_set(report,"workspace_bytes",j_int(pg_words*8));j_set(report,"nodes",j_int(pg_count));let stages=j_array();let i=0;
    while i<pg_stage_count {let v=load64(pg_stages+i*8);let item=j_object();j_set(item,"elements",j_int(pg_size(v)));j_set(item,"offset_words",j_int(load64(v+64)));j_set(item,"contraction",j_bool(load64(v+96)!=0));j_push(stages,item);i=i+1;}
    j_set(report,"stages",stages);return report;
}
fn main(argc,argv) {
    h_environment(argc,argv);h_timeout=300000;
    let compiler=h_real(b_option(argc,argv,"--compiler","build/flex-pup"));let model=b_option(argc,argv,"--model","libs/ml/examples/mnist-inference.pup");
    let target=b_option(argc,argv,"--target","sass-sm75");h_assert(h_equal(target,"sass-sm75") || h_equal(target,"ptx"),"choose sass-sm75 or ptx");
    let checkpoint=b_option(argc,argv,"--checkpoint",0);let images_path=b_option(argc,argv,"--images",0);let labels_path=b_option(argc,argv,"--labels",0);
    h_assert(checkpoint && images_path && labels_path,"provide --checkpoint, --images and --labels (uncompressed IDX files)");
    let artifact=b_option(argc,argv,"--output","build/mnist.cubin");let source_hash=h_sha(model);
    let args=h_args(compiler,"--frontend",h_real("libs/ml/pup/frontend.flex"),"--target",target,model);h_add(args,"-o");h_add(args,artifact);h_ok(args);
    h_assert(h_equal(source_hash,h_sha(model)),"model changed while compiling");let text=h_read(model);pup_parse(text,h_file_size,model);
    let images=h_read(images_path);let image_size=h_file_size;let labels=h_read(labels_path);let label_size=h_file_size;
    h_assert(image_size>=16 && label_size>=8 && mi_be32(images)==2051 && mi_be32(labels)==2049,"invalid MNIST IDX headers");
    let available=mi_be32(images+4);h_assert(available>0 && available<=100000 && mi_be32(labels+4)==available && mi_be32(images+8)==28 && mi_be32(images+12)==28,"invalid MNIST dataset dimensions");
    h_assert(image_size==16+available*784 && label_size==8+available,"truncated or trailing MNIST IDX data");
    let limit=mi_int(b_option(argc,argv,"--limit",h_int(available)));h_assert(limit>0 && limit<=available,"invalid inference limit");
    let verify=mi_int(b_option(argc,argv,"--verify-reference","1"));h_assert(verify>=0 && verify<=128,"reference count must be 0..128");
    let minimum=mi_int(b_option(argc,argv,"--min-accuracy-bps","0"));h_assert(minimum<=10000,"minimum accuracy must be 0..10000 basis points");
    let input=pup_parameter("images");h_assert(pg_rank(input)==2 && pg_dim(input,1)==784 && pg_output_count==1,"MNIST model requires [batch,784] images and one output");
    let batch=pg_dim(input,0);let output=load64(pg_outputs);h_assert(pg_rank(output)==2 && pg_dim(output,0)==batch && pg_dim(output,1)==10,"MNIST output must be [batch,10]");
    let context=cuda_context();pup_cuda(cuda_status);let module=cuda_module(h_read(artifact));pup_cuda(cuda_status);let run=pup_gpu_open(module);let memory=alloc(pg_words*8);
    mi_checkpoint(checkpoint,memory,run);let logits=alloc(pg_size(output)*8);let pixels=memory+load64(input+64)*8;let normalized=alloc(256*8);let p=0;
    while p<256 {store64(normalized+p*8,gpu_f32_div(gpu_f32_from_i64(p),gpu_f32_from_i64(255)));p=p+1;}
    let correct=0;let seen=0;let reference_checks=0;let start=mi_now();
    while seen<limit {
        let count=limit-seen;if count>batch {count=batch;}let i=0;
        while i<batch*784 {let value=0;if i<count*784 {value=load64(normalized+load8(images+16+seen*784+i)*8);}store64(pixels+i*8,value);i=i+1;}
        pup_gpu_bind(run,input,pixels,pg_size(input));pup_gpu_execute(run);pup_gpu_read(run,0,logits);
        if !seen && verify {
            h_print(1,"Checking GPU logits against the primitive graph reference...\n");pg_execute(memory);let n=verify;if n>count {n=count;}
            i=0;while i<n*10 {let expected=load64(memory+(load64(output+64)+i)*8);let actual=load64(logits+i*8);
                let error=f64_magnitude(f64_sub(gpu_f32_unpack(actual),gpu_f32_unpack(expected)));
                let tolerance=f64_mul(f64_div(f64_from_i64(1),f64_from_i64(100000)),f64_add(f64_from_i64(1),f64_magnitude(gpu_f32_unpack(expected))));
                h_assert(f64_is_finite(gpu_f32_unpack(actual)) && f64_le(error,tolerance),h_cat("GPU/reference logit mismatch at ",h_int(i)));reference_checks=reference_checks+1;i=i+1;
            }
        }
        i=0;while i<count {let best=0;let c=0;while c<10 {let value=gpu_f32_unpack(load64(logits+(i*10+c)*8));h_assert(f64_is_finite(value),"nonfinite MNIST logit");if f64_gt(value,gpu_f32_unpack(load64(logits+(i*10+best)*8))) {best=c;}c=c+1;}
            let label=load8(labels+8+seen+i);h_assert(label<10,"MNIST label out of range");if best==label {correct=correct+1;}i=i+1;}
        seen=seen+count;h_print(1,h_cat3("MNIST ",h_int(seen),h_cat3("/",h_int(limit),"\n")));
    }
    let report=mi_plan(model,artifact,target);j_set(report,"examples",j_int(seen));j_set(report,"correct",j_int(correct));j_set(report,"accuracy_basis_points",j_int(correct*10000/seen));j_set(report,"reference_logits",j_int(reference_checks));j_set(report,"elapsed_ms",j_int(mi_now()-start));
    j_set(report,"checkpoint_sha256",j_string(h_sha(checkpoint)));j_set(report,"images_sha256",j_string(h_sha(images_path)));j_set(report,"labels_sha256",j_string(h_sha(labels_path)));
    let report_path=b_option(argc,argv,"--report",h_cat(artifact,".json"));j_save(report_path,report);
    pup_gpu_close(run);pup_cuda(cuda_unload(module));pup_cuda(cuda_close(context));
    h_print(1,h_cat3("Correct: ",h_int(correct),h_cat3("/",h_int(seen),"\n")));
    h_assert(correct*10000>=minimum*seen,"MNIST accuracy below --min-accuracy-bps");return 0;
}
