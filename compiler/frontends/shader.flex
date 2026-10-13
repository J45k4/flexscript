// Typed SetaScript shader frontend. Both text backends consume the same AST;
// shader arithmetic is explicitly i32/u32/f32, separate from CPU word FIR.
global shader_target=0; // 1: desktop GLSL 450, 2: WGSL, 3: WebGL2 GLSL ES300
global sg_stage=0; // 1 vertex, 2 fragment, 3 compute
global sg_work=0;
global sg_decls=0;
global sg_decl_count=0;
global sg_functions=0;
global sg_function_count=0;
global sg_current=0;
global sg_locals=0;
global sg_local_count=0;
global sg_local_id=0;
global sg_depth=0;
global sg_nesting=0;
global sg_nodes=0;
global sg_node_count=0;
global sg_edges=0;
global sg_output=0;
global sg_output_size=0;
global sg_entry=-1;
global sg_structs=0;
global sg_struct_count=0;

// Types: i32/bool/u32/f32=1..4; float/signed/unsigned vectors=5..13;
// mat4f=14, void=15, texture=16, depth texture=17, structs=100+index. Buffer references add 32
// until indexed. Struct records (64 bytes): name, length, fields, count,
// portable size (0 when it contains bool). Fields (32 bytes): name, length,
// type, offset. Host-shareable structs use one std140-compatible layout on
// every target; WGSL members receive explicit @size padding to match it.
// Declaration records (64 bytes): name, length, type, kind, slot, builtin.
// Function records (64 bytes): name, length, return type, parameters, count,
// source offset, body AST. Locals (48 bytes): name, length, type, ID,
// read-only flag, depth. Nodes (64 bytes): kind, type, a, b, c, source offset,
// guaranteed-return flag, next; loop nodes use source offset for their body.
fn sg_type_word(ty) {
    if ty==1 {return "i32";}if ty==2 {return "bool";}if ty==3 {return "u32";}if ty==4 {return "f32";}
    if ty==5 {return "vec2f";}if ty==6 {return "vec3f";}if ty==7 {return "vec4f";}
    if ty==8 {return "vec2i";}if ty==9 {return "vec3i";}if ty==10 {return "vec4i";}
    if ty==11 {return "vec2u";}if ty==12 {return "vec3u";}if ty==13 {return "vec4u";}
    if ty==14 {return "mat4f";}if ty==15 {return "void";}return "texture2d";
}
fn sg_type_id() {
    let i=1;while i<=15 {if s_is(sg_type_word(i)) {return i;}i=i+1;}
    i=sg_find(sg_structs,sg_struct_count,64,ir_source+s_start,s_size);if i>=0 {return 100+i;}return 0;
}
fn sg_is_struct(ty) {return ty>=100 && ty<132;}
fn sg_struct(ty) {return sg_structs+(ty-100)*64;}
fn sg_is_ref(ty) {return (ty>32 && ty<=48) || ty>=132;}
fn sg_round(value,align) {return (value+align-1)/align*align;}
fn sg_shareable(ty) {if sg_is_struct(ty) {return load64(sg_struct(ty)+32)>0;}return ty==14 || (sg_numeric(ty) && sg_scalar(ty)!=2);}
fn sg_align(ty) {let width=sg_width(ty);if width==1 {return 4;}if width==2 {return 8;}return 16;}
fn sg_size(ty) {if sg_is_struct(ty) {return load64(sg_struct(ty)+32);}if ty==14 {return 64;}return sg_width(ty)*4;}
fn sg_type() {let ty=sg_type_id();if !ty {s_fail("unsupported shader type");}s_next();return ty;}
fn sg_width(ty) {if ty>=5 && ty<=13 {return 2+(ty-5)%3;}if ty>=1 && ty<=4 {return 1;}return 0;}
fn sg_scalar(ty) {if ty>=5 && ty<=7 {return 4;}if ty>=8 && ty<=10 {return 1;}if ty>=11 && ty<=13 {return 3;}return ty;}
fn sg_vector(scalar,width) {if width==1 {return scalar;}if scalar==4 {return width+3;}if scalar==1 {return width+6;}return width+9;}
fn sg_numeric(ty) {let scalar=sg_scalar(ty);return sg_width(ty)>0 && (scalar==1 || scalar==3 || scalar==4);}
fn sg_find(table,count,stride,name,size) {
    let i=0;while i<count {let p=table+i*stride;if s_equal(name,size,load64(p),load64(p+8)) {return i;}i=i+1;}return -1;
}
fn sg_name() {
    s_name();if sg_type_id() || s_is("shader") || s_is("input") || s_is("output") || s_is("uniform") || s_is("buffer") || s_is("texture") || s_is("depth_texture") || s_is("struct") {s_fail("reserved shader name");}return 0;
}
fn sg_node(kind,ty,a,b,c) {
    if sg_node_count>=65536 {s_fail("shader AST exceeds 65536 nodes");}
    let n=sg_nodes+sg_node_count*64;sg_node_count=sg_node_count+1;
    store64(n,kind);store64(n+8,ty);store64(n+16,a);store64(n+24,b);store64(n+32,c);store64(n+40,s_start);return n;
}
fn sg_require(a,b) {if a!=b {s_fail("shader type mismatch");}return 0;}
fn sg_local(name,size,ty,readonly) {
    if sg_local_count>=1024 || sg_local_id>=4096 {s_fail("too many shader locals");}
    let i=sg_local_count-1;while i>=0 && load64(sg_locals+i*48+40)==sg_depth {
        if s_equal(name,size,load64(sg_locals+i*48),load64(sg_locals+i*48+8)) {s_fail("duplicate shader local");}i=i-1;
    }
    let id=sg_local_id;sg_local_id=id+1;let p=sg_locals+sg_local_count*48;sg_local_count=sg_local_count+1;
    store64(p,name);store64(p+8,size);store64(p+16,ty);store64(p+24,id);store64(p+32,readonly);store64(p+40,sg_depth);return id;
}
fn sg_lookup(name,size) {
    let i=sg_local_count-1;while i>=0 {let p=sg_locals+i*48;if s_equal(name,size,load64(p),load64(p+8)) {return sg_node(2,load64(p+16),load64(p+24),load64(p+32),0);}i=i-1;}
    i=sg_find(sg_decls,sg_decl_count,64,name,size);if i<0 {s_fail("unknown shader value");}
    let p=sg_decls+i*64;let ty=load64(p+16);if load64(p+24)==4 || load64(p+24)==5 {ty=ty+32;}
    return sg_node(3,ty,i,load64(p+24)!=2 && load64(p+24)!=5,0);
}
// Builtins use backend-independent IDs; arbitrary host calls are never emitted.
fn sg_builtin(name,size) {
    if s_equal(name,size,"sin",3) {return 1;}if s_equal(name,size,"cos",3) {return 2;}
    if s_equal(name,size,"abs",3) {return 3;}if s_equal(name,size,"sqrt",4) {return 4;}
    if s_equal(name,size,"floor",5) {return 5;}if s_equal(name,size,"ceil",4) {return 6;}
    if s_equal(name,size,"fract",5) {return 7;}if s_equal(name,size,"normalize",9) {return 8;}
    if s_equal(name,size,"length",6) {return 9;}if s_equal(name,size,"dot",3) {return 10;}
    if s_equal(name,size,"cross",5) {return 11;}if s_equal(name,size,"min",3) {return 12;}
    if s_equal(name,size,"max",3) {return 13;}if s_equal(name,size,"clamp",5) {return 14;}
    if s_equal(name,size,"mix",3) {return 15;}if s_equal(name,size,"pow",3) {return 16;}
    if s_equal(name,size,"sample",6) {return 17;}if s_equal(name,size,"sample_level",12) {return 18;}
    if s_equal(name,size,"array_length",12) {return 19;}
    if s_equal(name,size,"sample_compare",14) {return 20;}return 0;
}
fn sg_arg_type(args,i) {return load64(load64(args+i*8)+8);}
// Compare decimal literals to the exact finite f32 maximum without depending
// on the host's floating point parser or changing CPU word arithmetic.
fn sg_float_literal(text,size) {
    let digits=alloc(39);let i=0;while i<39 {store8(digits+i,48);i=i+1;}
    let at=0;let count=0;let whole=0;let first=-1;let fraction=0;let beyond=0;
    while at<size && load8(text+at)!=101 && load8(text+at)!=69 {
        let c=load8(text+at);
        if c==46 {fraction=1;}else {
            if !fraction {whole=whole+1;}if first<0 && c!=48 {first=count;}
            if first>=0 {let offset=count-first;if offset<39 {store8(digits+offset,c);}else if c!=48 {beyond=1;}}
            count=count+1;
        }at=at+1;
    }
    let exponent=0;let sign=1;
    if at<size {at=at+1;if load8(text+at)==45 {sign=-1;at=at+1;}else if load8(text+at)==43 {at=at+1;}
        while at<size {exponent=exponent*10+load8(text+at)-48;at=at+1;}
    }
    if first<0 {return 0;}let order=whole-first-1+sign*exponent;
    if order>38 {s_fail("shader f32 literal out of range");}
    if order==38 {let maximum="340282346638528859811704183484516925440";i=0;
        while i<39 && load8(digits+i)==load8(maximum+i) {i=i+1;}
        if (i<39 && load8(digits+i)>load8(maximum+i)) || (i==39 && beyond) {s_fail("shader f32 literal out of range");}
    }return 0;
}
fn sg_call_type(id,args,count) {
    let expected=1;if id==10 || id==11 || id==12 || id==13 || id==16 || id==17 {expected=2;}
    if id==14 || id==15 || id==18 || id==20 {expected=3;}if count!=expected {s_fail("wrong shader builtin argument count");}
    let ty=sg_arg_type(args,0);let scalar=sg_scalar(ty);
    if id==17 || id==18 {
        let tex=load64(args);if load64(tex)!=3 || ty!=16 {s_fail("sample requires a declared texture");}
        sg_require(sg_arg_type(args,1),5);if id==18 {sg_require(sg_arg_type(args,2),4);}else if sg_stage!=2 {s_fail("implicit texture sampling requires fragment stage; use sample_level");}return 7;
    }
    // Depth comparison (shadow maps): 1.0 where ref passes the host's compare
    // function, filtered by the comparison sampler. Fragment stage only, like
    // WGSL textureSampleCompare and implicit-LOD GLSL shadow lookups.
    if id==20 {
        let tex=load64(args);if load64(tex)!=3 || ty!=17 {s_fail("sample_compare requires a declared depth_texture");}
        sg_require(sg_arg_type(args,1),5);sg_require(sg_arg_type(args,2),4);if sg_stage!=2 {s_fail("sample_compare requires fragment stage");}return 4;
    }
    if id==19 {let n=load64(args);if load64(n)!=3 {s_fail("array_length requires a buffer");}let kind=load64(sg_decls+load64(n+16)*64+24);if kind!=4 && kind!=5 {s_fail("array_length requires a buffer");}return 3;}
    if !sg_numeric(ty) {s_fail("shader builtin requires numeric values");}
    if id!=3 && id!=12 && id!=13 && id!=14 && scalar!=4 {s_fail("shader builtin requires f32 values");}
    if id==3 && scalar==3 {s_fail("abs requires signed or floating values");}
    if id==8 || id==9 || id==10 {if sg_width(ty)<2 {s_fail("shader builtin requires a vector");}}
    if id==11 {sg_require(ty,6);}if id==9 {return 4;}
    let i=1;while i<count {let other=sg_arg_type(args,i);
        if id==15 && i==2 && other==4 {}else {sg_require(other,ty);}i=i+1;
    }if id==10 {return 4;}return ty;
}
fn sg_prefix() {
    let n=0;
    if s_token==257 || s_token==258 || s_token==276 {
        let ty=1;if s_token==258 {ty=4;}if s_token==276 {ty=3;}
        if ty==1 && s_value>2147483647 {s_fail("shader i32 literal out of range");}
        if ty==3 && s_value>4294967295 {s_fail("shader u32 literal out of range");}
        if ty==4 {sg_float_literal(ir_source+s_start,s_size);}
        n=sg_node(1,ty,ir_source+s_start,s_size,s_value);s_next();
    }else if s_is("true") || s_is("false") {n=sg_node(1,2,ir_source+s_start,s_size,0);s_next();}
    else if s_token==45 || s_token==33 || s_token==126 {
        let op=s_token;s_next();
        if op==45 && s_token==257 && s_value==2147483648 {n=sg_node(12,1,0,0,0);s_next();}
        else {let value=sg_expression(11);let ty=load64(value+8);
            if op==33 {sg_require(ty,2);}else if !sg_numeric(ty) || (op==45 && sg_scalar(ty)==3) || (op==126 && sg_scalar(ty)==4) {s_fail("invalid shader unary operand");}
            n=sg_node(4,ty,op,value,0);
        }
    }else if s_token==40 {s_next();n=sg_expression(1);s_expect(41);}
    else if s_token==256 {
        let name=ir_source+s_start;let size=s_size;let ctor=sg_type_id();s_next();
        if s_token==40 {
            s_next();let args=alloc(16*8);let count=0;
            if s_token!=41 {let more=1;while more {if count==16 {s_fail("too many shader arguments");}store64(args+count*8,sg_expression(1));count=count+1;if s_token==44 {s_next();}else {more=0;}}}s_expect(41);
            if ctor {
                if !count || ctor==15 {s_fail("invalid shader constructor");}let width=sg_width(ctor);let scalar=sg_scalar(ctor);
                if sg_is_struct(ctor) {let st=sg_struct(ctor);if count!=load64(st+24) {s_fail("shader struct constructor requires every field in order");}
                    let i=0;while i<count {sg_require(sg_arg_type(args,i),load64(load64(st+16)+i*32+16));i=i+1;}
                }else if ctor==14 {if count!=4 {s_fail("mat4f requires four vec4f columns");}let i=0;while i<4 {sg_require(sg_arg_type(args,i),7);i=i+1;}}
                else if width==1 {
                    if count!=1 || sg_width(sg_arg_type(args,0))!=1 {s_fail("scalar constructor requires one scalar");}
                    if (ctor==2 || sg_arg_type(args,0)==2) && ctor!=sg_arg_type(args,0) {s_fail("shader bool and numeric conversions require an explicit if");}
                }
                else {let total=0;let i=0;while i<count {let ty=sg_arg_type(args,i);if sg_scalar(ty)!=scalar {s_fail("shader vector constructor type mismatch");}total=total+sg_width(ty);i=i+1;}if !(count==1 && total==1) && total!=width {s_fail("shader vector constructor component count");}}
                n=sg_node(6,ctor,args,count,0);
            }else {
                let builtin=sg_builtin(name,size);if builtin {n=sg_node(7,sg_call_type(builtin,args,count),builtin,args,count);}
                else {let f=sg_find(sg_functions,sg_function_count,64,name,size);if f<0 {s_fail("unknown shader function; host calls are unavailable");}
                    let function=sg_functions+f*64;let params=load64(function+24);if count!=load64(function+32) {s_fail("wrong shader function argument count");}
                    let i=0;while i<count {sg_require(sg_arg_type(args,i),load64(params+i*24+16));i=i+1;}
                    store8(sg_edges+sg_current*128+f,1);n=sg_node(8,load64(function+16),f,args,count);
                }
            }
        }else {if ctor {s_fail("expected shader constructor");}n=sg_lookup(name,size);}
    }else {s_fail("expected shader expression");}
    while s_token==46 || s_token==91 {
        if s_token==91 {
            if load64(n)!=3 {s_fail("indexing requires a storage buffer");}
            let kind=load64(sg_decls+load64(n+16)*64+24);if kind!=4 && kind!=5 {s_fail("indexing requires a storage buffer");}
            s_next();let index=sg_expression(1);let ty=load64(index+8);if ty!=1 && ty!=3 {s_fail("buffer index must be i32 or u32");}s_expect(93);n=sg_node(10,load64(n+8)-32,n,index,kind==4);
        }else {
            s_next();if s_token!=256 {s_fail("expected shader vector component");}
            if sg_is_struct(load64(n+8)) {let st=sg_struct(load64(n+8));let f=sg_find(load64(st+16),load64(st+24),32,ir_source+s_start,s_size);
                if f<0 {s_fail("unknown shader struct field");}n=sg_node(11,load64(load64(st+16)+f*32+16),n,f,0);s_next();
            }else {let width=sg_width(load64(n+8));if width<2 || s_size<1 || s_size>4 {s_fail("invalid shader swizzle");}
            let bits=0;let i=0;let family=-1;while i<s_size {let c=load8(ir_source+s_start+i);let component=-1;let group=0;
                if c==120 || c==114 {component=0;}if c==121 || c==103 {component=1;}if c==122 || c==98 {component=2;}if c==119 || c==97 {component=3;}
                if c==114 || c==103 || c==98 || c==97 {group=1;}if component<0 || component>=width || (family>=0 && family!=group) {s_fail("invalid shader swizzle");}family=group;bits=bits|(component<<(i*2));i=i+1;
            }n=sg_node(9,sg_vector(sg_scalar(load64(n+8)),s_size),n,bits,s_size);s_next();
            }
        }
    }return n;
}
fn sg_expression(minimum) {
    sg_nesting=sg_nesting+1;if sg_nesting>128 {s_fail("shader expression nesting exceeds 128");}
    let left=sg_prefix();while s_priority(s_token)>=minimum {
        let op=s_token;let priority=s_priority(op);s_next();let right=sg_expression(priority+1);let ty=load64(left+8);let other=load64(right+8);let result=ty;
        if op==263 || op==264 {sg_require(ty,2);sg_require(other,2);}
        else if op==259 || op==260 || op==60 || op==62 || op==261 || op==262 {
            sg_require(other,ty);if sg_width(ty)!=1 {s_fail("shader comparison requires scalar operands");}if ty==2 && op!=259 && op!=260 {s_fail("ordered comparison requires numeric operands");}result=2;
        }else if op==42 && ty==14 && (other==7 || other==14) {result=other;}
        else {
            if !sg_numeric(ty) || !sg_numeric(other) {s_fail("shader arithmetic requires numeric values");}
            if op==42 && sg_scalar(ty)==sg_scalar(other) && (sg_width(ty)==1 || sg_width(other)==1) {if sg_width(other)>1 {result=other;}}
            else {sg_require(other,ty);}
            if (op==37 || op==38 || op==124 || op==94 || op==265 || op==266) && sg_scalar(ty)==4 {s_fail("shader bit operations require integers");}
            if op==265 || op==266 {s_fail("shader shifts are not supported yet");}
        }left=sg_node(5,result,op,left,right);
    }
    if minimum==1 && s_token==63 {s_fail("shader conditional expressions require if/else for now");}
    sg_nesting=sg_nesting-1;return left;
}
fn sg_assignable(n) {
    let kind=load64(n);if (kind==2 || kind==3) && !load64(n+24) {if kind==3 && load64(sg_decls+load64(n+16)*64+24)==5 {s_fail("buffer assignment requires an index");}return 1;}
    if kind==10 && !load64(n+32) {return 1;}if kind==11 {return sg_assignable(load64(n+16));}s_fail("shader assignment target is read-only or not assignable");return 0;
}
fn sg_block() {
    sg_depth=sg_depth+1;if sg_depth>128 {s_fail("shader block nesting exceeds 128");}let before=sg_local_count;s_expect(123);let first=0;let last=0;let returned=0;
    while s_token!=125 {if !s_token {s_fail("unterminated shader block");}let n=sg_statement();if returned {s_fail("unreachable shader statement");}
        if !first {first=n;}else {store64(last+56,n);}last=n;returned=load64(n+48);
    }s_expect(125);sg_local_count=before;sg_depth=sg_depth-1;let block=sg_node(30,15,first,0,0);store64(block+48,returned);return block;
}
fn sg_statement() {
    sg_nesting=sg_nesting+1;if sg_nesting>128 {s_fail("shader statement nesting exceeds 128");}
    let n=0;
    if s_is("let") {
        s_next();sg_name();let name=ir_source+s_start;let size=s_size;s_next();let ty=0;if s_token==58 {s_next();ty=sg_type();}s_expect(61);let value=sg_expression(1);if ty {sg_require(load64(value+8),ty);}else {ty=load64(value+8);}
        if ty==15 || ty==16 || ty==17 || sg_is_ref(ty) {s_fail("invalid shader local type");}let id=sg_local(name,size,ty,0);n=sg_node(20,ty,id,value,0);s_semicolon();
    }else if s_is("return") {
        s_next();let ty=load64(sg_functions+sg_current*64+16);let value=0;if ty!=15 {value=sg_expression(1);sg_require(load64(value+8),ty);}n=sg_node(21,ty,value,0,0);store64(n+48,1);s_semicolon();
    }else if s_is("if") {
        s_next();let condition=sg_expression(1);sg_require(load64(condition+8),2);let yes=sg_block();let no=0;
        if s_is("else") {s_next();if s_is("if") {no=sg_statement();}else {no=sg_block();}}
        n=sg_node(22,15,condition,yes,no);if no {store64(n+48,load64(yes+48) && load64(no+48));}
    }else if s_is("for") {
        s_next();sg_name();let name=ir_source+s_start;let size=s_size;s_next();if !s_is("in") {s_fail("expected in");}s_next();let low=s_literal();s_expect(271);let high=s_literal();
        if low< -1000000 || high>1000000 || high<low || high-low>1000000 {s_fail("shader loop bounds exceed one million");}
        let before=sg_local_count;sg_depth=sg_depth+1;let id=sg_local(name,size,1,1);let body=sg_block();sg_depth=sg_depth-1;sg_local_count=before;n=sg_node(23,15,id,low,high);store64(n+40,body);
    }else if s_is("while") || s_is("repeat") {s_fail("shader loops require literal-bounded for");}
    else if s_token==123 {n=sg_block();}
    else {
        let value=sg_expression(1);let op=s_token;
        if op==61 || (op>=272 && op<=275) {
            sg_assignable(value);s_next();let right=sg_expression(1);sg_require(load64(value+8),load64(right+8));if op!=61 && !sg_numeric(load64(value+8)) {s_fail("shader compound assignment requires numeric values");}n=sg_node(24,15,value,right,op);
        }else {if load64(value)!=8 || load64(value+8)!=15 {s_fail("shader statement requires an assignment or void function call");}n=sg_node(25,15,value,0,0);}s_semicolon();
    }sg_nesting=sg_nesting-1;return n;
}
fn sg_builtin_id() {
    if s_is("position") {return 1;}if s_is("vertex_index") {return 2;}if s_is("instance_index") {return 3;}
    if s_is("front_facing") {return 4;}if s_is("frag_depth") {return 5;}
    if s_is("global_id") {return 6;}if s_is("local_id") {return 7;}if s_is("workgroup_id") {return 8;}return 0;
}
fn sg_builtin_valid(kind,ty,builtin) {
    if builtin==1 {return ty==7 && ((sg_stage==1 && kind==2) || (sg_stage==2 && kind==1));}
    if builtin==2 || builtin==3 {return sg_stage==1 && kind==1 && ty==3;}
    if builtin==4 {return sg_stage==2 && kind==1 && ty==2;}
    if builtin==5 {return sg_stage==2 && kind==2 && ty==4;}
    if builtin>=6 {return sg_stage==3 && kind==1 && ty==12;}return 0;
}
fn sg_declaration(kind) {
    if sg_decl_count==128 {s_fail("too many shader interface declarations");}s_next();sg_name();let name=ir_source+s_start;let size=s_size;
    if sg_find(sg_decls,sg_decl_count,64,name,size)>=0 {s_fail("duplicate shader interface name");}s_next();let ty=16;if kind==7 {ty=17;}
    if kind!=6 && kind!=7 {s_expect(58);ty=sg_type();if ty==15 {s_fail("void shader interface type");}}
    let builtin=0;let slot=0;
    if kind==1 || kind==2 {
        if s_is("builtin") {s_next();s_expect(40);builtin=sg_builtin_id();if !builtin || !sg_builtin_valid(kind,ty,builtin) {s_fail("invalid shader builtin for stage, direction or type");}s_next();s_expect(41);}
        else {if !s_is("location") {s_fail("shader input/output requires location or builtin");}s_next();s_expect(40);slot=s_literal();s_expect(41);if slot<0 || slot>15 || !sg_numeric(ty) || sg_stage==3 {s_fail("invalid shader location or interface type");}if kind==2 && sg_stage==2 && ty!=7 {s_fail("fragment color output must be vec4f");}}
    }else {
        if !s_is("binding") {s_fail("shader resource requires binding");}s_next();s_expect(40);slot=s_literal();s_expect(41);if slot<0 || slot>31 || ((kind==6 || kind==7) && slot==31) {s_fail("shader binding out of range");}
        if kind==4 {if s_is("read_write") {kind=5;}else if !s_is("read") {s_fail("buffer requires read or read_write");}s_next();}
        if kind!=6 && kind!=7 && !sg_shareable(ty) {s_fail("bool is not a host-shareable resource type");}
        if (kind==4 || kind==5) && (sg_stage!=3 || (ty!=1 && ty!=3 && ty!=4 && !sg_is_struct(ty))) {s_fail("storage buffers currently require compute stage and scalar or struct elements");}
    }
    let i=0;while i<sg_decl_count {let p=sg_decls+i*64;let other=load64(p+24);
        if kind<=2 && other==kind && ((builtin && builtin==load64(p+40)) || (!builtin && !load64(p+40) && slot==load64(p+32))) {s_fail("duplicate shader location or builtin");}
        if kind>=3 && other>=3 {let end=slot;if kind==6 || kind==7 {end=end+1;}let other_end=load64(p+32);if other==6 || other==7 {other_end=other_end+1;}if slot<=other_end && load64(p+32)<=end {s_fail("overlapping shader resource bindings");}}i=i+1;
    }
    let p=sg_decls+sg_decl_count*64;store64(p,name);store64(p+8,size);store64(p+16,ty);store64(p+24,kind);store64(p+32,slot);store64(p+40,builtin);sg_decl_count=sg_decl_count+1;s_semicolon();return 0;
}
fn sg_struct_declaration() {
    if sg_struct_count==32 {s_fail("too many shader structs");}s_next();sg_name();let name=ir_source+s_start;let size=s_size;
    if sg_builtin(name,size) || sg_find(sg_decls,sg_decl_count,64,name,size)>=0 {s_fail("duplicate or reserved shader struct name");}
    s_next();s_expect(123);let fields=alloc(32*32);let count=0;let offset=0;let shareable=1;
    while s_token!=125 {
        if count==32 {s_fail("too many shader struct fields");}s_name();let field=ir_source+s_start;let length=s_size;
        if sg_find(fields,count,32,field,length)>=0 {s_fail("duplicate shader struct field");}s_next();s_expect(58);let ty=sg_type();if ty==15 {s_fail("void shader struct field");}
        if !sg_shareable(ty) {shareable=0;}else if sg_is_struct(ty) {offset=sg_round(offset,16);}else {offset=sg_round(offset,sg_align(ty));}
        let p=fields+count*32;store64(p,field);store64(p+8,length);store64(p+16,ty);store64(p+24,offset);offset=offset+sg_size(ty);count=count+1;if s_token==44 {s_next();}
    }s_expect(125);if !count {s_fail("shader struct requires fields");}
    let p=sg_structs+sg_struct_count*64;store64(p,name);store64(p+8,size);store64(p+16,fields);store64(p+24,count);store64(p+32,shareable*sg_round(offset,16));
    sg_struct_count=sg_struct_count+1;s_semicolon();return 0;
}
fn sg_signatures() {
    s_next();if !s_is("plugin") {s_fail("expected plugin header");}s_next();s_name();s_next();while s_token==46 {s_next();s_name();s_next();}
    if !s_is("v1") {s_fail("expected plugin version v1");}s_next();s_expect(123);s_expect(125);
    if !s_is("shader") {s_fail("shader target requires a shader declaration");}s_next();
    if s_is("vertex") {sg_stage=1;}else if s_is("fragment") {sg_stage=2;}else if s_is("compute") {sg_stage=3;}else {s_fail("expected vertex, fragment or compute shader stage");}s_next();
    if shader_target==3 && sg_stage==3 {s_fail("WebGL2 does not support compute shaders");}
    if sg_stage==3 {s_expect(40);let i=0;let product=1;while i<3 {let value=s_literal();if value<1 || value>256 {s_fail("shader workgroup dimension must be 1..256");}store64(sg_work+i*8,value);product=product*value;i=i+1;if i<3 {s_expect(44);}}s_expect(41);if product>256 {s_fail("shader workgroup exceeds 256 invocations");}}
    s_expect(123);let functions_started=0;
    while s_token!=125 {
        let kind=0;if s_is("input") {kind=1;}if s_is("output") {kind=2;}if s_is("uniform") {kind=3;}if s_is("buffer") {kind=4;}if s_is("texture") {kind=6;}if s_is("depth_texture") {kind=7;}
        if s_is("struct") {if functions_started {s_fail("shader interface declarations must precede functions");}sg_struct_declaration();}
        else if kind {if functions_started {s_fail("shader interface declarations must precede functions");}sg_declaration(kind);}
        else {
            functions_started=1;if !s_is("fn") {s_fail("expected shader function or interface declaration");}s_next();sg_name();let name=ir_source+s_start;let size=s_size;
            if sg_function_count==128 {s_fail("too many shader functions");}if sg_find(sg_functions,sg_function_count,64,name,size)>=0 || sg_builtin(name,size) {s_fail("duplicate or reserved shader function name");}
            let f=sg_functions+sg_function_count*64;store64(f,name);store64(f+8,size);s_next();s_expect(40);let params=alloc(16*24);let count=0;
            if s_token!=41 {let more=1;while more {if count==16 {s_fail("too many shader parameters");}sg_name();let arg=ir_source+s_start;let length=s_size;
                if sg_find(params,count,24,arg,length)>=0 {s_fail("duplicate shader parameter");}store64(params+count*24,arg);store64(params+count*24+8,length);s_next();s_expect(58);let ty=sg_type();if ty==15 {s_fail("void shader parameter");}store64(params+count*24+16,ty);count=count+1;if s_token==44 {s_next();}else {more=0;}
            }}s_expect(41);s_expect(270);store64(f+16,sg_type());store64(f+24,params);store64(f+32,count);store64(f+40,s_start);
            if s_equal(name,size,"main",4) {sg_entry=sg_function_count;if count || load64(f+16)!=15 {s_fail("shader main must take no parameters and return void");}}
            s_expect(123);let braces=1;while braces {if !s_token {s_fail("unterminated shader function");}if s_token==123 {braces=braces+1;if braces>128 {s_fail("shader block nesting exceeds 128");}}else if s_token==125 {braces=braces-1;}s_next();}sg_function_count=sg_function_count+1;
        }
    }s_expect(125);if s_token {s_fail("only one shader module is supported per file");}if sg_entry<0 {s_fail("missing shader main function");}
    if sg_stage==1 {let found=0;let i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 && load64(p+40)==1 {found=1;}i=i+1;}if !found {s_fail("vertex shader requires builtin(position) output");}}
    return 0;
}
fn sg_no_recursion() {
    let degree=alloc(128*8);let i=0;while i<sg_function_count {let j=0;while j<sg_function_count {if load8(sg_edges+i*128+j) {store64(degree+j*8,load64(degree+j*8)+1);}j=j+1;}i=i+1;}
    let removed=0;let progress=1;while progress {progress=0;i=0;while i<sg_function_count {if !load64(degree+i*8) {store64(degree+i*8,-1);removed=removed+1;progress=1;let j=0;while j<sg_function_count {if load8(sg_edges+i*128+j) {store64(degree+j*8,load64(degree+j*8)-1);}j=j+1;}}i=i+1;}}
    if removed!=sg_function_count {s_fail("shader recursion is not allowed");}return 0;
}

fn sg_text(text) {let size=ir_length(text);sg_bytes(text,size);return 0;}
fn sg_bytes(text,size) {if size>4194304-sg_output_size {s_fail("shader output exceeds 4 MiB");}let i=0;while i<size {store8(sg_output+sg_output_size+i,load8(text+i));i=i+1;}sg_output_size=sg_output_size+size;return 0;}
fn sg_number(value) {if value<0 {sg_text("-");value=-value;}let buffer=alloc(32);let i=31;store8(buffer+i,0);while value || i==31 {i=i-1;store8(buffer+i,48+value%10);value=value/10;}sg_text(buffer+i);return 0;}
fn sg_id(prefix,id) {
    // Resource names also have to link across stages: declaration4 can be a
    // vertex matrix and a fragment texture. Bindings are the shared identity,
    // independent of each stage's declaration order.
    if s_equal(prefix,ir_length(prefix),"sw_r",4) && load64(sg_decls+id*64+24)>=3 {
        id=4000+load64(sg_decls+id*64+32);
    }
    else if s_equal(prefix,ir_length(prefix),"sw_block",8) {
        id=load64(sg_decls+id*64+32);
    }
    // ES300 links varyings by name rather than explicit location. Keep names
    // stable even when vertex/fragment declaration orders differ.
    else if shader_target==3 && s_equal(prefix,ir_length(prefix),"sw_r",4) {
        let p=sg_decls+id*64;let kind=load64(p+24);
        if kind<=2 && !load64(p+40) {
            id=load64(p+32)+2000;
            if kind==1 && sg_stage==1 {id=id-1000;}
            if kind==2 && sg_stage==2 {id=id+1000;}
        }
    }
    sg_text(prefix);sg_number(id);return 0;
}
fn sg_emit_type(ty) {
    if sg_is_struct(ty) {return sg_id("sw_t",ty-100);}
    if shader_target==2 {if ty==14 {sg_text("mat4x4f");}else {sg_text(sg_type_word(ty));}return 0;}
    if ty==1 {sg_text("int");}else if ty==2 {sg_text("bool");}else if ty==3 {sg_text("uint");}else if ty==4 {sg_text("float");}
    else if ty>=5 && ty<=13 {let prefix="vec";if ty>=8 && ty<=10 {prefix="ivec";}if ty>=11 {prefix="uvec";}sg_id(prefix,sg_width(ty));}
    else if ty==14 {sg_text("mat4");}else {sg_text("void");}return 0;
}
fn sg_variable(prefix,id,ty) {if shader_target!=2 {sg_emit_type(ty);sg_text(" ");sg_id(prefix,id);}else {sg_id(prefix,id);sg_text(": ");sg_emit_type(ty);}return 0;}
fn sg_builtin_word(id) {
    if id==1 {return "sin";}if id==2 {return "cos";}if id==3 {return "abs";}if id==4 {return "sqrt";}if id==5 {return "floor";}if id==6 {return "ceil";}if id==7 {return "fract";}if id==8 {return "normalize";}if id==9 {return "length";}if id==10 {return "dot";}if id==11 {return "cross";}if id==12 {return "min";}if id==13 {return "max";}if id==14 {return "clamp";}if id==15 {return "mix";}return "pow";
}
fn sg_emit_args(args,count) {let i=0;while i<count {if i {sg_text(", ");}sg_emit_expr(load64(args+i*8));i=i+1;}return 0;}
fn sg_operator(op) {
    if op==259 {return sg_text("==");}if op==260 {return sg_text("!=");}if op==261 {return sg_text("<=");}if op==262 {return sg_text(">=");}if op==263 {return sg_text("&&");}if op==264 {return sg_text("||");}
    let c=alloc(2);store8(c,op);return sg_text(c);
}
fn sg_emit_expr(n) {
    let kind=load64(n);let ty=load64(n+8);let a=load64(n+16);let b=load64(n+24);let c=load64(n+32);
    if kind==1 {
        // Decimal source integers must never turn into GLSL octal literals;
        // WGSL also forbids leading zeroes. Emit their parsed numeric value.
        if ty==1 || ty==3 {sg_number(c);if ty==3 {sg_text("u");}else if shader_target==2 {sg_text("i");}}
        else {sg_bytes(a,b);if shader_target==2 && ty==4 {sg_text("f");}}
    }
    else if kind==2 {sg_id("sw_v",a);}
    else if kind==3 {sg_id("sw_r",a);}
    else if kind==4 {sg_text("(");sg_operator(a);sg_emit_expr(b);sg_text(")");}
    else if kind==5 {sg_text("(");sg_emit_expr(b);sg_text(" ");sg_operator(a);sg_text(" ");sg_emit_expr(c);sg_text(")");}
    else if kind==6 {sg_emit_type(ty);sg_text("(");sg_emit_args(a,b);sg_text(")");}
    else if kind==7 {
        if a==19 {
            if shader_target==2 {sg_text("arrayLength(&");sg_emit_expr(load64(b));sg_text(")");}else {sg_text("uint(");sg_emit_expr(load64(b));sg_text(".length())");}
        }else if a==17 || a==18 {
            let tex=load64(b);let id=load64(tex+16);if shader_target!=2 {if a==17 {sg_text("texture(");}else {sg_text("textureLod(");}}
            else {if a==17 {sg_text("textureSample(");}else {sg_text("textureSampleLevel(");}}sg_id("sw_r",id);
            if shader_target==2 {sg_text(", ");sg_id("sw_s",id);}sg_text(", ");sg_emit_expr(load64(b+8));if a==18 {sg_text(", ");sg_emit_expr(load64(b+16));}sg_text(")");
        }else if a==20 {
            let id=load64(load64(b)+16);
            if shader_target==2 {sg_text("textureSampleCompare(");sg_id("sw_r",id);sg_text(", ");sg_id("sw_s",id);sg_text(", ");sg_emit_expr(load64(b+8));sg_text(", ");sg_emit_expr(load64(b+16));sg_text(")");}
            else {sg_text("texture(");sg_id("sw_r",id);sg_text(", vec3(");sg_emit_expr(load64(b+8));sg_text(", ");sg_emit_expr(load64(b+16));sg_text("))");}
        }else {sg_text(sg_builtin_word(a));sg_text("(");sg_emit_args(b,c);sg_text(")");}
    }else if kind==8 {sg_id("sw_f",a);sg_text("(");sg_emit_args(b,c);sg_text(")");}
    else if kind==9 {sg_text("(");sg_emit_expr(a);sg_text(").");let i=0;while i<c {sg_bytes("xyzw"+((b>>(i*2))&3),1);i=i+1;}}
    else if kind==10 {sg_emit_expr(a);sg_text("[");sg_emit_expr(b);sg_text("]");}
    else if kind==11 {sg_emit_expr(a);sg_id(".sw_m",b);}
    else if kind==12 {if shader_target==2 {sg_text("(-2147483647i - 1i)");}else {sg_text("(-2147483647 - 1)");}}
    return 0;
}
fn sg_emit_statement(n) {
    let kind=load64(n);let ty=load64(n+8);let a=load64(n+16);let b=load64(n+24);let c=load64(n+32);
    if kind==30 {sg_text("{\n");let next=a;while next {sg_emit_statement(next);next=load64(next+56);}sg_text("}\n");}
    else if kind==20 {if shader_target==2 {sg_text("var ");}sg_variable("sw_v",a,ty);sg_text(" = ");sg_emit_expr(b);sg_text(";\n");}
    else if kind==21 {sg_text("return");if a {sg_text(" ");sg_emit_expr(a);}sg_text(";\n");}
    else if kind==22 {sg_text("if (");sg_emit_expr(a);sg_text(") ");sg_emit_statement(b);if c {sg_text("else ");sg_emit_statement(c);}}
    else if kind==23 {
        sg_text("for (");if shader_target==2 {sg_text("var ");}sg_variable("sw_v",a,1);sg_text(" = ");sg_number(b);sg_text("; ");sg_id("sw_v",a);sg_text(" < ");sg_number(c);sg_text("; ");sg_id("sw_v",a);sg_text(" = ");sg_id("sw_v",a);sg_text(" + 1) ");sg_emit_statement(load64(n+40));
    }else if kind==24 {sg_emit_expr(a);sg_text(" ");if c!=61 {let op=43;if c==273 {op=45;}if c==274 {op=42;}if c==275 {op=47;}sg_operator(op);}sg_text("= ");sg_emit_expr(b);sg_text(";\n");}
    else if kind==25 {sg_emit_expr(a);sg_text(";\n");}return 0;
}
fn sg_attribute(p) {
    let builtin=load64(p+40);if !builtin {sg_text("@location(");sg_number(load64(p+32));sg_text(") ");if sg_scalar(load64(p+16))!=4 && ((load64(p+24)==2 && sg_stage==1) || (load64(p+24)==1 && sg_stage==2)) {sg_text("@interpolate(flat) ");}return 0;}
    sg_text("@builtin(");if builtin==1 {sg_text("position");}if builtin==2 {sg_text("vertex_index");}if builtin==3 {sg_text("instance_index");}if builtin==4 {sg_text("front_facing");}if builtin==5 {sg_text("frag_depth");}if builtin==6 {sg_text("global_invocation_id");}if builtin==7 {sg_text("local_invocation_id");}if builtin==8 {sg_text("workgroup_id");}sg_text(") ");return 0;
}
fn sg_gl_builtin(id) {
    if id==1 {if sg_stage==1 {return sg_text("gl_Position");}return sg_text("gl_FragCoord");}
    if id==2 {return sg_text("uint(gl_VertexID)");}if id==3 {return sg_text("uint(gl_InstanceID)");}
    if id==4 {return sg_text("gl_FrontFacing");}if id==5 {return sg_text("gl_FragDepth");}
    if id==6 {return sg_text("gl_GlobalInvocationID");}if id==7 {return sg_text("gl_LocalInvocationID");}return sg_text("gl_WorkGroupID");
}
// Structs come first so resources, prototypes and locals can name them. The
// layout comment is the host ABI: byte offsets and the padded struct size.
fn sg_emit_structs() {
    let k=0;while k<sg_struct_count {let st=sg_structs+k*64;let fields=load64(st+16);let count=load64(st+24);let size=load64(st+32);
        if size {sg_text("// layout ");sg_bytes(load64(st),load64(st+8));sg_text(" size ");sg_number(size);sg_text(":");let j=0;
            while j<count {let f=fields+j*32;sg_text(" ");sg_bytes(load64(f),load64(f+8));sg_text("@");sg_number(load64(f+24));j=j+1;}sg_text("\n");
        }sg_text("struct ");sg_id("sw_t",k);sg_text(" {\n");let j=0;
        while j<count {let f=fields+j*32;let ty=load64(f+16);
            if shader_target==2 {
                if size {let next=size;if j+1<count {next=load64(f+56);}if next-load64(f+24)!=sg_size(ty) {sg_text("@size(");sg_number(next-load64(f+24));sg_text(") ");}}
                sg_variable("sw_m",j,ty);sg_text(",\n");
            }else {sg_variable("sw_m",j,ty);sg_text(";\n");}j=j+1;
        }if shader_target==2 {sg_text("}\n");}else {sg_text("};\n");}k=k+1;
    }return 0;
}
fn sg_emit_interface() {
    if shader_target!=2 {if shader_target==3 {sg_text("#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;\nprecision highp sampler2DShadow;\n");}else {sg_text("#version 450 core\n");}if sg_stage==3 {sg_text("layout(local_size_x=");sg_number(load64(sg_work));sg_text(",local_size_y=");sg_number(load64(sg_work+8));sg_text(",local_size_z=");sg_number(load64(sg_work+16));sg_text(") in;\n");}}
    sg_emit_structs();
    let i=0;while i<sg_decl_count {let p=sg_decls+i*64;let ty=load64(p+16);let kind=load64(p+24);let slot=load64(p+32);let builtin=load64(p+40);
        if kind<=2 {
            if shader_target==2 {sg_text("var<private> ");sg_variable("sw_r",i,ty);sg_text(";\n");}
            else if builtin {sg_variable("sw_r",i,ty);sg_text(";\n");}
            else {if shader_target!=3 || (kind==1 && sg_stage==1) || (kind==2 && sg_stage==2) {sg_text("layout(location=");sg_number(slot);sg_text(") ");}if sg_scalar(ty)!=4 && ((kind==2 && sg_stage==1) || (kind==1 && sg_stage==2)) {sg_text("flat ");}if kind==1 {sg_text("in ");}else {sg_text("out ");}sg_variable("sw_r",i,ty);sg_text(";\n");}
        }else if shader_target!=2 {
            if shader_target==3 {if kind==3 {sg_text("layout(std140) ");}}else {sg_text("layout(");if kind==3 {sg_text("std140,");}else if sg_is_struct(ty) {sg_text("std140,");}else if kind==4 || kind==5 {sg_text("std430,");}sg_text("binding=");sg_number(slot);sg_text(") ");}
            if kind==6 {sg_text("uniform sampler2D ");sg_id("sw_r",i);sg_text(";\n");}
            else if kind==7 {sg_text("uniform sampler2DShadow ");sg_id("sw_r",i);sg_text(";\n");}
            else {if kind==3 {sg_text("uniform ");}else {if kind==4 {sg_text("readonly ");}sg_text("buffer ");}sg_id("sw_block",i);sg_text(" { ");sg_variable("sw_r",i,ty);if kind==4 || kind==5 {sg_text("[]");}sg_text("; };\n");}
        }else {
            sg_text("@group(0) @binding(");sg_number(slot);sg_text(") ");
            if kind==6 {sg_text("var ");sg_id("sw_r",i);sg_text(": texture_2d<f32>;\n@group(0) @binding(");sg_number(slot+1);sg_text(") var ");sg_id("sw_s",i);sg_text(": sampler;\n");}
            else if kind==7 {sg_text("var ");sg_id("sw_r",i);sg_text(": texture_depth_2d;\n@group(0) @binding(");sg_number(slot+1);sg_text(") var ");sg_id("sw_s",i);sg_text(": sampler_comparison;\n");}
            else {if kind==3 {sg_text("var<uniform> ");}else if kind==4 {sg_text("var<storage, read> ");}else {sg_text("var<storage, read_write> ");}sg_id("sw_r",i);sg_text(": ");if kind==4 || kind==5 {sg_text("array<");}sg_emit_type(ty);if kind==4 || kind==5 {sg_text(">");}sg_text(";\n");}
        }i=i+1;
    }return 0;
}
fn sg_emit_function(f,id,prototype) {
    if shader_target==2 {sg_text("fn ");}else {sg_emit_type(load64(f+16));sg_text(" ");}sg_id("sw_f",id);sg_text("(");let params=load64(f+24);let count=load64(f+32);let i=0;
    while i<count {if i {sg_text(", ");}sg_variable("sw_p",i,load64(params+i*24+16));i=i+1;}sg_text(")");if shader_target==2 && load64(f+16)!=15 {sg_text(" -> ");sg_emit_type(load64(f+16));}
    if prototype {sg_text(";\n");return 0;}sg_text(" {\n");i=0;while i<count {if shader_target==2 {sg_text("var ");}sg_variable("sw_v",i,load64(params+i*24+16));sg_text(" = ");sg_id("sw_p",i);sg_text(";\n");i=i+1;}
    let block=load64(f+48);let n=load64(block+16);while n {sg_emit_statement(n);n=load64(n+56);}sg_text("}\n");return 0;
}
fn sg_emit_entry() {
    let outputs=0;let i=0;while i<sg_decl_count {if load64(sg_decls+i*64+24)==2 {outputs=outputs+1;}i=i+1;}
    if shader_target==2 {
        if outputs {sg_text("struct sw_Output {\n");i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 {sg_attribute(p);sg_variable("sw_o",i,load64(p+16));sg_text(",\n");}i=i+1;}sg_text("}\n");}
        if sg_stage==1 {sg_text("@vertex ");}if sg_stage==2 {sg_text("@fragment ");}if sg_stage==3 {sg_text("@compute @workgroup_size(");sg_number(load64(sg_work));sg_text(", ");sg_number(load64(sg_work+8));sg_text(", ");sg_number(load64(sg_work+16));sg_text(") ");}
        sg_text("fn main(");let first=1;i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==1 {if !first {sg_text(", ");}first=0;sg_attribute(p);sg_variable("sw_i",i,load64(p+16));}i=i+1;}sg_text(")");if outputs {sg_text(" -> sw_Output");}sg_text(" {\n");
    }else {sg_text("void main() {\n");}
    // WGSL private variables start at zero. Explicitly give GLSL outputs the
    // same value before user code, including conditionally assigned outputs.
    if shader_target!=2 {i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 {sg_id("sw_r",i);sg_text(" = ");sg_emit_type(load64(p+16));sg_text("(0);\n");}i=i+1;}}
    i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==1 {if shader_target==2 || load64(p+40) {sg_id("sw_r",i);sg_text(" = ");if shader_target==2 {sg_id("sw_i",i);}else {sg_gl_builtin(load64(p+40));}sg_text(";\n");}}i=i+1;}
    sg_id("sw_f",sg_entry);sg_text("();\n");
    if shader_target==2 && outputs {sg_text("return sw_Output(");let first=1;i=0;while i<sg_decl_count {if load64(sg_decls+i*64+24)==2 {if !first {sg_text(", ");}first=0;sg_id("sw_r",i);}i=i+1;}sg_text(");\n");}
    else if shader_target!=2 {i=0;while i<sg_decl_count {let p=sg_decls+i*64;if load64(p+24)==2 && load64(p+40) {sg_gl_builtin(load64(p+40));sg_text(" = ");sg_id("sw_r",i);sg_text(";\n");}i=i+1;}}
    sg_text("}\n");return 0;
}
fn seta_shader_frontend(text,size,path) {
    ir_source=text;ir_source_size=size;ir_path=path;s_shader_mode=1;s_pos=0;sg_stage=0;sg_decl_count=0;sg_struct_count=0;sg_function_count=0;sg_node_count=0;sg_entry=-1;sg_nesting=0;
    sg_work=alloc(24);sg_decls=alloc(128*64);sg_functions=alloc(128*64);sg_locals=alloc(1024*48);sg_nodes=alloc(65536*64);sg_edges=alloc(128*128);sg_structs=alloc(32*64);sg_output=alloc(4194304);sg_output_size=0;
    if sg_work<0 || sg_decls<0 || sg_functions<0 || sg_locals<0 || sg_nodes<0 || sg_edges<0 || sg_structs<0 || sg_output<0 {s_fail("shader frontend allocation failed");}
    sg_signatures();sg_current=0;
    while sg_current<sg_function_count {let f=sg_functions+sg_current*64;sg_local_count=0;sg_local_id=0;sg_depth=1;let i=0;let params=load64(f+24);
        while i<load64(f+32) {let p=params+i*24;sg_local(load64(p),load64(p+8),load64(p+16),0);i=i+1;}
        s_pos=load64(f+40);s_next();sg_depth=0;let block=sg_block();store64(f+48,block);if load64(f+16)!=15 && !load64(block+48) {s_fail("shader function must return on every path");}sg_current=sg_current+1;
    }sg_no_recursion();sg_emit_interface();let i=0;
    i=0;if shader_target!=2 {while i<sg_function_count {sg_emit_function(sg_functions+i*64,i,1);i=i+1;}}
    i=0;while i<sg_function_count {sg_emit_function(sg_functions+i*64,i,0);i=i+1;}sg_emit_entry();s_shader_mode=0;return sg_output;
}
