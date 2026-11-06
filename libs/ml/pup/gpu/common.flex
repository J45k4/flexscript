// Native static-tensor lowering. Host operations use argv vectors, never a shell.
import "../../../../scripts/lib/json.flex";
global cg_values=0;
global cg_code=0;
global cg_work=0;
global cg_threads=128;
global cg_shared=0;
fn cg_min(a,b) {if a<b {return a;}return b;}
fn cg_max(a,b) {if a>b {return a;}return b;}
fn cg_power(n) {return n>0 && !(n&(n-1));}
fn cg_gcd(a,b) {while b {let c=a%b;a=b;b=c;}return a;}
fn cg_product(shape,start,end) {let n=1;while start<end {n=n*load64(shape+start*8);start=start+1;}return n;}
fn cg_node(nodes,i) {return nodes+i*224;}
fn cg_param(node,i) {return load64(node+160+i*8);}
fn cg_set(key,value) {j_set(cg_values,key,j_string(value));return value;}
fn cg_num(key,value) {return cg_set(key,h_int(value));}
fn cg_expand(text) {
    let out=h_buffer();let i=0;while load8(text+i) {if load8(text+i)==64 {let end=i+1;while load8(text+end) && load8(text+end)!=64 {end=end+1;}h_assert(load8(text+end),"unterminated kernel placeholder");let key=h_slice(text+i+1,end-i-1);let value=j_get(cg_values,key);h_assert(value,h_cat("missing kernel placeholder: ",key));h_text(out,j_value(value));i=end+1;}else {h_append(out,text+i,1);i=i+1;}}return h_data(out);
}
fn cg_f1(text,a) {return h_replace(text,"@0@",a);}
fn cg_f2(text,a,b) {return h_replace(cg_f1(text,a),"@1@",b);}
fn cg_f3(text,a,b,c) {return h_replace(cg_f2(text,a,b),"@2@",c);}
fn cg_f4(text,a,b,c,d) {return h_replace(cg_f3(text,a,b,c),"@3@",d);}
fn cg_line(text) {h_text(cg_code,cg_expand(text));h_text(cg_code,"\n");return 0;}
fn cg_q(value,divisor) {
    h_assert(divisor>0 && divisor<=16777216,"index divisor out of range");if divisor==1 {return h_cat3("(",value,")");}if cg_power(divisor) {let shift=0;while (1<<shift)<divisor {shift=shift+1;}return h_cat3("((",value,h_cat3(")>>",h_int(shift),")"));}return h_cat3("q",h_int(divisor),h_cat3("(",value,")"));
}
fn cg_r(value,divisor) {if cg_power(divisor) {return h_cat3("((",value,h_cat3(")&",h_int(divisor-1),")"));}return h_cat3("((",value,h_cat3(")-",cg_q(value,divisor),h_cat3("*",h_int(divisor),")")));}
fn cg_activation(value) {return h_cat3("vk_mul(",value,h_cat3(",vk_sigmoid(",value,"))"));}
fn cg_pitch(rows,reduction,vector) {let banks=1;while banks*reduction<32 {banks=banks*2;}if vector {banks=cg_max(2,banks);}while cg_gcd(rows,32)!=banks {rows=rows+1;}return rows;}
fn cg_broadcast(index,shape,source) {
    if h_bytes(shape,source,32) {return "index";}let terms=h_buffer();let stride=1;let i=3;while i>=0 {let d=load64(shape+i*8);let other=load64(source+i*8);if other!=1 {if h_size(terms) {h_text(terms,"+");}h_text(terms,h_cat3(cg_r(index,d),"*",h_int(stride)));}index=cg_q(index,d);stride=stride*other;i=i-1;}if !h_size(terms) {return "0";}return h_data(terms);
}
fn cg_dimensions(node) {
    cg_num("op",load64(node));let i=0;while i<4 {cg_num(h_cat("s",h_int(i)),load64(node+64+i*8));cg_num(h_cat("a",h_int(i)),load64(node+96+i*8));cg_num(h_cat("b",h_int(i)),load64(node+128+i*8));i=i+1;}
    cg_num("batch",load64(node+96));cg_num("cin",load64(node+104));cg_num("ih",load64(node+112));cg_num("iw",load64(node+120));cg_num("cout",load64(node+72));cg_num("oh",load64(node+80));cg_num("ow",load64(node+88));cg_num("k",cg_param(node,0));cg_num("stride",cg_param(node,1));cg_num("pad",cg_param(node,2));cg_num("groups",cg_param(node,3));return 0;
}
