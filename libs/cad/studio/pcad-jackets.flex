// A jacket owns its common path. Conductor tails leave each breakout on
// the jacket tangent before their own bends and terminal attachments.
fn pcr_jacket(document,assembly,profile,result) {
    if !assembly {return cg_fail("Resolve the assembly before routing a cable jacket");}
    if j_kind(profile)!=4 {return cg_fail("A cable jacket needs a route record");}
    let ends=pc_list(profile,"breakouts",2);let guides=pc_list(profile,"guides",8);
    if cg_error || cg_j_count(ends)!=2 {return cg_fail("A cable jacket needs two breakout records");}
    let lead=cg_number(j_get(profile,"lead_mm"));
    let radius=cg_number(j_get(profile,"bend_radius_mm"));let allowance=cg_number(j_get(profile,"allowance_mm"));
    if cg_error || lead<1000 || lead>50000000 || radius<=0 || radius>100000000 || allowance<0 {
        return cg_fail("Use a 0.001–50 mm breakout lead, a positive bend radius and a nonnegative jacket allowance");
    }
    let raw=cg_array();let seen=j_object();
    let first=load64(ends+16);let last=load64(first+24);
    pcr_add_guide(document,assembly,raw,seen,first);
    let guide=load64(guides+16);
    while guide && !cg_error {
        pcr_add_guide(document,assembly,raw,seen,guide);guide=load64(guide+24);
    }
    if !cg_error {pcr_add_guide(document,assembly,raw,seen,last);}
    if cg_error {return 0;}
    let path=pcr_finish(raw,radius,allowance,guides,result,1);
    if !path {return 0;}
    let direction_start=pcr_direction(cg_sub(cg_at(raw,0),cg_at(raw,1)));
    let direction_end=pcr_direction(cg_sub(cg_at(raw,cg_count(raw)-1),cg_at(raw,cg_count(raw)-2)));
    let jacket=m_take(24);store64(jacket,path);
    store64(jacket+8,pcl_along(cg_at(raw,0),direction_start,lead,1000000000));
    store64(jacket+16,pcl_along(cg_at(raw,cg_count(raw)-1),direction_end,lead,1000000000));
    let breakouts=j_array();
    let a=j_object();cg_j_text(a,"id",j_string(first,"id"));j_add(a,"at",pcr_json_point(cg_at(raw,0)));
    let b=j_object();cg_j_text(b,"id",j_string(last,"id"));j_add(b,"at",pcr_json_point(cg_at(raw,cg_count(raw)-1)));
    j_add(breakouts,0,a);j_add(breakouts,0,b);j_add(result,"breakouts",breakouts);
    return jacket;
}

fn pcr_path_join(target,source,reverse) {
    let points=load64(source);let margins=load64(source+8);
    let count=cg_count(points);let i=0;
    while i<count && !cg_error {
        let index=i;let edge=i;
        if reverse {index=count-1-i;edge=index+1;}
        let padding=0;if i && margins {padding=load64(margins+edge*8);}
        pcr_path_point(target,cg_at(points,index),padding);i=i+1;
    }
    return !cg_error;
}

fn pcr_tail(document,assembly,terminal,lead,breakout,guides,radius,result) {
    let raw=cg_array();let bends=j_array();let seen=j_object();
    cg_push(raw,terminal);
    let row=load64(guides+16);
    while row && !cg_error {
        pcr_add_guide(document,assembly,raw,seen,row);
        j_add(bends,0,j_parse(j_encode(row)));row=load64(row+24);
    }
    if cg_error {return 0;}
    // The end of this straight run is the fixed jacket breakout. The
    // bend at the lead point may trim the run up to the breakout.
    let lead_guide=j_object();cg_j_text(lead_guide,"id","breakout-lead");
    j_add(bends,0,lead_guide);cg_push(raw,lead);cg_push(raw,breakout);
    return pcr_finish(raw,radius,0,bends,result,1);
}

fn pcr_member(document,assembly,wire,route,start,end,radius,allowance,result) {
    let id=j_string(wire,"cable_id");let direction=j_string(route,"jacket_direction");
    if !m_len(id) || (!m_eq(direction,"forward") && !m_eq(direction,"reverse")) {
        return cg_fail("Choose a cable jacket and an explicit breakout order");
    }
    let profiles=j_get(j_get(j_get(document,"electrical"),"harness"),"cables");
    let cable=pcm_find(profiles,id);let profile=j_get(cable,"jacket");
    if !profile {return cg_fail("The selected cable jacket is missing");}
    let options=j_get(route,"branches");
    if j_kind(options)!=3 || cg_j_count(options)!=2 {return cg_fail("A cable member needs two branch guide lists");}
    let a=load64(options+16);let b=load64(a+24);
    if j_kind(a)!=3 || j_kind(b)!=3 || cg_j_count(a)>2 || cg_j_count(b)>2 {
        return cg_fail("Each cable branch supports up to two guides");
    }
    let common=j_object();let jacket=pcr_jacket(document,assembly,profile,common);
    if !jacket || cg_error {return 0;}
    let shared=load64(jacket);let shared_points=load64(shared);let count=cg_count(shared_points);
    if load64(shared+8)== -1 {return cg_fail("Repair the jacket bends before routing its conductors");}
    if cg_j_count(j_get(common,"bends")) && radius>cg_number(j_get(profile,"bend_radius_mm")) {
        return cg_fail("The jacket bend radius is smaller than the conductor minimum");
    }
    let reverse=m_eq(direction,"reverse");
    let entrance=cg_at(shared_points,0);let exit=cg_at(shared_points,count-1);
    let first_lead=load64(jacket+8);let last_lead=load64(jacket+16);
    if reverse {
        entrance=cg_at(shared_points,count-1);exit=cg_at(shared_points,0);
        first_lead=load64(jacket+16);last_lead=load64(jacket+8);
    }
    let first=j_object();let last=j_object();
    let tail_a=pcr_tail(document,assembly,start,first_lead,entrance,a,radius,first);
    if !tail_a || cg_error {return 0;}
    let tail_b=pcr_tail(document,assembly,end,last_lead,exit,b,radius,last);
    if !tail_b || cg_error {return 0;}
    if load64(tail_a+8)== -1 || load64(tail_b+8)== -1 {
        return cg_fail("A conductor branch bend does not fit before its breakout");
    }
    // 298 common points and at most 113 for each branch.
    let path=m_take(32);store64(path,cg_array());store64(path+8,m_take(524*8));
    store64(path+16,shared);store64(path+24,profile);
    pcr_path_join(path,tail_a,0);
    let from=cg_count(load64(path))-1;
    pcr_path_join(path,shared,reverse);
    let to=cg_count(load64(path))-1;
    pcr_path_join(path,tail_b,1);
    if cg_error {return 0;}
    let range=j_array();j_add(range,0,j_number(from));j_add(range,0,j_number(to));
    let breakout=j_get(common,"breakouts");let opening=load64(breakout+16);let closing=load64(opening+24);
    let refs=j_array();
    if reverse {j_add(refs,0,j_text(j_string(closing,"id")));j_add(refs,0,j_text(j_string(opening,"id")));}
    else {j_add(refs,0,j_text(j_string(opening,"id")));j_add(refs,0,j_text(j_string(closing,"id")));}
    let branches=j_array();j_add(branches,0,first);j_add(branches,0,last);
    // Member report retains both branch lengths and the common jacket length.
    // Do not parse a total back through cg_number, which is limited to 500 mm.
    let length=load64(tail_a+32)+load64(shared+32)+load64(tail_b+32);
    j_add(result,"length_mm",cg_json_number(length));
    j_add(result,"allowance_mm",cg_json_number(allowance));
    j_add(result,"provisional_cut_mm",cg_json_number(length+allowance));
    cg_j_text(result,"centerline","rounded");cg_j_text(result,"jacket_id",id);
    j_add(result,"breakout_ids",refs);j_add(result,"jacket_range",range);
    j_add(result,"jacket_length_mm",cg_json_number(load64(shared+32)));
    j_add(result,"branches",branches);j_add(result,"issues",j_array());
    return path;
}
