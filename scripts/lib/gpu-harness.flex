// Shared physical-device differential check; the caller imports its kernel source.
import "build.flex";
import "../../lib/cuda.flex";
fn gpu_check(status) {
    if status {
        h_print(2,h_cat3("CUDA: ",cuda_error(),"\n"));
        if cuda_log && load8(cuda_log) {h_print(2,cuda_log);}
        syscall(231,1,0,0,0,0,0);
    }return 0;
}
fn gpu_run_stride(path,count,stride) {
    h_assert(count>=0 && count<=1048576,"GPU harness element limit");
    h_assert(stride==8 || stride==16,"GPU harness element stride");
    let image=h_read(path);let context=cuda_context();
    if !context {h_print(2,h_cat3("CUDA unavailable: ",cuda_error(),"\n"));return 77;}
    let module=cuda_module(image);gpu_check(cuda_status);
    let words=count*stride/8;let bytes=words*8+8;let input=h_take(bytes);let output=h_take(bytes);let expected=h_take(bytes);
    let i=0;let word=0x123456789abcdef0;
    while i<words {
        word=word*6364136223846793005+1442695040888963407;
        if i==0 {word=0;}else if i==1 {word=-1;}
        else if i==2 {word=0x8000000000000000;}else if i==3 {word=0x7fffffffffffffff;}
        store64(input+i*8,word);store64(expected+i*8,0);store64(output+i*8,0);
        i=i+1;
    }
    store64(input+words*8,0x0807060504030201);
    i=0;while i<count {kernel(i,input,expected,count);i=i+1;}
    // The extra output word detects a missing count guard in a partial block.
    store64(output+words*8,0x123456789abcdef0);
    let device_input=cuda_buffer(bytes);gpu_check(cuda_status);
    let device_output=cuda_buffer(bytes);gpu_check(cuda_status);
    gpu_check(cuda_upload(device_input,input,bytes));gpu_check(cuda_upload(device_output,output,bytes));
    gpu_check(cuda_launch(module,device_input,device_output,count));
    gpu_check(cuda_download(output,device_output,bytes));
    i=0;while i<words {h_assert(load64(output+i*8)==load64(expected+i*8),h_cat("GPU/CPU mismatch at index ",h_int(i)));i=i+1;}
    h_assert(load64(output+words*8)==0x123456789abcdef0,"GPU wrote beyond count");
    gpu_check(cuda_free(device_output));gpu_check(cuda_free(device_input));
    gpu_check(cuda_unload(module));gpu_check(cuda_close(context));
    h_print(1,h_cat3("GPU/CPU parity: ",h_int(words)," words passed\n"));return 0;
}
fn gpu_run(path,count) {return gpu_run_stride(path,count,8);}
