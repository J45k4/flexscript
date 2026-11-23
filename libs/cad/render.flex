// Deterministic orthographic CAD snapshots with RGB24 pixels and a depth buffer.
import "math.flex";

fn cr_at(values,index) {return values+index*24;}
fn cr_edge(a,b,x,y) {
    return (x-load64(a))*(load64(b+8)-load64(a+8))-(y-load64(a+8))*(load64(b)-load64(a));
}
fn cr_channel(color,shift,shade) {return (((color>>shift)&255)*shade/255)<<shift;}
fn cr_color(text) {
    if !text || load8(text)!=35 {return -1;}
    let color=0;let i=1;
    while i<7 {
        let digit=j_hex(load8(text+i));if digit<0 {return -1;}
        color=(color<<4)|digit;i=i+1;
    }
    if load8(text+7) {return -1;}
    return color;
}

fn cr_project(vertices,world,projected,width,height,view) {
    let count=0;let row=load64(vertices+16);
    let min_x=2000000;let min_y=2000000;let max_x=-2000000;let max_y=-2000000;
    while row {
        if count>=8000 {return cg_fail("Render vertex limit");}
        if j_kind(row)!=3 {return cg_fail("Invalid render vertex");}
        let x_node=load64(row+16);if !x_node {return cg_fail("Render vertex requires three coordinates");}
        let y_node=load64(x_node+24);if !y_node {return cg_fail("Render vertex requires three coordinates");}
        let z_node=load64(y_node+24);
        if !z_node || load64(z_node+24) {return cg_fail("Render vertex requires three coordinates");}
        let x=cg_number(x_node)/1000;let y=cg_number(y_node)/1000;let z=cg_number(z_node)/1000;
        if cg_error {return 0;}
        let sx=(x-y)*707/1000;let sy=(x+y-2*z)*408/1000;let depth=x+y+z;
        if view==1 {sx=x;sy=-y;depth=z;}
        else if view==2 {sx=x;sy=-z;depth=-y;}
        else if view==3 {sx=y;sy=-z;depth=x;}
        let pv=cr_at(projected,count);store64(pv,sx);store64(pv+8,sy);store64(pv+16,depth);
        let wv=cr_at(world,count);store64(wv,x);store64(wv+8,y);store64(wv+16,z);
        if sx<min_x {min_x=sx;}if sx>max_x {max_x=sx;}
        if sy<min_y {min_y=sy;}if sy>max_y {max_y=sy;}
        count=count+1;row=load64(row+24);
    }
    if count<3 {return cg_fail("Cannot render an invalid/empty CAD mesh");}
    let span_x=max_x-min_x;let span_y=max_y-min_y;let scale=1000000000;
    if span_x>0 {scale=(width-16)*16000000/span_x;}
    if span_y>0 && (height-16)*16000000/span_y<scale {scale=(height-16)*16000000/span_y;}
    let i=0;
    while i<count {
        let v=cr_at(projected,i);
        store64(v,(load64(v)-(min_x+max_x)/2)*scale/1000000+width*8);
        store64(v+8,(load64(v+8)-(min_y+max_y)/2)*scale/1000000+height*8);
        i=i+1;
    }
    return count;
}

fn cr_shade(a,b,c,color) {
    let normal=cg_cross(cg_sub(b,a),cg_sub(c,a));
    let nx=load64(normal);let ny=load64(normal+8);let nz=load64(normal+16);
    let norm=cg_abs(nx)+cg_abs(ny)+cg_abs(nz);let shade=160;
    if norm {shade=90+165*cg_abs(nx-2*ny+3*nz)/(norm*3);}
    return cr_channel(color,16,shade)|cr_channel(color,8,shade)|cr_channel(color,0,shade);
}

// Picture fields are pixel width, height, RGB24 buffer and signed depths.
fn cr_triangle(picture,projected,world,ia,ib,ic,color) {
    let a=cr_at(projected,ia);let b=cr_at(projected,ib);let c=cr_at(projected,ic);
    let area=cr_edge(a,b,load64(c),load64(c+8));
    if !area {return 0;}
    let width=load64(picture);let height=load64(picture+8);
    let pixels=load64(picture+16);let zbuffer=load64(picture+24);
    let paint=cr_shade(cr_at(world,ia),cr_at(world,ib),cr_at(world,ic),color);
    let left=load64(a);let right=left;let top=load64(a+8);let bottom=top;let i=1;
    while i<3 {
        let v=b;if i==2 {v=c;}
        let x=load64(v);let y=load64(v+8);
        if x<left {left=x;}if x>right {right=x;}
        if y<top {top=y;}if y>bottom {bottom=y;}
        i=i+1;
    }
    left=left/16;right=right/16;top=top/16;bottom=bottom/16;
    if left<0 {left=0;}if top<0 {top=0;}
    if right>=width {right=width-1;}if bottom>=height {bottom=height-1;}

    // Each horizontal step advances the three barycentric numerators by fixed amounts.
    let du=(load64(c+8)-load64(b+8))*16;
    let dv=(load64(a+8)-load64(c+8))*16;
    let dw=(load64(b+8)-load64(a+8))*16;
    let za=load64(a+16);let zb=load64(b+16);let zc=load64(c+16);
    let dz=du*za+dv*zb+dw*zc;
    let red=(paint>>16)&255;let green=(paint>>8)&255;let blue=paint&255;
    let y=top;
    while y<=bottom {
        let x=left;
        let u=cr_edge(b,c,x*16+8,y*16+8);let v=cr_edge(c,a,x*16+8,y*16+8);
        let w=cr_edge(a,b,x*16+8,y*16+8);let z=u*za+v*zb+w*zc;
        while x<=right {
            if (area>0 && u>=0 && v>=0 && w>=0) || (area<0 && u<=0 && v<=0 && w<=0) {
                let depth=z/area;let offset=y*width+x;let at=zbuffer+offset*8;
                if depth>=load64(at) {
                    store64(at,depth);
                    let pixel=pixels+offset*3;store8(pixel,red);store8(pixel+1,green);store8(pixel+2,blue);
                }
            }
            u=u+du;v=v+dv;w=w+dw;z=z+dz;x=x+1;
        }
        y=y+1;
    }
    return 1;
}

fn cr_parts(picture,parts,projected,world,vertices) {
    let triangles=0;let count=0;let part=load64(parts+16);
    while part {
        if count>=16000 {return cg_fail("Render part limit");}
        let color=cr_color(j_string(part,"color"));if color<0 {return cg_fail("Invalid CAD render color");}
        let indices=j_get(part,"triangles");
        if j_kind(indices)!=3 {return cg_fail("CAD render triangles must be an array");}
        let index=load64(indices+16);
        while index {
            if triangles>=10000 {return cg_fail("Render triangle limit");}
            let a=index;let b=load64(a+24);
            if !b {return cg_fail("Incomplete CAD render triangle");}
            let c=load64(b+24);
            if !c {return cg_fail("Incomplete CAD render triangle");}
            let ia=j_value(a);let ib=j_value(b);let ic=j_value(c);
            if j_kind(a)!=1 || j_kind(b)!=1 || j_kind(c)!=1 || ia<0 || ia>=vertices ||
                ib<0 || ib>=vertices || ic<0 || ic>=vertices {return cg_fail("Invalid render triangle index");}
            cr_triangle(picture,projected,world,ia,ib,ic,color);
            triangles=triangles+1;index=load64(c+24);
        }
        count=count+1;part=load64(part+24);
    }
    if !triangles {return cg_fail("Cannot render an invalid/empty CAD mesh");}
    return 1;
}

// Return width*height*3 row-major RGB bytes from a mesh with vertices and colored
// parts. The pixels are arena-owned. Failure returns zero and sets cg_error.
fn cad_render_rgb(mesh,width,height,view) {
    cg_begin();
    if width<16 || width>512 || height<16 || height>512 {return cg_fail("Render edges must be 16..512 pixels");}
    let mode=0;
    if m_eq(view,"top") {mode=1;}
    else if m_eq(view,"front") {mode=2;}
    else if m_eq(view,"right") {mode=3;}
    else if !m_eq(view,"iso") {return cg_fail("View must be iso, top, front or right");}
    let vertices=j_get(mesh,"vertices");let parts=j_get(mesh,"parts");
    if j_get(mesh,"error") || j_kind(vertices)!=3 || j_kind(parts)!=3 {
        return cg_fail("Cannot render an invalid/empty CAD mesh");
    }
    let projected=m_take(8000*24);let world=m_take(8000*24);
    let vertex_count=cr_project(vertices,world,projected,width,height,mode);
    if !vertex_count {return 0;}
    let size=width*height;let pixels=m_take(size*3);let zbuffer=m_take(size*8);
    let i=0;
    while i<size {
        store8(pixels+i*3,247);store8(pixels+i*3+1,247);store8(pixels+i*3+2,242);
        store64(zbuffer+i*8,-4000000);i=i+1;
    }
    let picture=m_take(32);store64(picture,width);store64(picture+8,height);
    store64(picture+16,pixels);store64(picture+24,zbuffer);
    if !cr_parts(picture,parts,projected,world,vertex_count) {return 0;}
    return pixels;
}
