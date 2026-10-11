// Nontrivial shapes, tail warps, head grouping and retained state references.
fn lt_fraction(n,d) {return gpu_f32_div(gpu_f32_from_i64(n),gpu_f32_from_i64(d));}
fn lt_rms_width(width,name) {
    let rows=2;let values=alloc(rows*width*4);let scales=alloc(width*2);let actual=alloc(rows*width*4);let i=0;
    while i<rows*width {gpu_store_u32(values+i*4,lt_fraction(i%17-8,8));i=i+1;}
    i=0;while i<width {let bits=lt_fraction(i%5+1,4)>>16;store8(scales+i*2,bits);store8(scales+i*2+1,bits>>8);i=i+1;}
    let d=alloc(64);store64(d,lt_buffer(values,rows*width*4));store64(d+8,lt_buffer(scales,width*2));let y=lm_alloc(rows*width*4);
    store64(d+16,y);store64(d+24,width);store64(d+32,lt_fraction(1,width));store64(d+40,0x358637bd);
    let retained=0;if h_equal(name,"rms-add") {let extra=alloc(rows*width*4);i=0;while i<rows*width {gpu_store_u32(extra+i*4,lt_fraction(i%7-3,16));i=i+1;}
        store64(d+48,load64(d+8));store64(d+8,lt_buffer(extra,rows*width*4));retained=lm_alloc(rows*width*4);store64(d+56,retained);
        i=0;while i<rows*width {gpu_store_u32(values+i*4,gpu_f32_add(gpu_load_u32(values+i*4),gpu_load_u32(extra+i*4)));i=i+1;}}
    let group=128;if h_equal(name,"rms-wide") && width==128 {group=32;}lt_launch(name,d,rows*group);lm_check(cuda_download(actual,y,rows*width*4));let row=0;
    if retained {let residual=alloc(rows*width*4);lm_check(cuda_download(residual,retained,rows*width*4));i=0;while i<rows*width {h_assert(gpu_load_u32(residual+i*4)==gpu_load_u32(values+i*4),"fused residual must retain exact F32 addition");lt_checks=lt_checks+1;i=i+1;}}
    while row<rows {let sum=0;let k=0;while k<width {let a=gpu_f32_unpack(gpu_load_u32(values+(row*width+k)*4));sum=f64_add(sum,f64_mul(a,a));k=k+1;}
        let inverse=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(width)),gpu_f32_unpack(0x358637bd))));k=0;
        while k<width {let expected=f64_mul(f64_mul(gpu_f32_unpack(gpu_load_u32(values+(row*width+k)*4)),inverse),gpu_f32_unpack(gpu_load_bf16(scales+k*2)));
            lt_near(gpu_load_u32(actual+(row*width+k)*4),gpu_f32_pack(expected));k=k+1;}row=row+1;}
    return 0;
}
fn lt_more() {
    lt_three(4);lt_three(132);lt_three(2048);
    lt_mlp_pair(4);lt_mlp_pair(132);lt_mlp_pair(2048);
    lt_rms_width(193,"rms");lt_rms_width(2048,"rms");lt_rms_width(128,"rms-wide");lt_rms_width(132,"rms-wide");lt_rms_width(2048,"rms-wide");lt_rms_width(132,"rms-add");lt_rms_width(2048,"rms-add");
    let rows=33;let inner=193;let weights=alloc(rows*inner*2);let input=alloc(inner*4);let i=0;
    while i<rows*inner {let bits=lt_fraction(i%13-6,8)>>16;store8(weights+i*2,bits);store8(weights+i*2+1,bits>>8);i=i+1;}
    i=0;while i<inner {gpu_store_u32(input+i*4,lt_fraction(i%9-4,4));i=i+1;}
    let w=lt_buffer(weights,rows*inner*2);let x=lt_buffer(input,inner*4);let y=lm_alloc(rows*4);let d=alloc(64);let actual=alloc(4096);
    store64(d,w);store64(d+8,x);store64(d+16,y);store64(d+24,inner);lt_launch("gemv",d,rows*32);lm_check(cuda_download(actual,y,rows*4));i=0;
    while i<rows {let expected=0;let k=0;while k<inner {expected=gpu_f32_add(expected,gpu_f32_mul(gpu_load_bf16(weights+(i*inner+k)*2),gpu_load_u32(input+k*4)));k=k+1;}
        lt_near(gpu_load_u32(actual+i*4),expected);i=i+1;}
    // Packed loads, a partial final warp, and the full model's inner dimensions.
    let widths=h_args(4,132,2048,6144,0,0);let shape=0;
    while shape<h_count(widths) {
        inner=h_at(widths,shape);weights=alloc(rows*inner*2);input=alloc(inner*4);i=0;
        while i<rows*inner {let bits=lt_fraction(i%13-6,8)>>16;store8(weights+i*2,bits);store8(weights+i*2+1,bits>>8);i=i+1;}
        i=0;while i<inner {gpu_store_u32(input+i*4,lt_fraction(i%9-4,4));i=i+1;}
        w=lt_buffer(weights,rows*inner*2);x=lt_buffer(input,inner*4);y=lm_alloc(rows*4);
        store64(d,w);store64(d+8,x);store64(d+16,y);store64(d+24,inner);lt_launch("gemv-wide",d,rows*32);lm_check(cuda_download(actual,y,rows*4));i=0;
        while i<rows {let expected=0;let k=0;while k<inner {expected=gpu_f32_add(expected,gpu_f32_mul(gpu_load_bf16(weights+(i*inner+k)*2),gpu_load_u32(input+k*4)));k=k+1;}
            lt_near(gpu_load_u32(actual+i*4),expected);i=i+1;}shape=shape+1;
    }
    // Nonuniform RMSNorm across three independent heads, with nonunit scales.
    let values=alloc(384*4);let scales=alloc(256);i=0;while i<384 {gpu_store_u32(values+i*4,lt_fraction(i%17-8,8));i=i+1;}
    i=0;while i<128 {let bits=lt_fraction(i%5+1,4)>>16;store8(scales+i*2,bits);store8(scales+i*2+1,bits>>8);i=i+1;}
    x=lt_buffer(values,384*4);w=lt_buffer(scales,256);y=lm_alloc(384*4);store64(d,x);store64(d+8,w);store64(d+16,y);store64(d+24,128);store64(d+32,lt_fraction(1,128));store64(d+40,0x358637bd);
    lt_launch("rms",d,384);lm_check(cuda_download(actual,y,384*4));let row=0;
    while row<3 {let sum=0;let k=0;while k<128 {let a=gpu_f32_unpack(gpu_load_u32(values+(row*128+k)*4));sum=f64_add(sum,f64_mul(a,a));k=k+1;}
        let inverse=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(128)),gpu_f32_unpack(0x358637bd))));k=0;
        while k<128 {let expected=f64_mul(f64_mul(gpu_f32_unpack(gpu_load_u32(values+(row*128+k)*4)),inverse),gpu_f32_unpack(gpu_load_bf16(scales+k*2)));
            lt_near(gpu_load_u32(actual+(row*128+k)*4),gpu_f32_pack(expected));k=k+1;}row=row+1;}
    // Distinct sine/cosine pairs, three heads and a nonzero retained position.
    let table=alloc(1024);i=0;while i<64 {let angle=f64_div(f64_from_i64(i+1),f64_from_i64(32));gpu_store_u32(table+512+i*8,gpu_f32_pack(f64_cos(angle)));gpu_store_u32(table+516+i*8,gpu_f32_pack(f64_sin(angle)));i=i+1;}
    let trig=lt_buffer(table,1024);store64(lm_host_state,1);lm_check(cuda_upload(lm_state,lm_host_state,16));store64(d,x);store64(d+8,y);store64(d+16,trig);store64(d+24,lm_state);
    lt_launch("rope",d,192);lm_check(cuda_download(actual,y,384*4));i=0;
    while i<192 {let head=i>>6;let dim=i&63;let at=head*512+dim*4;let a=gpu_load_u32(values+at);let b=gpu_load_u32(values+at+256);let c=gpu_load_u32(table+512+dim*8);let s=gpu_load_u32(table+516+dim*8);
        lt_near(gpu_load_u32(actual+at),gpu_f32_sub(gpu_f32_mul(a,c),gpu_f32_mul(b,s)));lt_near(gpu_load_u32(actual+at+256),gpu_f32_add(gpu_f32_mul(b,c),gpu_f32_mul(a,s)));i=i+1;}
    // Fused RMSNorm/rotary must retain normalization for other graph consumers.
    let norm=lm_alloc(384*4);let normal=alloc(384*4);let reference=alloc(384*4);
    store64(d,x);store64(d+8,w);store64(d+16,y);store64(d+24,0x358637bd);store64(d+32,trig);store64(d+40,lm_state);store64(d+48,norm);
    lt_launch("rms-rope",d,96);lm_check(cuda_download(actual,y,384*4));lm_check(cuda_download(normal,norm,384*4));row=0;
    while row<3 {let sum=0;let k=0;while k<128 {let a=gpu_f32_unpack(gpu_load_u32(values+(row*128+k)*4));sum=f64_add(sum,f64_mul(a,a));k=k+1;}
        let inverse=f64_div(0x3ff0000000000000,f64_sqrt(f64_add(f64_div(sum,f64_from_i64(128)),gpu_f32_unpack(0x358637bd))));k=0;
        while k<128 {let expected=gpu_f32_pack(f64_mul(f64_mul(gpu_f32_unpack(gpu_load_u32(values+(row*128+k)*4)),inverse),gpu_f32_unpack(gpu_load_bf16(scales+k*2))));
            gpu_store_u32(reference+(row*128+k)*4,expected);lt_near(gpu_load_u32(normal+(row*128+k)*4),expected);k=k+1;}row=row+1;}
    i=0;while i<192 {let head=i>>6;let dim=i&63;let at=head*512+dim*4;let a=gpu_load_u32(reference+at);let b=gpu_load_u32(reference+at+256);let c=gpu_load_u32(table+512+dim*8);let s=gpu_load_u32(table+516+dim*8);
        lt_near(gpu_load_u32(actual+at),gpu_f32_sub(gpu_f32_mul(a,c),gpu_f32_mul(b,s)));lt_near(gpu_load_u32(actual+at+256),gpu_f32_add(gpu_f32_mul(b,c),gpu_f32_mul(a,s)));i=i+1;}
    // Grouped heads, short tails, and boundaries beyond one and two 16-warp tiles.
    let queries=alloc(512*4);let keys=alloc(33*256*4);let vals=alloc(33*256*4);i=0;
    while i<512 {gpu_store_u32(queries+i*4,lt_fraction(i%11-5,16));i=i+1;}
    i=0;while i<33*256 {gpu_store_u32(keys+i*4,lt_fraction(i%19-9,16));gpu_store_u32(vals+i*4,lt_fraction(i%23-11,8));i=i+1;}
    let q=lt_buffer(queries,512*4);let kbuf=lt_buffer(keys,33*256*4);let vbuf=lt_buffer(vals,33*256*4);y=lm_alloc(512*4);
    store64(d,q);store64(d+8,kbuf);store64(d+16,vbuf);store64(d+24,y);store64(d+32,lm_state);store64(d+40,256);store64(d+48,1);
    let positions=h_vec();i=0;while i<9 {h_add(positions,i);i=i+1;}h_add(positions,15);h_add(positions,16);h_add(positions,31);h_add(positions,32);
    let sample=0;while sample<h_count(positions) {let position=h_at(positions,sample);store64(lm_host_state,position);lm_check(cuda_upload(lm_state,lm_host_state,16));lt_launch("attention",d,2048);lm_check(cuda_download(actual,y,512*4));let head=0;
        while head<4 {let probabilities=alloc(264);let denominator=0;let t=0;
            while t<=position {let score=0;let dim=0;while dim<128 {score=f64_add(score,f64_mul(gpu_f32_unpack(gpu_load_u32(queries+(head*128+dim)*4)),gpu_f32_unpack(gpu_load_u32(keys+(t*256+(head>>1)*128+dim)*4))));dim=dim+1;}
                let probability=f64_exp(f64_div(score,f64_sqrt(f64_from_i64(128))));store64(probabilities+t*8,probability);denominator=f64_add(denominator,probability);t=t+1;}
            let dim=0;while dim<128 {let expected=0;t=0;while t<=position {expected=f64_add(expected,f64_mul(load64(probabilities+t*8),gpu_f32_unpack(gpu_load_u32(vals+(t*256+(head>>1)*128+dim)*4))));t=t+1;}
                lt_near(gpu_load_u32(actual+(head*128+dim)*4),gpu_f32_pack(f64_div(expected,denominator)));dim=dim+1;}head=head+1;}
        sample=sample+1;
    }
    // Append exactly one retained row; neighboring rows must survive.
    let cache=alloc(512*4);i=0;while i<512 {gpu_store_u32(cache+i*4,0x42f60000);i=i+1;}let cb=lt_buffer(cache,512*4);
    store64(lm_host_state,2);lm_check(cuda_upload(lm_state,lm_host_state,16));store64(d,x);store64(d+8,0);store64(d+16,cb);store64(d+24,5);store64(d+32,lm_state);store64(d+40,128);
    lt_launch("element",d,128);lm_check(cuda_download(actual,cb,512*4));i=0;while i<512 {let expected=0x42f60000;if i>=256 && i<384 {expected=gpu_load_u32(values+(i-256)*4);}lt_near(gpu_load_u32(actual+i*4),expected);i=i+1;}
    return 0;
}
fn lt_mlp_pair(width) {
    let rows=33;let gate=alloc(rows*width*2);let up=alloc(rows*width*2);let values=alloc(width*4);let i=0;
    while i<rows*width {let g=lt_fraction(i%13-6,8)>>16;let u=lt_fraction(i%17-8,16)>>16;store8(gate+i*2,g);store8(gate+i*2+1,g>>8);store8(up+i*2,u);store8(up+i*2+1,u>>8);i=i+1;}
    i=0;while i<width {gpu_store_u32(values+i*4,lt_fraction(i%9-4,4));i=i+1;}
    let raw=lm_alloc(rows*4);let silu=lm_alloc(rows*4);let projected=lm_alloc(rows*4);let product=lm_alloc(rows*4);let d=alloc(64);
    store64(d,lt_buffer(gate,rows*width*2));store64(d+8,lt_buffer(up,rows*width*2));store64(d+16,lt_buffer(values,width*4));store64(d+24,width);
    store64(d+32,raw);store64(d+40,silu);store64(d+48,projected);store64(d+56,product);lt_launch("mlp-pair",d,rows*32);
    let a=alloc(rows*4);let b=alloc(rows*4);let c=alloc(rows*4);let e=alloc(rows*4);
    lm_check(cuda_download(a,raw,rows*4));lm_check(cuda_download(b,silu,rows*4));lm_check(cuda_download(c,projected,rows*4));lm_check(cuda_download(e,product,rows*4));i=0;
    while i<rows {let g=0;let u=0;let k=0;
        while k<width {let x=gpu_load_u32(values+k*4);g=gpu_f32_add(g,gpu_f32_mul(gpu_load_bf16(gate+(i*width+k)*2),x));u=gpu_f32_add(u,gpu_f32_mul(gpu_load_bf16(up+(i*width+k)*2),x));k=k+1;}
        let gf=gpu_f32_unpack(g);let activated=gpu_f32_pack(f64_div(gf,f64_add(0x3ff0000000000000,f64_exp(f64_sub(0,gf)))));
        lt_near(gpu_load_u32(a+i*4),g);lt_near(gpu_load_u32(b+i*4),activated);lt_near(gpu_load_u32(c+i*4),u);lt_near(gpu_load_u32(e+i*4),gpu_f32_mul(activated,u));i=i+1;
    }return 0;
}
// Unequal projection heights and a partial final warp across the three ranges.
fn lt_three(width) {
    let rows0=33;let rows1=17;let total=67;let values=alloc(width*4);let i=0;
    while i<width {gpu_store_u32(values+i*4,lt_fraction(i%9-4,4));i=i+1;}
    let weights=alloc(total*width*2);i=0;
    while i<total*width {let value=lt_fraction(i%13-6,8)>>16;store8(weights+i*2,value);store8(weights+i*2+1,value>>8);i=i+1;}
    let d=alloc(64);store64(d,lt_buffer(values,width*4));store64(d+8,lt_buffer(weights,rows0*width*2));
    store64(d+16,lt_buffer(weights+rows0*width*2,rows1*width*2));store64(d+24,lt_buffer(weights+(rows0+rows1)*width*2,rows1*width*2));
    let y0=lm_alloc(rows0*4);let y1=lm_alloc(rows1*4);let y2=lm_alloc(rows1*4);
    store64(d+32,y0);store64(d+40,y1);store64(d+48,y2);store64(d+56,width);
    lt_launch_extra=rows0|(rows1<<32);lt_launch("gemv-three",d,total*32);lt_launch_extra=0;
    let actual=alloc(total*4);lm_check(cuda_download(actual,y0,rows0*4));lm_check(cuda_download(actual+rows0*4,y1,rows1*4));lm_check(cuda_download(actual+(rows0+rows1)*4,y2,rows1*4));i=0;
    while i<total {let expected=0;let k=0;while k<width {expected=gpu_f32_add(expected,gpu_f32_mul(gpu_load_bf16(weights+(i*width+k)*2),gpu_load_u32(values+k*4)));k=k+1;}
        lt_near(gpu_load_u32(actual+i*4),expected);i=i+1;}return 0;
}
