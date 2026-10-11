import "../../../lib/gpu.flex";
// Packed input: rows, inner, cols, row-major A then row-major B; f64 words.
// Deliberately simple reference kernel: one output element per GPU thread.
fn kernel(index,input,output,count) {
    let rows=load64(input);let inner=load64(input+8);let cols=load64(input+16);
    let a=input+24;let b=a+rows*inner*8;let row=index/cols;let col=index%cols;
    let value=0;let k=0;while k<inner {
        value=gpu_f64_add(value,gpu_f64_mul(load64(a+(row*inner+k)*8),load64(b+(k*cols+col)*8)));k=k+1;
    }store64(output+index*8,value);return 0;
}
