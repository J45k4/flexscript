import "math.flex";
fn cg_box(size) {
    return cg_box_bounds(cg_v(0,0,0),size);
}
fn cg_box_bounds(minimum,maximum) {
    let x0=load64(minimum);let y0=load64(minimum+8);let z0=load64(minimum+16);
    let x1=load64(maximum);let y1=load64(maximum+8);let z1=load64(maximum+16);
    let out=cg_array();
    if x1-x0<10000 || y1-y0<10000 || z1-z0<10000 {
        cg_fail("Box dimensions must be at least 0.01 mm");
        return out;
    }
    let a=cg_v(x0,y0,z0);
    let b=cg_v(x1,y0,z0);
    let c=cg_v(x1,y1,z0);
    let d=cg_v(x0,y1,z0);
    let e=cg_v(x0,y0,z1);
    let f=cg_v(x1,y0,z1);
    let g=cg_v(x1,y1,z1);
    let h=cg_v(x0,y1,z1);
    cg_face(out,a,d,c,b);
    cg_face(out,e,f,g,h);
    cg_face(out,a,b,f,e);
    cg_face(out,b,c,g,f);
    cg_face(out,c,d,h,g);
    cg_face(out,d,a,e,h);
    return out;
}
fn cg_cylinder(radius,height,segments) {
    let out=cg_array();
    if radius<10000 || height<10000 {
        cg_fail("Cylinder radius and height must be at least 0.01 mm");
        return out;
    }
    let bottom=cg_array();let top=cg_array();let sides=cg_array();
    let i=0;
    while i<segments {
        let a=i*360000/segments;
        let b=(i+1)*360000/segments;
        let p=cg_v(radius*cg_cos(a)/1000000,radius*cg_sin(a)/1000000,0);
        let q=cg_v(radius*cg_cos(b)/1000000,radius*cg_sin(b)/1000000,0);
        let r=cg_v(load64(q),load64(q+8),height);
        let s=cg_v(load64(p),load64(p+8),height);
        cg_push(bottom,p);cg_push(top,s);
        cg_face(sides,p,q,r,s);
        i=i+1;
    }
    // Convex caps are single polygons. A triangle fan here multiplies BSP
    // splitters and is triangulated again at the mesh boundary.
    let cap=cg_poly(bottom);cg_flip(cap);cg_push(out,cap);cg_push(out,cg_poly(top));cg_join(out,sides);
    return out;
}
fn cg_sphere_point(radius,longitude,latitude) {
    let ring=radius*cg_cos(latitude)/1000000;
    return cg_v(ring*cg_cos(longitude)/1000000,ring*cg_sin(longitude)/1000000,radius*cg_sin(latitude)/1000000);
}
fn cg_sphere(radius,segments) {
    let out=cg_array();
    if radius<10000 {
        cg_fail("Sphere radius must be at least 0.01 mm");
        return out;
    }
    let bands=segments/2;
    let i=0;
    while i<bands {
        let low=-90000+i*180000/bands;
        let high=-90000+(i+1)*180000/bands;
        let j=0;
        while j<segments {
            let a=j*360000/segments;
            let b=(j+1)*360000/segments;
            let p=cg_sphere_point(radius,a,low);
            let q=cg_sphere_point(radius,b,low);
            let r=cg_sphere_point(radius,b,high);
            let s=cg_sphere_point(radius,a,high);
            if i==0 {
                cg_face(out,p,r,s,0);
            }
            else if i==bands-1 {
                cg_face(out,p,q,r,0);
            }
            else {
                cg_face(out,p,q,r,s);
            }
            j=j+1;
        }
        i=i+1;
    }
    return out;
}
fn cg_transform_point(point,offset,angles) {
    let x=load64(point);
    let y=load64(point+8);
    let z=load64(point+16);
    let a=load64(angles)/1000;
    let b=load64(angles+8)/1000;
    let c=load64(angles+16)/1000;
    let yy=(y*cg_cos(a)-z*cg_sin(a))/1000000;
    z=(y*cg_sin(a)+z*cg_cos(a))/1000000;
    y=yy;
    let xx=(x*cg_cos(b)+z*cg_sin(b))/1000000;
    z=(-x*cg_sin(b)+z*cg_cos(b))/1000000;
    x=xx;
    xx=(x*cg_cos(c)-y*cg_sin(c))/1000000;
    y=(x*cg_sin(c)+y*cg_cos(c))/1000000;
    x=xx;
    x=x+load64(offset);
    y=y+load64(offset+8);
    z=z+load64(offset+16);
    if cg_abs(x)>500000000 || cg_abs(y)>500000000 || cg_abs(z)>500000000 {
        cg_fail("Transformed CAD coordinates exceed +/-500 mm");
    }
    return cg_v(x,y,z);
}
fn cg_transform(polys,offset,angles) {
    let out=cg_array();
    let i=0;
    while i<cg_count(polys) && !cg_error {
        let original=load64(cg_at(polys,i));
        let vertices=cg_array();
        let j=0;
        while j<cg_count(original) {
            cg_push(vertices,cg_transform_point(cg_at(original,j),offset,angles));
            j=j+1;
        }
        cg_push(out,cg_poly(vertices));
        i=i+1;
    }
    return out;
}
