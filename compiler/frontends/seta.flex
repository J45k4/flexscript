import "../extension-sdk.flex";
// Initial SetaScript frontend: pure i32/bool functions and literal-bounded loops.
// Integer words follow the existing SetaScript runtime's signed i64 IR.
global s_pos=0;
global s_token=0;
global s_start=0;
global s_size=0;
global s_value=0;
// Shader targets share tokens, but retain their own typed representation.
// Ordinary SetaScript integer/FIR semantics remain unchanged.
global s_shader_mode=0;
global s_functions=0;
global s_function_names=0;
global s_count=0;
global s_current=0;
global s_locals=0;
global s_local_count=0;
global s_slots=0;
global s_types=0;
global s_readonly=0;
global s_depth=0;
global s_nesting=0;
global s_state_fields=0;
global s_state_count=0;
// Imported files keep their own bytes. Each record holds text, size, path,
// declaration offset, import list and import count; ir_source/ir_path follow
// the file being parsed, so diagnostics name that file and line.
global s_files=0;
global s_file_count=0;
global s_order=0;
global s_order_count=0;
fn s_fail(message) {return ir_error(message,s_start);}
fn s_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122) || c==95;}
fn s_digit(c) {return c>=48 && c<=57;}
fn s_equal(a,n,b,k) {if n!=k {return 0;}let i=0;while i<n {if load8(a+i)!=load8(b+i) {return 0;}i=i+1;}return 1;}
fn s_is(word) {return s_equal(ir_source+s_start,s_size,word,ir_length(word));}
fn s_next() {
    let scan=1;while scan {
        while s_pos<ir_source_size && (load8(ir_source+s_pos)==32 || load8(ir_source+s_pos)==9 || load8(ir_source+s_pos)==10 || load8(ir_source+s_pos)==13) {s_pos=s_pos+1;}
        if s_pos+1<ir_source_size && load8(ir_source+s_pos)==47 && load8(ir_source+s_pos+1)==47 {
            while s_pos<ir_source_size && load8(ir_source+s_pos)!=10 {s_pos=s_pos+1;}
        }else {scan=0;}
    }
    s_start=s_pos;s_size=0;s_value=0;s_token=0;if s_pos==ir_source_size {return 0;}
    let c=load8(ir_source+s_pos);s_pos=s_pos+1;
    if s_letter(c) {s_token=256;while s_pos<ir_source_size && (s_letter(load8(ir_source+s_pos)) || s_digit(load8(ir_source+s_pos))) {s_pos=s_pos+1;}}
    else if s_digit(c) {
        s_token=257;s_value=c-48;let overflow=0;
        while s_pos<ir_source_size && s_digit(load8(ir_source+s_pos)) {
            let d=load8(ir_source+s_pos)-48;if s_value>(9223372036854775807-d)/10 {overflow=1;if !s_shader_mode {s_fail("integer literal out of range");}}
            if !overflow {s_value=s_value*10+d;}s_pos=s_pos+1;
        }
        if s_shader_mode && s_pos<ir_source_size && load8(ir_source+s_pos)==46 && s_pos+1<ir_source_size && load8(ir_source+s_pos+1)!=46 {
            s_token=258;s_pos=s_pos+1;
            if !s_digit(load8(ir_source+s_pos)) {s_fail("expected digits after shader decimal point");}
            while s_pos<ir_source_size && s_digit(load8(ir_source+s_pos)) {s_pos=s_pos+1;}
        }
        if s_shader_mode && s_pos<ir_source_size && (load8(ir_source+s_pos)==101 || load8(ir_source+s_pos)==69) {
            s_token=258;s_pos=s_pos+1;
            if s_pos<ir_source_size && (load8(ir_source+s_pos)==43 || load8(ir_source+s_pos)==45) {s_pos=s_pos+1;}
            if s_pos==ir_source_size || !s_digit(load8(ir_source+s_pos)) {s_fail("expected shader exponent digits");}
            let exponent=0;while s_pos<ir_source_size && s_digit(load8(ir_source+s_pos)) {exponent=exponent*10+load8(ir_source+s_pos)-48;if exponent>38 {s_fail("shader exponent exceeds f32 range");}s_pos=s_pos+1;}
        }
        if s_shader_mode && s_token==257 && s_pos<ir_source_size && load8(ir_source+s_pos)==117 {s_token=276;s_pos=s_pos+1;}
        if overflow && s_token!=258 {s_fail("integer literal out of range");}
        if s_pos<ir_source_size && (s_letter(load8(ir_source+s_pos)) || (load8(ir_source+s_pos)==46 && (s_pos+1==ir_source_size || load8(ir_source+s_pos+1)!=46))) {
            s_fail("floating point, units and suffixed literals are not supported yet");
        }
    }else {
        s_token=c;let d=0;if s_pos<ir_source_size {d=load8(ir_source+s_pos);}
        if c==61 && d==61 {s_token=259;}else if c==33 && d==61 {s_token=260;}
        else if c==60 && d==61 {s_token=261;}else if c==62 && d==61 {s_token=262;}
        else if c==60 && d==60 {s_token=265;}else if c==62 && d==62 {s_token=266;}
        else if c==45 && d==62 {s_token=270;}else if c==46 && d==46 {s_token=271;}
        else if c==43 && d==61 {s_token=272;}else if c==45 && d==61 {s_token=273;}
        else if c==42 && d==61 {s_token=274;}else if c==47 && d==61 {s_token=275;}
        if s_token>=259 {s_pos=s_pos+1;}
        if c!=40 && c!=41 && c!=123 && c!=125 && c!=44 && c!=59 && c!=58 && c!=63 && c!=46
            && c!=61 && c!=43 && c!=45 && c!=42 && c!=47 && c!=37 && c!=60 && c!=62
            && c!=91 && c!=93 && c!=33 && c!=126 && c!=38 && c!=124 && c!=94 {s_fail("unsupported SetaScript syntax");}
    }
    s_size=s_pos-s_start;
    if s_token==256 {if s_is("and") {s_token=263;}else if s_is("or") {s_token=264;}else if s_is("not") {s_token=33;}}
    return 0;
}
fn s_expect(t) {if s_token!=t {s_fail("unexpected SetaScript token");}s_next();return 0;}
fn s_keyword() {
    return s_is("fn") || s_is("cosmetic") || s_is("gen") || s_is("plugin") || s_is("let") || s_is("return")
        || s_is("if") || s_is("else") || s_is("for") || s_is("in") || s_is("repeat") || s_is("while")
        || s_is("true") || s_is("false") || s_is("i32") || s_is("bool") || s_is("state")
        || s_is("read_word") || s_is("write_word") || s_is("extern");
}
fn s_name() {if s_token!=256 || s_keyword() {s_fail("expected SetaScript name");}return 0;}
fn s_type() {
    let ty=0;if s_is("i32") {ty=1;}else if s_is("bool") {ty=2;}else {s_fail("only i32 and bool are supported by this frontend yet");}
    s_next();return ty;
}
// Half-full open-addressed name index keeps large restricted frontends within
// their existing fuel budget. Records still retain declaration-order indices.
fn s_function_name_slot(name,size) {
    let hash=5381;let i=0;while i<size {hash=((hash*33)^load8(name+i))&32767;i=i+1;}
    while load64(s_function_names+hash*8) {
        let f=s_functions+(load64(s_function_names+hash*8)-1)*64;
        if s_equal(name,size,load64(f),load64(f+8)) {return hash;}
        hash=(hash+1)&32767;
    }return hash;
}
fn s_find_function(name,size) {return load64(s_function_names+s_function_name_slot(name,size)*8)-1;}
fn s_find_local(name,size) {
    let i=s_local_count-1;while i>=0 {let f=s_locals+i*32;if s_equal(name,size,load64(f),load64(f+8)) {return i;}i=i-1;}return -1;
}
fn s_declare(name,size,ty,readonly) {
    if s_local_count>=4096 || s_slots>=4096 {s_fail("too many SetaScript locals");}
    let prior=s_find_local(name,size);if prior>=0 && load64(s_locals+prior*32+24)==s_depth {s_fail("duplicate SetaScript local");}
    let f=s_locals+s_local_count*32;store64(f,name);store64(f+8,size);store64(f+16,s_slots);store64(f+24,s_depth);
    store64(s_types+s_slots*8,ty);store64(s_readonly+s_slots*8,readonly);s_local_count=s_local_count+1;s_slots=s_slots+1;return s_slots-1;
}
fn s_require(actual,expected) {if actual!=expected {s_fail("SetaScript type mismatch");}return 0;}
fn s_priority(op) {
    if op==264 {return 1;}if op==263 {return 2;}if op==124 {return 3;}if op==94 {return 4;}if op==38 {return 5;}
    if op==259 || op==260 {return 6;}if op==60 || op==62 || op==261 || op==262 {return 7;}
    if op==265 || op==266 {return 8;}if op==43 || op==45 {return 9;}if op==42 || op==47 || op==37 {return 10;}return 0;
}
fn s_prefix() {
    if s_is("state") {
        let field=s_state_reference();let f=s_state_fields+field*40;let base=load64(f+24);let span=load64(f+32);
        if span {s_expect(91);s_require(s_expression(1),1);s_expect(93);ir_emit(21,(span<<32)|base);}
        else {ir_emit(5,base);}return load64(f+16);
    }
    if s_is("read_word") {s_next();s_expect(40);s_expect(41);ir_emit(20,0);return 1;}
    if s_is("write_word") {s_next();s_expect(40);s_require(s_expression(1),1);s_expect(41);ir_emit(19,0);return 1;}
    if s_token==257 {ir_emit(1,s_value);s_next();return 1;}
    if s_is("true") || s_is("false") {ir_emit(1,s_is("true"));s_next();return 2;}
    if s_token==45 || s_token==33 || s_token==126 {
        let op=s_token;s_next();let ty=s_expression(11);let kind=14;
        if op==33 {s_require(ty,2);kind=15;}else {s_require(ty,1);if op==126 {kind=16;}}
        ir_emit(kind,0);return ty;
    }
    if s_token==40 {s_next();let ty=s_expression(1);s_expect(41);return ty;}
    if s_token==256 {
        s_name();let name=ir_source+s_start;let size=s_size;s_next();
        if s_token==40 {
            let target=s_find_function(name,size);if target<0 {s_fail("unknown SetaScript function (host calls are not supported yet)");}
            let f=s_functions+target*64;let args=load64(f+16);let count=0;s_next();
            if s_token!=41 {let more=1;while more {
                if count>=load64(f+24) {s_fail("wrong SetaScript argument count");}
                s_require(s_expression(1),load64(args+count*32+16));ir_emit(2,0);count=count+1;
                if s_token==44 {s_next();}else {more=0;}
            }}
            s_expect(41);if count!=load64(f+24) {s_fail("wrong SetaScript argument count");}
            ir_emit(8,target);
            // Trusted platform code returns raw words; keep SetaScript bools 0/1.
            if load64(f+56) && load64(f+32)==2 {ir_emit(13,0);}return load64(f+32);
        }
        let local=s_find_local(name,size);if local<0 {s_fail("unknown SetaScript local");}
        let slot=load64(s_locals+local*32+16);ir_emit(3,slot);return load64(s_types+slot*8);
    }
    s_fail("expected SetaScript expression");return 0;
}
fn s_expression(minimum) {
    s_nesting=s_nesting+1;if s_nesting>128 {s_fail("SetaScript expression nesting limit exceeded");}
    let ty=s_prefix();
    while s_priority(s_token)>=minimum {
        let op=s_token;let priority=s_priority(op);s_next();
        if op==263 || op==264 {
            s_require(ty,2);let kind=11;if op==264 {kind=12;}let skip=ir_emit(kind,0);
            s_require(s_expression(priority+1),2);ir_patch(skip,ir_code_size);
        }else {
            ir_emit(2,0);let right=s_expression(priority+1);s_require(right,ty);
            if op!=259 && op!=260 {s_require(ty,1);}
            ir_emit(7,op);if op==259 || op==260 || op==60 || op==62 || op==261 || op==262 {ty=2;}
        }
    }
    if minimum==1 && s_token==63 {
        s_require(ty,2);s_next();let otherwise=ir_emit(11,0);ty=s_expression(1);s_expect(58);
        let end=ir_emit(10,0);ir_patch(otherwise,ir_code_size);s_require(s_expression(1),ty);ir_patch(end,ir_code_size);
    }
    s_nesting=s_nesting-1;return ty;
}
fn s_semicolon() {if s_token==59 {s_next();}return 0;}
fn s_if() {
    s_next();s_require(s_expression(1),2);let otherwise=ir_emit(11,0);let left=s_block();let right=0;
    if s_is("else") {
        s_next();let end=ir_emit(10,0);ir_patch(otherwise,ir_code_size);
        if s_is("if") {right=s_if();}else {right=s_block();}ir_patch(end,ir_code_size);
    }else {ir_patch(otherwise,ir_code_size);}return left && right;
}
fn s_literal() {let sign=1;if s_token==45 {sign=-1;s_next();}if s_token!=257 {s_fail("loop bounds must be integer literals");}let n=s_value*sign;s_next();return n;}
fn s_loop() {
    let repeat=s_is("repeat");s_next();let name=0;let size=0;let low=0;let high=0;
    if repeat {s_expect(40);high=s_literal();s_expect(41);}
    else {s_name();name=ir_source+s_start;size=s_size;s_next();if !s_is("in") {s_fail("expected in");}s_next();low=s_literal();s_expect(271);high=s_literal();}
    if low< -1000000 || high>1000000 || high<low || high-low>1000000 {s_fail("loop literal bounds exceed the initial frontend limit");}
    let before=s_local_count;s_depth=s_depth+1;if s_depth>128 {s_fail("SetaScript block nesting limit exceeded");}
    let slot=0;if repeat {if s_slots>=4096 {s_fail("too many SetaScript locals");}slot=s_slots;s_slots=s_slots+1;}
    else {slot=s_declare(name,size,1,1);}
    ir_emit(1,low);ir_emit(4,slot);let start=ir_code_size;
    ir_emit(3,slot);ir_emit(2,0);ir_emit(1,high);ir_emit(7,60);let end=ir_emit(11,0);
    s_block();ir_emit(3,slot);ir_emit(2,0);ir_emit(1,1);ir_emit(7,43);ir_emit(4,slot);ir_emit(10,start);ir_patch(end,ir_code_size);
    s_local_count=before;s_depth=s_depth-1;return 0;
}
fn s_statement() {
    if s_is("state") {
        let field=s_state_reference();let f=s_state_fields+field*40;let base=load64(f+24);let span=load64(f+32);let ty=load64(f+16);
        if span {
            s_expect(91);s_require(s_expression(1),1);s_expect(93);let op=s_token;
            if op!=61 && (op<272 || op>275) {s_fail("expected state assignment");}
            // Evaluate the index once, including for compound assignments.
            let slot=s_slots;if slot>=4096 {s_fail("too many SetaScript locals");}s_slots=s_slots+1;
            ir_emit(4,slot);ir_emit(2,0);s_next();
            if op!=61 {s_require(ty,1);ir_emit(21,(span<<32)|base);ir_emit(2,0);}
            s_require(s_expression(1),ty);
            if op!=61 {let binary_op=43;if op==273 {binary_op=45;}else if op==274 {binary_op=42;}else if op==275 {binary_op=47;}ir_emit(7,binary_op);}
            ir_emit(22,(span<<32)|base);s_semicolon();
        }else {
            let op=s_token;if op!=61 && (op<272 || op>275) {s_fail("expected state assignment");}
            s_assignment(base,ty,op,6);
        }return 0;
    }
    if s_is("let") {
        s_next();s_name();let name=ir_source+s_start;let size=s_size;s_next();let declared=0;
        if s_token==58 {s_next();declared=s_type();}s_expect(61);let ty=s_expression(1);
        if declared {s_require(ty,declared);}let slot=s_declare(name,size,ty,0);ir_emit(4,slot);s_semicolon();return 0;
    }
    if s_is("return") {s_next();s_require(s_expression(1),load64(s_functions+s_current*64+32));ir_emit(9,0);s_semicolon();return 1;}
    if s_is("if") {return s_if();}if s_is("for") || s_is("repeat") {return s_loop();}
    if s_is("while") {s_fail("SetaScript does not allow unbounded while loops");}
    if s_token==123 {return s_block();}
    let start=s_start;
    if s_token==256 {
        let name=ir_source+s_start;let size=s_size;s_next();
        if s_token==61 || (s_token>=272 && s_token<=275) {
            let op=s_token;let local=s_find_local(name,size);if local<0 {s_fail("unknown assignment local");}
            let slot=load64(s_locals+local*32+16);let ty=load64(s_types+slot*8);
            if load64(s_readonly+slot*8) {s_fail("loop index is read-only");}
            s_assignment(slot,ty,op,4);return 0;
        }
    }
    s_pos=start;s_next();s_expression(1);s_semicolon();return 0;
}
fn s_assignment(index,ty,op,storing) {
    s_next();if op!=61 {s_require(ty,1);ir_emit(storing-1,index);ir_emit(2,0);}
    s_require(s_expression(1),ty);
    if op!=61 {let binary_op=43;if op==273 {binary_op=45;}else if op==274 {binary_op=42;}else if op==275 {binary_op=47;}ir_emit(7,binary_op);}
    ir_emit(storing,index);s_semicolon();return 0;
}
fn s_state_reference() {
    s_next();s_expect(46);s_name();let i=0;let field=-1;
    while i<s_state_count {let f=s_state_fields+i*40;if s_equal(load64(f),load64(f+8),ir_source+s_start,s_size) {field=i;}i=i+1;}
    if field<0 {s_fail("unknown engine state field");}s_next();return field;
}
fn s_initializer(ty) {
    if ty==2 {if !s_is("true") && !s_is("false") {s_fail("boolean state initializer required");}let n=s_is("true");s_next();return n;}
    return s_literal();
}
fn s_state_definition() {
    s_next();s_expect(123);
    while s_token!=125 {
        s_name();let name=ir_source+s_start;let size=s_size;let i=0;
        while i<s_state_count {let f=s_state_fields+i*40;if s_equal(load64(f),load64(f+8),name,size) {s_fail("duplicate engine state field");}i=i+1;}
        if s_state_count>=2048 {s_fail("too many engine state fields");}
        s_next();s_expect(58);let ty=s_type();let span=0;
        if s_token==91 {s_next();span=s_literal();if span<1 || span>16777216 {s_fail("invalid state array span");}s_expect(93);if ir_profile<3 {ir_profile=3;}}
        s_expect(61);let base=ir_state_count;
        if span && s_token==91 {
            s_next();i=0;while i<span {ir_state_word(s_initializer(ty));i=i+1;if i<span {s_expect(44);}}
            s_expect(93);
        }else {
            let value=s_initializer(ty);let count=span;if !count {count=1;}i=0;
            while i<count {ir_state_word(value);i=i+1;}
        }
        let f=s_state_fields+s_state_count*40;store64(f,name);store64(f+8,size);store64(f+16,ty);store64(f+24,base);store64(f+32,span);
        s_state_count=s_state_count+1;s_semicolon();
    }s_next();return 0;
}
fn s_block() {
    s_depth=s_depth+1;if s_depth>128 {s_fail("SetaScript block nesting limit exceeded");}
    let before=s_local_count;let returns=0;s_expect(123);
    while s_token!=125 {if !s_token {s_fail("unterminated SetaScript block");}let r=s_statement();returns=returns || r;}
    s_expect(125);s_local_count=before;s_depth=s_depth-1;return returns;
}
fn s_file(index) {let f=s_files+index*48;ir_source=load64(f);ir_source_size=load64(f+8);ir_path=load64(f+16);return f;}
fn seta_add_file(text,size,path) {
    if s_file_count>=256 {s_fail("too many SetaScript files (maximum 256 including entry)");}
    let f=s_files+s_file_count*48;store64(f,text);store64(f+8,size);store64(f+16,path);s_file_count=s_file_count+1;return s_file_count-1;
}
fn seta_include(index) {store64(s_order+s_order_count*8,index);s_order_count=s_order_count+1;return 0;}
// A quoted path follows import: no escapes, newlines or empty paths.
fn s_import_path() {
    while s_pos<ir_source_size && (load8(ir_source+s_pos)==32 || load8(ir_source+s_pos)==9 || load8(ir_source+s_pos)==10 || load8(ir_source+s_pos)==13) {s_pos=s_pos+1;}
    s_start=s_pos;if s_pos==ir_source_size || load8(ir_source+s_pos)!=34 {s_fail("expected quoted SetaScript import path");}
    let open=s_pos;s_pos=s_pos+1;
    while s_pos<ir_source_size && load8(ir_source+s_pos)!=34 {
        let c=load8(ir_source+s_pos);if c==10 || c==13 || c==0 || c==92 {s_start=s_pos;s_fail("invalid character in SetaScript import path");}s_pos=s_pos+1;
    }
    if s_pos==ir_source_size {s_fail("unterminated SetaScript import path");}
    let n=s_pos-open-1;if n<1 {s_fail("SetaScript import path cannot be empty");}if n>4095 {s_fail("SetaScript import path exceeds 4095 bytes");}
    let path=alloc(n+1);if path<0 {s_fail("frontend allocation failed");}
    let i=0;while i<n {store8(path+i,load8(ir_source+open+1+i));i=i+1;}s_pos=s_pos+1;return path;
}
// Parse the entry plugin header (imported files have none) and leading imports.
// Returns the import count; resolution belongs to the bundled compiler host.
fn seta_scan(index) {
    let f=s_file(index);s_pos=0;s_next();
    if index==0 {
        if !s_is("plugin") {s_fail("expected plugin header");}s_next();s_name();s_next();
        while s_token==46 {s_next();s_name();s_next();}
        if !s_is("v1") {s_fail("expected plugin version v1");}s_next();s_expect(123);
        if s_token!=125 {s_fail("plugin configuration is not supported by this frontend yet");}s_next();
    }else if s_is("plugin") {s_fail("imported SetaScript files cannot declare a plugin header");}
    let list=0;let count=0;
    while s_token==256 && s_is("import") {
        if !list {list=alloc(256*16);if list<0 {s_fail("frontend allocation failed");}}
        if count>=256 {s_fail("too many imports in one SetaScript file (maximum 256)");}
        let path=s_import_path();store64(list+count*16,path);store64(list+count*16+8,s_start);count=count+1;
        s_next();s_semicolon();
    }
    store64(f+24,s_start);store64(f+32,list);store64(f+40,count);return count;
}
fn s_signatures(index) {
    s_file(index);s_pos=load64(s_files+index*48+24);s_next();
    if s_is("state") {s_state_definition();}
    while s_token {
        if s_is("import") {s_fail("SetaScript imports must precede state and functions");}
        // `extern fn` declares a body supplied by a trusted --platform module.
        let platform=0;if s_is("extern") {platform=1;s_next();}else if s_is("cosmetic") {s_next();}
        if !s_is("fn") {s_fail("only pure function declarations are supported yet");}s_next();s_name();
        if s_count>=ir_function_capacity {s_fail("too many SetaScript functions (maximum 16384)");}
        let name=ir_source+s_start;let size=s_size;if s_find_function(name,size)>=0 {s_fail("duplicate SetaScript function");}
        let f=s_functions+s_count*64;store64(f,name);store64(f+8,size);let args=s_locals;s_next();s_expect(40);
        let count=0;if s_token!=41 {let more=1;while more {
            s_name();if count>=4096 {s_fail("too many parameters");}store64(args+count*32,ir_source+s_start);store64(args+count*32+8,s_size);
            s_next();s_expect(58);store64(args+count*32+16,s_type());count=count+1;
            if s_token==44 {s_next();}else {more=0;}
        }}
        s_expect(41);let saved=alloc((count+1)*32);if saved<0 {s_fail("frontend allocation failed");}let at=0;while at<count*32 {store8(saved+at,load8(args+at));at=at+1;}store64(f+16,saved);store64(f+24,count);s_expect(270);store64(f+32,s_type());store64(f+40,s_start);store64(f+48,index);store64(f+56,platform);
        if platform {if s_equal(name,size,"main",4) {s_fail("SetaScript main cannot be extern");}s_semicolon();}else {
        s_expect(123);
        let braces=1;while braces {if !s_token {s_fail("unterminated SetaScript function");}if s_token==123 {braces=braces+1;if braces>128 {s_fail("SetaScript block nesting limit exceeded");}}else if s_token==125 {braces=braces-1;}s_next();}
        }store64(s_function_names+s_function_name_slot(name,size)*8,s_count+1);s_count=s_count+1;
    }return 0;
}
// Kahn's algorithm over emitted calls uses O(functions) scratch space and
// O(functions + instructions) time.
// Repeated calls count as repeated edges and are removed together. A worklist
// also avoids recursive host calls for long, valid SetaScript chains.
fn s_no_recursion() {
    let degrees=alloc(s_count*8);let queue=alloc(s_count*8);
    if degrees<0 || queue<0 {s_fail("frontend allocation failed");}
    let i=0;while i<ir_code_size {if load64(ir_code+i)==8 {
        let target=load64(ir_code+i+8);store64(degrees+target*8,load64(degrees+target*8)+1);
    }i=i+16;}
    let used=0;i=0;while i<s_count {if !load64(degrees+i*8) {store64(queue+used*8,i);used=used+1;}i=i+1;}
    let read=0;while read<used {
        let function=load64(queue+read*8);read=read+1;
        let pc=load64(ir_functions+function*64+16);let end=ir_code_size;
        if function+1<s_count {end=load64(ir_functions+(function+1)*64+16);}
        while pc<end {if load64(ir_code+pc)==8 {
            let target=load64(ir_code+pc+8);let degree=load64(degrees+target*8)-1;store64(degrees+target*8,degree);
            if !degree {store64(queue+used*8,target);used=used+1;}
        }pc=pc+16;}
    }
    if used!=s_count {s_fail("SetaScript recursion is not allowed");}return 0;
}
fn seta_begin(text,size,version,path) {
    ir_init(text,size,path,version);s_shader_mode=0;s_pos=0;s_count=0;s_nesting=0;s_state_count=0;
    s_functions=alloc(ir_function_capacity*64);s_function_names=alloc(32768*8);s_locals=alloc(4096*32);s_types=alloc(4096*8);s_readonly=alloc(4096*8);
    s_state_fields=alloc(2048*40);s_files=alloc(256*48);s_order=alloc(256*8);s_file_count=0;s_order_count=0;
    if s_functions<0 || s_function_names<0 || s_locals<0 || s_types<0 || s_readonly<0 || s_state_fields<0 || s_files<0 || s_order<0 {s_fail("frontend allocation failed");}
    seta_add_file(text,size,path);return 0;
}
// Files are compiled in include order: each import's files precede the importer.
fn seta_finish() {
    let k=0;while k<s_order_count {s_signatures(load64(s_order+k*8));k=k+1;}s_current=0;
    while s_current<s_count {
        let f=s_functions+s_current*64;s_file(load64(f+48));s_local_count=0;s_slots=0;s_depth=1;
        ir_begin(load64(f),load64(f+8),load64(f+24));let args=load64(f+16);let i=0;
        while i<load64(f+24) {let a=args+i*32;s_declare(load64(a),load64(a+8),load64(a+16),0);i=i+1;}
        if load64(f+56) {ir_import();ir_emit(9,0);}else {
        s_pos=load64(f+40);s_next();s_depth=0;
        if !s_block() {s_fail("SetaScript function must return on every path");}
        ir_emit(1,0);ir_emit(9,0);}ir_end(s_slots);s_current=s_current+1;
    }
    if ir_source!=load64(s_files) {s_file(0);s_start=ir_source_size;}
    s_no_recursion();let main=s_find_function("main",4);
    if main<0 {s_fail("missing main function");}let m=s_functions+main*64;
    if load64(m+24) || load64(m+32)!=1 {s_file(load64(m+48));s_start=load64(m)-ir_source;s_fail("SetaScript main must take no parameters and return i32");}
    return ir_finish();
}
// Single-buffer entry point, shared by the restricted external frontend route.
fn seta_frontend(text,size,version,path) {
    seta_begin(text,size,version,path);
    if seta_scan(0) {s_start=load64(load64(s_files+32)+8);s_fail("SetaScript imports require the bundled compiler frontend");}
    seta_include(0);return seta_finish();
}
