// Inference Pup subset -> resident tensor schedule. Model math remains a graph
// of embedding, linear, RMSNorm, rotary, cached attention and elementwise ops.
// Static layer loops expand here; the GPU runtime has no Qwen layer interpreter.
import "checkpoint.flex";
global lp_text=0;
global lp_at=0;
global lp_token=0;
global lp_word=0;
global lp_bindings=0;
global lp_layer=0;
global lp_line=1;
global lp_path=0;
global lp_depth=0;
global lp_output_seen=0;
global lp_in_loop=0;
fn lp_fail(message) {h_die(h_cat3(lp_path,h_cat3(":",h_int(lp_line),": "),message));return 0;}
fn lp_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95;}
fn lp_next() {
    while load8(lp_text+lp_at)==32 || load8(lp_text+lp_at)==13 || load8(lp_text+lp_at)==35 {
        if load8(lp_text+lp_at)==35 {while load8(lp_text+lp_at) && load8(lp_text+lp_at)!=10 {lp_at=lp_at+1;}}else {lp_at=lp_at+1;}
    }
    let c=load8(lp_text+lp_at);lp_token=c;if !c {return 0;}lp_at=lp_at+1;
    if c==10 {lp_line=lp_line+1;return 0;}
    if lp_letter(c) {let start=lp_at-1;while lp_letter(load8(lp_text+lp_at)) || (load8(lp_text+lp_at)>=48 && load8(lp_text+lp_at)<=57) {lp_at=lp_at+1;}
        lp_word=h_slice(lp_text+start,lp_at-start);lp_token=200;
        if h_equal(lp_word,"f") && load8(lp_text+lp_at)==34 {lp_at=lp_at+1;lp_string();lp_word=h_replace(lp_word,"{layer}",h_int(lp_layer));}
    }else if c==34 {lp_string();}
    else if c>=48 && c<=57 {let start=lp_at-1;while load8(lp_text+lp_at)>=48 && load8(lp_text+lp_at)<=57 {lp_at=lp_at+1;}lp_word=h_slice(lp_text+start,lp_at-start);lp_token=202;}
    else if c==9 {lp_fail("tabs are unsupported");}return 0;
}
fn lp_string() {
    let start=lp_at;while load8(lp_text+lp_at) && load8(lp_text+lp_at)!=34 {if load8(lp_text+lp_at)==10 || load8(lp_text+lp_at)==92 {lp_fail("invalid string literal");}lp_at=lp_at+1;}
    if !load8(lp_text+lp_at) {lp_fail("unterminated string");}lp_word=h_slice(lp_text+start,lp_at-start);lp_at=lp_at+1;lp_token=201;return 0;
}
fn lp_expect(token) {if lp_token!=token {lp_fail("unexpected model token");}lp_next();return 0;}
fn lp_is(name) {return lp_token==200 && h_equal(lp_word,name);}
fn lp_get(name) {let node=j_get(lp_bindings,name);if !node {lp_fail(h_cat("undefined model binding: ",name));}return node;}
fn lp_arg(args,i) {return h_at(args,i);}
fn lp_tensor(v) {if load64(v)!=2 {lp_fail("expected a tensor");}return load64(v+16);}
fn lp_call(name,args) {
    let count=h_count(args);let a=0;let b=0;if count {a=lp_arg(args,0);}if count>1 {b=lp_arg(args,1);}
    if h_equal(name,"config") && count==1 {h_assert(load64(a)==5,"config name must be a string");return lm_value(3,lw_config_number(load64(a+8)),0,0);}
    if h_equal(name,"weight") && count==1 {h_assert(load64(a)==5,"weight name must be a string");return lw_weight(load64(a+8));}
    if h_equal(name,"input") && count==1 {h_assert(load64(a)==5 && h_equal(load64(a+8),"tokens"),"only token input is supported");return lm_value(4,lm_state,0,0);}
    if h_equal(name,"embedding") && count==2 {
        h_assert(load64(a)==1 && load64(b)==4,"embedding requires weights and tokens");let n=load64(a+24);let y=lm_tensor(n);
        lm_emit(3,load64(a+8),lm_state,load64(y+8),4,0,n,n);return y;
    }
    if h_equal(name,"linear") && count==2 {
        let n=lp_tensor(a);h_assert(load64(b)==1 && n==load64(b+24),"linear weight shape mismatch");let rows=load64(b+32);let y=lm_tensor(rows);
        let kind=0;if n%4==0 {kind=5;}lm_emit(kind,load64(b+8),load64(a+8),load64(y+8),n,0,0,rows*32);return y;
    }
    if h_equal(name,"rms_norm") && count==3 {
        let n=lp_tensor(a);let width=load64(b+24);h_assert(load64(b)==1 && load64(b+32)==1 && width>0 && n%width==0,"RMSNorm shape mismatch");
        let epsilon=lp_arg(args,2);h_assert(load64(epsilon)==3,"RMSNorm epsilon must be scalar");let y=lm_tensor(n);
        let kind=1;let group=128;if width%4==0 {kind=6;if width==128 {group=32;}}
        lm_emit(kind,load64(a+8),load64(b+8),load64(y+8),width,gpu_f32_div(1065353216,gpu_f32_from_i64(width)),gpu_f32_pack(load64(epsilon+8)),n/width*group);return y;
    }
    if h_equal(name,"rope") && count==1 {let n=lp_tensor(a);h_assert(n%128==0,"rotary requires 128-wide heads");let y=lm_tensor(n);
        lm_emit(2,load64(a+8),load64(y+8),lm_table,lm_state,0,0,n/2);return y;}
    if h_equal(name,"attention") && count==3 {
        let qn=lp_tensor(a);let kn=lp_tensor(b);let v=lp_arg(args,2);h_assert(lp_tensor(v)==kn && qn%128==0 && kn%128==0 && qn%kn==0,"attention head shape mismatch");
        let ratio=qn/kn;let shift=0;while (1<<shift)<ratio {shift=shift+1;}h_assert((1<<shift)==ratio,"attention head ratio must be power of two");
        let kcache=lm_alloc(lm_capacity*kn*4);let vcache=lm_alloc(lm_capacity*kn*4);
        lm_emit(3,load64(b+8),0,kcache,5,lm_state,kn,kn);lm_emit(3,load64(v+8),0,vcache,5,lm_state,kn,kn);
        let y=lm_tensor(qn);lm_emit(4,load64(a+8),kcache,vcache,load64(y+8),lm_state,kn,qn/128*512);
        store64(h_at(lm_steps,h_count(lm_steps)-1)+64,shift);return y;
    }
    if h_equal(name,"silu") && count==1 {let n=lp_tensor(a);let y=lm_tensor(n);lm_emit(3,load64(a+8),0,load64(y+8),3,0,0,n);return y;}
    if (h_equal(name,"add") || h_equal(name,"mul")) && count==2 {let n=lp_tensor(a);h_assert(lp_tensor(b)==n,"elementwise shape mismatch");let op=1;if h_equal(name,"mul") {op=2;}let y=lm_tensor(n);
        lm_emit(3,load64(a+8),load64(b+8),load64(y+8),op,0,0,n);return y;}
    lp_fail(h_cat("unsupported model operation/arity: ",name));return 0;
}
fn lp_primary() {
    if lp_token==201 {let v=lm_value(5,lp_word,0,0);lp_next();return v;}
    if lp_token==202 {let v=lm_value(3,f64_from_i64(lw_int(lp_word)),0,0);lp_next();return v;}
    if lp_token==40 {lp_next();let v=lp_expression();lp_expect(41);return v;}
    if lp_token==200 {let name=lp_word;lp_next();if lp_token!=40 {if h_equal(name,"layer") {return lm_value(3,f64_from_i64(lp_layer),0,0);}return lp_get(name);}
        lp_next();let args=h_vec();while lp_token!=41 {h_assert(h_count(args)<8,"too many model arguments");h_add(args,lp_expression());if lp_token!=41 {lp_expect(44);}}
        lp_expect(41);return lp_call(name,args);
    }lp_fail("expected model expression");return 0;
}
fn lp_product() {let a=lp_primary();while lp_token==42 {lp_next();let args=h_args(a,lp_primary(),0,0,0,0);a=lp_call("mul",args);}return a;}
fn lp_expression() {lp_depth=lp_depth+1;h_assert(lp_depth<=32,"model expression depth exceeded");let a=lp_product();while lp_token==43 {lp_next();let args=h_args(a,lp_product(),0,0,0,0);a=lp_call("add",args);}lp_depth=lp_depth-1;return a;}
fn lp_statement() {
    if lp_output_seen {lp_fail("output must be the final declaration");}
    if lp_is("output") {if lp_in_loop {lp_fail("output cannot occur inside a layer loop");}lp_output_seen=1;lp_next();let out=lp_expression();lp_tensor(out);lm_output=load64(out+8);lm_output_size=load64(out+16);}
    else {if lp_token!=200 {lp_fail("expected model binding");}let name=lp_word;lp_next();lp_expect(61);j_set(lp_bindings,name,lp_expression());}
    if lp_token && lp_token!=10 {lp_fail("expected end of model line");}if lp_token==10 {lp_next();}return 0;
}
fn lp_parse(path) {
    lp_text=h_read(path);lp_path=path;lp_at=0;lp_line=1;lp_layer=0;lp_depth=0;lp_output_seen=0;lp_in_loop=0;lp_bindings=j_object();lp_next();let outputs=0;
    while lp_token {
        if lp_token==10 {lp_next();}
        else if lp_is("for") {
            if lp_output_seen {lp_fail("output must be the final declaration");}
            lp_next();h_assert(lp_is("layer"),"only static layer loops are supported");lp_next();h_assert(lp_is("in"),"expected in");lp_next();h_assert(lp_is("range"),"expected range");lp_next();lp_expect(40);
            let length=lp_expression();h_assert(load64(length)==3,"loop bound must be scalar");let n=f64_to_i64_trunc(load64(length+8));h_assert(n>0 && n<=128,"invalid layer count");lp_expect(41);lp_expect(58);
            h_assert(lp_token==10,"expected indented model loop");let start=lp_at;let line=lp_line;let end=start;
            // The lexer ignores spaces; the source indentation defines the body.
            while load8(lp_text+end)==32 {while load8(lp_text+end) && load8(lp_text+end)!=10 {end=end+1;}if load8(lp_text+end)==10 {end=end+1;}}
            h_assert(end>start,"empty layer loop");lp_layer=0;lp_in_loop=1;
            while lp_layer<n {lp_at=start;lp_line=line;lp_next();while lp_token && lp_at<=end {lp_statement();}lp_layer=lp_layer+1;}
            lp_in_loop=0;lp_at=end;lp_next();
        }else {if lp_is("output") {outputs=outputs+1;}lp_statement();}
    }
    h_assert(outputs==1 && lm_output && lm_output_size==lw_config_int("vocab_size"),"model must output vocabulary logits");return 0;
}
