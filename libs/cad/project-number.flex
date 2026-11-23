import "math.flex";
// Quantize a JSON decimal once, including values serialized by a float solver.
fn pc_serial_number(value,places,factor,limit) {
    if j_kind(value)==1 {let n=j_value(value);if n< -limit || n>limit {return cg_fail("Coordinate or angle exceeds range");}return n*factor;}
    if j_kind(value)!=6 {return cg_fail("Expected a finite coordinate or angle");}
    let s=j_value(value);let negative=load8(s)==45;let i=negative;let digits=m_buffer();
    let whole=0;let fraction=0;let exponent=0;
    while load8(s+i) && load8(s+i)!=101 && load8(s+i)!=69 {
        if load8(s+i)==46 {fraction=1;}
        else {m_append(digits,s+i,1);if !fraction {whole=whole+1;}}
        i=i+1;
    }
    if load8(s+i) {
        i=i+1;let minus=load8(s+i)==45;if minus || load8(s+i)==43 {i=i+1;}
        while load8(s+i) {if exponent<100000 {exponent=exponent*10+load8(s+i)-48;}i=i+1;}
        if minus {exponent=-exponent;}
    }
    let at=whole+exponent+places;let count=load64(digits+8);let data=m_data(digits);
    i=0;while i<count && load8(data+i)==48 {i=i+1;}
    if i==count {return 0;}
    if at-i>19 {return cg_fail("Coordinate or angle exceeds range");}
    let n=0;
    while i<at {if n>limit*factor/10 {return cg_fail("Coordinate or angle exceeds range");}n=n*10;if i<count {n=n+load8(data+i)-48;}i=i+1;}
    if at>=0 && at<count && load8(data+at)>=53 {n=n+1;}
    if n>limit*factor {return cg_fail("Coordinate or angle exceeds range");}
    if negative {return -n;}return n;
}
fn pc_pose_number(value) {return pc_serial_number(value,6,1000000,500);}
fn pc_uv(row) {
    return cg_v(pc_pose_number(j_get(row,"x")),pc_pose_number(j_get(row,"y")),0);
}

// Serialize picoradians with enough precision to reconnect curve endpoints.
fn pc_arc_json_angle(value) {
    let scale=1000000000000;let n=f64_to_i64_round(f64_mul(value,f64_from_i64(scale)));
    let digits=m_int(scale+cg_abs(n)%scale);let sign="";if n<0 {sign="-";}
    return j_new(6,m_cat(sign,m_cat(m_int(cg_abs(n)/scale),m_cat(".",digits+1))));
}
