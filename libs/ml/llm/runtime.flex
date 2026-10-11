// Resident 16-bit weights, packed FP32 tensors/KV, and selectable prefill lowering.
import "../../../scripts/lib/build.flex";
import "../../../lib/device.flex";
import "../../../lib/gpu.flex";
import "../../../lib/f64-math.flex";
import "fuse.flex";
import "prefill.flex";
import "sample.flex";
import "limits.flex";
global lm_weight_format=0;
// Opt-in worker telemetry; ordinary inference/benchmark stdout stays unchanged.
global lm_progress_json=0;
// NVIDIA uses CUDA; AMD HIP loads source or gfx1201 native code objects.
global lm_backend=0;
global lm_device_ordinal=0;
global lm_tiled_weights=0;
global lm_prompt_block=128;
global lm_steps=0;
global lm_buffers=0;
global lm_modules=0;
global lm_functions=0;
global lm_state=0;
global lm_host_state=0;
global lm_bytes=0;
global lm_capacity=0;
global lm_context=0;
global lm_output=0;
global lm_output_size=0;
global lm_table=0;
global lm_clock=0;
global lm_dry_run=0;
global lm_stream=0;
global lm_graphs=0;
global lm_names=0;
fn lm_progress(text,done,total) {if lm_progress_json {let e=j_object();j_set(e,"event",j_string("progress"));j_set(e,"text",j_string(text));j_set(e,"completed",j_int(done));j_set(e,"total",j_int(total));h_print(1,h_cat(j_dump(e),"\n"));}return 0;}
fn lm_kernel_names() {let names=h_args("gemv","rms","rope","element","attention","gemv-wide");h_add(names,"rms-wide");h_add(names,"rms-rope");h_add(names,"mlp-pair");h_add(names,"rms-add");h_add(names,"gemv-three");h_add(names,"prefill-gemm");h_add(names,"prefill-element");h_add(names,"prefill-rope");h_add(names,"prefill-attention");h_add(names,"prefill-reduce");h_add(names,"prefill-pack");h_add(names,"weight-pack");h_add(names,"gemv-wide-tiled");h_add(names,"gemv-three-tiled");h_add(names,"mlp-pair-tiled");h_add(names,"prefill-gemm-tiled");h_add(names,"weight-tile");h_add(names,"prefill-pack-tiled");h_add(names,"prefill-rms-pack");h_add(names,"prefill-epilogue");h_add(names,"argmax");return names;}
fn lm_block(kind) {if kind==11 || kind==21 {return lm_prompt_block;}if kind==4 {return 512;}if kind==5 || kind==8 || kind==10 || kind==18 || kind==19 || kind==20 {return 256;}if kind==7 {return 32;}return 128;}
fn lm_check(status) {if status {h_die(h_cat3("GPU status ",h_int(status),h_cat(": ",device_error())));}return 0;}
fn lm_select_backend(name) {
    h_assert(h_equal(name,"sass") || h_equal(name,"cuda") || h_equal(name,"hip") || h_equal(name,"rdna"),"--backend must be sass, cuda, hip or rdna");
    lm_backend=0;if h_equal(name,"cuda") {lm_backend=1;}else if h_equal(name,"hip") {lm_backend=2;}else if h_equal(name,"rdna") {lm_backend=3;}
    device_select_hip(lm_backend>=2);return 0;
}
fn lm_default_backend() {if hip_device_count()>0 {return "rdna";}return "sass";}
fn lm_default_compiler() {if h_exists("build/flex") {return "build/flex";}return "build/flex-llm";}
fn lm_backend_name() {if lm_backend==3 {return "rdna";}if lm_backend==2 {return "hip";}if lm_backend {return "cuda";}return "sass";}
fn lm_target() {if lm_backend==3 {return "rdna-gfx1201";}if lm_backend==2 {return "hip";}if lm_backend {return "ptx";}return "sass-sm75";}
fn lm_kernel_suffix() {if lm_backend==3 {return ".hsaco";}if lm_backend==2 {return ".hip";}if lm_backend {return ".ptx";}return ".cubin";}
fn lm_report_backend(report) {j_set(report,"backend",j_string(lm_backend_name()));j_set(report,"target",j_string(lm_target()));return 0;}
fn lm_now_us() {if !lm_clock {lm_clock=alloc(16);}h_assert(syscall(228,1,lm_clock,0,0,0,0)==0,"clock unavailable");return load64(lm_clock)*1000000+load64(lm_clock+8)/1000;}
fn lm_now() {return lm_now_us()/1000;}
fn lm_alloc(bytes) {
    h_assert(bytes>0 && bytes<=8589934592,"invalid device allocation size");let p=4096+lm_bytes;
    if !lm_dry_run {p=device_buffer(bytes);lm_check(device_status);}
    lm_bytes=lm_bytes+bytes;h_add(lm_buffers,p);return p;
}
fn lm_value(kind,p,n,width) {let v=h_take(40);store64(v,kind);store64(v+8,p);store64(v+16,n);store64(v+24,width);return v;}
fn lm_tensor(n) {h_assert(n>0 && n<=100000000,"invalid tensor length");return lm_value(2,lm_alloc(n*4),n,n);}
fn lm_emit(kind,a,b,out,n,e1,e2,threads) {
    let s=h_take(104);store64(s,kind);store64(s+8,threads);
    store64(s+16,a);store64(s+24,b);store64(s+32,out);store64(s+40,n);store64(s+48,e1);store64(s+56,e2);
    h_add(lm_steps,s);return s+16;
}
fn lm_start(directory,capacity) {
    h_assert(capacity>=1 && capacity<=ll_context_max(),"context exceeds the runner limit");
    lm_capacity=capacity;lm_buffers=h_vec();lm_steps=h_vec();lm_names=lm_kernel_names();lm_modules=alloc(h_count(lm_names)*8);lm_functions=alloc(h_count(lm_names)*8);
    lm_tiled_weights=j_object();lm_bytes=0;lm_stream=0;lm_graphs=0;lm_prompt_graph=0;lm_prompt_host=0;if !lm_dry_run {lm_context=device_context_device(lm_device_ordinal);lm_check(device_status);}lm_state=lm_alloc(16);lm_host_state=alloc(16);
    if lm_dry_run {return 0;}
    let device=device_device(lm_device_ordinal);lm_check(device_status);let major=device_device_attribute(device,75);lm_check(device_status);let minor=device_device_attribute(device,76);lm_check(device_status);
    if lm_backend>=2 {h_assert(device_device_attribute(device,10)==32,"HIP LLM kernels currently require an AMD wave32 device");}
    else if lm_backend {h_assert(major*10+minor>=75,"CUDA LLM kernels require compute capability 7.5 or newer");}
    else {h_assert(major==7 && minor==5,"direct SASS requires SM75; select --backend cuda for newer NVIDIA GPUs");}
    lm_host_state=device_host_buffer(16);lm_check(device_status);store64(lm_host_state,0);store64(lm_host_state+8,0);
    let i=0;
    lm_progress("Loading GPU modules",0,h_count(lm_names));
    while i<h_count(lm_names) {let module=device_module(h_read(h_cat3(directory,"/",h_cat(h_at(lm_names,i),lm_kernel_suffix()))));lm_check(device_status);
        store64(lm_modules+i*8,module);store64(lm_functions+i*8,device_function(module,"flex_kernel"));lm_check(device_status);i=i+1;lm_progress("Loading GPU modules",i,h_count(lm_names));}
    return 0;
}
fn lm_prepare() {
    lm_prompt_save();lm_fuse();
    let remap=0;while remap<h_count(lm_steps) {let s=h_at(lm_steps,remap);let kind=load64(s);let w=load64(s+16);if kind==10 {w=load64(s+24);}
        if j_get(lm_tiled_weights,h_int(w)) {if kind==5 {store64(s,18);}else if kind==10 {store64(s,19);}else if kind==8 {store64(s,20);}else {h_die("tiled weights require wide projection lowering");}}remap=remap+1;}
    let i=0;
    if lm_dry_run {return 0;}
    lm_stream=device_stream();lm_check(device_status);
    if lm_sampling_enabled {lm_sampling_setup();}
    while i<h_count(lm_steps) {
        let s=h_at(lm_steps,i);
        let values=h_take(24);store64(values,load64(s+96)&4294967295);store64(values+8,load64(s+96)>>32);store64(values+16,load64(s+8));
        let args=h_take(88);store64(args,values);store64(args+8,values+8);store64(args+16,values+16);let word=0;while word<8 {store64(args+24+word*8,s+16+word*8);word=word+1;}
        let shared=0;if load64(s)==1 || load64(s)==6 || load64(s)==9 {shared=32;}else if load64(s)==4 {shared=16640;}
        let block=lm_block(load64(s));store64(s+80,args);store64(s+88,device_config((load64(s+8)+block-1)/block,1,1,block,1,1,shared,lm_stream));lm_check(device_status);i=i+1;
    }
    lm_check(device_synchronize());lm_graphs=alloc(16);store64(lm_graphs,lm_capture(0));store64(lm_graphs+8,lm_capture(1));
    lm_check(device_graph_upload(load64(lm_graphs),lm_stream));lm_check(device_graph_upload(load64(lm_graphs+8),lm_stream));lm_check(device_stream_wait(lm_stream));return 0;
}
fn lm_capture(logits) {
    lm_check(device_capture_begin(lm_stream));lm_check(device_upload_async(lm_state,lm_host_state,16,lm_stream));
    let n=h_count(lm_steps);if !logits {n=n-1;}let i=0;
    while i<n {let s=h_at(lm_steps,i);lm_check(device_dispatch(load64(lm_functions+load64(s)*8),load64(s+88),load64(s+80)));i=i+1;}
    if logits && lm_sampling_enabled {lm_sampling_dispatch();}
    let graph=device_capture_end(lm_stream);lm_check(device_status);let instance=device_graph_instance(graph);lm_check(device_status);lm_check(device_graph_close(graph));return instance;
}
fn lm_execute(token,position,logits) {
    h_assert(position>=0 && position<lm_capacity,"KV capacity exhausted");
    store64(lm_host_state,position);store64(lm_host_state+8,token);let graph=load64(lm_graphs);if logits {graph=load64(lm_graphs+8);}
    lm_check(device_graph_launch(graph,lm_stream));return lm_check(device_stream_wait(lm_stream));
}
fn lm_close() {
    if lm_dry_run {return 0;}
    lm_prompt_clear();
    if lm_graphs {lm_check(device_graph_instance_close(load64(lm_graphs)));lm_check(device_graph_instance_close(load64(lm_graphs+8)));}
    if lm_stream {lm_check(device_stream_close(lm_stream));}lm_check(device_host_free(lm_host_state));
    if lm_sampling_host {syscall(11,lm_sampling_host,8,0,0,0,0);lm_sampling_host=0;}
    let i=0;while i<h_count(lm_buffers) {lm_check(device_free(h_at(lm_buffers,i)));i=i+1;}
    i=0;while i<h_count(lm_names) {lm_check(device_unload(load64(lm_modules+i*8)));i=i+1;}return lm_check(device_close(lm_context));
}

fn lm_compile_kernels(compiler,directory) {
    h_mkdir(directory);h_mkdir(h_join(directory,"sources"));let names=lm_kernel_names();let i=0;
    lm_progress("Compiling GPU kernels",0,h_count(names));
    while i<h_count(names) {let name=h_at(names,i);let source=h_cat3("libs/ml/llm/kernels/",name,".flex");
        if lm_backend>=2 && (i==11 || i==21) {source="libs/ml/llm/kernels/prefill-gemm-rdna.flex";}
        if lm_weight_format {let text=h_read(source);text=h_replace(text,"import \"common.flex\";",h_cat3("import \"",h_real("libs/ml/llm/kernels/common-f16.flex"),"\";"));
            source=h_cat3(directory,"/sources/",h_cat(name,".flex"));h_save(source,text);}
        h_ok(h_args(compiler,"--target",lm_target(),source,"-o",h_cat3(directory,"/",h_cat(name,lm_kernel_suffix()))));i=i+1;lm_progress("Compiling GPU kernels",i,h_count(names));}
    return 0;
}
