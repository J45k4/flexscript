// Batch lowering of the unfused tensor schedule. Decode buffers and retained
// KV allocations keep their original identities; only prompt temporaries grow.
global lm_prompt_source=0;
global lm_prompt_steps=0;
global lm_prompt_tensors=0;
global lm_prompt_count=0;
global lm_prompt_tokens=0;
global lm_prompt_host=0;
global lm_prompt_graph=0;
global lm_prompt_partial=0;
global lm_prompt_split=-1;
global lm_prompt_tile_rows=16;

global lm_prompt_half=0;
global lm_prompt_last=0;
global lm_prompt_live=0;
global lm_prompt_pool=0;
global lm_prompt_buffer_base=0;
global lm_prompt_buffer_end=0;
global lm_prompt_bytes=0;
global lm_prompt_partial_bytes=0;
global lm_prompt_half_bytes=0;
fn lm_prompt_clear() {
    if !lm_prompt_graph {return 0;}
    lm_check(cuda_stream_wait(lm_stream));lm_check(cuda_graph_instance_close(lm_prompt_graph));lm_check(cuda_host_free(lm_prompt_host));
    let at=lm_prompt_buffer_base;while at<lm_prompt_buffer_end {lm_check(cuda_free(h_at(lm_buffers,at)));at=at+1;}
    let count=h_count(lm_buffers);at=lm_prompt_buffer_end;while at<count {store64(lm_buffers+8+(at-lm_prompt_buffer_end+lm_prompt_buffer_base)*8,h_at(lm_buffers,at));at=at+1;}
    store64(lm_buffers,count-lm_prompt_buffer_end+lm_prompt_buffer_base);lm_bytes=lm_bytes-lm_prompt_bytes;
    lm_prompt_graph=0;lm_prompt_host=0;lm_prompt_count=0;lm_prompt_steps=0;lm_prompt_tensors=0;return 0;
}
fn lm_prompt_shift(rows,width,n) {
    if lm_prompt_split>=0 {return lm_prompt_split;}let shift=0;let warps=((rows+15)/16)*((n+23)/24);
    while shift<5 && (warps<<shift)<512 && width%(16<<shift)==0 {shift=shift+1;}return shift;
}
fn lm_prompt_save() {
    lm_prompt_source=h_vec();let i=0;while i<h_count(lm_steps) {let copy=h_take(104);h_copy(copy,h_at(lm_steps,i),104);h_add(lm_prompt_source,copy);i=i+1;}return 0;
}
fn lm_prompt_use(pointer,index) {
    if !pointer {return 0;}let item=h_take(8);store64(item,index);j_set(lm_prompt_last,h_int(pointer),item);return 0;
}
fn lm_prompt_lifetimes() {
    lm_prompt_last=j_object();lm_prompt_live=h_vec();lm_prompt_pool=h_vec();let i=0;
    while i<h_count(lm_prompt_source) {let s=h_at(lm_prompt_source,i);let kind=load64(s);let a=load64(s+16);let b=load64(s+24);
        if kind==0 || kind==5 {lm_prompt_use(b,i);}
        else if kind==1 || kind==6 || kind==2 || kind==4 {lm_prompt_use(a,i);}
        else if kind==3 && load64(s+40)!=4 {lm_prompt_use(a,i);if load64(s+40)==1 || load64(s+40)==2 {lm_prompt_use(b,i);}}i=i+1;}
    return 0;
}
fn lm_prompt_tensor(pointer,n) {
    let key=h_int(pointer);let found=j_get(lm_prompt_tensors,key);if found {return load64(found);}
    let bytes=n*lm_prompt_count*4;let entry=h_take(40);let at=0;let chosen=-1;let best=0;
    while at<h_count(lm_prompt_pool) {let candidate=h_at(lm_prompt_pool,at);if candidate && load64(candidate+8)>=bytes && (!best || load64(candidate+8)<best) {chosen=at;best=load64(candidate+8);}at=at+1;}
    if chosen>=0 {let old=h_at(lm_prompt_pool,chosen);store64(entry,load64(old));store64(entry+8,load64(old+8));store64(lm_prompt_pool+8+chosen*8,0);}
    else {store64(entry,lm_alloc(bytes));store64(entry+8,bytes);}
    let last=j_get(lm_prompt_last,key);h_assert(last,"batch tensor has no consumer");store64(entry+16,1);store64(entry+24,pointer);store64(entry+32,load64(last));
    j_set(lm_prompt_tensors,key,entry);h_add(lm_prompt_live,entry);return load64(entry);
}
fn lm_prompt_release(index) {
    let i=0;while i<h_count(lm_prompt_live) {let entry=h_at(lm_prompt_live,i);if load64(entry+16) && load64(entry+32)==index {
        store64(entry+16,0);let slot=0;while slot<h_count(lm_prompt_pool) && h_at(lm_prompt_pool,slot) {slot=slot+1;}
        if slot<h_count(lm_prompt_pool) {store64(lm_prompt_pool+8+slot*8,entry);}else {h_add(lm_prompt_pool,entry);}}
        i=i+1;}return 0;
}
fn lm_prompt_emit(kind,a,b,y,n,e1,e2,e3,e4,threads) {
    let s=h_take(104);store64(s,kind);store64(s+8,threads);store64(s+16,a);store64(s+24,b);store64(s+32,y);store64(s+40,n);
    store64(s+48,e1);store64(s+56,e2);store64(s+64,e3);store64(s+72,e4);h_add(lm_prompt_steps,s);return s;
}
fn lm_prompt_prepare(n) {
    h_assert(n>0 && n<=lm_capacity,"invalid prompt length");h_assert(!lm_prompt_graph,"prompt shape is already prepared");
    lm_prompt_buffer_base=h_count(lm_buffers);let bytes_before=lm_bytes;
    lm_prompt_count=n;lm_prompt_tensors=j_object();lm_prompt_lifetimes();lm_prompt_steps=h_vec();lm_prompt_tokens=lm_alloc(n*8);if lm_dry_run {lm_prompt_host=h_take(n*8);}else {lm_prompt_host=cuda_host_buffer(n*8);lm_check(cuda_status);}
    let partial_bytes=0;let maxwidth=0;let i=0;while i+1<h_count(lm_prompt_source) {let s=h_at(lm_prompt_source,i);if load64(s)==0 || load64(s)==5 {let rows=load64(s+8)/32;let bytes=rows*n*(1<<lm_prompt_shift(rows,load64(s+40),n))*4;if bytes>partial_bytes {partial_bytes=bytes;}if load64(s+40)>maxwidth {maxwidth=load64(s+40);}}i=i+1;}
    lm_prompt_partial=lm_alloc(partial_bytes);lm_prompt_half=lm_alloc(maxwidth*((n+23)/24)*24*2);let packed=0;let packed_kind=0;let skipped=-1;i=0;while i<h_count(lm_prompt_source) {
        let s=h_at(lm_prompt_source,i);let kind=load64(s);let a=load64(s+16);let b=load64(s+24);let y=load64(s+32);let width=load64(s+40);let e1=load64(s+48);let e2=load64(s+56);let threads=load64(s+8);
        if i!=skipped {if kind==0 || kind==5 {
            let rows=threads/32;let x=lm_prompt_tensor(b,width);
            if i==h_count(lm_prompt_source)-1 {lm_prompt_emit(kind,a,x+(n-1)*width*4,y,width,0,0,0,0,threads);}
            else {let shift=lm_prompt_shift(rows,width,n);let partitions=1<<shift;
                h_assert(width%(partitions*8)==0,"tensor-core prefill width must be divisible by eight times the K partition count");
                let out=lm_prompt_tensor(y,rows);let matrix_kind=11;let pack_kind=16;if j_get(lm_tiled_weights,h_int(a)) {matrix_kind=21;pack_kind=23;}if packed!=b || packed_kind!=pack_kind {lm_prompt_emit(pack_kind,x,lm_prompt_half,width*n/2,width,n,0,0,0,width*n/2);packed=b;packed_kind=pack_kind;}lm_prompt_emit(matrix_kind,a,lm_prompt_half,lm_prompt_partial,width,rows,n,shift,0,0);
                if matrix_kind==21 && rows%2==0 {let op=0;let extra=0;let other=0;let half=0;
                    let next=h_at(lm_prompt_source,i+1);if load64(next)==3 && (load64(next+40)==3 || load64(next+40)==2) && (load64(next+16)==y || load64(next+24)==y) {
                        op=load64(next+40);extra=lm_prompt_tensor(load64(next+32),rows);skipped=i+1;
                        if op==2 {let source=load64(next+16);if source==y {source=load64(next+24);}other=lm_prompt_tensor(source,rows);
                            if i+2<h_count(lm_prompt_source)-1 {let after=h_at(lm_prompt_source,i+2);if (load64(after)==0 || load64(after)==5) && load64(after+24)==load64(next+32) && j_get(lm_tiled_weights,h_int(load64(after+16))) {half=lm_prompt_half;packed=load64(next+32);packed_kind=23;}}}
                    }
                    lm_prompt_emit(25,lm_prompt_partial,out,rows|(n<<32),partitions,extra,op,other,half,rows*n/2);
                }else {lm_prompt_emit(15,lm_prompt_partial,out,rows*n,partitions,0,0,0,0,rows*n);}}
        }else if kind==1 || kind==6 {
            let group=128;if kind==6 && width==128 {group=32;}let elements=threads/group*width;
            let rms_kind=kind;let half=0;let depth=0;let rms_threads=threads*n;
            if kind==6 && width!=128 && threads==128 && i+1<h_count(lm_prompt_source)-1 {let next=h_at(lm_prompt_source,i+1);
                if (load64(next)==0 || load64(next)==5) && load64(next+24)==y && j_get(lm_tiled_weights,h_int(load64(next+16))) {
                    rms_kind=24;half=lm_prompt_half;depth=n;rms_threads=128*((n+23)/24)*24;packed=y;packed_kind=23;}}
            lm_prompt_emit(rms_kind,lm_prompt_tensor(a,elements),b,lm_prompt_tensor(y,elements),width,e1,e2,half,depth,rms_threads);
        }else if kind==2 {
            let elements=threads*2;lm_prompt_emit(13,lm_prompt_tensor(a,elements),lm_prompt_tensor(b,elements),y,elements,0,0,0,0,threads*n);
        }else if kind==3 {
            if width==4 {lm_prompt_emit(12,a,lm_prompt_tokens,lm_prompt_tensor(y,e2),4,0,e2,0,0,e2*n);}
            else if width==5 {lm_prompt_emit(12,lm_prompt_tensor(a,e2),0,y,5,0,e2,0,0,e2*n);}
            else {let bp=0;if b {bp=lm_prompt_tensor(b,threads);}lm_prompt_emit(12,lm_prompt_tensor(a,threads),bp,lm_prompt_tensor(y,threads),width,0,threads,0,0,threads*n);}
        }else if kind==4 {
            let qn=threads/512*128;lm_prompt_emit(14,lm_prompt_tensor(a,qn),b,y,lm_prompt_tensor(width,qn),qn,e2,load64(s+64),n,qn/128*n*32);
        }else {h_die("unsupported operation in batched prefill");}}lm_prompt_release(i);i=i+1;
    }
    lm_prompt_buffer_end=h_count(lm_buffers);lm_prompt_bytes=lm_bytes-bytes_before;lm_prompt_partial_bytes=partial_bytes;lm_prompt_half_bytes=maxwidth*((n+23)/24)*24*2;
    if lm_dry_run {return 0;}
    i=0;while i<h_count(lm_prompt_steps) {
        let s=h_at(lm_prompt_steps,i);let values=h_take(24);store64(values+16,load64(s+8));let args=h_take(88);store64(args,values);store64(args+8,values+8);store64(args+16,values+16);
        let word=0;while word<8 {store64(args+24+word*8,s+16+word*8);word=word+1;}
        let shared=0;if load64(s)==1 || load64(s)==6 || load64(s)==24 {shared=32;}else if (load64(s)==11 || load64(s)==21) {shared=lm_prompt_block*8;}let block=lm_block(load64(s));
        let gx=(load64(s+8)+block-1)/block;let gy=1;let gz=1;
        if (load64(s)==11 || load64(s)==21) {gx=(load64(s+48)+lm_prompt_tile_rows*(block/32)-1)/(lm_prompt_tile_rows*(block/32));gy=(n+23)/24;gz=1<<load64(s+64);}
        else if load64(s)==25 {gx=((load64(s+32)&4294967295)/2+127)/128;gy=n;if load64(s+72) {gy=(n+23)/24*24;}}
        else if load64(s)==23 {gx=(load64(s+40)/2+127)/128;gy=(n+23)/24*24;}
        else if load64(s)==12 {gx=(load64(s+56)+127)/128;gy=n;}
        else if load64(s)==13 {gx=(load64(s+40)/2+127)/128;gy=n;}
        else if load64(s)==14 {gx=(load64(s+48)/128+3)/4;gy=n;}
        store64(values+16,gx*gy*gz*block);store64(s+80,args);store64(s+88,cuda_config(gx,gy,gz,block,1,1,shared,lm_stream));lm_check(cuda_status);i=i+1;
    }
    lm_check(cuda_capture_begin(lm_stream));lm_check(cuda_upload_async(lm_prompt_tokens,lm_prompt_host,n*8,lm_stream));i=0;
    while i<h_count(lm_prompt_steps) {let s=h_at(lm_prompt_steps,i);lm_check(cuda_dispatch(load64(lm_functions+load64(s)*8),load64(s+88),load64(s+80)));i=i+1;}
    let graph=cuda_capture_end(lm_stream);lm_check(cuda_status);lm_prompt_graph=cuda_graph_instance(graph);lm_check(cuda_status);lm_check(cuda_graph_close(graph));
    lm_prompt_buffer_end=h_count(lm_buffers);lm_prompt_bytes=lm_bytes-bytes_before;
    lm_check(cuda_graph_upload(lm_prompt_graph,lm_stream));return lm_check(cuda_stream_wait(lm_stream));
}
fn lm_prefill(tokens) {
    let n=h_count(tokens);if !lm_prompt_graph {lm_prompt_prepare(n);}h_assert(n==lm_prompt_count,"prepared prompt length differs");
    let i=0;while i<n {store64(lm_prompt_host+i*8,h_at(tokens,i));i=i+1;}lm_check(cuda_graph_launch(lm_prompt_graph,lm_stream));return lm_check(cuda_stream_wait(lm_stream));
}
