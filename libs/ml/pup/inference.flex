// Static inference additions to the named-network frontend. Execution stays in
// the host backend; these operations only validate shapes and emit factories.
fn pni_axis(x,value) {let axis=pn_integer(value);if axis<0 {axis=axis+pg_rank(x);}if axis<0 || axis>=pg_rank(x) {pg_error("inference axis out of range");}return axis;}
fn pni_shape(x) {let shape=alloc(pg_rank(x)*8+8);pg_copy(shape,load64(x+40),pg_rank(x)*8);return shape;}
fn pni_call(name,args,count) {
    if !pn_inference_mode {return 0;}
    let x=load64(args);
    if pg_eq(name,"tensor") && count==2 {let key=pn_name(x);pn_unique(key);let dims=load64(args+8);if load64(dims)!=100 {pg_error("tensor needs a shape list");}let rank=load64(dims+48);if rank>4 {pg_error("inference tensor rank exceeds four");}let shape=alloc(rank*8+8);let i=0;while i<rank {store64(shape+i*8,pn_integer(load64(load64(dims+56)+i*8)));i=i+1;}let v=pg_node(23,0,0,rank,shape,0,0);store64(v+80,key);return v;}
    if pg_eq(name,"sigmoid") && count==1 {return pg_node(24,x,0,pg_rank(x),load64(x+40),0,0);}
    if pg_eq(name,"concat") && count==3 {let y=load64(args+8);let axis=pni_axis(x,load64(args+16));if pg_rank(x)!=pg_rank(y) {pg_error("concat ranks differ");}let shape=pni_shape(x);let i=0;while i<pg_rank(x) {if i!=axis && pg_dim(x,i)!=pg_dim(y,i) {pg_error("concat dimensions differ");}i=i+1;}store64(shape+axis*8,pg_dim(x,axis)+pg_dim(y,axis));return pg_node(25,x,y,pg_rank(x),shape,axis,0);}
    if pg_eq(name,"slice") && count==4 {let axis=pni_axis(x,load64(args+8));let start=pn_integer(load64(args+16));let end=pn_integer(load64(args+24));if start<0 || start>=end || end>pg_dim(x,axis) {pg_error("invalid inference slice interval");}let shape=pni_shape(x);store64(shape+axis*8,end-start);return pg_node(26,x,0,pg_rank(x),shape,axis,start);}
    if pg_eq(name,"upsample2d") && count==2 {pn_nchw(x);let scale=pn_integer(load64(args+8));if scale<1 || scale>8 {pg_error("upsample scale outside 1..8");}let shape=pni_shape(x);store64(shape+16,pg_dim(x,2)*scale);store64(shape+24,pg_dim(x,3)*scale);return pg_node(27,x,0,4,shape,scale,0);}
    if pg_eq(name,"softmax") && count==2 {let axis=pni_axis(x,load64(args+8));return pg_node(28,x,0,pg_rank(x),load64(x+40),axis,0);}
    if pg_eq(name,"batch_matmul") && count==2 {let y=load64(args+8);let rank=pg_rank(x);if rank<2 || rank>4 || rank!=pg_rank(y) || pg_dim(x,rank-1)!=pg_dim(y,rank-2) {pg_error("invalid batched matrix dimensions");}let shape=pni_shape(x);let i=0;while i<rank-2 {if pg_dim(x,i)!=pg_dim(y,i) {pg_error("batched matrix prefixes differ");}i=i+1;}store64(shape+(rank-1)*8,pg_dim(y,rank-1));return pg_node(29,x,y,rank,shape,0,0);}
    return 0;
}
fn pni_dims(rank,shape) {pn_emit("pup_shape(");pn_emit(pg_num(rank));let i=0;while i<4 {pn_emit(",");let d=1;if i<rank {d=load64(shape+i*8);}pn_emit(pg_num(d));i=i+1;}return pn_emit(")");}
fn pni_emit(node) {
    let op=load64(node);let a=load64(node+8);let b=load64(node+16);let rank=pg_rank(node);if rank>4 {pg_error("inference backend rank exceeds four");}
    if op==1 || op==23 {pn_emit("pup_tensor(\"");pn_emit(load64(node+80));pn_emit("\",");pni_dims(rank,load64(node+40));pn_emit(");\n");if op==1 {pn_emit(pg_cat(pg_cat("h_add(inputs,h_args(\"",load64(node+80)),"\","));pn_emit(pn_variable(node));pn_emit(",0,0,0,0));\n");}return 0;}
    if op==2 {pn_emit("pup_scalar(");pn_emit(pg_num(load64(node+48)));return pn_emit(");\n");}
    if op>=3 && op<=7 {pn_emit("pup_binary(");pn_emit(pg_num(op));pn_emit(",");pn_emit(pn_variable(a));pn_emit(",");pn_emit(pn_variable(b));return pn_emit(");\n");}
    if op==9 || op==10 {let name="pup_reshape";let shape=load64(node+40);if op==10 {name="pup_permute";shape=load64(node+56);}pn_emit(name);pn_emit("(");pn_emit(pn_variable(a));pn_emit(",");pni_dims(rank,shape);return pn_emit(");\n");}
    if op==12 {let meta=load64(node+48);pn_emit("pup_conv2d(");pn_emit(pn_variable(a));pn_emit(",\"");pn_emit(load64(meta));pn_emit("\"");let i=1;while i<8 {pn_emit(",");pn_emit(pg_num(load64(meta+i*8)));i=i+1;}return pn_emit(");\n");}
    if op==14 {let meta=load64(node+48);pn_emit("pup_maxpool2d(");pn_emit(pn_variable(a));let i=0;while i<3 {pn_emit(",");pn_emit(pg_num(load64(meta+i*8)));i=i+1;}return pn_emit(");\n");}
    let name="";if op==24 {name="pup_sigmoid";}else if op==25 {name="pup_concat";}else if op==26 {name="pup_slice";}else if op==27 {name="pup_upsample2d";}else if op==28 {name="pup_softmax";}else if op==29 {name="pup_batch_matmul";}else {pg_error("unsupported static inference operation");}
    pn_emit(name);pn_emit("(");pn_emit(pn_variable(a));if b {pn_emit(",");pn_emit(pn_variable(b));}if op>=25 && op<=28 {pn_emit(",");pn_emit(pg_num(load64(node+48)));}if op==26 {pn_emit(",");pn_emit(pg_num(load64(node+56)));pn_emit(",");pn_emit(pg_num(pg_dim(node,load64(node+48))));}return pn_emit(");\n");
}
