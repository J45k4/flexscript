// Optional native-host adapter. Caller owns the current CUDA context and module.
// Forward matmul runs on GPU; its reverse rule uses the portable CPU engine.
import "ml.flex";
import "../../lib/cuda.flex";
fn ml_cuda_matmul(module,a,b) {
    ml_matmul_shape(a,b);let t=ml_node(a,b,ml_rows(a),ml_cols(b),7,0);let ctx=load64(a);
    let used=ml_used(ctx);let bytes=24+(ml_size(a)+ml_size(b))*8;let packed=ml_alloc(ctx,bytes);
    store64(packed,ml_rows(a));store64(packed+8,ml_cols(a));store64(packed+16,ml_cols(b));
    let i=0;while i<ml_size(a) {store64(packed+24+i*8,ml_get(a,i));i=i+1;}
    i=0;while i<ml_size(b) {store64(packed+24+(ml_size(a)+i)*8,ml_get(b,i));i=i+1;}
    let input=cuda_buffer(bytes);let status=cuda_status;let output=0;
    if !status {output=cuda_buffer(ml_size(t)*8);status=cuda_status;}
    if !status {status=cuda_upload(input,packed,bytes);}
    if !status {status=cuda_launch(module,input,output,ml_size(t));}
    if !status {status=cuda_download(ml_data(t),output,ml_size(t)*8);}
    if output {let s=cuda_free(output);if !status {status=s;}}
    if input {let s=cuda_free(input);if !status {status=s;}}
    store64(ctx+16,used);cuda_status=status;
    if status {ml_fail(cuda_error());}return t;
}
