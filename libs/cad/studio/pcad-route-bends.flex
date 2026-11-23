// Circular fillets in 3D. Coordinates and radii use CAD's millionths of a mm;
// unit directions use billionths and angles use thousandths of a degree.
fn pcr_direction(delta) {
    let x=load64(delta);let y=load64(delta+8);let z=load64(delta+16);
    let largest=cg_abs(x);
    if cg_abs(y)>largest {largest=cg_abs(y);}
    if cg_abs(z)>largest {largest=cg_abs(z);}
    if !largest {return 0;}
    let scale=1000000000/largest;
    return cg_normal(cg_v(x*scale,y*scale,z*scale));
}

fn pcr_turn(dot,sine) {
    if !dot {return 90000;}
    let low=0;let high=90000;let cosine=cg_abs(dot);
    while low<high {
        let angle=(low+high)/2;
        if cg_sin(angle)*cosine<cg_cos(angle)*sine {low=angle+1;}
        else {high=angle;}
    }
    if dot<0 {return 180000-low;}
    return low;
}

fn pcr_path_point(path,point,padding) {
    let points=load64(path);let count=cg_count(points);
    if count && !pcl_norm2(cg_sub(point,cg_at(points,count-1))) {return 1;}
    let margins=load64(path+8);
    if margins {store64(margins+count*8,padding);}
    return cg_push(points,point);
}

fn pcr_bend(path,vertex,inbound,outbound,radius,trim,angle,guide,bends) {
    let axis=cg_normal(cg_cross(inbound,outbound));
    if !axis {return cg_fail("The route bend plane could not be resolved");}
    let inward=cg_normal(cg_cross(axis,inbound));
    let start=pcl_along(vertex,inbound,-trim,1000000000);
    let finish=pcl_along(vertex,outbound,trim,1000000000);
    let center=pcl_along(start,inward,radius,1000000000);
    let chords=(angle+4999)/5000;
    // A five-degree chord has sagitta < 0.000952 times the radius.
    // Reserve another 0.01 mm for fixed-point and millidegree trig rounding.
    let padding=(radius*952+999999)/1000000+10000;
    pcr_path_point(path,start,0);
    let i=1;
    while i<chords && !cg_error {
        let step=angle*i/chords;
        let point=pcl_along(start,inward,radius*(1000000-cg_cos(step))/1000000,1000000000);
        point=pcl_along(point,inbound,radius*cg_sin(step)/1000000,1000000000);
        pcr_path_point(path,point,padding);
        i=i+1;
    }
    pcr_path_point(path,finish,padding);
    let bend=j_object();
    cg_j_text(bend,"guide_id",j_string(guide,"id"));
    j_add(bend,"radius_mm",cg_json_number(radius));
    j_add(bend,"sweep_deg",cg_json_number(angle*1000));
    j_add(bend,"start",pcr_json_point(start));
    j_add(bend,"center",pcr_json_point(center));
    j_add(bend,"end",pcr_json_point(finish));
    j_add(bend,"chord_deviation_bound_mm",cg_json_number(padding));
    j_add(bends,0,bend);
    return !cg_error;
}
