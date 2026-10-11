// CUDA runtime for a planned Pup graph. Graph construction remains platform-free.
import "graph.flex";
import "../../../lib/cuda.flex";
fn pup_cuda(status) {if status {pg_error(cuda_error());}return 0;}
fn pup_parameter(name) {
    let i=0;while i<pg_param_count {let v=load64(pg_params+i*8);if pg_eq(load64(v+80),name) {return v;}i=i+1;}
    pg_error(pg_cat("unknown input parameter: ",name));return 0;
}
// Session: device workspace, module, host launch selector, initialized slots.
fn pup_gpu_open(module) {
    let run=alloc(32);let device=cuda_buffer(pg_words*8);pup_cuda(cuda_status);
    store64(run,device);store64(run+8,module);store64(run+16,alloc(8));return run;
}
fn pup_gpu_bind(run,parameter,data,elements) {
    if elements!=pg_size(parameter) {pg_error("input buffer length differs from model shape");}
    pup_cuda(cuda_upload(load64(run)+load64(parameter+64)*8,data,elements*8));
    store64(run+24,load64(run+24)|(1<<load64(parameter+48)));return 0;
}
fn pup_gpu_execute(run) {
    let i=0;while i<pg_param_count {let v=load64(pg_params+i*8);if !(load64(run+24)&(1<<load64(v+48))) {pg_error("uninitialized model input");}i=i+1;}
    i=0;while i<pg_stage_count {
        let v=load64(pg_stages+i*8);store64(load64(run+16),i);pup_cuda(cuda_upload(load64(run),load64(run+16),8));
        pup_cuda(cuda_launch(load64(run+8),load64(run),load64(run),pg_size(v)));i=i+1;
    }return 0;
}
fn pup_gpu_read(run,index,data) {
    if index<0 || index>=pg_output_count {pg_error("output index out of bounds");}let v=load64(pg_outputs+index*8);
    return pup_cuda(cuda_download(data,load64(run)+load64(v+64)*8,pg_size(v)*8));
}
fn pup_gpu_close(run) {let status=cuda_free(load64(run));store64(run,0);return pup_cuda(status);}
