// Quantities carry an IEEE binary64 value and a kind (scalar, length, angle).
// Keep full precision until the dimension enters the nanometre sketch solver.
import "math.flex";
import "../../lib/f64.flex";

fn pcv_letter(c) {return (c>=65 && c<=90) || (c>=97 && c<=122);}
fn pcv_digit(c) {return c>=48 && c<=57;}
fn pcv_ident(c) {return pcv_letter(c) || pcv_digit(c) || c==95;}
fn pcv_kind(name) {
    if m_eq(name,"scalar") {return 0;}if m_eq(name,"length") {return 1;}
    if m_eq(name,"angle") {return 2;}return -1;
}
fn pcv_space(p) {
    let c=load8(p);if c==32 || (c>=9 && c<=13) {return 1;}
    if c==194 && (load8(p+1)==160 || load8(p+1)==133) {return 2;}
    if c==225 && load8(p+1)==154 && load8(p+2)==128 {return 3;}
    if c==226 {
        let b=load8(p+1);let d=load8(p+2);
        if (b==128 && ((d>=128 && d<=138) || d==168 || d==169 || d==175)) || (b==129 && d==159) {return 3;}
    }
    if c==227 && load8(p+1)==128 && load8(p+2)==128 {return 3;}return 0;
}
fn pcv_skip(p) {let n=pcv_space(p);while n {p=p+n;n=pcv_space(p);}return p;}
fn pcv_trim(text) {
    let start=pcv_skip(text);let p=start;let end=start;
    while load8(p) {let n=pcv_space(p);if n {p=p+n;}else {p=p+1;end=p;}}
    return m_slice(start,end-start);
}
fn pcv_quantity(value,kind) {
    if !f64_is_finite(value) {return cg_fail("Dimension must be finite");}
    return cg_v(value,kind,0);
}
fn pcv_literal_parts(parser) {
    let p=load64(parser);let digits=0;let kept=0;let value=0;let scale=0;let fraction=0;
    while pcv_digit(load8(p)) || (load8(p)==46 && !fraction) {
        let c=load8(p);p=p+1;
        if c==46 {fraction=1;}
        else {
            digits=digits+1;if fraction {scale=scale-1;}
            if kept<18 {
                value=value*10+c-48;if value {kept=kept+1;}
            }else {scale=scale+1;}
        }
    }
    if !digits {return cg_fail("Expected a number, pi, variable or parenthesis");}
    if load8(p)==69 || load8(p)==101 {
        p=p+1;let sign=1;if load8(p)==45 {sign=-1;}
        if load8(p)==45 || load8(p)==43 {p=p+1;}
        if !pcv_digit(load8(p)) {return cg_fail("Expected an exponent");}
        let exponent=0;while pcv_digit(load8(p)) {if exponent<1000 {exponent=exponent*10+load8(p)-48;}p=p+1;}
        scale=scale+sign*exponent;
    }
    store64(parser,p);return cg_v(value,scale,0);
}
fn pcv_literal_value(value,scale) {
    let number=f64_from_i64(value);
    if value && scale>309 {return cg_fail("Dimension must be finite");}
    if scale< -345 || !value {return pcv_quantity(0,0);}
    let ten=f64_from_i64(10);let chunk=f64_from_i64(10000000000000000);
    while scale>=16 {number=f64_mul(number,chunk);scale=scale-16;}
    while scale<= -16 {number=f64_div(number,chunk);scale=scale+16;}
    while scale>0 {number=f64_mul(number,ten);scale=scale-1;}
    while scale<0 {number=f64_div(number,ten);scale=scale+1;}
    return pcv_quantity(number,0);
}
fn pcv_literal(parser) {
    let parts=pcv_literal_parts(parser);if !parts {return 0;}
    return pcv_literal_value(load64(parts),load64(parts+8));
}
fn pcv_unit(word) {
    if m_eq(word,"mm") {return pcv_quantity(f64_from_i64(1),1);}
    if m_eq(word,"cm") {return pcv_quantity(f64_from_i64(10),1);}
    if m_eq(word,"m") {return pcv_quantity(f64_from_i64(1000),1);}
    if m_eq(word,"um") || m_eq(word,"μm") || m_eq(word,"µm") {return pcv_quantity(f64_div(f64_from_i64(1),f64_from_i64(1000)),1);}
    if m_eq(word,"in") || m_eq(word,"inch") {return pcv_quantity(f64_div(f64_from_i64(254),f64_from_i64(10)),1);}
    if m_eq(word,"ft") {return pcv_quantity(f64_div(f64_from_i64(3048),f64_from_i64(10)),1);}
    if m_eq(word,"deg") || m_eq(word,"°") {return pcv_quantity(f64_from_i64(1),2);}
    if m_eq(word,"rad") {return pcv_quantity(f64_div(f64_from_i64(180),0x400921fb54442d18),2);}return 0;
}
fn pcv_word(parser) {
    let p=load64(parser);let start=p;
    while pcv_letter(load8(p)) || (load8(p)>=128 && !pcv_space(p)) {p=p+1;}
    store64(parser,p);let word=m_slice(start,p-start);let i=0;
    while i<p-start {let c=load8(word+i);if c>=65 && c<=90 {store8(word+i,c+32);}i=i+1;}return word;
}
fn pcv_primary(parser,depth) {
    if depth>32 {return cg_fail("Dimension expression is nested too deeply");}
    let p=pcv_skip(load64(parser));let c=load8(p);store64(parser,p);let result=0;
    if c==43 || c==45 {
        store64(parser,p+1);result=pcv_primary(parser,depth+1);
        if !result || c==43 {return result;}return pcv_quantity(f64_sub(0,load64(result)),load64(result+8));
    }
    if c==40 {
        store64(parser,p+1);result=pcv_sum(parser,depth+1);p=pcv_skip(load64(parser));
        if load8(p)!=41 {return cg_fail("Missing closing parenthesis");}store64(parser,p+1);
    }else if c==35 {
        let start=p+1;p=start;while pcv_ident(load8(p)) {p=p+1;}
        store64(parser,p);result=pcv_resolve(load64(parser+8),m_slice(start,p-start),load64(parser+16));
    }else if pcv_letter(c) {
        if !m_eq(pcv_word(parser),"pi") {return cg_fail("Expected a number, pi, variable or parenthesis");}
        result=pcv_quantity(0x400921fb54442d18,0);
    }else {result=pcv_literal(parser);}
    if !result {return 0;}p=pcv_skip(load64(parser));store64(parser,p);
    if pcv_letter(load8(p)) || load8(p)>=128 {
        let unit=pcv_unit(pcv_word(parser));if !unit {return cg_fail("Unknown dimension unit");}
        if load64(result+8) {return cg_fail("A unit can only follow a dimensionless value");}
        result=pcv_quantity(f64_mul(load64(result),load64(unit)),load64(unit+8));
    }
    return result;
}
fn pcv_product(parser,depth) {
    let a=pcv_primary(parser,depth);let p=pcv_skip(load64(parser));
    while a && (load8(p)==42 || load8(p)==47) {
        let op=load8(p);store64(parser,p+1);let b=pcv_primary(parser,depth);if !b {return 0;}
        let kind=load64(a+8);let bk=load64(b+8);
        if op==42 {
            if kind && bk {return cg_fail("Multiplication needs a dimensionless operand");}
            a=pcv_quantity(f64_mul(load64(a),load64(b)),kind+bk);
        }else {
            if bk && bk!=kind {return cg_fail("Cannot divide incompatible dimensions");}
            if !f64_magnitude(load64(b)) {return cg_fail("Cannot divide by zero");}
            a=pcv_quantity(f64_div(load64(a),load64(b)),kind-bk);
        }
        p=pcv_skip(load64(parser));
    }
    return a;
}
fn pcv_sum(parser,depth) {
    let a=pcv_product(parser,depth);let p=pcv_skip(load64(parser));
    while a && (load8(p)==43 || load8(p)==45) {
        let op=load8(p);store64(parser,p+1);let b=pcv_product(parser,depth);if !b {return 0;}
        if load64(a+8)!=load64(b+8) {return cg_fail("Addition and subtraction require matching units");}
        let value=load64(b);if op==45 {value=f64_sub(0,value);}
        a=pcv_quantity(f64_add(load64(a),value),load64(a+8));p=pcv_skip(load64(parser));
    }
    return a;
}
fn pcv_evaluate(text,kind,bindings,level) {
    if m_len(text)>512 {return cg_fail("Dimension expression exceeds 512 bytes");}
    let parser=cg_v(text,bindings,level);let result=pcv_sum(parser,0);
    if !result {return 0;}
    if load8(pcv_skip(load64(parser))) {return cg_fail("Unexpected dimension token");}
    if load64(result+8) && load64(result+8)!=kind {return cg_fail("Incompatible dimension units");}
    return pcv_quantity(load64(result),kind);
}
fn pcv_resolve(bindings,name,level) {
    let slot=j_integer(bindings,name);if !slot {return cg_fail(m_cat("Unknown sketch variable: #",name));}
    if load64(slot+16) {return load64(slot+16);}
    if load64(slot+8) {return cg_fail(m_cat("Cyclic sketch variable: #",name));}
    if level>=64 {return cg_fail("Sketch variable dependencies exceed 64 levels");}
    store64(slot+8,1);let row=load64(slot);
    let result=pcv_evaluate(j_string(row,"expression"),pcv_kind(j_string(row,"kind")),bindings,level+1);
    store64(slot+8,0);store64(slot+16,result);return result;
}
fn pcv_bind(variables) {
    let bindings=j_object();
    if !variables {return bindings;}
    if j_kind(variables)!=3 || cg_j_count(variables)>256 {return cg_fail("Expected up to 256 sketch variables");}
    let row=load64(variables+16);
    while row {
        let name=j_string(row,"name");let n=m_len(name);
        if !n || n>64 || pcv_digit(load8(name)) {return cg_fail("Invalid sketch variable name");}
        let i=0;while i<n {if !pcv_ident(load8(name+i)) {return cg_fail("Invalid sketch variable name");}i=i+1;}
        if j_get(bindings,name) {return cg_fail(m_cat("Duplicate sketch variable: #",name));}
        if pcv_kind(j_string(row,"kind"))<0 || j_kind(j_get(row,"expression"))!=2 {return cg_fail("Invalid sketch variable definition");}
        cg_j_int(bindings,name,cg_v(row,0,0));row=load64(row+24);
    }
    row=load64(variables+16);
    while row {if !pcv_resolve(bindings,j_string(row,"name"),0) {return 0;}row=load64(row+24);}
    return bindings;
}
fn pcv_length(text,bindings) {
    let result=pcv_evaluate(text,1,bindings,0);if !result {return 0;}
    let value=load64(result);
    if f64_lt(value,0) || f64_lt(f64_from_i64(500),value) {return cg_fail("Line length must be from 0.01 to 500 mm");}
    return f64_to_i64_round(f64_mul(value,f64_from_i64(1000000)));
}
// Called after successful parsing. A signed decimal or exponent literal
// becomes a plain driving value, while arithmetic and units retain their text.
fn pcv_plain(text) {
    let p=text;if load8(p)==43 || load8(p)==45 {p=p+1;}
    if !pcv_digit(load8(p)) && load8(p)!=46 {return 0;}
    let parser=cg_v(p,0,0);pcv_literal(parser);return !load8(load64(parser));
}
