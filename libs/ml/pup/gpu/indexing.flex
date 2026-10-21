// Parse generated scalar index expressions, preserving 64-bit device pointers.
import "common.flex";
global cx_text=0;
global cx_at=0;
global cx_pointer=0;
fn cx_space() {while load8(cx_text+cx_at)==32 || load8(cx_text+cx_at)==10 || load8(cx_text+cx_at)==13 || load8(cx_text+cx_at)==9 {cx_at=cx_at+1;}return 0;}
fn cx_name(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95 || (c>=48 && c<=57);}
fn cx_node(kind,op,a,b,value) {let p=h_take(40);store64(p,kind);store64(p+8,op);store64(p+16,a);store64(p+24,b);store64(p+32,value);return p;}
fn cx_operator() {
    cx_space();let c=load8(cx_text+cx_at);let d=load8(cx_text+cx_at+1);
    if c==38 && d==38 {return 1;}if c==60 && d==61 {return 2;}if c==62 && d==61 {return 3;}if c==61 && d==61 {return 4;}if c==33 && d==61 {return 5;}if c==60 && d==60 {return 12;}if c==62 && d==62 {return 13;}
    if c==60 {return 6;}if c==62 {return 7;}if c==124 {return 8;}if c==94 {return 9;}if c==38 {return 10;}if c==43 {return 14;}if c==45 {return 15;}if c==42 {return 16;}return 0;
}
fn cx_precedence(op) {if op==1 {return 1;}if op<=7 {return 2;}if op==8 {return 3;}if op==9 {return 4;}if op==10 {return 5;}if op==12 || op==13 {return 6;}if op==14 || op==15 {return 7;}return 8;}
fn cx_width(op) {return 1+(op<=5 || op==12 || op==13);}
fn cx_primary() {
    cx_space();let c=load8(cx_text+cx_at);if c==45 || c==126 {cx_at=cx_at+1;return cx_node(4,c,cx_primary(),0,0);}
    if c==40 {cx_at=cx_at+1;let p=cx_parse(1);cx_space();h_assert(load8(cx_text+cx_at)==41,"index expression missing close parenthesis");cx_at=cx_at+1;return p;}
    let start=cx_at;
    if c>=48 && c<=57 {let base=10;let n=0;if c==48 && load8(cx_text+cx_at+1)==120 {base=16;cx_at=cx_at+2;}let more=1;while more {c=load8(cx_text+cx_at);let digit=-1;if c>=48 && c<=57 {digit=c-48;}if c>=97 && c<=102 {digit=c-87;}if digit<0 || digit>=base {more=0;}else {n=n*base+digit;cx_at=cx_at+1;}}return cx_node(0,0,0,0,n);}
    h_assert(cx_name(c),"invalid generated index expression");while cx_name(load8(cx_text+cx_at)) {cx_at=cx_at+1;}let name=h_slice(cx_text+start,cx_at-start);cx_space();if load8(cx_text+cx_at)!=40 {return cx_node(1,0,0,0,name);}cx_at=cx_at+1;let args=h_vec();cx_space();if load8(cx_text+cx_at)!=41 {let more=1;while more {h_add(args,cx_parse(1));cx_space();if load8(cx_text+cx_at)!=44 {more=0;}else {cx_at=cx_at+1;}}}h_assert(load8(cx_text+cx_at)==41,"generated call missing close parenthesis");cx_at=cx_at+1;return cx_node(2,0,args,0,name);
}
fn cx_parse(minimum) {
    let left=cx_primary();while 1 {let op=cx_operator();if !op || cx_precedence(op)<minimum {return left;}cx_at=cx_at+cx_width(op);let right=cx_parse(cx_precedence(op)+1);let kind=3;if op>=2 && op<=7 {kind=5;}if op==1 {kind=6;}left=cx_node(kind,op,left,right,0);}return left;
}
fn cx_is_pointer(name) {return h_equal(name,"input") || h_equal(name,"output") || h_equal(name,"other") || h_equal(name,"weights") || h_equal(name,"bias") || h_equal(name,"source") || h_equal(name,"mrb") || h_equal(name,"nrb") || h_equal(name,"lookup") || h_equal(name,"a_base") || h_equal(name,"b_base") || h_equal(name,"residual") || (h_starts(name,"nrb") && load8(name+3)>=48 && load8(name+3)<=57);}
fn cx_symbol(op) {if op==8 {return "|";}if op==9 {return "^";}if op==10 {return "&";}if op==12 {return "<<";}if op==13 {return ">>";}if op==14 {return "+";}if op==15 {return "-";}return "*";}
fn cx_function(op) {if op==2 {return "gpu_i32_le";}if op==3 {return "gpu_i32_ge";}if op==4 {return "gpu_u32_eq";}if op==5 {return "gpu_u32_ne";}if op==6 {return "gpu_i32_lt";}if op==7 {return "gpu_i32_gt";}if op==14 {return "gpu_u32_add";}if op==15 {return "gpu_u32_sub";}return "gpu_u32_mul";}
fn cx_call2(name,a,b) {return h_cat3(name,"(",h_cat3(a,",",h_cat(b,")")));}
fn cx_constant(op,a,b) {if op==8 {return a|b;}if op==9 {return a^b;}if op==10 {return a&b;}if op==12 {return a<<b;}if op==13 {return a>>b;}if op==14 {return a+b;}if op==15 {return a-b;}return a*b;}
fn cx_lower(node) {
    let kind=load64(node);let op=load64(node+8);let a=load64(node+16);let b=load64(node+24);let value=load64(node+32);cx_pointer=0;
    if kind==0 {return h_int(value);}if kind==1 {cx_pointer=cx_is_pointer(value);return value;}
    if kind==2 {let out=h_buffer();h_text(out,value);h_text(out,"(");let i=0;while i<h_count(a) {if i {h_text(out,",");}h_text(out,cx_lower(h_at(a,i)));i=i+1;}h_text(out,")");cx_pointer=h_equal(value,"gpu_address_f32");return h_data(out);}
    if kind==3 {
        if load64(a)==0 && load64(b)==0 {return h_int(cx_constant(op,load64(a+32),load64(b+32)));}
        if load64(b)==0 {let n=load64(b+32);if ((!n && (op==14 || op==15 || op==8 || op==9)) || (n==1 && op==16)) {return cx_lower(a);}if !n && op==16 {return "0";}}
        if load64(a)==0 {let n=load64(a+32);if ((!n && (op==14 || op==8 || op==9)) || (n==1 && op==16)) {return cx_lower(b);}if !n && op==16 {return "0";}}
    }
    let left=cx_lower(a);let lp=cx_pointer;
    if kind==4 {cx_pointer=0;if op==45 {return cx_call2("gpu_u32_sub","0",left);}return h_cat3("(",left,"^4294967295)");}
    let right=cx_lower(b);let rp=cx_pointer;cx_pointer=0;
    if kind==5 {return cx_call2(cx_function(op),left,right);}if kind==6 {return cx_call2("gpu_u32_mul",left,right);}
    if op==14 && lp && load64(b)==3 && load64(b+8)==16 && load64(load64(b+24))==0 && load64(load64(b+24)+32)==4 {let index=cx_lower(load64(b+16));cx_pointer=1;return cx_call2("gpu_address_f32",left,index);}
    if (op==14 || op==15 || op==16) && !lp && !rp {
        if op==14 && load64(a)==3 && load64(a+8)==16 {let x=cx_lower(load64(a+16));let y=cx_lower(load64(a+24));cx_pointer=0;return h_cat3("gpu_u32_mad(",x,h_cat3(",",y,h_cat3(",",right,")")));}return cx_call2(cx_function(op),left,right);
    }
    cx_pointer=lp || rp;return h_cat3("(",left,h_cat3(cx_symbol(op),right,")"));
}
fn cx_expression(text) {cx_text=text;cx_at=0;let node=cx_parse(1);cx_space();h_assert(!load8(cx_text+cx_at),h_cat("unparsed index expression: ",cx_text+cx_at));return cx_lower(node);}
fn cx_word_replace(text,old,replacement) {
    let out=h_buffer();let i=0;let n=h_len(old);while load8(text+i) {if (!i || !cx_name(load8(text+i-1))) && h_starts(text+i,old) && !cx_name(load8(text+i+n)) {h_text(out,replacement);i=i+n;}else {h_append(out,text+i,1);i=i+1;}}return h_data(out);
}
fn cx_narrow(body) {
    let out=h_buffer();let i=0;let valid=0;while load8(body+i) {
        let start=i;while load8(body+i) && load8(body+i)!=59 && load8(body+i)!=123 && load8(body+i)!=125 {i=i+1;}let original=h_slice(body+start,i-start);let text=h_trim(original);
        if h_len(text) && !h_equal(text,"else") {
            let offset=0;if h_starts(text,"let ") {offset=4;}let equal=h_find(text+offset,"=");let assignment=equal>=0;let end=0;while cx_name(load8(text+offset+end)) {end=end+1;}assignment=assignment && equal==end;
            if assignment && h_equal(h_slice(text+offset,equal),"valid") {valid=h_equal(text+offset+equal+1,"1");}else if valid {text=cx_word_replace(text,"valid","1");}
            let condition=0;if h_starts(text,"if ") {condition=3;}if h_starts(text,"while ") {condition=6;}
            if condition {h_text(out,h_slice(text,condition));h_text(out,cx_expression(text+condition));h_text(out," ");}
            else if assignment {h_text(out,h_slice(text,offset+equal+1));h_text(out,cx_expression(text+offset+equal+1));}
            else {h_text(out,cx_expression(text));}
        }else {h_text(out,original);}
        if load8(body+i) {h_append(out,body+i,1);i=i+1;}
    }return h_data(out);
}
fn cx_declarations() {return "\nfn gpu_address_f32(pointer,index) {return pointer+(index&0xffffffff)*4;}\nfn gpu_u32_add(a,b) {return (a+b)&0xffffffff;}\nfn gpu_u32_sub(a,b) {return (a-b)&0xffffffff;}\nfn gpu_u32_mul(a,b) {return (a*b)&0xffffffff;}\nfn gpu_u32_mad(a,b,c) {return (a*b+c)&0xffffffff;}\nfn gpu_u32_mul_hi(a,b) {return (((a&0xffffffff)*(b&0xffffffff))>>32)&0xffffffff;}\nfn gpu_i32_lt(a,b) {return ((a^0x80000000)&0xffffffff)<((b^0x80000000)&0xffffffff);}\nfn gpu_i32_le(a,b) {return !gpu_i32_lt(b,a);}\nfn gpu_i32_gt(a,b) {return gpu_i32_lt(b,a);}\nfn gpu_i32_ge(a,b) {return !gpu_i32_lt(a,b);}\nfn gpu_u32_eq(a,b) {return (a&0xffffffff)==(b&0xffffffff);}\nfn gpu_u32_ne(a,b) {return (a&0xffffffff)!=(b&0xffffffff);}\n";}
