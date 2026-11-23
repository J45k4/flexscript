import "model.flex";
global cg_mesh_vertices=0;
global cg_mesh_bins=0;
global cg_boundary_tree=0;
fn cg_vertex(v) {
    // Visit only cells that intersect the 100 nm weld range on each axis.
    let x=load64(v);let y=load64(v+8);let z=load64(v+16);
    let min_x=cg_cell(x-100);let max_x=cg_cell(x+100);
    let min_y=cg_cell(y-100);let max_y=cg_cell(y+100);
    let min_z=cg_cell(z-100);let max_z=cg_cell(z+100);
    let best=-1;let a=min_x;
    while a<=max_x && !cg_error {
        let b=min_y;
        while b<=max_y && !cg_error {
            let c=min_z;
            while c<=max_z && !cg_error {
                let p=load64(cg_mesh_bins+cg_bin(a,b,c)*8);
                while p && !cg_error {
                    if !cg_step() {return 0;}
                    let q=load64(p);let id=load64(p+8);
                    if cg_abs(load64(q)-x)<=100 && cg_abs(load64(q+8)-y)<=100 && cg_abs(load64(q+16)-z)<=100
                        && (best<0 || id<best) {best=id;}
                    p=load64(p+16);
                }
                c=c+1;
            }
            b=b+1;
        }
        a=a+1;
    }
    if best>=0 {return best;}
    let id=cg_count(cg_mesh_vertices);
    cg_push(cg_mesh_vertices,v);
    let bucket=cg_mesh_bins+cg_bin(cg_cell(x),cg_cell(y),cg_cell(z))*8;let entry=m_take(24);
    store64(entry,v);store64(entry+8,id);store64(entry+16,load64(bucket));store64(bucket,entry);
    return id;
}
// Boundary and edge-split vertices already point to canonical welded entries.
// Distinct entries are outside the weld tolerance, so only their bin is needed.
fn cg_welded_index(v) {
    let p=load64(cg_mesh_bins+cg_bin(cg_cell(load64(v)),cg_cell(load64(v+8)),cg_cell(load64(v+16)))*8);
    while p && !cg_error {
        if !cg_step() {return 0;}
        if load64(p)==v {return load64(p+8);}
        p=load64(p+16);
    }
    return cg_fail("Missing welded mesh vertex");
}
fn cg_cell(n) {if n<0 {return -((-n+127)/128);}return n/128;}
fn cg_bin(x,y,z) {return (x*73856093+y*19349663+z*83492791)&4095;}
fn cg_kd_select(points,low,high,middle,axis) {
    while low<high && !cg_error {
        let pivot=load64(cg_at(points,(low+high)/2)+axis*8);let i=low;let j=high;
        while i<=j && !cg_error {
            while i<=high && load64(cg_at(points,i)+axis*8)<pivot {if !cg_step() {return 0;}i=i+1;}
            while j>=low && load64(cg_at(points,j)+axis*8)>pivot {if !cg_step() {return 0;}j=j-1;}
            if i<=j {if !cg_step() {return 0;}let p=cg_at(points,i);let q=cg_at(points,j);store64(load64(points+16)+i*8,q);store64(load64(points+16)+j*8,p);i=i+1;j=j-1;}
        }
        if middle<=j {high=j;}else if middle>=i {low=i;}else {return 0;}
    }
    return 0;
}
fn cg_kd_build(points,low,high,depth) {
    if low>high || cg_error {return 0;}
    let middle=(low+high)/2;let axis=depth%3;cg_kd_select(points,low,high,middle,axis);
    if cg_error {return 0;}
    let node=m_take(32);store64(node,cg_at(points,middle));store64(node+8,axis);
    store64(node+16,cg_kd_build(points,low,middle-1,depth+1));store64(node+24,cg_kd_build(points,middle+1,high,depth+1));return node;
}
// Query fields are the expanded XYZ box, edge origin and delta, squared
// length, cross-product tolerance and output array. They are constant along
// the tree traversal for one edge.
fn cg_prepare_edge(query,a,b,splits) {
    let delta=cg_sub(b,a);let length=0;let margin=0;let axis=0;
    while axis<24 {
        let low=load64(a+axis);let high=load64(b+axis);
        if low>high {let swap=low;low=high;high=swap;}
        store64(query+axis,low-100);store64(query+24+axis,high+100);
        let span=high-low;length=length+span*span;
        if span>margin {margin=span;}
        axis=axis+8;
    }
    store64(query+48,a);store64(query+56,delta);store64(query+64,length);
    store64(query+72,margin*100);store64(query+80,splits);
    return 0;
}
fn cg_edge_query_prepared(node,query) {
    if !node || cg_error {return 0;}if !cg_step() {return 0;}
    let v=load64(node);let x=load64(v);let y=load64(v+8);let z=load64(v+16);
    if x>=load64(query) && x<=load64(query+24) && y>=load64(query+8) && y<=load64(query+32)
        && z>=load64(query+16) && z<=load64(query+40) {
        let d=cg_sub(v,load64(query+48));let delta=load64(query+56);
        let dot=load64(d)*load64(delta)+load64(d+8)*load64(delta+8)+load64(d+16)*load64(delta+16);
        if dot>0 && dot<load64(query+64) {
            let cross=cg_cross(delta,d);let tolerance=load64(query+72);
            if cg_abs(load64(cross))<=tolerance && cg_abs(load64(cross+8))<=tolerance && cg_abs(load64(cross+16))<=tolerance {
                let item=m_take(16);store64(item,dot);store64(item+8,v);cg_push(load64(query+80),item);
            }
        }
    }
    let axis=load64(node+8)*8;let pivot=load64(v+axis);
    if load64(query+axis)<=pivot {cg_edge_query_prepared(load64(node+16),query);}
    if load64(query+24+axis)>=pivot {cg_edge_query_prepared(load64(node+24),query);}
    return 0;
}
// Compatibility entry point used by existing Biscuit spatial programs.
fn cg_edge_query(node,a,b,delta,length,splits) {
    let query=m_take(88);cg_prepare_edge(query,a,b,splits);
    let margin=0;let axis=0;while axis<24 {
        let span=cg_abs(load64(delta+axis));if span>margin {margin=span;}axis=axis+8;
    }
    store64(query+56,delta);store64(query+64,length);store64(query+72,margin*100);
    return cg_edge_query_prepared(node,query);
}
fn cg_edges(vertices) {
    // Split polygon edges at all coincident vertices before triangulating; BSP
    // clipping otherwise leaves T-junctions in exported triangle meshes.
    let out=cg_array();let query=m_take(88);
    let i=0;
    while i<cg_count(vertices) && !cg_error {
        let a=cg_at(vertices,i);
        let b=cg_at(vertices,(i+1)%cg_count(vertices));
        cg_push(out,a);
        let splits=cg_array();
        cg_prepare_edge(query,a,b,splits);
        cg_edge_query_prepared(cg_boundary_tree,query);
        let k=0;
        while k<cg_count(splits) {
            let best=-1;
            let n=0;
            while n<cg_count(splits) {
                let item=cg_at(splits,n);
                if load64(item)>0 && (best<0 || load64(item)<load64(cg_at(splits,best))) {
                    best=n;
                }
                n=n+1;
            }
            if best>=0 {
                let item=cg_at(splits,best);
                cg_push(out,load64(item+8));
                store64(item,-1);
            }
            k=k+1;
        }
        i=i+1;
    }
    return out;
}
fn cg_edge_map() {
    let map=m_take(16);let bins=m_take(4096*8);let i=0;
    while i<4096 {store64(bins+i*8,0);i=i+1;}store64(map,bins);store64(map+8,0);return map;
}
fn cg_edge_count(edges,a,b) {
    let low=a;let high=b;let direction=1;
    if a>b {low=b;high=a;direction=-1;}
    let bucket=load64(edges)+((low*73856093+high*19349663)&4095)*8;let entry=load64(bucket);
    while entry {
        if !cg_step() {return 0;}
        if load64(entry)==low && load64(entry+8)==high {store64(entry+16,load64(entry+16)+1);store64(entry+24,load64(entry+24)+direction);return 0;}
        entry=load64(entry+32);
    }
    if !cg_step() {return 0;}
    entry=m_take(48);store64(entry,low);store64(entry+8,high);store64(entry+16,1);store64(entry+24,direction);
    store64(entry+32,load64(bucket));store64(bucket,entry);store64(entry+40,load64(edges+8));store64(edges+8,entry);return 0;
}
fn cg_edges_closed(edges) {
    let entry=load64(edges+8);
    while entry && !cg_error {
        if !cg_step() {return 0;}
        if load64(entry+16)!=2 || load64(entry+24)!=0 {return 0;}
        entry=load64(entry+40);
    }
    return !cg_error;
}
fn cg_mesh(source) {
    return cg_tessellate(cg_compile(source));
}
fn cg_tessellate(solids) {
    return cg_tessellate_faces(solids,0);
}
fn cg_tessellate_faces(solids,map_faces) {
    let output=j_object();
    if cg_error {
        cg_j_text(output,"error",cg_error);
        return output;
    }
    cg_mesh_vertices=cg_array();
    cg_mesh_bins=m_take(4096*8);let slot=0;
    while slot<4096 {store64(cg_mesh_bins+slot*8,0);slot=slot+1;}
    let normals=0;if map_faces {normals=cg_array();}
    let boundaries=cg_array();let seen=m_take(16000*8);slot=0;
    while slot<16000 {store64(seen+slot*8,0);slot=slot+1;}
    let i=0;
    while i<cg_count(solids) {
        let boundary=cg_array();cg_push(boundaries,boundary);
        let polygons=load64(cg_at(solids,i)+24);
        let directions=0;if normals {directions=cg_array();cg_push(normals,directions);}
        let j=0;
        while j<cg_count(polygons) {
            let polygon=cg_at(polygons,j);
            if directions {cg_push(directions,load64(polygon+8));}
            let verts=load64(polygon);
            let k=0;
            while k<cg_count(verts) {
                let index=cg_vertex(cg_at(verts,k));
                if cg_error {cg_j_text(output,"error",cg_error);return output;}
                if load64(seen+index*8)!=i+1 {store64(seen+index*8,i+1);cg_push(boundary,cg_at(cg_mesh_vertices,index));}
                store64(load64(verts+16)+k*8,cg_at(cg_mesh_vertices,index));
                k=k+1;
            }
            j=j+1;
        }
        let filtered=cg_array();
        j=0;
        while j<cg_count(polygons) {
            cg_push(filtered,cg_poly(load64(cg_at(polygons,j))));
            j=j+1;
        }
        store64(cg_at(solids,i)+24,filtered);
        i=i+1;
    }
    let parts=cg_json_array();
    let all_closed=1;
    i=0;
    let total_triangles=0;
    while i<cg_count(solids) && !cg_error {
        let solid=cg_at(solids,i);
        // Each part is an independent solid: other components' vertices cannot
        // introduce T junctions in this part's topology.
        let boundary=cg_at(boundaries,i);cg_boundary_tree=cg_kd_build(boundary,0,cg_count(boundary)-1,0);
        let polygons=load64(solid+24);
        let triangles=cg_json_array();let face_spans=0;let first_triangle=total_triangles;
        if normals {face_spans=cg_json_array();}
        let edges=cg_edge_map();
        let minimum=cg_v(500000001,500000001,500000001);
        let maximum=cg_v(-500000001,-500000001,-500000001);
        let volume=0;
        let j=0;
        while j<cg_count(polygons) && !cg_error {
            let prior=total_triangles;
            let verts=cg_edges(load64(cg_at(polygons,j)));
            let count=cg_count(verts);
            let sum=cg_v(0,0,0);
            let k=0;
            while k<count {
                let v=cg_at(verts,k);
                let axis=0;
                while axis<3 {
                    store64(sum+axis*8,load64(sum+axis*8)+load64(v+axis*8));
                    axis=axis+1;
                }
                k=k+1;
            }
            if count>=3 {
                let center=cg_v(load64(sum)/count,load64(sum+8)/count,load64(sum+16)/count);
                let ci=cg_vertex(center);
                k=0;
                while k<count && !cg_error {
                    let a=cg_at(verts,k);
                    let b=cg_at(verts,(k+1)%count);
                    // Only the zero-area test is needed here. Normalizing the
                    // cross product does not change whether it is zero.
                    let cross=cg_cross(cg_sub(a,center),cg_sub(b,center));
                    let ai=cg_welded_index(a);
                    let bi=cg_welded_index(b);
                    if (load64(cross) || load64(cross+8) || load64(cross+16)) && ai!=bi && ai!=ci && bi!=ci {
                        cg_json_push(triangles,j_number(ci));
                        cg_json_push(triangles,j_number(ai));
                        cg_json_push(triangles,j_number(bi));
                        cg_edge_count(edges,ci,ai);
                        cg_edge_count(edges,ai,bi);
                        cg_edge_count(edges,bi,ci);
                        volume=volume+cg_volume(center,a,b);
                        total_triangles=total_triangles+1;
                        if total_triangles>10000 {
                            cg_fail("Preview exceeds 10000 triangles; reduce design complexity");
                        }
                        let axis=0;
                        while axis<3 {
                            let val=load64(a+axis*8);
                            if val<load64(minimum+axis*8) {
                                store64(minimum+axis*8,val);
                            }
                            if val>load64(maximum+axis*8) {
                                store64(maximum+axis*8,val);
                            }
                            axis=axis+1;
                        }
                    }
                    k=k+1;
                }
            }
            if face_spans && total_triangles>prior && !cg_error {
                let span=cg_json_array();cg_json_push(span,j_number(total_triangles-first_triangle));
                let normal=cg_at(cg_at(normals,i),j);let axis=0;
                while axis<3 {
                    cg_json_push(span,cg_json_number(load64(normal+axis*8)/1000));axis=axis+1;
                }
                cg_json_push(face_spans,span);
            }
            j=j+1;
        }
        let closed=cg_edges_closed(edges);
        if volume<=0 {
            closed=0;
        }
        if !closed {
            all_closed=0;
        }
        let item=j_object();
        cg_j_text(item,"id",load64(solid));
        cg_j_text(item,"name",load64(solid+8));
        cg_j_text(item,"color",load64(solid+16));
        j_add(item,"triangles",triangles);
        if face_spans {j_add(item,"face_spans",face_spans);}
        cg_j_set(item,"closed",j_new(5,closed));
        j_add(item,"volume_mm3",cg_json_number(volume*1000));
        let bounds=cg_json_array();
        let lo=cg_json_array();
        let hi=cg_json_array();
        let axis=0;
        while axis<3 {
            cg_json_push(lo,cg_json_number(load64(minimum+axis*8)));
            cg_json_push(hi,cg_json_number(load64(maximum+axis*8)));
            axis=axis+1;
        }
        cg_json_push(bounds,lo);
        cg_json_push(bounds,hi);
        j_add(item,"bounds",bounds);
        cg_json_push(parts,item);
        i=i+1;
    }
    if cg_error {
        output=j_object();
        cg_j_text(output,"error",cg_error);
        return output;
    }
    let vertices=cg_json_array();
    i=0;
    while i<cg_count(cg_mesh_vertices) {
        let v=cg_at(cg_mesh_vertices,i);
        let point=cg_json_array();
        cg_json_push(point,cg_json_number(load64(v)));
        cg_json_push(point,cg_json_number(load64(v+8)));
        cg_json_push(point,cg_json_number(load64(v+16)));
        cg_json_push(vertices,point);
        i=i+1;
    }
    cg_j_int(output,"version",1);
    cg_j_text(output,"units","mm");
    cg_j_text(output,"geometry","tessellated CSG");
    cg_j_int(output,"triangles",total_triangles);
    cg_j_set(output,"closed",j_new(5,all_closed));
    j_add(output,"vertices",vertices);
    j_add(output,"parts",parts);
    return output;
}
fn cg_f32(n,d) {
    if !n {
        return 0;
    }
    let sign=0;
    if n<0 {
        sign=2147483648;
        n=-n;
    }
    let e=0;
    let divisor=d;
    if n>=d {
        while n>=divisor*2 {
            divisor=divisor*2;
            e=e+1;
        }
    }
    else {
        let value=n;
        while value<d {
            value=value*2;
            e=e-1;
        }
    }
    let shift=23-e;
    let numerator=n;
    divisor=d;
    if shift>=0 {
        numerator=n<<shift;
    }
    else {
        divisor=d<<(-shift);
    }
    let mantissa=(numerator+divisor/2)/divisor;
    if mantissa>=16777216 {
        mantissa=mantissa/2;
        e=e+1;
    }
    return sign|((e+127)<<23)|(mantissa&8388607);
}
fn cg_put32(p,n) {
    store8(p,n&255);
    store8(p+1,(n>>8)&255);
    store8(p+2,(n>>16)&255);
    store8(p+3,(n>>24)&255);
    return 0;
}
// Validate again after binary STL float32 quantization. Native nanometre
// vertices can collapse at large coordinates; never export a broken mesh.
fn cg_f32_nm(bits) {
    if !(bits&2147483647) {
        return 0;
    }
    let exponent=((bits>>23)&255)-127;
    let numerator=((bits&8388607)|8388608)*1000000;
    let divisor=1<<(23-exponent);
    let value=(numerator+divisor/2)/divisor;
    if bits&2147483648 {
        value=-value;
    }
    return value;
}
fn cg_stl_valid(mesh) {
    let map=j_object();
    let ids=cg_array();
    let points=cg_array();
    let i=0;
    let next=0;
    while i<cg_count(cg_mesh_vertices) && !cg_error {
        if !cg_step() {
            return 0;
        }
        let v=cg_at(cg_mesh_vertices,i);
        let x=cg_f32(load64(v),1000000);
        let y=cg_f32(load64(v+8),1000000);
        let z=cg_f32(load64(v+16),1000000);
        let key=m_cat(m_int(x),m_cat(":",m_cat(m_int(y),m_cat(":",m_int(z)))));
        let found=j_get(map,key);
        let id=next;
        if found {
            id=j_value(found);
        }
        else {
            j_add(map,key,j_number(next));
            next=next+1;
        }
        let p=m_take(8);
        store64(p,id);
        cg_push(ids,p);
        cg_push(points,cg_v(cg_f32_nm(x),cg_f32_nm(y),cg_f32_nm(z)));
        i=i+1;
    }
    let part=load64(j_get(mesh,"parts")+16);
    while part && !cg_error {
        let edges=cg_edge_map();
        let triangle=load64(j_get(part,"triangles")+16);
        while triangle && !cg_error {
            if !cg_step() {
                return 0;
            }
            let ai=j_value(triangle);
            triangle=load64(triangle+24);
            let bi=j_value(triangle);
            triangle=load64(triangle+24);
            let ci=j_value(triangle);
            triangle=load64(triangle+24);
            let a=cg_at(points,ai);
            let b=cg_at(points,bi);
            let c=cg_at(points,ci);
            if !cg_normal(cg_cross(cg_sub(b,a),cg_sub(c,a))) {
                return 0;
            }
            let x=load64(cg_at(ids,ai));
            let y=load64(cg_at(ids,bi));
            let z=load64(cg_at(ids,ci));
            if x==y || x==z || y==z {
                return 0;
            }
            cg_edge_count(edges,x,y);
            cg_edge_count(edges,y,z);
            cg_edge_count(edges,z,x);
        }
        if !cg_edges_closed(edges) {return 0;}
        part=load64(part+24);
    }
    return !cg_error;
}
fn cg_stl(mesh) {
    if !j_value(j_get(mesh,"closed")) || !cg_stl_valid(mesh) {
        return 0;
    }
    let size=84+j_integer(mesh,"triangles")*50;
    let bytes=m_take(size);
    let i=0;
    while i<size {
        store8(bytes+i,0);
        i=i+1;
    }
    let header="Biscuit native Flexscript CAD; tessellated CSG; units millimetres";
    i=0;
    while load8(header+i) {
        store8(bytes+i,load8(header+i));
        i=i+1;
    }
    cg_put32(bytes+80,j_integer(mesh,"triangles"));
    let at=84;
    let part=load64(j_get(mesh,"parts")+16);
    while part {
        let triangle=load64(j_get(part,"triangles")+16);
        while triangle {
            let a=cg_at(cg_mesh_vertices,j_value(triangle));
            triangle=load64(triangle+24);
            let b=cg_at(cg_mesh_vertices,j_value(triangle));
            triangle=load64(triangle+24);
            let c=cg_at(cg_mesh_vertices,j_value(triangle));
            triangle=load64(triangle+24);
            let normal=cg_normal(cg_cross(cg_sub(b,a),cg_sub(c,a)));
            if !normal {
                return 0;
            }
            let axis=0;
            while axis<3 {
                cg_put32(bytes+at+axis*4,cg_f32(load64(normal+axis*8),1000000000));
                cg_put32(bytes+at+12+axis*4,cg_f32(load64(a+axis*8),1000000));
                cg_put32(bytes+at+24+axis*4,cg_f32(load64(b+axis*8),1000000));
                cg_put32(bytes+at+36+axis*4,cg_f32(load64(c+axis*8),1000000));
                axis=axis+1;
            }
            at=at+50;
        }
        part=load64(part+24);
    }
    let result=m_take(16);
    store64(result,bytes);
    store64(result+8,size);
    return result;
}
