import "json/tree.flex";
import "monolith/support.flex";
// Native CAD arithmetic. Coordinates are integer nanometres; normals use 1e9.
// Model input/output uses millimetres. No GPU, FFI geometry kernel or host files.
global cg_error=0;
global cg_work=0;
global cg_deadline=0;
fn cg_begin() {
    cg_error=0;
    cg_work=0;
    cg_deadline=m_now()+1500;
    return 0;
}
fn cg_fail(message) {
    if !cg_error {
        cg_error=message;
    }
    return 0;
}
fn cg_step() {
    cg_work=cg_work+1;
    if cg_work>2000000 {
        return cg_fail("Geometry work limit exceeded; reduce segments or split the design");
    }
    if cg_work%256==0 && m_now()>cg_deadline {
        return cg_fail("Geometry build exceeded its time budget");
    }
    return !cg_error;
}
fn cg_int(n) {
    if n<0 {
        return m_cat("-",m_int(-n));
    }
    return m_int(n);
}
fn cg_abs(n) {
    if n<0 {
        return -n;
    }
    return n;
}
fn cg_sqrt(n) {
    if n<=0 {
        return 0;
    }
    let x=n;
    let y=(x+1)/2;
    while y<x {
        x=y;
        y=(x+n/x)/2;
    }
    return x;
}
fn cg_array() {
    let a=m_take(24);
    store64(a,0);
    store64(a+8,0);
    store64(a+16,0);
    return a;
}
fn cg_count(a) {
    if !a {
        return 0;
    }
    return load64(a);
}
fn cg_at(a,i) {
    if !a || i<0 || i>=load64(a) {
        return 0;
    }
    return load64(load64(a+16)+i*8);
}
fn cg_push(a,item) {
    if !cg_step() {
        return 0;
    }
    if !item {
        return 0;
    }
    let n=load64(a);
    let capacity=load64(a+8);
    if n>=16000 {
        return cg_fail("Geometry polygon/vertex limit exceeded");
    }
    if n==capacity {
        let size=capacity*2;
        if size<8 {
            size=8;
        }
        let data=m_take(size*8);
        let i=0;
        while i<n {
            store64(data+i*8,load64(load64(a+16)+i*8));
            i=i+1;
        }
        store64(a+8,size);
        store64(a+16,data);
    }
    store64(load64(a+16)+n*8,item);
    store64(a,n+1);
    return item;
}
fn cg_join(a,b) {
    let i=0;
    while i<cg_count(b) && !cg_error {
        cg_push(a,cg_at(b,i));
        i=i+1;
    }
    return a;
}
fn cg_v(x,y,z) {
    let p=m_take(24);
    store64(p,x);
    store64(p+8,y);
    store64(p+16,z);
    return p;
}
fn cg_sub(a,b) {
    return cg_v(load64(a)-load64(b),load64(a+8)-load64(b+8),load64(a+16)-load64(b+16));
}
fn cg_distance2(a,b) {
    let x=load64(a)-load64(b);let y=load64(a+8)-load64(b+8);let z=load64(a+16)-load64(b+16);
    return x*x+y*y+z*z;
}
fn cg_cross(a,b) {
    return cg_v(load64(a+8)*load64(b+16)-load64(a+16)*load64(b+8),load64(a+16)*load64(b)-load64(a)*load64(b+16),load64(a)*load64(b+8)-load64(a+8)*load64(b));
}
fn cg_dot(a,b) {
    return (load64(a)*load64(b)+load64(a+8)*load64(b+8)+load64(a+16)*load64(b+16))/1000000000;
}
fn cg_normal(a) {
    let largest=cg_abs(load64(a));
    let i=1;
    while i<3 {
        if cg_abs(load64(a+i*8))>largest {
            largest=cg_abs(load64(a+i*8));
        }
        i=i+1;
    }
    if !largest {
        return 0;
    }
    let divisor=largest/1000000000+1;
    let x=load64(a)/divisor;
    let y=load64(a+8)/divisor;
    let z=load64(a+16)/divisor;
    let length=cg_sqrt(x*x+y*y+z*z);
    if !length {
        return 0;
    }
    return cg_v(x*1000000000/length,y*1000000000/length,z*1000000000/length);
}
fn cg_poly(vertices) {
    if cg_error || cg_count(vertices)<3 {
        return 0;
    }
    let a=cg_at(vertices,0);
    let i=2;
    let normal=0;
    while i<cg_count(vertices) && !normal {
        let u=cg_sub(cg_at(vertices,i-1),a);
        let v=cg_sub(cg_at(vertices,i),a);
        let cross=cg_cross(u,v);
        let extent=0;
        let axis=0;
        let area=0;
        while axis<3 {
            if cg_abs(load64(u+axis*8))>extent {
                extent=cg_abs(load64(u+axis*8));
            }
            if cg_abs(load64(v+axis*8))>extent {
                extent=cg_abs(load64(v+axis*8));
            }
            if cg_abs(load64(cross+axis*8))>area {
                area=cg_abs(load64(cross+axis*8));
            }
            axis=axis+1;
        }
        if area>extent*4 {
            normal=cg_normal(cross);
        }
        i=i+1;
    }
    if !normal {
        return 0;
    }
    let p=m_take(24);
    store64(p,vertices);
    store64(p+8,normal);
    store64(p+16,cg_dot(normal,a));
    return p;
}
fn cg_face(out,a,b,c,d) {
    let vertices=cg_array();
    cg_push(vertices,a);
    cg_push(vertices,b);
    cg_push(vertices,c);
    if d {
        cg_push(vertices,d);
    }
    cg_push(out,cg_poly(vertices));
    return 0;
}
fn cg_flip(poly) {
    let vertices=cg_array();
    let old=load64(poly);
    let i=cg_count(old)-1;
    while i>=0 {
        cg_push(vertices,cg_at(old,i));
        i=i-1;
    }
    let n=load64(poly+8);
    store64(poly,vertices);
    store64(poly+8,cg_v(-load64(n),-load64(n+8),-load64(n+16)));
    store64(poly+16,-load64(poly+16));
    return 0;
}
fn cg_copy(polys) {
    let out=cg_array();
    let i=0;
    while i<cg_count(polys) {
        let old=cg_at(polys,i);
        let p=m_take(24);
        store64(p,load64(old));
        store64(p+8,load64(old+8));
        store64(p+16,load64(old+16));
        cg_push(out,p);
        i=i+1;
    }
    return out;
}
fn cg_sin(angle) {
    if angle%180000==0 {
        return 0;
    }
    if angle%360000==90000 || angle%360000== -270000 {
        return 1000000;
    }
    if angle%360000== -90000 || angle%360000==270000 {
        return -1000000;
    }
    while angle>180000 {
        angle=angle-360000;
    }
    while angle< -180000 {
        angle=angle+360000;
    }
    if angle>90000 {
        angle=180000-angle;
    }
    if angle< -90000 {
        angle=-180000-angle;
    }
    let x=angle*3141593/180000;
    let square=x*x/1000000;
    let term=x;
    let sum=x;
    let i=1;
    while i<8 {
        term=-term*square/(1000000*(i*2)*(i*2+1));
        sum=sum+term;
        i=i+1;
    }
    return sum;
}
fn cg_cos(angle) {
    return cg_sin(angle+90000);
}
fn cg_number(value) {return cg_number_bounded(value,500);}
fn cg_number_bounded(value,limit) {
    if j_kind(value)==1 {
        let n=j_value(value);
        if n< -limit || n>limit {
            cg_fail(m_cat("CAD dimensions and coordinates must be within +/-",m_cat(m_int(limit)," mm")));
            return 0;
        }
        return n*1000000;
    }
    if j_kind(value)!=6 {
        cg_fail("CAD dimensions must be finite millimetre numbers");
        return 0;
    }
    let text=j_value(value);
    let at=0;
    let sign=1;
    if load8(text)==45 {
        sign=-1;
        at=1;
    }
    let n=0;
    while load8(text+at)>=48 && load8(text+at)<=57 {
        n=n*10+load8(text+at)-48;
        at=at+1;
        if n>limit {
            cg_fail(m_cat("CAD dimension exceeds ",m_cat(m_int(limit)," mm")));
            return 0;
        }
    }
    n=n*1000000;
    if load8(text+at)==46 {
        at=at+1;
        let scale=100000;
        while load8(text+at)>=48 && load8(text+at)<=57 {
            if scale {
                n=n+(load8(text+at)-48)*scale;
                scale=scale/10;
            }
            else if load8(text+at)!=48 {
                cg_fail("CAD dimensions support up to six decimal places in mm");
                return 0;
            }
            at=at+1;
        }
    }
    if load8(text+at) || n>limit*1000000 {
        cg_fail(m_cat("Use decimal CAD dimensions within +/-",m_cat(m_int(limit)," mm; exponent notation is unsupported")));
        return 0;
    }
    return sign*n;
}
fn cg_vector(value,optional) {
    if !value && optional {
        return cg_v(0,0,0);
    }
    if j_kind(value)!=3 || cg_j_count(value)!=3 {
        cg_fail("Expected three numbers for size, position or rotation");
        return cg_v(0,0,0);
    }
    let p=load64(value+16);
    let x=cg_number(p);
    p=load64(p+24);
    let y=cg_number(p);
    p=load64(p+24);
    let z=cg_number(p);
    return cg_v(x,y,z);
}
fn cg_decimal(n) {
    let sign="";
    if n<0 {
        sign="-";
        n=-n;
    }
    let fraction=m_int(n%1000000);
    while m_len(fraction)<6 {
        fraction=m_cat("0",fraction);
    }
    return m_cat(sign,m_cat(m_int(n/1000000),m_cat(".",fraction)));
}
fn cg_json_number(n) {
    return j_new(6,cg_decimal(n));
}
// Owned output arrays retain a tail outside the standard 40-byte JSON header.
// Only pass arrays created here; parsed document arrays remain ordinary JSON.
fn cg_json_array() {
    let row=m_take(48);let i=0;while i<6 {store64(row+i*8,0);i=i+1;}store64(row,3);return row;
}
fn cg_json_push(array,value) {
    store64(value+32,0);let tail=load64(array+40);
    if tail {store64(tail+24,value);}else {store64(array+16,value);}
    store64(array+40,value);return value;
}
// Volume uses micrometre coordinates to keep the determinant within i64.
// Displayed volumes are approximate to 0.001 mm3 per triangle.
fn cg_volume(a,b,c) {
    let ax=load64(a)/1000;
    let ay=load64(a+8)/1000;
    let az=load64(a+16)/1000;
    let bx=load64(b)/1000;
    let by=load64(b+8)/1000;
    let bz=load64(b+16)/1000;
    let cx=load64(c)/1000;
    let cy=load64(c+8)/1000;
    let cz=load64(c+16)/1000;
    return (ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx))/6000000;
}
fn cg_j_count(rows) {
    if !rows {
        return 0;
    }
    let count=0;
    let p=load64(rows+16);
    while p {
        count=count+1;
        p=load64(p+24);
    }
    return count;
}
fn cg_j_set(row,key,value) {
    let p=j_get(row,key);
    if p {
        store64(p,j_kind(value));
        store64(p+8,j_value(value));
        store64(p+16,load64(value+16));
        return row;
    }
    j_add(row,key,value);
    return row;
}
fn cg_j_text(row,key,value) {
    return cg_j_set(row,key,j_text(value));
}
fn cg_j_int(row,key,value) {
    return cg_j_set(row,key,j_number(value));
}
