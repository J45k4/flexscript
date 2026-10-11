// Immutable f32 tensor graph; metadata and schedules are separate from values.
import "../../../lib/gpu.flex";
global pg_nodes=0;
global pg_count=0;
global pg_params=0;
global pg_param_count=0;
global pg_outputs=0;
global pg_output_count=0;
global pg_stages=0;
global pg_stage_count=0;
global pg_words=1;
global pg_source=0;
global pg_source_size=0;
global pg_path=0;
global pg_site=0;
global pg_depths=0;
global pg_material_flags=0;
fn pg_len(s) {let n=0;while load8(s+n) {n=n+1;}return n;}
fn pg_copy(p,q,n) {let i=0;while i<n {store8(p+i,load8(q+i));i=i+1;}return p;}
fn pg_str(p,n) {let s=alloc(n+1);if s<0 {syscall(60,1,0,0,0,0,0);}pg_copy(s,p,n);return s;}
fn pg_cat(a,b) {let n=pg_len(a);let m=pg_len(b);let s=alloc(n+m+1);pg_copy(s,a,n);pg_copy(s+n,b,m);return s;}
fn pg_eq(a,b) {let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);}
fn pg_num(n) {let s=alloc(32);let i=31;let negative=n<0;if !negative {n=-n;}while n || i==31 {i=i-1;store8(s+i,48-n%10);n=n/10;}if negative {i=i-1;store8(s+i,45);}return pg_str(s+i,31-i);}
fn pg_print(s) {return syscall(1,2,s,pg_len(s),0,0,0);}
fn pg_error(message) {
    let line=1;let col=1;let i=0;while i<pg_site && i<pg_source_size {if load8(pg_source+i)==10 {line=line+1;col=1;}else {col=col+1;}i=i+1;}
    pg_print(pg_path);pg_print(":");pg_print(pg_num(line));pg_print(":");pg_print(pg_num(col));pg_print(": error: ");pg_print(message);pg_print("\n");
    syscall(60,1,0,0,0,0,0);return 0;
}
fn pg_init(text,size,path) {
    pg_source=text;pg_source_size=size;pg_path=path;pg_site=0;
    pg_nodes=alloc(4096*8);pg_params=alloc(64*8);pg_outputs=alloc(32*8);pg_stages=alloc(4096*8);
    pg_depths=alloc(4096*8);pg_material_flags=alloc(4096*8);
    pg_count=0;pg_param_count=0;pg_output_count=0;pg_stage_count=0;pg_words=1;return 0;
}
// Node: op,a,b,size,rank,shape,arg,axes,material offset,source site, name,
// literal-is-integer, contraction-left/right hints, reachable, identity.
fn pg_node(op,a,b,rank,shape,arg,axes) {
    if pg_count>=4096 || rank<0 || rank>8 {pg_error("Pup graph limit exceeded");}
    if (a && load64(a)>=100) || (b && load64(b)>=100) {pg_error("expected tensor operands");}
    let depth=1;if a {depth=load64(pg_depths+load64(a+120)*8)+1;}if b {let other=load64(pg_depths+load64(b+120)*8)+1;if other>depth {depth=other;}}
    if depth>64 {pg_error("tensor graph depth exceeds 64");}store64(pg_depths+pg_count*8,depth);
    let n=1;let i=0;while i<rank {let d=load64(shape+i*8);if d<1 || d>16777216 || n>16777216/d {pg_error("invalid or excessive tensor shape");}n=n*d;i=i+1;}
    let v=alloc(128);store64(v,op);store64(v+8,a);store64(v+16,b);store64(v+24,n);store64(v+32,rank);
    let dims=alloc(rank*8+8);pg_copy(dims,shape,rank*8);store64(v+40,dims);store64(v+48,arg);store64(v+56,axes);
    store64(v+64,-1);store64(v+72,pg_site);store64(v+120,pg_count);store64(pg_nodes+pg_count*8,v);pg_count=pg_count+1;return v;
}
fn pg_rank(v) {return load64(v+32);}
fn pg_dim(v,axis) {return load64(load64(v+40)+axis*8);}
fn pg_size(v) {return load64(v+24);}
fn pg_integer(v) {
    if load64(v)!=2 || !load64(v+88) {pg_error("expected a static integer");}
    return f64_to_i64_trunc(gpu_f32_unpack(load64(v+48)));
}
fn pg_constant(bits,integer) {let v=pg_node(2,0,0,0,0,bits,0);store64(v+88,integer);return v;}
fn pg_parameter(slot,name,rank,shape) {
    if slot<0 || slot>=64 || pg_param_count>=64 {pg_error("parameter slot limit exceeded");}
    let i=0;while i<pg_param_count {let p=load64(pg_params+i*8);if load64(p+48)==slot || pg_eq(load64(p+80),name) {pg_error("duplicate parameter slot or name");}i=i+1;}
    let v=pg_node(1,0,0,rank,shape,slot,0);store64(v+80,name);store64(pg_params+pg_param_count*8,v);pg_param_count=pg_param_count+1;return v;
}
fn pg_binary(op,a,b) {
    if load64(a)>=100 || load64(b)>=100 {pg_error("expected tensor operands");}
    let rank=pg_rank(a);if pg_rank(b)>rank {rank=pg_rank(b);}let shape=alloc(rank*8+8);let i=0;
    while i<rank {
        let x=1;let y=1;let ai=i-(rank-pg_rank(a));let bi=i-(rank-pg_rank(b));
        if ai>=0 {x=pg_dim(a,ai);}if bi>=0 {y=pg_dim(b,bi);}
        if x!=y && x!=1 && y!=1 {pg_error("incompatible broadcast shapes");}
        let d=x;if y>d {d=y;}store64(shape+i*8,d);i=i+1;
    }return pg_node(op,a,b,rank,shape,0,0);
}
fn pg_reshape(a,rank,shape) {
    let v=pg_node(9,a,0,rank,shape,0,0);if pg_size(v)!=pg_size(a) {pg_error("reshape changes element count");}return v;
}
fn pg_permute(a,rank,axes) {
    if rank!=pg_rank(a) {pg_error("permutation rank mismatch");}let shape=alloc(rank*8+8);let mask=0;let i=0;
    while i<rank {let axis=load64(axes+i*8);if axis<0 || axis>=rank || (mask&(1<<axis)) {pg_error("invalid permutation");}
        mask=mask|(1<<axis);store64(shape+i*8,pg_dim(a,axis));i=i+1;}
    let copy=alloc(rank*8+8);pg_copy(copy,axes,rank*8);return pg_node(10,a,0,rank,shape,0,copy);
}
fn pg_reduce(a,operation,count) {
    if count<1 || count>pg_rank(a) || (operation!=3 && operation!=7) {pg_error("unsupported reduction");}
    let v=pg_node(11,a,0,pg_rank(a)-count,load64(a+40)+count*8,count,operation);return v;
}
fn pg_output(v) {if load64(v)>=100 || pg_output_count>=32 {pg_error("invalid or excessive graph outputs");}store64(pg_outputs+pg_output_count*8,v);pg_output_count=pg_output_count+1;return 0;}
fn pg_materialize(v) {
    if load64(v+64)>=0 {return 0;}if pg_words>16777216-pg_size(v) {pg_error("execution workspace exceeds 128 MiB");}
    store64(v+64,pg_words);pg_words=pg_words+pg_size(v);return 0;
}
fn pg_plan() {
    if !pg_output_count {pg_error("missing output declaration");}
    let i=0;while i<pg_output_count {store64(load64(pg_outputs+i*8)+112,1);i=i+1;}
    i=pg_count;while i {i=i-1;let v=load64(pg_nodes+i*8);if load64(v+112) {if load64(v+8) {store64(load64(v+8)+112,1);}if load64(v+16) {store64(load64(v+16)+112,1);}}}
    // Materialize composite contraction operands once, avoiding repeated work.
    i=0;while i<pg_count {let v=load64(pg_nodes+i*8);if load64(v+112) && load64(v+96) {
        let a=load64(v+96);let b=load64(v+104);
        if load64(a)>=3 && load64(a)!=9 && load64(a)!=10 {store64(pg_material_flags+load64(a+120)*8,1);}
        if load64(b)>=3 && load64(b)!=9 && load64(b)!=10 {store64(pg_material_flags+load64(b+120)*8,1);}
    }i=i+1;}
    i=0;while i<pg_output_count {let v=load64(pg_outputs+i*8);store64(pg_material_flags+load64(v+120)*8,1);i=i+1;}
    i=0;while i<pg_param_count {pg_materialize(load64(pg_params+i*8));i=i+1;}
    // Every materialized value precedes all consumers, including another output.
    i=0;while i<pg_count {let v=load64(pg_nodes+i*8);
        if load64(v+112) && (load64(v)==11 || load64(pg_material_flags+i*8)) && load64(v+64)<0 {
            pg_materialize(v);store64(pg_stages+pg_stage_count*8,v);pg_stage_count=pg_stage_count+1;
        }i=i+1;
    }
    return 0;
}
fn pg_max(a,b) {
    let aa=a&0x7fffffff;let bb=b&0x7fffffff;
    if aa>0x7f800000 || bb>0x7f800000 {return 0x7fc00000;}
    if !aa && !bb {return (a&b)&0x80000000;}
    if (a^b)&0x80000000 {if a&0x80000000 {return b;}return a;}
    if a&0x80000000 {if aa<bb {return a;}return b;}if aa>bb {return a;}return b;
}
fn pg_broadcast_index(parent,child,index) {
    if pg_rank(child)==0 {return 0;}let stride=1;let result=0;let i=pg_rank(parent);let delta=pg_rank(parent)-pg_rank(child);
    let child_stride=1;while i {i=i-1;let d=pg_dim(parent,i);let axis=i-delta;
        if axis>=0 {if pg_dim(child,axis)!=1 {result=result+((index/stride)%d)*child_stride;}child_stride=child_stride*pg_dim(child,axis);}stride=stride*d;
    }return result;
}
fn pg_permute_index(v,index) {
    let a=load64(v+8);let axes=load64(v+56);let result=0;let outstride=pg_size(v);let i=0;
    while i<pg_rank(v) {outstride=outstride/pg_dim(v,i);let coordinate=(index/outstride)%pg_dim(v,i);let axis=load64(axes+i*8);let stride=1;let j=axis+1;
        while j<pg_rank(a) {stride=stride*pg_dim(a,j);j=j+1;}result=result+coordinate*stride;i=i+1;}return result;
}
// Independent mathematical evaluator; reductions materialize, views never do.
fn pg_eval(v,index,memory,root) {
    if v!=root && load64(v+64)>=0 {return load64(memory+(load64(v+64)+index)*8);}
    let op=load64(v);let a=load64(v+8);let b=load64(v+16);
    if op==1 {return load64(memory+(load64(v+64)+index)*8);}if op==2 {return load64(v+48);}
    if op==9 {return pg_eval(a,index,memory,root);}if op==10 {return pg_eval(a,pg_permute_index(v,index),memory,root);}
    if op==8 {return pg_eval(a,index,memory,root)^0x80000000;}
    if op==11 {
        let count=pg_size(a)/pg_size(v);let k=0;let value=0;if load64(v+56)==7 {value=0xff800000;}
        while k<count {let x=pg_eval(a,k*pg_size(v)+index,memory,root);if load64(v+56)==7 {value=pg_max(value,x);}else {value=gpu_f32_add(value,x);}k=k+1;}return value;
    }
    let x=pg_eval(a,pg_broadcast_index(v,a,index),memory,root);let y=pg_eval(b,pg_broadcast_index(v,b,index),memory,root);
    if op==3 {return gpu_f32_add(x,y);}if op==4 {return gpu_f32_sub(x,y);}if op==5 {return gpu_f32_mul(x,y);}if op==6 {return gpu_f32_div(x,y);}if op==7 {return pg_max(x,y);}
    pg_error("unsupported reference operation");return 0;
}
fn pg_execute(memory) {
    let stage=0;while stage<pg_stage_count {let v=load64(pg_stages+stage*8);let i=0;
        while i<pg_size(v) {store64(memory+(load64(v+64)+i)*8,pg_eval(v,i,memory,v));i=i+1;}stage=stage+1;}return 0;
}
