// Compiles directly to Turing SASS and an ELF cubin with --target sass-sm75.
// The same function remains usable by the CPU reference and PTX backend.
fn kernel(index,input,output,count) {
    let value=load64(input+index*8);
    value=(value+7)*3;
    value=value^(value-0x123456789abcdef0);
    store64(output+index*8,value);
    return 0;
}
