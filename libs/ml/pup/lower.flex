// Scheduled graph -> ordinary Flexscript kernel source. No platform opcodes here.
import "parser.flex";
global pl_source=0;
global pl_size=0;
fn pl_emit(text) {let n=pg_len(text);if pl_size+n>=2097152 {pg_error("generated kernel source exceeds 2 MiB");}pg_copy(pl_source+pl_size,text,n);pl_size=pl_size+n;return 0;}
fn pl_binary(a,op,b) {return pg_cat(pg_cat(pg_cat(pg_cat("(",a),op),b),")");}
fn pl_scale(a,n) {if n==1 {return a;}if !n {return "0";}return pl_binary(a,"*",pg_num(n));}
fn pl_coord(index,stride,dim,first) {
    if dim==1 {return "0";}let s=index;if stride!=1 {s=pl_binary(s,"/",pg_num(stride));}if !first {s=pl_binary(s,"%",pg_num(dim));}return s;
}
fn pl_broadcast(parent,child,index) {
    if pg_rank(child)==0 {return "0";}if pg_rank(parent)==pg_rank(child) {
        let same=1;let i=0;while i<pg_rank(parent) {if pg_dim(parent,i)!=pg_dim(child,i) {same=0;}i=i+1;}if same {return index;}
    }
    let stride=1;let child_stride=1;let result="0";let i=pg_rank(parent);let delta=pg_rank(parent)-pg_rank(child);
    while i {i=i-1;let axis=i-delta;if axis>=0 {
        if pg_dim(child,axis)!=1 {let term=pl_scale(pl_coord(index,stride,pg_dim(parent,i),i==0),child_stride);if pg_eq(result,"0") {result=term;}else {result=pl_binary(result,"+",term);}}
        child_stride=child_stride*pg_dim(child,axis);
    }stride=stride*pg_dim(parent,i);}return result;
}
fn pl_permute(v,index) {
    let a=load64(v+8);let result="0";let stride=pg_size(v);let i=0;
    while i<pg_rank(v) {stride=stride/pg_dim(v,i);let axis=load64(load64(v+56)+i*8);let oldstride=1;let j=axis+1;
        while j<pg_rank(a) {oldstride=oldstride*pg_dim(a,j);j=j+1;}
        if pg_dim(v,i)>1 {let term=pl_scale(pl_coord(index,stride,pg_dim(v,i),i==0),oldstride);if pg_eq(result,"0") {result=term;}else {result=pl_binary(result,"+",term);}}i=i+1;
    }return result;
}
fn pl_expr(v,index,root) {
    if (v!=root && load64(v+64)>=0) || load64(v)==1 {return pg_cat(pg_cat("load64(input+",pl_scale(pl_binary(pg_num(load64(v+64)),"+",index),8)),")");}
    let op=load64(v);let a=load64(v+8);let b=load64(v+16);
    if op==2 {return pg_num(load64(v+48));}if op==9 {return pl_expr(a,index,root);}if op==10 {return pl_expr(a,pl_permute(v,index),root);}
    if op==8 {return pl_binary(pl_expr(a,index,root),"^","2147483648");}
    if op<3 || op>7 {pg_error("unsupported inline graph operation");}
    let x=pl_expr(a,pl_broadcast(v,a,index),root);let y=pl_expr(b,pl_broadcast(v,b,index),root);let name="gpu_f32_add";
    if op==4 {name="gpu_f32_sub";}else if op==5 {name="gpu_f32_mul";}else if op==6 {name="gpu_f32_div";}else if op==7 {name="pup_max";}
    return pg_cat(pg_cat(pg_cat(pg_cat(name,"("),x),pg_cat(",",y)),")");
}
fn pl_stage(v,stage) {
    pl_emit(pg_cat("fn pup_s",pg_num(stage)));pl_emit("(i,input,output){");
    let expression="";
    if load64(v)==11 {
        let a=load64(v+8);let initial="0";if load64(v+56)==7 {initial="4286578688";}
        let ca=load64(v+96);let cb=load64(v+104);
        if ca {
            pl_emit(pg_cat("let row=i/",pg_num(pg_dim(cb,1))));pl_emit(pg_cat(";let col=i%",pg_num(pg_dim(cb,1))));
            pl_emit(";let k=0;let acc=0;while k<");pl_emit(pg_num(pg_dim(ca,1)));pl_emit("{");
            let ai=pl_binary(pl_scale("row",pg_dim(ca,1)),"+","k");let bi=pl_binary(pl_scale("k",pg_dim(cb,1)),"+","col");
            pl_emit(pg_cat("let a=",pl_expr(ca,ai,v)));pl_emit(pg_cat(";let b=",pl_expr(cb,bi,v)));
            pl_emit(";acc=gpu_f32_add(acc,gpu_f32_mul(a,b));k=k+1;}");
        }else {
            pl_emit(pg_cat("let k=0;let acc=",initial));pl_emit(pg_cat(";while k<",pg_num(pg_size(a)/pg_size(v))));pl_emit("{");
            let index=pl_binary(pl_scale("k",pg_size(v)),"+","i");let call="gpu_f32_add";if load64(v+56)==7 {call="pup_max";}
            pl_emit(pg_cat(pg_cat("acc=",call),"(acc,"));pl_emit(pl_expr(a,index,v));pl_emit(");k=k+1;}");
        }expression="acc";
    }else {expression=pl_expr(v,"i",v);}
    pl_emit("store64(output+");pl_emit(pl_scale(pl_binary(pg_num(load64(v+64)),"+","i"),8));pl_emit(pg_cat(",",expression));pl_emit(");return 0;}\n");return 0;
}
fn pup_lower() {
    pl_source=alloc(2097152);pl_size=0;
    // These declarations name GPU intrinsics; CPU calls fail explicitly.
    pl_emit("fn gpu_f32_add(a,b){syscall(60,78,0,0,0,0,0);return 0;}\nfn gpu_f32_sub(a,b){syscall(60,78,0,0,0,0,0);return 0;}\nfn gpu_f32_mul(a,b){syscall(60,78,0,0,0,0,0);return 0;}\nfn gpu_f32_div(a,b){syscall(60,78,0,0,0,0,0);return 0;}\n");
    pl_emit("fn pup_max(a,b){let aa=a&2147483647;let bb=b&2147483647;if aa>2139095040 || bb>2139095040{return 2143289344;}if !aa && !bb{return (a&b)&2147483648;}if (a^b)&2147483648{if a&2147483648{return b;}return a;}if a&2147483648{if aa<bb{return a;}return b;}if aa>bb{return a;}return b;}\n");
    let i=0;while i<pg_stage_count {pl_stage(load64(pg_stages+i*8),i);i=i+1;}
    pl_emit("fn kernel(index,input,output,count){let stage=load64(input);");i=0;
    while i<pg_stage_count {pl_emit(pg_cat("if stage==",pg_num(i)));pl_emit(pg_cat("{pup_s",pg_num(i)));pl_emit("(index,input,output);return 0;}");i=i+1;}
    pl_emit("return 0;}\nfn main(){return 78;}\n");return pl_source;
}
