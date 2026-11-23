// Circuit arithmetic uses portable binary64 bit patterns in both native and
// checked execution. No host math, files or platform-dependent tolerances.
import "../../../lib/f64-math.flex";
import "json/tree.flex";

fn psc_power10(exponent) {
    let factor=f64_from_i64(10);let result=f64_from_i64(1);
    while exponent>0 {
        if exponent&1 {result=f64_mul(result,factor);}
        exponent=exponent>>1;
        if exponent {factor=f64_mul(factor,factor);}
    }
    return result;
}

fn psc_scale10(value,exponent) {
    // Split extreme exponents so the intermediate power stays finite.
    while exponent>100 {value=f64_mul(value,psc_power10(100));exponent=exponent-100;}
    while exponent < -100 {value=f64_div(value,psc_power10(100));exponent=exponent+100;}
    if exponent<0 {return f64_div(value,psc_power10(-exponent));}
    return f64_mul(value,psc_power10(exponent));
}

fn psc_number(node) {
    if j_kind(node)==1 {return f64_from_i64(j_value(node));}
    if j_kind(node)!=6 {return f64_nan();}
    // Raw-number nodes from the JSON parser have already passed JSON grammar.
    // Keep the first 17 significant digits and round discarded digits once.
    let text=j_value(node);let length=m_len(text);
    if length>80 {return f64_nan();}
    let negative=load8(text)==45;let i=negative;
    let mantissa=0;let kept=0;let discarded=0;let round=-1;let more=0;
    let fraction=0;let dot=0;
    while i<length && load8(text+i)!=69 && load8(text+i)!=101 {
        let c=load8(text+i);i=i+1;
        if c==46 {dot=1;}
        else if c>=48 && c<=57 {
            let digit=c-48;
            fraction=fraction+dot;
            if kept<17 {
                if mantissa || digit {mantissa=mantissa*10+digit;kept=kept+1;}
            }else {
                discarded=discarded+1;
                if round<0 {round=digit;}
                else if digit {more=1;}
            }
        }else {return f64_nan();}
    }
    let exponent=0;let sign=1;
    if i<length {
        i=i+1;
        if load8(text+i)==45 {sign=-1;i=i+1;}
        else if load8(text+i)==43 {i=i+1;}
        while i<length {
            let digit=load8(text+i)-48;i=i+1;
            if digit<0 || digit>9 || exponent>1000 {return f64_nan();}
            exponent=exponent*10+digit;
        }
    }
    if !mantissa {return 0;}
    if round>5 || (round==5 && (more || (mantissa&1))) {mantissa=mantissa+1;}
    exponent=sign*exponent+discarded-fraction;
    if exponent>308 || exponent < -350 {return f64_nan();}
    let value=psc_scale10(f64_from_i64(mantissa),exponent);
    if negative {value=f64_math_neg(value);}
    return value;
}

fn psc_decimal(value) {
    if !f64_is_finite(value) {return j_new(0,0);}
    if f64_magnitude(value)==0 {return j_number(0);}
    // Normalize to 16 significant decimal digits for portable result vectors.
    let magnitude=f64_magnitude(value);
    let exponent=(f64_exponent(magnitude)-1023)*30103/100000;
    let normalized=psc_scale10(magnitude,-exponent);
    let one=f64_from_i64(1);let ten=f64_from_i64(10);
    while f64_lt(normalized,one) {normalized=f64_mul(normalized,ten);exponent=exponent-1;}
    while f64_ge(normalized,ten) {normalized=f64_div(normalized,ten);exponent=exponent+1;}
    let digits=f64_to_i64_nearest(f64_mul(normalized,f64_from_i64(1000000000000000)));
    if digits>=10000000000000000 {digits=digits/10;exponent=exponent+1;}
    let scientific=m_cat(m_int(digits),m_cat("e",j_signed(exponent-15)));
    if f64_sign(value) {scientific=m_cat("-",scientific);}
    return j_new(6,scientific);
}

fn psc_log(value) {
    // For positive inputs, reduce the mantissa near 1 and evaluate
    // log(x)=2( t+t^3/3+... ), t=(x-1)/(x+1), |t|<0.172.
    let shift=0;
    if f64_exponent(value)==0 {value=f64_scalbn(value,54);shift=54;}
    let exponent=f64_exponent(value)-1023-shift;
    let x=f64_fraction(value)|0x3ff0000000000000;
    if x>0x3ff6a09e667f3bcd {x=f64_scalbn(x,-1);exponent=exponent+1;}
    let one=f64_from_i64(1);
    let t=f64_div(f64_sub(x,one),f64_add(x,one));
    let square=f64_mul(t,t);let term=t;let sum=t;let k=3;
    while k<=23 {
        term=f64_mul(term,square);
        sum=f64_add(sum,f64_div(term,f64_from_i64(k)));
        k=k+2;
    }
    return f64_add(f64_scalbn(sum,1),f64_mul(f64_from_i64(exponent),0x3fe62e42fefa39ef));
}

// Dense row-major matrices are bounded by the number of modeled nets and
// independent voltage constraints. Factorization stores L and U in one copy.
fn psc_factor(matrix,lu,pivots,n) {
    let i=0;while i<n*n {store64(lu+i*8,load64(matrix+i*8));i=i+1;}
    let k=0;
    while k<n {
        let pivot=k;let magnitude=0;i=k;
        while i<n {
            let v=f64_magnitude(load64(lu+(i*n+k)*8));
            if v>magnitude {magnitude=v;pivot=i;}
            i=i+1;
        }
        if !f64_is_finite(magnitude) || magnitude<0x3cd203af9ee75616 {return 0;}
        store64(pivots+k*8,pivot);
        let j=0;while pivot!=k && j<n {
            let a=lu+(pivot*n+j)*8;let b=lu+(k*n+j)*8;
            let swap=load64(a);store64(a,load64(b));store64(b,swap);j=j+1;
        }
        let row=lu+k*n*8;let diagonal=load64(row+k*8);i=k+1;
        while i<n {
            let dst=lu+i*n*8;let lhs=load64(dst+k*8);
            if f64_magnitude(lhs) {
                let scale=f64_div(lhs,diagonal);store64(dst+k*8,scale);
                j=k+1;while j<n {
                    let rhs=load64(row+j*8);
                    if f64_magnitude(rhs) {store64(dst+j*8,f64_sub(load64(dst+j*8),f64_mul(scale,rhs)));}
                    j=j+1;
                }
            }
            i=i+1;
        }
        k=k+1;
    }
    return 1;
}

fn psc_solve(matrix,lu,pivots,rhs,x,n) {
    let i=0;
    while i<n {store64(x+i*8,load64(rhs+i*8));i=i+1;}
    i=0;
    while i<n {
        let pivot=load64(pivots+i*8)*8;let value=load64(x+pivot);
        store64(x+pivot,load64(x+i*8));store64(x+i*8,value);i=i+1;
    }
    i=0;
    while i<n {
        let value=load64(x+i*8);let j=0;
        while j<i {
            let lower=load64(lu+(i*n+j)*8);
            if f64_magnitude(lower) {value=f64_sub(value,f64_mul(lower,load64(x+j*8)));}
            j=j+1;
        }
        store64(x+i*8,value);i=i+1;
    }
    i=n-1;
    while i>=0 {
        let value=load64(x+i*8);let j=i+1;
        while j<n {
            let upper=load64(lu+(i*n+j)*8);
            if f64_magnitude(upper) {value=f64_sub(value,f64_mul(upper,load64(x+j*8)));}
            j=j+1;
        }
        value=f64_div(value,load64(lu+(i*n+i)*8));
        if !f64_is_finite(value) || f64_magnitude(value)>0x41cdcd6500000000 {return 0;}
        store64(x+i*8,value);i=i-1;
    }
    i=0;
    while i<n {
        let total=0;let target=load64(rhs+i*8);let scale=f64_magnitude(target);let j=0;
        while j<n {
            let entry=load64(matrix+(i*n+j)*8);
            if f64_magnitude(entry) {
                let t=f64_mul(entry,load64(x+j*8));
                total=f64_add(total,t);
                scale=f64_add(scale,f64_magnitude(t));
            }
            j=j+1;
        }
        if scale<0x3ff0000000000000 {scale=0x3ff0000000000000;}
        if f64_gt(f64_magnitude(f64_sub(total,target)),f64_mul(0x3e45798ee2308c3a,scale)) {return 0;}
        i=i+1;
    }
    return 1;
}

// The fixed-step solver and its release receipt use the same time grid.
fn psc_transient_steps(stop,dt) {
    if !f64_is_finite(stop) || !f64_is_finite(dt) || !f64_gt(dt,0) || f64_gt(dt,stop) || f64_gt(stop,f64_from_i64(3600)) {return -1;}
    let steps=f64_to_i64_nearest(f64_div(stop,dt));
    let delta=f64_magnitude(f64_sub(f64_mul(f64_from_i64(steps),dt),stop));
    if steps<1 || steps>500 || f64_gt(delta,f64_mul(stop,0x3e112e0be826d695)) {return 0;}
    return steps;
}

fn psc_final_timing(experiment) {
    let analysis=j_string(experiment,"analysis");
    if m_eq(analysis,"dc") {
        return j_parse("{\"sample_count\":1,\"time_ps\":0}");
    }
    if !m_eq(analysis,"transient") {return 0;}
    let stop=psc_number(j_get(experiment,"stop_s"));let dt=psc_number(j_get(experiment,"step_s"));
    let steps=psc_transient_steps(stop,dt);if steps<1 {return 0;}
    let time=psc_number(psc_decimal(f64_mul(dt,f64_from_i64(steps))));
    let result=j_object();j_add(result,"sample_count",j_number(steps+1));
    j_add(result,"time_ps",j_number(f64_to_i64_nearest(f64_mul(time,f64_from_i64(1000000000000)))));
    return result;
}
