// One independent lane per 64-bit input word. Also callable directly on the CPU.
fn transform(value) {
    let n=0;
    while n<3 {value=value*3+7;n=n+1;}
    if value<0 {return (value>>65)^0x8000000000000000;}
    return value^(value<<7);
}
fn kernel(index,input,output,count) {
    store64(output+index*8,transform(load64(input+index*8)));
    return 0;
}
