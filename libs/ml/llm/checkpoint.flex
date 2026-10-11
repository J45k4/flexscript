import "runtime.flex";
global lw_tensors=0;
global lw_config=0;
fn lw_int(text) {
    let n=0;let i=0;while load8(text+i) {let c=load8(text+i);h_assert(c>=48 && c<=57 && i<9,"invalid positive integer");n=n*10+c-48;i=i+1;}
    h_assert(i>0,"empty integer");return n;
}
fn lw_number(text) {
    let i=0;let n=0;let denominator=1;let fractional=0;
    while (load8(text+i)>=48 && load8(text+i)<=57) || load8(text+i)==46 {
        let c=load8(text+i);if c==46 {h_assert(!fractional,"invalid decimal");fractional=1;}else {n=n*10+c-48;if fractional {denominator=denominator*10;}}i=i+1;
    }
    let v=f64_div(f64_from_i64(n),f64_from_i64(denominator));
    if load8(text+i)==101 || load8(text+i)==69 {i=i+1;let negative=0;if load8(text+i)==45 {negative=1;i=i+1;}else if load8(text+i)==43 {i=i+1;}
        let exponent=0;while load8(text+i)>=48 && load8(text+i)<=57 {exponent=exponent*10+load8(text+i)-48;i=i+1;h_assert(exponent<100,"exponent out of range");}
        while exponent {if negative {v=f64_div(v,f64_from_i64(10));}else {v=f64_mul(v,f64_from_i64(10));}exponent=exponent-1;}
    }return v;
}
fn lw_field(name) {
    let at=h_find(lw_config,h_cat3("\"",name,"\""));h_assert(at>=0,h_cat("missing model config: ",name));
    at=at+h_len(name)+2;while load8(lw_config+at)==32 || load8(lw_config+at)==9 {at=at+1;}h_assert(load8(lw_config+at)==58,"invalid config field");at=at+1;
    while load8(lw_config+at)==32 || load8(lw_config+at)==9 || load8(lw_config+at)==10 || load8(lw_config+at)==13 {at=at+1;}return lw_config+at;
}
fn lw_config_number(name) {return lw_number(lw_field(name));}
fn lw_config_bool(name) {let value=lw_field(name);h_assert(h_starts(value,"true") || h_starts(value,"false"),"invalid boolean config");return h_starts(value,"true");}
fn lw_config_int(name) {return f64_to_i64_trunc(lw_config_number(name));}
fn lw_context_max() {let n=lw_config_int("max_position_embeddings");h_assert(n>=32,"invalid checkpoint context limit");if n>ll_context_max() {n=ll_context_max();}return n;}
fn lw_map(path) {
    let fd=syscall(2,path,0x80000,0,0,0,0);h_assert(fd>=0,h_cat("cannot open checkpoint: ",path));
    let size=syscall(8,fd,0,2,0,0,0);h_assert(size>=10 && size<=8589934592,"invalid checkpoint size");
    let p=syscall(9,0,size,1,2,fd,0);h_close(fd);h_assert(p>0,"checkpoint mmap failed");
    let map=h_take(16);store64(map,p);store64(map+8,size);return map;
}
fn lw_load(directory) {
    lw_config=h_read(h_join(directory,"config.json"));
    h_assert(lm_capacity<=lw_context_max(),"context exceeds checkpoint max_position_embeddings");
    h_assert(h_has(lw_config,"Qwen3ForCausalLM") && lw_config_int("head_dim")==128,"requires Qwen3 text model with 128-wide heads");
    h_assert(!lw_config_bool("attention_bias") && !lw_config_bool("use_sliding_window") && h_starts(lw_field("rope_scaling"),"null"),"initial Qwen3 recipe requires bias-free full attention and unscaled rotary");
    let tied=lw_config_bool("tie_word_embeddings");
    let index=j_parse(h_read(h_join(directory,"model.safetensors.index.json")));let files=h_vec();let fields=j_value(j_need(index,"weight_map"));let i=0;
    while i<h_count(fields) {let pair=h_at(fields,i);let name=j_value(load64(pair+8));let j=0;let found=tied && h_equal(load64(pair),"lm_head.weight");
        while j<h_count(files) {if h_equal(name,h_at(files,j)) {found=1;}j=j+1;}if !found {h_assert(!h_has(name,"/") && h_has(name,".safetensors"),"invalid checkpoint shard name");h_add(files,name);}i=i+1;
    }
    lw_tensors=j_object();i=0;
    while i<h_count(files) {
        let name=h_at(files,i);h_print(2,h_cat3("Loading ",name,"...\n"));let map=lw_map(h_join(directory,name));let p=load64(map);let size=load64(map+8);let n=load64(p);
        h_assert(n>=2 && n<=1048576 && n<=size-8,"invalid safetensors header");let header=j_parse(h_slice(p+8,n));let tensors=j_value(header);
        let data=lm_alloc(size-8-n);if !lm_dry_run {
            if lm_progress_json || lm_backend>=2 {let bytes=size-8-n;let sent=0;let label=h_cat("Loading weights: ",name);lm_progress(label,0,bytes);
                // Bound host pinning on AMD: copying from a multi-GB file mmap
                // directly can thrash under host-memory pressure during SDMA.
                let staging=0;let copy=0;let staging_bytes=67108864;if bytes<staging_bytes {staging_bytes=bytes;}
                if lm_backend>=2 {staging=device_host_buffer(staging_bytes);lm_check(device_status);copy=ffi_symbol(ffi_open("libc.so.6"),"memcpy");h_assert(copy,"memcpy unavailable");}
                while sent<bytes {let chunk=bytes-sent;if chunk>67108864 {chunk=67108864;}let source=p+8+n+sent;
                    if staging {ffi_call(copy,staging,source,chunk,0,0,0);source=staging;}
                    lm_check(device_upload(data+sent,source,chunk));sent=sent+chunk;lm_progress(label,sent,bytes);}
                if staging {lm_check(device_host_free(staging));}}
            else {lm_check(device_upload(data,p+8+n,size-8-n));}
            if lm_weight_format {h_assert((size-8-n)%4==0,"FP16 staging requires packed checkpoint words");let words=h_take(64);store64(words,data);store64(words+8,(size-8-n)/4);
                lm_check(device_launch_words(load64(lm_modules+17*8),0,0,(size-8-n)/4,device_config(((size-8-n)/4+127)/128,1,1,128,1,1,0,0),words));}}let j=0;
        lm_progress("Preparing weights",0,h_count(tensors));
        while j<h_count(tensors) {let pair=h_at(tensors,j);let tensor_name=load64(pair);let spec=load64(pair+8);
            if !h_equal(tensor_name,"__metadata__") {
                h_assert(h_equal(j_s(spec,"dtype"),"BF16"),"LLM checkpoint weights must be BF16");let shape=j_need(spec,"shape");let rank=j_count(shape);h_assert(rank==1 || rank==2,"invalid weight rank");
                let rows=1;let width=j_value(j_at(shape,rank-1));if rank==2 {rows=j_value(j_at(shape,0));}
                h_assert(rows>0 && width>0 && rows<=200000 && width<=65536,"invalid weight dimensions");
                let offsets=j_need(spec,"data_offsets");h_assert(j_count(offsets)==2,"invalid tensor offsets");let begin=j_value(j_at(offsets,0));let end=j_value(j_at(offsets,1));
                h_assert(begin>=0 && begin%2==0 && end>=begin && end-begin==rows*width*2 && end<=size-8-n,"tensor exceeds checkpoint bounds");
                if lm_weight_format==2 && rank==2 && !h_equal(tensor_name,"model.embed_tokens.weight") && !h_equal(tensor_name,"lm_head.weight") {
                    h_assert(rows%16==0 && width%8==0,"tiled matrix dimensions must be multiples of 16 by 8");
                    if !lm_dry_run {let scratch=device_buffer(end-begin);lm_check(device_status);let desc=h_take(64);store64(desc,data+begin);store64(desc+8,scratch);store64(desc+16,width);
                        lm_check(device_launch_words(load64(lm_modules+22*8),0,0,rows*width/4,device_config((width/4+127)/128,rows,1,128,1,1,0,0),desc));
                        lm_check(device_copy(data+begin,scratch,end-begin));lm_check(device_free(scratch));}
                    j_set(lm_tiled_weights,h_int(data+begin),j_int(1));}
                let v=lm_value(1,data+begin,rows*width,width);store64(v+32,rows);h_assert(!j_get(lw_tensors,tensor_name),"duplicate checkpoint tensor");j_set(lw_tensors,tensor_name,v);
            }j=j+1;if j%16==0 || j==h_count(tensors) {lm_progress("Preparing weights",j,h_count(tensors));}
        }
        h_assert(syscall(11,p,size,0,0,0,0)==0,"checkpoint unmap failed");i=i+1;
    }
    if tied {j_set(lw_tensors,"lm_head.weight",lw_weight("model.embed_tokens.weight"));}return 0;
}
fn lw_weight(name) {let value=j_get(lw_tensors,name);h_assert(value,h_cat("missing checkpoint tensor: ",name));return value;}
fn lw_rotary() {
    let theta=lw_config_number("rope_theta");let logtheta=0;
    // Qwen3 uses theta=1e6; avoid a host log dependency in this initial recipe.
    h_assert(f64_eq(theta,f64_from_i64(1000000)),"initial rotary table requires rope_theta=1000000");logtheta=0x402ba18a998fffa0;
    if lm_dry_run {lm_table=lm_alloc(lm_capacity*512);return 0;}
    let table=alloc(lm_capacity*64*8);let d=0;
    lm_progress("Building rotary table",0,64);
    while d<64 {let frequency=f64_exp(f64_mul(logtheta,f64_div(f64_from_i64(-d),f64_from_i64(64))));let p=0;
        while p<lm_capacity {let angle=f64_mul(f64_from_i64(p),frequency);let out=table+(p*64+d)*8;
            gpu_store_u32(out,gpu_f32_pack(f64_cos(angle)));gpu_store_u32(out+4,gpu_f32_pack(f64_sin(angle)));p=p+1;}d=d+1;if d%8==0 {lm_progress("Building rotary table",d,64);}
    }
    lm_table=lm_alloc(lm_capacity*512);return lm_check(device_upload(lm_table,table,lm_capacity*512));
}
