// Free-placement v4 mate solver. Distances are millimetres, rotations radians.
// A fasten-connected group moves as a rigid body about its initial mean origin.
import "least-squares.flex";
import "../../lib/f64-math.flex";
import "assembly.flex";

global PC_FASTEN=0;
global PC_SERVO=1;
global PC_REVOLUTE=2;
global PC_PRISMATIC=3;
global PC_PLANAR=4;
global PC_BALL=5;

fn pf_identity() {
    let t=ls_zero(12);store64(t,0x3ff0000000000000);store64(t+32,0x3ff0000000000000);store64(t+64,0x3ff0000000000000);return t;
}
fn pf_from_cad(t) {
    let out=m_take(96);let k=0;
    while k<96 {store64(out+k,f64_div(f64_from_i64(load64(t+k)),f64_from_i64(1000000)));k=k+8;}
    return out;
}
// Free degrees of freedom are sensitive to rounding in connector rotations.
// Keep saved frames in binary64 until converting the final mesh placement.
fn pf_frame(row,position) {
    let r=pc_pose_vector(j_get(row,"rotation"),0);let p=pc_pose_vector(j_get(row,position),0);
    let x=pc_radians(load64(r));let y=pc_radians(load64(r+8));let z=pc_radians(load64(r+16));
    let a=f64_cos(x);let b=f64_sin(x);let c=f64_cos(y);let d=f64_sin(y);let e=f64_cos(z);let f=f64_sin(z);
    let ae=f64_mul(a,e);let af=f64_mul(a,f);let be=f64_mul(b,e);let bf=f64_mul(b,f);let out=m_take(96);
    store64(out,f64_mul(c,e));store64(out+8,f64_math_neg(f64_mul(c,f)));store64(out+16,d);
    store64(out+24,f64_add(af,f64_mul(be,d)));store64(out+32,f64_sub(ae,f64_mul(bf,d)));store64(out+40,f64_math_neg(f64_mul(b,c)));
    store64(out+48,f64_sub(bf,f64_mul(ae,d)));store64(out+56,f64_add(be,f64_mul(af,d)));store64(out+64,f64_mul(a,c));
    let k=0;while k<24 {store64(out+72+k,f64_div(f64_from_i64(load64(p+k)),f64_from_i64(1000000)));k=k+8;}
    return out;
}
fn pf_start(row) {
    if load64(row+72)==load64(row+24) {return pf_frame(j_get(load64(row+8),"transform"),"translation");}
    return pf_from_cad(load64(row+24));
}
fn pf_product(a,b,out) {
    let i=0;
    while i<3 {
        let j=0;
        while j<4 {
            let offset=j*8;let step=24;let dest=(i*3+j)*8;let sum=0;
            if j==3 {offset=72;step=8;dest=72+i*8;sum=load64(a+dest);}
            let k=0;
            while k<3 {
                sum=f64_add(sum,f64_mul(load64(a+(i*3+k)*8),load64(b+offset+k*step)));k=k+1;
            }
            store64(out+dest,sum);j=j+1;
        }
        i=i+1;
    }
    return out;
}
fn pf_root(row) {
    let root=row;while load64(root+56)!=root {root=load64(root+56);}
    store64(row+56,root);return root;
}
// Group record: parameter offset, pivot, current and tentative motions, member count.
fn pf_group(row) {
    let root=pf_root(row);let group=load64(root+64);
    if !group {
        group=m_take(40);store64(group,-1);store64(group+8,ls_zero(3));store64(group+16,pf_identity());
        store64(group+24,pf_identity());store64(group+32,0);store64(root+64,group);
    }
    return group;
}
fn pf_groups(instances,world,links) {
    let i=0;
    while i<cg_count(links) {
        let link=cg_at(links,i);
        if !load64(link+32) {let a=pf_root(load64(link));let b=pf_root(load64(link+8));store64(a+56,b);}
        i=i+1;
    }
    let ground=pf_group(world);let first=pf_group(cg_at(instances,0));
    i=0;while i<cg_count(instances) {
        let row=cg_at(instances,i);let group=pf_group(row);let pivot=load64(group+8);let k=0;
        while k<24 {store64(pivot+k,f64_add(load64(pivot+k),f64_from_i64(load64(load64(row+24)+72+k))));k=k+8;}
        store64(group+32,load64(group+32)+1);i=i+1;
    }
    let free=cg_array();i=0;
    while i<cg_count(links) && !cg_error {
        let link=cg_at(links,i);let side=0;
        while load64(link+32) && side<2 {
            let group=pf_group(load64(link+side*8));
            if group!=ground && group!=first && !pc_unscaled(load64(link+side*8)) {return cg_fail("Moving mates require unscaled instances");}
            if group!=ground && group!=first && load64(group)<0 {
                store64(group,cg_count(free)*6);cg_push(free,group);let k=0;let pivot=load64(group+8);
                while k<24 {
                    store64(pivot+k,f64_div(load64(pivot+k),f64_from_i64(1000000*load64(group+32))));k=k+8;
                }
            }
            side=side+1;
        }
        i=i+1;
    }
    return free;
}
// Store each connector in world coordinates at the start of the solve.
// One motion matrix per group moves every attached connector and part.
fn pf_constraints(links) {
    let out=cg_array();let i=0;
    while i<cg_count(links) && !cg_error {
        let link=cg_at(links,i);let kind=load64(link+32);
        if kind {
            let c=m_take(40);store64(c,kind);let side=0;
            while side<2 {
                let row=load64(link+side*8);store64(c+8+side*8,pf_group(row));
                let f=pf_frame(load64(link+40+side*8),"position");let pose=pf_start(row);
                if !side && kind==PC_SERVO {f=pf_product(f,pf_from_cad(load64(link+56)),m_take(96));}
                store64(c+24+side*8,pf_product(pose,f,m_take(96)));side=side+1;
            }
            cg_push(out,c);
        }
        i=i+1;
    }
    return out;
}
fn pf_residual(kind,a,b,out) {
    let at=0;let i=0;
    if kind==PC_SERVO || kind==PC_REVOLUTE || kind==PC_BALL {
        while i<3 {store64(out+at,f64_sub(load64(b+72+i*8),load64(a+72+i*8)));at=at+8;i=i+1;}
    }
    if kind!=PC_BALL {
        let axis=2;
        while axis>=0 {
            i=0;while i<3 {
                let k=(i*3+axis)*8;store64(out+at,f64_sub(load64(b+k),load64(a+k)));at=at+8;i=i+1;
            }
            if axis==2 && (kind==PC_PRISMATIC || kind==PC_SERVO) {axis=0;}else {axis=-1;}
        }
    }
    if kind==PC_PRISMATIC || kind==PC_PLANAR {
        let axis=0;if kind==PC_PLANAR {axis=2;}
        let last=1;if kind==PC_PLANAR {last=2;}
        while axis<=last {
            let dot=0;i=0;while i<3 {
                let d=f64_sub(load64(b+72+i*8),load64(a+72+i*8));
                dot=f64_add(dot,f64_mul(d,load64(a+(i*3+axis)*8)));i=i+1;
            }
            store64(out+at,dot);at=at+8;axis=axis+1;
        }
    }
    return at/8;
}
// Numeric Jacobian about the same world-space pivots as the accepted update.
// A single-axis probe only changes the other two rows of the connector frame.
fn pf_probe(frame,pivot,param,out) {
    let h=0x3e7ad7f29abcaf48; // 1e-7
    m_copy(out,frame,96);
    if param>=3 {let k=72+(param-3)*8;store64(out+k,f64_add(load64(frame+k),h));return out;}
    let u=(param+1)%3;let v=(param+2)%3;let j=0;
    let cm1=0xbcf6800000000000; // cos(h) - 1
    while j<4 {
        let ku=(u*3+j)*8;let kv=(v*3+j)*8;let cu=0;let cv=0;
        if j==3 {ku=72+u*8;kv=72+v*8;cu=load64(pivot+u*8);cv=load64(pivot+v*8);}
        let x=f64_sub(load64(frame+ku),cu);let y=f64_sub(load64(frame+kv),cv);
        store64(out+ku,f64_add(load64(frame+ku),f64_sub(f64_mul(cm1,x),f64_mul(h,y))));
        store64(out+kv,f64_add(load64(frame+kv),f64_add(f64_mul(cm1,y),f64_mul(h,x))));j=j+1;
    }
    return out;
}
fn pf_linearize(c,a,b,r,count,normal,rhs,n,scratch) {
    let jac=scratch;let cols=scratch+12*9*8;let ap=cols+96;let bp=ap+96;let rp=bp+96;
    let sides=0;let side=0;
    while side<2 {
        let group=load64(c+8+side*8);let offset=load64(group);
        if offset>=0 && (side==0 || group!=load64(c+8)) {
            let p=0;
            while p<6 {
                let col=sides*6+p;store64(cols+col*8,offset+p);let aa=a;let bb=b;
                if group==load64(c+8) {aa=pf_probe(a,load64(group+8),p,ap);}
                if group==load64(c+16) {bb=pf_probe(b,load64(group+8),p,bp);}
                pf_residual(load64(c),aa,bb,rp);let j=0;
                while j<count {
                    store64(jac+(col*9+j)*8,f64_div(f64_sub(load64(rp+j*8),load64(r+j*8)),0x3e7ad7f29abcaf48));j=j+1;
                }
                p=p+1;
            }
            sides=sides+1;
        }
        side=side+1;
    }
    let i=0;
    while i<sides*6 {
        let row=load64(cols+i*8);let j=0;let bsum=load64(rhs+row*8);
        while j<count {bsum=f64_sub(bsum,f64_mul(load64(jac+(i*9+j)*8),load64(r+j*8)));j=j+1;}
        store64(rhs+row*8,bsum);let col=0;
        while col<=i {
            if !cg_step() {return 0;}
            let column=load64(cols+col*8);let cell=normal+(row*n+column)*8;let sum=load64(cell);j=0;
            while j<count {sum=f64_add(sum,f64_mul(load64(jac+(i*9+j)*8),load64(jac+(col*9+j)*8)));j=j+1;}
            store64(cell,sum);store64(normal+(column*n+row)*8,sum);col=col+1;
        }
        i=i+1;
    }
    return 1;
}
fn pf_measure(constraints,slot,normal,rhs,n,score,work) {
    let r=work;let a=r+72;let b=a+96;let scratch=b+96;
    let sum=0;let worst=0;let i=0;
    while i<cg_count(constraints) && !cg_error {
        if !cg_step() {return 0;}
        let c=cg_at(constraints,i);
        pf_product(load64(load64(c+8)+slot),load64(c+24),a);
        pf_product(load64(load64(c+16)+slot),load64(c+32),b);
        let count=pf_residual(load64(c),a,b,r);let j=0;
        while j<count {let v=load64(r+j*8);if f64_magnitude(v)>worst {worst=f64_magnitude(v);}sum=f64_add(sum,f64_mul(v,v));j=j+1;}
        if normal {pf_linearize(c,a,b,r,count,normal,rhs,n,scratch);}
        i=i+1;
    }
    store64(score,sum);store64(score+8,worst);return !cg_error;
}
// Rodrigues rotation and translation of one rigid group about its fixed pivot.
fn pf_trial(group,step,work) {
    let w=step+8*load64(group);let sum=0;let i=0;
    while i<3 {let v=load64(w+i*8);sum=f64_add(sum,f64_mul(v,v));i=i+1;}
    let angle=f64_sqrt(sum);if !f64_is_finite(angle) || !f64_trig_supported(angle) {return 0;}
    let motion=ls_clear(work,12);let one=0x3ff0000000000000;
    store64(motion,one);store64(motion+32,one);store64(motion+64,one);
    if angle>=0x3cd203af9ee75616 {
        let axis=work+96;i=0;
        while i<3 {store64(axis+i*8,f64_div(load64(w+i*8),angle));i=i+1;}
        let sine=f64_sin(angle);let cosine=f64_cos(angle);let t=f64_sub(one,cosine);i=0;
        while i<3 {
            let j=0;while j<3 {
                let val=f64_mul(t,f64_mul(load64(axis+i*8),load64(axis+j*8)));
                if i==j {val=f64_add(val,cosine);}
                else {
                    let skew=f64_mul(sine,load64(axis+(3-i-j)*8));
                    if j==(i+1)%3 {val=f64_sub(val,skew);}else {val=f64_add(val,skew);}
                }
                store64(motion+(i*3+j)*8,val);j=j+1;
            }
            i=i+1;
        }
    }
    let pivot=load64(group+8);i=0;
    while i<3 {
        let rotated=0;let j=0;
        while j<3 {rotated=f64_add(rotated,f64_mul(load64(motion+(i*3+j)*8),load64(pivot+j*8)));j=j+1;}
        store64(motion+72+i*8,f64_add(f64_sub(load64(pivot+i*8),rotated),load64(w+24+i*8)));i=i+1;
    }
    pf_product(motion,load64(group+16),load64(group+24));return 1;
}
fn pf_solve(instances,world,links) {
    let groups=pf_groups(instances,world,links);if cg_error {return 0;}
    let constraints=pf_constraints(links);
    let n=cg_count(groups)*6;let score=m_take(16);let candidate=m_take(16);
    let work=m_take(1488);pf_measure(constraints,16,0,0,n,score,work);
    let lambda=0x3eb0c6f7a0b5ed8d;let round=0;let improved=1;
    let normal=0;let rhs=0;let step=0;let matrix=0;
    while n && improved && round<200 && !cg_error && load64(score+8)>0x3e112e0be826d695 {
        // The arena's single-allocation limit also bounds the dense workspace.
        if n*(n+1)*8>=16777216 {return cg_fail("Assembly solver workspace exceeds geometry budget");}
        if !normal {normal=m_take(n*n*8);rhs=m_take(n*8);step=m_take(n*8);matrix=m_take(n*(n+1)*8);}
        ls_clear(normal,n*n);ls_clear(rhs,n);
        pf_measure(constraints,16,normal,rhs,n,score,work);
        improved=0;let trial=0;
        while trial<12 && !improved && !cg_error {
            let valid=ls_step(normal,rhs,n,lambda,step,matrix);let i=0;
            while valid && i<cg_count(groups) {valid=pf_trial(cg_at(groups,i),step,work);i=i+1;}
            if valid && pf_measure(constraints,24,0,0,n,candidate,work) && f64_lt(load64(candidate),load64(score)) {
                i=0;while i<cg_count(groups) {
                    let group=cg_at(groups,i);m_copy(load64(group+16),load64(group+24),96);i=i+1;
                }
                improved=1;m_copy(score,candidate,16);lambda=f64_mul(lambda,0x3fd3333333333333);
                if lambda<0x3d719799812dea11 {lambda=0x3d719799812dea11;}
            }else {lambda=f64_mul(lambda,0x4024000000000000);}
            trial=trial+1;
        }
        round=round+1;
    }
    if cg_error {return 0;}
    if load64(score+8)>0x3f1a36e2eb1c432d {return cg_fail("Conflicting assembly mates");}
    let i=0;
    while i<cg_count(instances) {
        let row=cg_at(instances,i);let group=pf_group(row);
        if load64(group)>=0 {
            let pose=load64(row+24);let placed=pf_product(load64(group+16),pf_start(row),m_take(96));
            let k=0;while k<96 {
                let value=f64_to_i64_round(f64_mul(load64(placed+k),f64_from_i64(1000000)));
                if k>=72 && (value>500000000 || value< -500000000) {return cg_fail("Assembly pose exceeds +/-500 mm");}
                store64(pose+k,value);k=k+8;
            }
        }
        i=i+1;
    }
    return 1;
}
