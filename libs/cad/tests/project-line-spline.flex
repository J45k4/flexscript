import "cad/project-line-edit.flex";

fn line_spline_add(project,mode,coordinates) {
    let points=cg_array();let row=pc_first(j_parse(coordinates));
    while row {cg_push(points,pc_uv(row));row=load64(row+24);}
    let curve=cad_project_add_curve(project,"native-sketch-1",mode,points);m_assert(curve,cg_error);
    return curve;
}

fn line_spline_hits(shape,a,b) {
    cg_begin();let hits=cg_array();m_assert(plb_parameters(hits,a,b,shape),cg_error);
    let x=0;while x<cg_count(hits) {
        let at=ple_at(a,b,cg_at(hits,x));store64(load64(hits+16)+x*8,at);x=x+1;
    }
    return hits;
}

fn line_spline_crossings() {
    let sketch="native-sketch-1";let id="native-entity-1";let boundary="native-entity-2";
    let project=cad_project_new("Three spline crossings");
    let a=cg_v(-10000000,0,0);let b=cg_v(40000000,0,0);
    m_assert(cad_project_add_primitive(project,sketch,"line",a,b),cg_error);
    let curve=line_spline_add(project,"control","[{\"x\":0,\"y\":-8},{\"x\":10,\"y\":14},{\"x\":20,\"y\":-14},{\"x\":30,\"y\":8}]");
    let hits=line_spline_hits(curve,a,b);
    m_assert(cg_count(hits)==3 && load64(cg_at(hits,0))==6000000 && load64(cg_at(hits,1))==15000000
        && load64(cg_at(hits,2))==24000000,"Keep all three roots of one cubic in line order");
    let source=j_encode(project);let original_spline=j_encode(curve);
    let trimmed=cad_project_trim_line(project,sketch,id,cg_v(10000000,0,0),1000000);
    m_assert(trimmed && m_eq(j_encode(project),source),"Trim updates a copy");
    trimmed=cad_project_open(j_encode(trimmed));m_assert(trimmed,cg_error);
    let nodes=pc_nodes(cad_project_part(trimmed));
    m_assert(load64(pc_uv(j_get(pc_find(nodes,id),"p1")))==6000000
        && load64(pc_uv(j_get(pc_find(nodes,"native-entity-3"),"p0")))==15000000,"Trim the selected interval only");
    m_assert(m_eq(j_encode(pc_find(nodes,boundary)),original_spline),"The boundary survives byte-for-byte in the saved sketch");
    let extended=cad_project_extend_line(trimmed,sketch,id,cg_v(5000000,0,0),1000000);m_assert(extended,cg_error);
    nodes=pc_nodes(cad_project_part(extended));
    m_assert(load64(pc_uv(j_get(pc_find(nodes,id),"p1")))==15000000,"Extend past the current endpoint to the next cubic crossing");
    m_assert(m_eq(j_encode(pc_find(nodes,boundary)),original_spline),"Extension leaves the boundary intact");
}

fn line_spline_tangent_and_coincident() {
    let project=cad_project_new("Spline tangent");
    let arch=line_spline_add(project,"control","[{\"x\":-15,\"y\":0},{\"x\":-5,\"y\":16},{\"x\":5,\"y\":16},{\"x\":15,\"y\":0}]");
    let a=cg_v(-25000000,12000000,0);let b=cg_v(25000000,12000000,0);
    let hits=line_spline_hits(arch,a,b);
    m_assert(cg_count(hits)==1 && !load64(cg_at(hits,0)),"Keep one even-multiplicity tangent at the cubic apex");
    m_assert(!cg_count(line_spline_hits(arch,cg_v(-25000000,12000001,0),cg_v(25000000,12000001,0))),"A line one nanometre above the apex misses");
    let flat=line_spline_add(project,"control","[{\"x\":-15,\"y\":12},{\"x\":-5,\"y\":12},{\"x\":5,\"y\":12},{\"x\":15,\"y\":12}]");
    m_assert(!cg_count(line_spline_hits(flat,a,b)),"A coincident spline span is not a crossing");
    let fit=line_spline_add(project,"fit","[{\"x\":-15,\"y\":-15},{\"x\":-7,\"y\":-7},{\"x\":12,\"y\":12},{\"x\":15,\"y\":15}]");
    m_assert(!cg_count(line_spline_hits(fit,cg_v(-25000000,-25000000,0),cg_v(25000000,25000000,0))),"Do not invent intersections from coincident fit handles");
}

fn line_spline_fit_and_periodic() {
    let project=cad_project_new("Fit spline boundaries");
    let fit=line_spline_add(project,"fit","[{\"x\":0,\"y\":0},{\"x\":12,\"y\":12},{\"x\":24,\"y\":0}]");
    let a=cg_v(-10000000,4406250,0);let b=cg_v(0,4406250,0);
    let hits=line_spline_hits(fit,a,b);
    // The first natural-fit polynomial has y = 18u - 6u^3. At u=1/4,
    // x=3 mm and y=4.40625 mm, with the second crossing reflected at x=21 mm.
    m_assert(cg_count(hits)==2 && load64(cg_at(hits,0))==3000000 && load64(cg_at(hits,1))==21000000,
        "Intersect the fit curve between its knots, beyond the target line");
    let line=cad_project_add_primitive(project,"native-sketch-1","line",a,b);m_assert(line,cg_error);
    let id=j_string(line,"id");
    let extended=cad_project_extend_line(project,"native-sketch-1",id,cg_v(-1000000,4406250,0),1000000);
    m_assert(extended && load64(pc_uv(j_get(pc_find(pc_nodes(cad_project_part(extended)),id),"p1")))==3000000,
        "Extend to the nearest contact on an open fit spline");
    let loop=line_spline_add(project,"periodic","[{\"x\":-10,\"y\":0},{\"x\":0,\"y\":10},{\"x\":10,\"y\":0},{\"x\":0,\"y\":-10}]");
    hits=line_spline_hits(loop,cg_v(-20000000,0,0),cg_v(20000000,0,0));
    m_assert(cg_count(hits)==2 && load64(cg_at(hits,0))==-10000000 && load64(cg_at(hits,1))==10000000,
        "Deduplicate shared hits at the periodic seam and at an interior knot");
}

fn main() {
    line_spline_crossings();line_spline_tangent_and_coincident();line_spline_fit_and_periodic();
    return 0;
}
