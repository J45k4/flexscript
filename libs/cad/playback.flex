// Native pose frames and one immutable mesh. Browser playback only applies the
// prepared rigid transforms; it does not construct geometry or solve mates.
import "assembly.flex";
fn cap_matrix(matrix) {
    let result=cg_json_array();let i=0;
    while i<3 {let j=0;while j<3 {cg_json_push(result,cg_json_number(load64(matrix+(i*3+j)*8)));j=j+1;}cg_json_push(result,cg_json_number(load64(matrix+72+i*8)));i=i+1;}
    return result;
}
fn cap_moving(row) {
    let depth=0;
    while row && depth<32 {
        let mate=load64(row+32);
        if load64(mate+120) {row=load64(row+72);}
        else {
            if !m_eq(load64(mate+8),"fixed") && !load64(mate+112) {return 1;}
            row=load64(mate+16);
        }
        depth=depth+1;
    }
    return 0;
}
// This receives only poses interpolated between already validated endpoints.
// ca_motion still checks driven scalar travel while placing each occurrence.
fn cap_resolve(assembly,moving,pose) {
    if !ca_validate_pose(assembly,pose) {return 0;}
    return cap_resolve_rows(moving,pose);
}
fn cap_resolve_rows(moving,pose) {
    let i=0;while i<cg_count(moving) {store64(cg_at(moving,i)+40,0);i=i+1;}
    let pass=0;let resolved=0;
    while resolved<cg_count(moving) && pass<cg_count(moving) && !cg_error {
        i=0;while i<cg_count(moving) {
            resolved=resolved+ca_try_place(cg_at(moving,i),pose);
            i=i+1;
        }pass=pass+1;
    }
    return !cg_error && resolved==cg_count(moving);
}
fn cap_check_bounds(bounds,matrix,minimum,maximum) {
    let corner=0;
    while corner<8 && !cg_error {
        let p=cg_v(load64(bounds+(corner&1)*24),load64(bounds+8+((corner>>1)&1)*24),load64(bounds+16+((corner>>2)&1)*24));
        let v=ca_point(matrix,p);let k=0;
        while k<3 {let n=load64(v+k*8);if cg_abs(n)>500000000 {cg_fail("Playback bounds exceed +/-500 mm");return 0;}if n<load64(minimum+k*8) {store64(minimum+k*8,n);}if n>load64(maximum+k*8) {store64(maximum+k*8,n);}k=k+1;}
        corner=corner+1;
    }
    return !cg_error;
}
// Frame count is explicit: frames are displayed exactly, without interpolated
// solver states. Collision checks are on demand via separate pose evaluation.
fn cad_assembly_playback(source,from,to,frames,duration_ms) {
    let assembly=ca_compile(source);if cg_error {return ca_error();}
    if frames<2 || frames>121 || duration_ms<100 || duration_ms>60000 {cg_fail("Playback requires 2-121 frames and a duration of 100-60000 ms");return ca_error();}
    if !ca_validate_pose(assembly,from) || !ca_validate_pose(assembly,to) {return ca_error();}
    let solids=ca_evaluate(assembly,from);if cg_error {return ca_error();}
    let mesh=cg_tessellate(solids);if cg_error {return ca_error();}
    if !j_value(j_get(mesh,"closed")) {cg_fail("Playback components must be closed oriented solids");return ca_error();}
    let check=j_object();cg_j_text(check,"status","unchecked");cg_j_text(check,"method","Playback frames are not collision-checked; inspect a selected pose");j_add(check,"pairs",j_array());
    let metadata=ca_metadata(assembly,from);j_add(metadata,"collision_check",check);j_add(mesh,"assembly",metadata);
    let moving=cg_array();let displayed=cg_array();let inverse=cg_array();let bounds=cg_array();let ids=cg_json_array();let rows=load64(assembly);let i=0;
    let minimum=cg_v(500000001,500000001,500000001);let maximum=cg_v(-500000001,-500000001,-500000001);
    let solid_index=0;
    while i<cg_count(rows) && !cg_error {
        let row=cg_at(rows,i);let moves=cap_moving(row);
        if moves {cg_push(moving,row);}
        if !load64(row+56) {
            let box=ca_bounds(load64(cg_at(solids,solid_index)+24));solid_index=solid_index+1;
            if moves {
                cg_push(displayed,row);cg_push(inverse,ca_inverse(load64(row+40)));
                cg_push(bounds,box);cg_json_push(ids,j_text(load64(row)));
            }
            cap_check_bounds(box,ca_identity(),minimum,maximum);
        }
        i=i+1;
    }
    let sequence=cg_json_array();let index=0;let mates=load64(assembly+8);
    while index<frames && !cg_error {
        if m_now()>cg_deadline {cg_fail("Playback build exceeded its time budget");return ca_error();}
        if !cg_step() {return ca_error();}
        let pose=ca_pose_frame(mates,from,to,index,frames-1);
        if !cap_resolve_rows(moving,pose) {return ca_error();}
        let transforms=cg_json_array();i=0;
        while i<cg_count(displayed) && !cg_error {
            let delta=ca_identity();if index {delta=ca_product(load64(cg_at(displayed,i)+40),cg_at(inverse,i));}
            let k=0;while k<3 {if cg_abs(load64(delta+72+k*8))>500000000 {cg_fail("Playback relative translation exceeds +/-500 mm");}k=k+1;}
            cap_check_bounds(cg_at(bounds,i),delta,minimum,maximum);cg_json_push(transforms,cap_matrix(delta));i=i+1;
        }
        let frame=j_object();j_add(frame,"pose",pose);j_add(frame,"transforms",transforms);cg_json_push(sequence,frame);index=index+1;
    }
    if cg_error {return ca_error();}
    let playback=j_object();cg_j_int(playback,"version",1);cg_j_int(playback,"duration_ms",duration_ms);j_add(playback,"parts",ids);j_add(playback,"frames",sequence);j_add(playback,"initial_collision_check",j_parse(j_encode(check)));
    let envelope=cg_json_array();let lo=cg_json_array();let hi=cg_json_array();i=0;
    while i<3 {cg_json_push(lo,cg_json_number(load64(minimum+i*8)));cg_json_push(hi,cg_json_number(load64(maximum+i*8)));i=i+1;}
    cg_json_push(envelope,lo);cg_json_push(envelope,hi);j_add(playback,"bounds",envelope);j_add(mesh,"playback",playback);
    if m_len(j_encode(mesh))>400000 {cg_fail("Playback mesh exceeds 400000 bytes; reduce frame count or geometry");return ca_error();}
    return mesh;
}
