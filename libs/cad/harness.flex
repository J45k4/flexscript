// Frozen connector pinouts and wire schedules. Preparation records bind the
// authored physical endpoint and its reviewed connector contact revision.
import "studio/pcad-bom.flex";
import "continuity.flex";

fn phd_text(value,limit) {
    if !m_len(value) || m_len(value)>limit {return 0;}
    let i=0;let content=0;
    while i<m_len(value) {
        let c=load8(value+i);
        if c<32 || c==127 {return 0;}
        if c!=32 {content=1;}
        i=i+1;
    }
    return content;
}

fn phd_issue(issues,kind,id,detail) {
    let row=j_object();cg_j_text(row,"record_kind",kind);cg_j_text(row,"record_id",id);cg_j_text(row,"detail",detail);
    cg_json_push(issues,row);return 0;
}

fn phd_definition(e,component) {
    let binding=j_get(component,"connector");
    let def=pcm_find(j_get(e,"connector_definitions"),j_string(binding,"definition_id"));
    if !def || j_integer(binding,"revision")!=j_integer(def,"revision") {return 0;}
    return def;
}

fn phd_connector(e,id) {
    let component=pcm_find(j_get(e,"components"),id);
    if !component {return 0;}
    let out=j_object();let def=phd_definition(e,component);
    cg_j_text(out,"component_id",id);pcc_copy(component,"reference",out);
    if def {
        cg_j_text(out,"family",j_string(def,"name"));cg_j_text(out,"definition_id",j_string(def,"id"));
        cg_j_int(out,"definition_revision",j_integer(def,"revision"));
        pcc_copy(def,"viewing_direction",out);pcc_copy(def,"manufacturer",out);pcc_copy(def,"part_number",out);
    }
    return out;
}

fn phd_terminal(context,id,terminal_id) {
    let e=load64(context);let graph=load64(context+8);
    let component=pcm_find(j_get(e,"components"),id);
    let terminal=pcm_find(j_get(component,"terminals"),terminal_id);
    let pin=pcm_find(j_get(component,"pins"),j_string(terminal,"pin_id"));
    if !component || !terminal || !pin {return 0;}
    let out=j_object();let key=pgt_contact(id,terminal_id);
    if !key {return 0;}
    cg_j_text(out,"key",key);cg_j_text(out,"component_id",id);cg_j_text(out,"terminal_id",terminal_id);
    cg_j_text(out,"reference",j_string(component,"reference"));cg_j_text(out,"contact",j_string(terminal,"name"));
    cg_j_text(out,"pin_id",j_string(pin,"id"));cg_j_text(out,"pin_number",j_string(pin,"number"));
    let net=j_string(load64(graph+16),pgt_pair(id,j_string(pin,"id")));
    if m_len(net) {cg_j_text(out,"net_id",net);cg_j_text(out,"net_name",j_string(load64(graph+24),net));}
    pcc_copy(pin,"no_connect",out);
    let binding=j_get(component,"connector");let definition=phd_definition(e,component);
    let contact_key="";
    if definition {
        let map=load64(j_get(binding,"contacts")+16);
        while map && !m_eq(j_string(map,"terminal_id"),terminal_id) {map=load64(map+24);}
        let contact=j_string(map,"definition_contact_id");
        let authored=pcm_find(j_get(definition,"contacts"),contact);
        if authored {
            contact_key=m_cat(j_string(definition,"id"),m_cat("@",m_cat(m_int(j_integer(definition,"revision")),m_cat(":",contact))));
        }
    }
    if binding && !m_len(contact_key) {return 0;}
    cg_j_text(out,"contact_key",contact_key);
    return out;
}

fn phd_endpoint(context,harness,end) {
    if m_eq(j_string(end,"kind"),"terminal") {return phd_terminal(context,j_string(end,"component_id"),j_string(end,"terminal_id"));}
    if !m_eq(j_string(end,"kind"),"splice") {return 0;}
    let id=j_string(end,"splice_id");let splice=pcm_find(j_get(harness,"splices"),id);
    if !splice {return 0;}
    let key=pgt_end(end);if !key {return 0;}
    let out=j_object();cg_j_text(out,"key",key);cg_j_text(out,"splice_id",id);
    cg_j_text(out,"reference","Splice");cg_j_text(out,"contact",pgt_label(splice,"name",id));
    cg_j_text(out,"contact_key","");
    return out;
}

fn phd_pairs_add(out,a,b) {
    let row=j_object();
    if a {j_add(row,"a",a);}
    if b {j_add(row,"b",b);}
    cg_json_push(out,row);return 0;
}

fn phd_unmapped(context,out,component,used,side_a) {
    if !component {return 0;}
    let terminal=load64(j_get(component,"terminals")+16);let id=j_string(component,"id");
    while terminal {
        let key=j_string(terminal,"id");
        if !j_get(used,key) {
            let endpoint=phd_terminal(context,id,key);
            if !endpoint {return 0;}
            if side_a {phd_pairs_add(out,endpoint,0);}else {phd_pairs_add(out,0,endpoint);}
        }
        terminal=load64(terminal+24);
    }
    return 1;
}

fn phd_pinout(context,map,standalone,issues) {
    let e=load64(context);
    let id=j_string(map,"id");let a=j_string(map,"a_component_id");let b=j_string(map,"b_component_id");
    let kind="mating";
    if !map {id=standalone;a=standalone;kind="connector";}
    let out=j_object();let pairs=cg_json_array();
    cg_j_text(out,"kind",kind);
    cg_j_text(out,"id",id);j_add(out,"contacts",pairs);
    let left=phd_connector(e,a);let right=0;
    if map {right=phd_connector(e,b);}
    if left {j_add(out,"a",left);}
    if right {j_add(out,"b",right);}
    if !m_len(j_string(left,"viewing_direction")) || (map && !m_len(j_string(right,"viewing_direction"))) {
        phd_issue(issues,kind,id,"Connector family, revision or viewing direction is missing");
    }
    let used_a=j_object();let used_b=j_object();let list=j_get(map,"pairs");let pair=0;
    let valid=1;
    if map {
        let state=j_get(map,"connected");
        pcc_copy(map,"connected",out);
        if !right || !left || !pgt_id(id) || m_eq(a,b) || j_kind(state)!=5
            || j_kind(list)!=3 || !cg_j_count(list) || cg_j_count(list)>64 {
            phd_issue(issues,kind,id,"Connector mating has an incomplete contact map");valid=0;
        }else {pair=load64(list+16);}
    }
    while pair {
        let aa=j_string(pair,"a_terminal_id");let bb=j_string(pair,"b_terminal_id");
        let x=phd_terminal(context,a,aa);let y=phd_terminal(context,b,bb);
        if !x || !y || j_get(used_a,aa) || j_get(used_b,bb) {
            phd_issue(issues,kind,id,"Connector mating has a missing or duplicate mapped contact");valid=0;
        }else {
            let a_net=j_string(x,"net_id");let b_net=j_string(y,"net_id");
            if (m_len(a_net) && m_len(b_net) && !m_eq(a_net,b_net))
                || (m_len(a_net) && j_value(j_get(y,"no_connect"))) || (m_len(b_net) && j_value(j_get(x,"no_connect"))) {
                phd_issue(issues,kind,id,"Mapped mating contacts disagree on intended nets or no-connect state");
            }
            cg_j_int(used_a,aa,1);cg_j_int(used_b,bb,1);phd_pairs_add(pairs,x,y);
        }
        pair=load64(pair+24);
    }
    if valid {
        if !phd_unmapped(context,pairs,pcm_find(j_get(e,"components"),a),used_a,1)
            || (map && !phd_unmapped(context,pairs,pcm_find(j_get(e,"components"),b),used_b,0)) {
            phd_issue(issues,kind,id,"One or more pinout contacts could not be resolved");
        }
    }
    return out;
}

fn phd_termination(value,endpoint) {
    let method=j_string(value,"method");let strip=pcd_length(j_get(value,"strip_mm"),50);
    if !endpoint || !m_eq(j_string(value,"endpoint_key"),j_string(endpoint,"key"))
        || j_kind(j_get(value,"contact_key"))!=2 || !m_eq(j_string(value,"contact_key"),j_string(endpoint,"contact_key")) {return 0;}
    if m_eq(method,"idc") {return strip==0;}
    return strip>0 && (m_eq(method,"crimp") || m_eq(method,"solder") || m_eq(method,"ferrule") || m_eq(method,"ring-lug"));
}

fn phd_wire(context,harness,wire,route,issues) {
    let e=load64(context);
    let id=j_string(wire,"id");let output=j_object();let construction=j_get(wire,"construction");
    cg_j_text(output,"id",id);cg_j_text(output,"name",pgt_label(wire,"name",id));
    pcc_copy(wire,"color",output);pcc_copy(wire,"stock_id",output);
    let cable=j_string(wire,"cable_id");
    if m_len(cable) {
        let bundle=pcm_find(j_get(harness,"cables"),cable);
        cg_j_text(output,"cable_id",cable);
        if bundle {cg_j_text(output,"cable_name",pgt_label(bundle,"name",cable));}
        else {phd_issue(issues,"wire",id,"Wire names a missing cable or bundle");}
    }
    let net=j_string(wire,"net_id");let intent=pcm_find(j_get(e,"nets"),net);
    if !intent {phd_issue(issues,"wire",id,"Wire needs an assigned logical net");}
    else {cg_j_text(output,"net_id",net);cg_j_text(output,"net_name",j_string(intent,"name"));}
    let spec=j_string(construction,"specification");
    if phd_text(spec,120) {cg_j_text(output,"specification",spec);}
    else {phd_issue(issues,"wire",id,"Wire specification is missing");}
    let length=j_get(wire,"length_mm");let cut=pcd_length(length,1000000);
    let minimum=pcd_length(j_get(route,"provisional_cut_mm"),1000000);
    if minimum<=0 || !m_eq(j_string(route,"status"),"evaluated")
        || cg_j_count(j_get(route,"issues")) || !m_eq(j_string(j_get(route,"clearance"),"status"),"clear") {
        phd_issue(issues,"wire",id,"Wire route and clearance need review");
    }
    let geometric=j_get(route,"length_mm");
    if geometric {j_add(output,"route_length_mm",j_parse(j_encode(geometric)));}
    pcc_copy(route,"centerline",output);pcc_copy(route,"allowance_mm",output);pcc_copy(route,"provisional_cut_mm",output);
    pcc_copy(route,"breakout_ids",output);pcc_copy(route,"jacket_length_mm",output);
    if cut>0 {
        cg_j_text(output,"cut_method","manual");pcc_copy(wire,"length_mm",output);
        let reason=j_string(construction,"cut_reason");
        if phd_text(reason,140) {cg_j_text(output,"cut_reason",reason);}
        else {phd_issue(issues,"wire",id,"A manual cut length needs an explanation");}
        if minimum>0 && cut<minimum {phd_issue(issues,"wire",id,"Specified cut length is shorter than route plus allowance");}
    }else {
        let method="unknown";if minimum>0 {method="provisional-route";}
        cg_j_text(output,"cut_method",method);
        phd_issue(issues,"wire",id,"An explicit positive cut length is required for manufacturing");
    }
    let ends=j_get(wire,"ends");let prep=j_get(construction,"terminations");
    let from=0;let finish=0;
    if j_kind(ends)==3 && cg_j_count(ends)==2 {
        from=load64(ends+16);finish=load64(from+24);
    }
    let a=phd_endpoint(context,harness,from);let b=phd_endpoint(context,harness,finish);
    let attachments=j_get(route,"attachments");
    let admitted=0;if j_kind(attachments)==3 && cg_j_count(attachments)==2 {admitted=load64(attachments+16);}
    if a {
        if admitted && m_eq(j_string(a,"splice_id"),j_string(admitted,"splice_id")) {pcc_copy(admitted,"at",a);}
        j_add(output,"from",a);
    }
    if b {
        let other=0;if admitted {other=load64(admitted+24);}
        if other && m_eq(j_string(b,"splice_id"),j_string(other,"splice_id")) {pcc_copy(other,"at",b);}
        j_add(output,"to",b);
    }
    if !a || !b || m_eq(j_string(a,"key"),j_string(b,"key")) {phd_issue(issues,"wire",id,"Wire endpoints are missing or identical");}
    let termination=0;if j_kind(prep)==3 && cg_j_count(prep)==2 {termination=load64(prep+16);}
    let strips=0;
    let i=0;
    while i<2 {
        let endpoint=a;let label="From end preparation is missing or needs contact review";
        if i {endpoint=b;label="To end preparation is missing or needs contact review";}
        let linked=j_string(endpoint,"net_id");
        if j_value(j_get(endpoint,"no_connect"))
            || (m_len(j_string(endpoint,"terminal_id")) && !m_eq(linked,net)) {
            phd_issue(issues,"wire",id,"Wire endpoint conflicts with its logical net or no-connect state");
        }
        if phd_termination(termination,endpoint) {
            let info=j_object();pcc_copy(termination,"method",info);pcc_copy(termination,"strip_mm",info);
            j_add(endpoint,"preparation",info);strips=strips+pcd_length(j_get(info,"strip_mm"),50);
        }else {phd_issue(issues,"wire",id,label);}
        if termination {termination=load64(termination+24);}
        i=i+1;
    }
    if cut>0 && strips>cut {phd_issue(issues,"wire",id,"Termination strip lengths exceed the specified cut length");}
    return output;
}

fn phd_splice_schedule(harness,harness_report,issues) {
    let out=j_array();let pose=j_get(harness_report,"pose_splices");let row=0;
    if pose {row=load64(pose+16);}
    while row && !cg_error {
        let id=j_string(row,"splice_id");let splice=pcm_find(j_get(harness,"splices"),id);
        let construction=j_get(splice,"construction");
        let entry=j_parse(j_encode(row));
        let spec=j_string(construction,"specification");
        let method=j_string(construction,"method");
        if m_eq(method,"crimp") || m_eq(method,"solder") || m_eq(method,"terminal-block") {
            cg_j_text(entry,"method",method);
        }else {phd_issue(issues,"splice",id,"Splice joining method needs review");}
        if phd_text(spec,120) {cg_j_text(entry,"specification",spec);}
        else {phd_issue(issues,"splice",id,"Splice specification is missing");}
        let members=j_get(entry,"members");let member=load64(members+16);let net="";
        let consistent=cg_j_count(members)>=2;
        while member && !cg_error {
            let wire=pcm_find(j_get(harness,"wires"),j_string(member,"wire_id"));let assigned=j_string(wire,"net_id");
            if !m_len(assigned) || (m_len(net) && !m_eq(net,assigned)) {consistent=0;}
            net=assigned;member=load64(member+24);
        }
        if consistent {cg_j_text(entry,"net_id",net);}
        else {phd_issue(issues,"splice",id,"Splice needs two or more wire ends on one assigned net");}
        if !m_eq(j_string(row,"status"),"positioned") {phd_issue(issues,"splice",id,"Splice placement is unresolved");}
        j_add(out,0,entry);row=load64(row+24);
    }
    return out;
}

fn pcad_harness_document(doc,harness_report) {
    cg_begin();
    let e=j_get(doc,"electrical");let harness=j_get(e,"harness");
    let mode=j_string(j_get(harness,"documentation"),"mode");
    if j_kind(j_get(harness,"documentation"))!=4 || (!m_eq(mode,"review") && !m_eq(mode,"manufacturing")) {
        cg_fail("Harness documentation mode must be review or manufacturing");return ca_error();
    }
    let graph=pgt_new();
    if !pgt_intent(graph,e) {return ca_error();}
    let context=m_take(16);store64(context,e);store64(context+8,graph);
    let out=j_object();let wires=cg_json_array();let pinouts=cg_json_array();let issues=cg_json_array();
    cg_j_text(out,"format","biscuit-pcad-harness-docs-1");cg_j_text(out,"mode",mode);
    j_add(out,"wire_schedule",wires);j_add(out,"pinouts",pinouts);j_add(out,"issues",issues);
    let seen=j_object();let mapped=j_object();let map=pdb_first(harness,"matings",32);
    while map && !cg_error {
        let id=j_string(map,"id");let a=j_string(map,"a_component_id");let b=j_string(map,"b_component_id");
        if j_get(seen,id) {cg_fail("Harness documentation needs unique mating IDs");return ca_error();}
        cg_j_int(seen,id,1);
        if !j_get(mapped,a) {cg_j_int(mapped,a,1);}
        if !j_get(mapped,b) {cg_j_int(mapped,b,1);}
        cg_json_push(pinouts,phd_pinout(context,map,"",issues));map=load64(map+24);
    }
    let source=pdb_first(harness,"wires",256);
    if !source {phd_issue(issues,"harness","harness","No wire segments are declared");}
    while source && !cg_error {
        let id=j_string(source,"id");let row=pcm_find(j_get(harness_report,"wires"),id);
        let schedule=phd_wire(context,harness,source,j_get(row,"pose_route"),issues);
        cg_json_push(wires,schedule);
        let i=0;
        while i<2 {
            let side=j_get(schedule,"from");if i {side=j_get(schedule,"to");}
            let owner=j_string(side,"component_id");
            if m_len(j_string(side,"contact_key")) && !j_get(mapped,owner) {
                cg_json_push(pinouts,phd_pinout(context,0,owner,issues));cg_j_int(mapped,owner,1);
            }
            i=i+1;
        }
        source=load64(source+24);
    }
    let jackets=j_get(harness_report,"jackets");
    let jacket=0;if jackets {jacket=load64(jackets+16);}
    let jacket_schedule=j_array();
    while jacket && !cg_error {
        let id=j_string(jacket,"cable_id");let cable=pcm_find(j_get(harness,"cables"),id);
        let profile=j_get(cable,"jacket");let row=j_object();cg_j_text(row,"cable_id",id);
        pcc_copy(cable,"name",row);pcc_copy(jacket,"breakouts",row);
        pcc_copy(jacket,"length_mm",row);pcc_copy(jacket,"allowance_mm",row);pcc_copy(jacket,"provisional_cut_mm",row);
        let cut=pcd_length(j_get(profile,"cut_length_mm"),1000000);
        let minimum=pcd_length(j_get(jacket,"provisional_cut_mm"),1000000);
        let spec=j_string(profile,"specification");
        if phd_text(spec,120) {cg_j_text(row,"specification",spec);}
        else {phd_issue(issues,"jacket",id,"Jacket specification is missing");}
        if cut>0 {pcc_copy(profile,"cut_length_mm",row);}
        if !minimum || cut<minimum {phd_issue(issues,"jacket",id,"Jacket cut must cover its fitted length and allowance");}
        j_add(jacket_schedule,0,row);jacket=load64(jacket+24);
    }
    if cg_j_count(jacket_schedule) {j_add(out,"jacket_schedule",jacket_schedule);}
    let splice_schedule=phd_splice_schedule(harness,harness_report,issues);
    if cg_j_count(splice_schedule) {j_add(out,"splice_schedule",splice_schedule);}
    if cg_error {return ca_error();}
    cg_j_set(out,"manufacturing_ready",j_new(5,m_eq(mode,"manufacturing") && !cg_j_count(issues)));
    return out;
}

// A wiring-only record can omit conductors. Declared conductors need a
// unique stable identity to match the evaluated routes.
fn phd_route_ids(wires) {
    if !wires {return 1;}
    if j_kind(wires)!=3 || cg_j_count(wires)>256 {return 0;}
    let seen=j_object();let wire=load64(wires+16);
    while wire {
        let id=j_string(wire,"id");
        if !pgt_id(id) || j_get(seen,id) {return 0;}
        cg_j_int(seen,id,1);wire=load64(wire+24);
    }
    return 1;
}

fn pcad_harness_pose(doc,mesh) {
    let output=j_object();let reports=j_array();
    cg_j_text(output,"format","biscuit-pcad-harness-1");cg_j_text(output,"length_units","mm");
    let harness=j_get(j_get(doc,"electrical"),"harness");
    let wires=j_get(harness,"wires");let routes=j_get(mesh,"routes");
    j_add(output,"wires",reports);pcc_copy(harness,"cables",output);pcc_copy(harness,"splices",output);
    pcc_copy(harness,"matings",output);pcc_copy(harness,"required_joins",output);pcc_copy(harness,"diagram",output);
    let valid=j_kind(harness)==4 && j_kind(mesh)==4 && !j_get(mesh,"error") && !m_len(j_string(mesh,"route_error"));
    let wire=0;if j_kind(wires)==3 {wire=load64(wires+16);}
    let jackets=j_get(mesh,"jackets");pcc_copy(mesh,"jackets",output);
    let owners=j_object();let jacket=0;
    if jackets {jacket=load64(jackets+16);}
    let issues=j_array();
    if !valid && j_kind(harness)!=4 {j_add(issues,0,j_text("Expected a harness object"));}
    let error=j_string(mesh,"route_error");
    if m_len(error) {j_add(issues,0,j_text(error));}
    if !phd_route_ids(wires) {valid=0;j_add(issues,0,j_text("Invalid harness wire identities"));wire=0;}
    error=j_string(mesh,"jacket_error");
    if m_len(error) {valid=0;j_add(issues,0,j_text(error));}
    while wire {
        let id=j_string(wire,"id");let row=j_object();let result=0;
        if j_kind(routes)==3 {result=load64(routes+16);}
        while result && !m_eq(j_string(result,"wire_id"),id) {result=load64(result+24);}
        cg_j_text(row,"id",id);
        pcc_copy(wire,"name",row);pcc_copy(wire,"ends",row);pcc_copy(wire,"net_id",row);
        pcc_copy(wire,"cable_id",row);pcc_copy(wire,"color",row);
        let length=j_get(wire,"length_mm");
        if length {j_add(row,"specified_cut_length_mm",j_parse(j_encode(length)));}
        if result {j_add(row,"pose_route",j_parse(j_encode(result)));}
        if !m_eq(j_string(result,"status"),"evaluated")
            || cg_j_count(j_get(result,"issues")) || !m_eq(j_string(j_get(result,"clearance"),"status"),"clear") {
            valid=0;j_add(issues,0,j_text(id));
        }
        let cable=j_string(result,"jacket_id");
        if m_len(cable) {cg_j_int(owners,cable,j_integer(owners,cable)+1);}
        let membership=j_string(wire,"cable_id");
        if m_len(membership) && !j_get(j_get(wire,"route"),"jacket_direction")
            && j_get(pcm_find(j_get(harness,"cables"),membership),"jacket") {
            valid=0;j_add(issues,0,j_text(m_cat("Conductor needs an explicit jacket route: ",id)));
        }
        j_add(reports,0,row);wire=load64(wire+24);
    }
    while jacket {
        let id=j_string(jacket,"cable_id");
        if !j_integer(owners,id) || !m_eq(j_string(jacket,"status"),"evaluated")
            || cg_j_count(j_get(jacket,"issues")) || !m_eq(j_string(j_get(jacket,"clearance"),"status"),"clear") {
            valid=0;j_add(issues,0,j_text(m_cat("Jacket needs clearance and routed members: ",id)));
        }
        jacket=load64(jacket+24);
    }
    if j_get(mesh,"splices") {j_add(output,"pose_splices",j_parse(j_encode(j_get(mesh,"splices"))));}
    let splices=j_get(mesh,"splices");let splice=0;
    if splices {splice=load64(splices+16);}
    error=j_string(mesh,"splice_error");
    if m_len(error) {valid=0;j_add(issues,0,j_text(error));}
    while splice {
        if !m_eq(j_string(splice,"status"),"positioned") || cg_j_count(j_get(splice,"members"))<2 {
            valid=0;j_add(issues,0,j_text(m_cat("Splice needs placement and at least two wire ends: ",j_string(splice,"splice_id"))));
        }
        splice=load64(splice+24);
    }
    j_add(output,"routes_ready",j_new(5,valid));
    j_add(output,"route_issues",issues);
    return output;
}
