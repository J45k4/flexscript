import "nn.flex";
global pp_pos=0;
global pp_start=0;
global pp_token=0;
global pp_text=0;
global pp_value=0;
global pp_bindings=0;
global pp_binding_count=0;
global pp_depth=0;
fn pp_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95;}
fn pp_digit(c) {return c>=48 && c<=57;}
fn pp_next() {
    while pp_pos<pg_source_size && (load8(pg_source+pp_pos)==32 || load8(pg_source+pp_pos)==13 || load8(pg_source+pp_pos)==35) {
        if load8(pg_source+pp_pos)==35 {while pp_pos<pg_source_size && load8(pg_source+pp_pos)!=10 {pp_pos=pp_pos+1;}}
        else {pp_pos=pp_pos+1;}
    }
    pp_start=pp_pos;pg_site=pp_start;pp_token=0;if pp_pos>=pg_source_size {return 0;}
    let c=load8(pg_source+pp_pos);pp_pos=pp_pos+1;pp_token=c;
    if pp_letter(c) {
        while pp_pos<pg_source_size && (pp_letter(load8(pg_source+pp_pos)) || pp_digit(load8(pg_source+pp_pos))) {pp_pos=pp_pos+1;}
        if pp_pos-pp_start>255 {pg_error("identifier exceeds 255 bytes");}pp_text=pg_str(pg_source+pp_start,pp_pos-pp_start);pp_token=200;
    }else if pp_digit(c) || c==46 {
        let value=0;let denominator=0x3ff0000000000000;let fraction=0;let digits=0;let integer=1;let active=1;pp_pos=pp_start;
        while pp_pos<pg_source_size && active {
            c=load8(pg_source+pp_pos);
            if pp_digit(c) {value=f64_add(f64_mul(value,f64_from_i64(10)),f64_from_i64(c-48));if fraction {denominator=f64_mul(denominator,f64_from_i64(10));}digits=digits+1;pp_pos=pp_pos+1;}
            else if c==46 && !fraction {fraction=1;integer=0;pp_pos=pp_pos+1;}else {active=0;}
            if pp_pos-pp_start>64 {pg_error("numeric literal exceeds 64 bytes");}
        }
        if !digits {pg_error("invalid numeric literal");}value=f64_div(value,denominator);
        c=load8(pg_source+pp_pos);if c==101 || c==69 {
            integer=0;pp_pos=pp_pos+1;let sign=1;c=load8(pg_source+pp_pos);if c==43 || c==45 {if c==45 {sign=-1;}pp_pos=pp_pos+1;}
            let exponent=0;digits=0;while pp_pos<pg_source_size && pp_digit(load8(pg_source+pp_pos)) {exponent=exponent*10+load8(pg_source+pp_pos)-48;pp_pos=pp_pos+1;digits=digits+1;if exponent>100 {pg_error("numeric exponent out of range");}}
            if !digits {pg_error("missing numeric exponent");}let i=0;while i<exponent {if sign<0 {value=f64_div(value,f64_from_i64(10));}else {value=f64_mul(value,f64_from_i64(10));}i=i+1;}
        }
        if !f64_is_finite(value) {pg_error("nonfinite numeric literal");}
        let bits=gpu_f32_pack(value);if (bits&0x7fffffff)>=0x7f800000 {pg_error("numeric literal exceeds finite f32 range");}
        if integer && f64_gt(value,f64_from_i64(16777216)) {integer=0;}
        pp_value=pg_constant(bits,integer);pp_token=201;
    }else if c==34 {
        let start=pp_pos;while pp_pos<pg_source_size && load8(pg_source+pp_pos)!=34 {if load8(pg_source+pp_pos)==10 || load8(pg_source+pp_pos)==92 {pg_error("unsupported string escape or newline");}pp_pos=pp_pos+1;}
        if pp_pos>=pg_source_size || pp_pos-start>255 {pg_error("invalid parameter name string");}
        pp_text=pg_str(pg_source+start,pp_pos-start);pp_pos=pp_pos+1;pp_token=202;
    }else if c==9 {pg_error("tabs are not supported");}
    return 0;
}
fn pp_expect(token) {if pp_token!=token {pg_error("unexpected Pup token");}pp_next();return 0;}
fn pp_name(name) {return pp_token==200 && pg_eq(pp_text,name);}
fn pp_bind(name,value) {
    let i=0;while i<pp_binding_count {if pg_eq(load64(pp_bindings+i*16),name) {pg_error("duplicate binding");}i=i+1;}
    if pp_binding_count>=2048 {pg_error("too many bindings");}
    store64(pp_bindings+pp_binding_count*16,name);store64(pp_bindings+pp_binding_count*16+8,value);pp_binding_count=pp_binding_count+1;return 0;
}
fn pp_lookup(name) {
    let i=pp_binding_count;while i {i=i-1;if pg_eq(load64(pp_bindings+i*16),name) {return load64(pp_bindings+i*16+8);}}
    if pg_eq(name,"f32") {return pg_node(101,0,0,0,0,0,0);}
    if pg_eq(name,"add") {return pg_node(102,0,0,0,0,3,0);}if pg_eq(name,"max") {return pg_node(102,0,0,0,0,7,0);}
    pg_error(pg_cat("unknown binding: ",name));return 0;
}
fn pp_arg(args,index) {return load64(args+index*8);}
fn pp_shape(value) {
    if load64(value)!=100 {pg_error("expected a shape/axis list");}
    let count=load64(value+48);if count>8 {pg_error("rank exceeds eight");}let shape=alloc(count*8+8);let i=0;
    while i<count {store64(shape+i*8,pg_integer(load64(load64(value+56)+i*8)));i=i+1;}return shape;
}
fn pp_call(name,args,count) {
    if pg_eq(name,"param") && count==3 {
        if load64(pp_arg(args,1))!=101 {pg_error("only f32 parameters are supported");}
        let slot=pg_integer(pp_arg(args,0));let shape=alloc(8);store64(shape,pg_integer(pp_arg(args,2)));
        return pg_parameter(slot,pg_cat("slot",pg_num(slot)),1,shape);
    }
    if pg_eq(name,"input") && count==2 {
        let name_value=pp_arg(args,0);let dims=pp_arg(args,1);if load64(name_value)!=103 {pg_error("input name must be a string");}
        return pg_parameter(pg_param_count,load64(name_value+80),load64(dims+48),pp_shape(dims));
    }
    if pg_eq(name,"const") && count==1 {if load64(pp_arg(args,0))!=2 {pg_error("const requires a literal");}return pp_arg(args,0);}
    if pg_eq(name,"stack") {let list=pg_node(100,0,0,0,0,count,args);return list;}
    if pg_eq(name,"reshape") && count==2 {let shape=pp_arg(args,1);return pg_reshape(pp_arg(args,0),load64(shape+48),pp_shape(shape));}
    if pg_eq(name,"permute") && count==2 {let axes=pp_arg(args,1);return pg_permute(pp_arg(args,0),load64(axes+48),pp_shape(axes));}
    if pg_eq(name,"reduce") && count==3 {
        let operation=pp_arg(args,1);if load64(operation)!=102 {pg_error("expected add or max reduction");}
        return pg_reduce(pp_arg(args,0),load64(operation+48),pg_integer(pp_arg(args,2)));
    }
    if pg_eq(name,"cast") && count==2 {if load64(pp_arg(args,1))!=101 {pg_error("only f32 casts are supported");}if load64(pp_arg(args,0))>=100 {pg_error("expected tensor operands");}return pp_arg(args,0);}
    if pg_eq(name,"dim") && count==2 {let a=pp_arg(args,0);let axis=pg_integer(pp_arg(args,1));if axis<0 || axis>=pg_rank(a) {pg_error("dim axis out of bounds");}return pg_constant(gpu_f32_from_i64(pg_dim(a,axis)),1);}
    if pg_eq(name,"matmul") && count==2 {return pg_matmul(pp_arg(args,0),pp_arg(args,1));}
    if pg_eq(name,"dense") && count==3 {return pg_dense(pp_arg(args,0),pp_arg(args,1),pp_arg(args,2));}
    if pg_eq(name,"linear") && count==3 {return pg_dense(pp_arg(args,0),pg_permute(pp_arg(args,1),2,pg_dims3(1,0,0)),pp_arg(args,2));}
    if pg_eq(name,"relu") && count==1 {return pg_binary(7,pp_arg(args,0),pg_constant(0,0));}
    let op=0;if pg_eq(name,"add") {op=3;}else if pg_eq(name,"sub") {op=4;}else if pg_eq(name,"mul") {op=5;}else if pg_eq(name,"fdiv") {op=6;}else if pg_eq(name,"max") {op=7;}
    if op && count==2 {return pg_binary(op,pp_arg(args,0),pp_arg(args,1));}
    pg_error(pg_cat("unsupported operation or arity: ",name));return 0;
}
fn pp_primary() {
    if pp_token==201 {let v=pp_value;pp_next();return v;}
    if pp_token==202 {let v=pg_node(103,0,0,0,0,0,0);store64(v+80,pp_text);pp_next();return v;}
    if pp_token==40 {pp_next();let v=pp_expression();pp_expect(41);return v;}
    if pp_token==91 {
        pp_next();let values=alloc(8*8);let count=0;
        while pp_token!=93 {if count>=8 {pg_error("rank exceeds eight");}store64(values+count*8,pp_expression());count=count+1;if pp_token!=93 {pp_expect(44);}}
        pp_expect(93);return pg_node(100,0,0,0,0,count,values);
    }
    if pp_token==200 {
        let name=pp_text;pp_next();if pp_token!=40 {return pp_lookup(name);}pp_next();let args=alloc(16*8);let count=0;
        while pp_token!=41 {if count>=16 {pg_error("too many operation arguments");}store64(args+count*8,pp_expression());count=count+1;if pp_token!=41 {pp_expect(44);}}
        pp_expect(41);return pp_call(name,args,count);
    }
    pg_error("expected tensor expression");return 0;
}
fn pp_unary() {
    let negative=0;let count=0;while pp_token==45 || pp_token==43 {
        count=count+1;if count>64 {pg_error("unary nesting exceeds 64");}if pp_token==45 {negative=negative^1;}pp_next();
    }
    let v=pp_primary();if count && load64(v)>=100 {pg_error("expected tensor operands");}
    if negative {if load64(v)==2 {return pg_constant(load64(v+48)^0x80000000,load64(v+88));}return pg_node(8,v,0,pg_rank(v),load64(v+40),0,0);}return v;
}
fn pp_product() {let v=pp_unary();while pp_token==42 || pp_token==47 {let op=5;if pp_token==47 {op=6;}pp_next();v=pg_binary(op,v,pp_unary());}return v;}
fn pp_expression() {
    pp_depth=pp_depth+1;if pp_depth>64 {pg_error("expression nesting exceeds 64");}let v=pp_product();
    while pp_token==43 || pp_token==45 {let op=3;if pp_token==45 {op=4;}pp_next();v=pg_binary(op,v,pp_product());}pp_depth=pp_depth-1;return v;
}
fn pup_parse(text,size,path) {
    pg_init(text,size,path);pp_pos=0;pp_depth=0;pp_bindings=alloc(2048*16);pp_binding_count=0;pp_next();let outputs=0;
    while pp_token {
        if pp_token==10 {pp_next();}else if pp_name("output") {
            outputs=1;pp_next();pg_output(pp_expression());while pp_token==44 {pp_next();pg_output(pp_expression());}
            if pp_token && pp_token!=10 {pg_error("unexpected token after output");}
        }else {
            if outputs {pg_error("bindings must precede output");}if pp_token!=200 {pg_error("expected binding or output");}
            let name=pp_text;pp_next();pp_expect(61);let value=pp_expression();pp_bind(name,value);
            if pp_token && pp_token!=10 {pg_error("expressions must occupy one line");}
        }
    }pg_plan();return 0;
}
