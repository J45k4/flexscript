// Textual pinouts preserve the authored viewing direction and contact map.
// Wire sheet geometry and cut quantities are printed in separate fields.
import "studio/pcad-drawings.flex";

fn phd_pdf_header(out,page,title,subtitle) {
    m_text(out,".283464567 0 0 .283464567 0 0 cm\n0.13 0.19 0.17 rg 0.22 0.27 0.25 RG 2 w\n");
    pdd_pdf_text(out,145,1940,21,title);
    pdd_pdf_text(out,145,1845,11,pdd_pdf_short(subtitle,115));
    let report=j_integer(page,"harness_report");
    let mode="REVIEW SCHEDULE";
    if j_value(j_get(report,"manufacturing_ready")) {mode="MANUFACTURING SCHEDULE";}
    let label=m_cat(mode,m_cat("  |  Sheet ",m_int(j_integer(page,"sheet_no"))));
    pdd_pdf_text(out,145,1775,9,label);
    pdd_pdf_line(out,145,1740,2825,1740);m_text(out,"S\n");
    return report;
}

fn phd_pdf_footer(out,report) {
    pdd_pdf_line(out,145,186,2825,186);m_text(out,"S\n");
    pdd_pdf_text(out,145,119,8,m_cat("Harness SHA-256  ",j_string(report,"harness_sha256")));
    pdd_pdf_text(out,145,69,8,m_cat("Frozen build source SHA-256  ",j_string(report,"source_sha256")));
    pdd_pdf_text(out,2600,69,8,"A4 landscape");
    return m_data(out);
}

fn phd_pdf_number(row,key) {
    let value=j_get(row,key);
    if j_kind(value)==1 || j_kind(value)==6 {return m_cat(j_encode(value)," mm");}
    return "Unknown";
}

fn phd_pdf_contact(row) {
    if !row {return "Unmapped";}
    let intent="Unassigned";
    if m_len(j_string(row,"net_name")) {intent=j_string(row,"net_name");}
    if j_value(j_get(row,"no_connect")) {intent="No connect";}
    let contact=m_cat(pdd_pdf_short(j_string(row,"contact"),32),m_cat("  |  pin ",pdd_pdf_short(j_string(row,"pin_number"),16)));
    return pdd_pdf_short(m_cat(contact,m_cat("  |  ",intent)),65);
}

fn phd_pdf_side(out,side,x,label) {
    if !side {
        pdd_pdf_text(out,x,1660,10,"Unmated side");
        return 0;
    }
    let view=pgt_label(side,"viewing_direction","view not specified");
    let family=pgt_label(side,"family","Family not specified");
    pdd_pdf_text(out,x,1660,11,m_cat(label,m_cat(j_string(side,"reference"),m_cat("  |  ",view))));
    pdd_pdf_text(out,x,1598,9,pdd_pdf_short(family,65));
    let part=j_string(side,"definition_id");let identity=j_string(side,"component_id");
    let rev=j_integer(side,"definition_revision");let prefix=m_cat("Occurrence ",identity);
    if rev {prefix=m_cat(prefix,m_cat("  |  ",m_cat(part,m_cat(" rev ",m_int(rev)))));}
    pdd_pdf_text(out,x,1545,8,pdd_pdf_short(prefix,75));
    return 0;
}

fn phd_pdf_pinout(page) {
    let out=m_buffer();let sheet=j_integer(page,"pinout");
    let detail=m_cat("Interface ",j_string(sheet,"id"));
    let connected=j_get(sheet,"connected");
    if connected {
        let state="Disconnected";if j_value(connected) {state="Connected";}
        detail=m_cat(detail,m_cat("  |  ",state));
    }
    let report=phd_pdf_header(out,page,"Connector pinout",detail);
    phd_pdf_side(out,j_get(sheet,"a"),145,"A  ");phd_pdf_side(out,j_get(sheet,"b"),1515,"B  ");
    let map=j_string(sheet,"mapping_sha256");
    if m_len(map) {pdd_pdf_text(out,145,1488,8,m_cat("Mating map SHA-256  ",map));}
    pdd_pdf_line(out,145,1448,2825,1448);m_text(out,"S\n");
    let row=j_integer(page,"first");let i=0;let y=1388;
    if !row {pdd_pdf_text(out,145,y,10,"No contacts could be resolved for this interface");}
    while row && i<20 {
        pdd_pdf_text(out,145,y,9,phd_pdf_contact(j_get(row,"a")));
        pdd_pdf_text(out,1515,y,9,phd_pdf_contact(j_get(row,"b")));
        y=y-58;row=load64(row+24);i=i+1;
    }
    return phd_pdf_footer(out,report);
}

fn phd_pdf_preparation(out,side,x,y,label) {
    let name="Unresolved endpoint";let method="Preparation needs review";
    if side {
        name=m_cat(j_string(side,"reference"),m_cat(" / ",j_string(side,"contact")));
        let prep=j_get(side,"preparation");
        if prep {
            method=m_cat(j_string(prep,"method"),m_cat("  |  strip ",phd_pdf_number(prep,"strip_mm")));
        }
    }
    pdd_pdf_text(out,x,y,9,pdd_pdf_short(m_cat(label,name),60));
    pdd_pdf_text(out,x,y-47,8,pdd_pdf_short(method,65));
    return 0;
}

fn phd_pdf_issue(out,report,kind,id,y) {
    let issue=load64(j_get(report,"issues")+16);
    while issue && (!m_eq(j_string(issue,"record_kind"),kind) || !m_eq(j_string(issue,"record_id"),id)) {
        issue=load64(issue+24);
    }
    if !issue {return 0;}
    m_text(out,"q 0.61 0.14 0.11 rg\n");
    pdd_pdf_text(out,145,y,8,pdd_pdf_short(j_string(issue,"detail"),128));
    m_text(out,"Q\n");
    return 0;
}

fn phd_pdf_wire(page) {
    let out=m_buffer();
    let report=phd_pdf_header(out,page,"Wire schedule","Cut lengths, route allowances and end preparation in millimetres");
    let row=j_integer(page,"first");let i=0;let y=1680;
    if !row {pdd_pdf_text(out,145,y,10,"No wire segments are declared");}
    while row && i<4 {
        let id=j_string(row,"id");let title=m_cat(j_string(row,"name"),m_cat("  |  ",id));
        let net=pgt_label(row,"net_name","Unassigned net");
        title=m_cat(title,m_cat("  |  ",net));
        let color=j_string(row,"color");
        if m_len(color) {title=m_cat(title,m_cat("  |  ",color));}
        pdd_pdf_text(out,145,y,11,pdd_pdf_short(title,103));
        let spec=pgt_label(row,"specification","Wire specification needs review");
        pdd_pdf_text(out,145,y-54,9,pdd_pdf_short(spec,60));
        let cable=j_string(row,"cable_name");
        if m_len(cable) {pdd_pdf_text(out,1515,y-54,9,pdd_pdf_short(m_cat("Cable or bundle  ",cable),62));}
        let cut=phd_pdf_number(row,"length_mm");
        let numbers=m_cat("Specified cut ",m_cat(cut,m_cat("  |  route ",phd_pdf_number(row,"route_length_mm"))));
        numbers=m_cat(numbers,m_cat("  |  allowance ",m_cat(phd_pdf_number(row,"allowance_mm"),
            m_cat("  |  provisional ",phd_pdf_number(row,"provisional_cut_mm")))));
        if m_eq(j_string(row,"centerline"),"rounded") {numbers=m_cat(numbers,"  |  rounded centerline");}
        pdd_pdf_text(out,145,y-106,8,numbers);
        phd_pdf_preparation(out,j_get(row,"from"),145,y-162,"From  ");
        phd_pdf_preparation(out,j_get(row,"to"),1515,y-162,"To  ");
        let reason=pgt_label(row,"cut_reason","Cut method needs review");
        pdd_pdf_text(out,145,y-258,8,pdd_pdf_short(reason,135));
        phd_pdf_issue(out,report,"wire",id,y-305);
        pdd_pdf_line(out,145,y-333,2825,y-333);m_text(out,"S\n");
        y=y-380;i=i+1;row=load64(row+24);
    }
    return phd_pdf_footer(out,report);
}

fn phd_pdf_jackets(page) {
    let out=m_buffer();
    let report=phd_pdf_header(out,page,"Cable jacket schedule","Shared jacket lengths, breakout identities and cut allowances in millimetres");
    let row=j_integer(page,"first");let i=0;let y=1680;
    while row && i<4 {
        let id=j_string(row,"cable_id");
        let title=m_cat(pgt_label(row,"name",id),m_cat("  |  ",id));
        pdd_pdf_text(out,145,y,11,pdd_pdf_short(title,100));
        pdd_pdf_text(out,145,y-54,9,pdd_pdf_short(pgt_label(row,"specification","Jacket specification needs review"),110));
        let cut=m_cat("Specified cut ",phd_pdf_number(row,"cut_length_mm"));
        let length=m_cat("  |  jacket ",phd_pdf_number(row,"length_mm"));
        let allowance=m_cat("  |  allowance ",phd_pdf_number(row,"allowance_mm"));
        let provisional=m_cat("  |  provisional ",phd_pdf_number(row,"provisional_cut_mm"));
        pdd_pdf_text(out,145,y-106,8,m_cat(cut,m_cat(length,m_cat(allowance,provisional))));
        let point=load64(j_get(row,"breakouts")+16);let line=y-159;let n=1;
        while point && n<=2 {
            let text=m_cat("Breakout ",m_cat(m_int(n),m_cat("  ",j_string(point,"id"))));
            pdd_pdf_text(out,145,line,8,pdd_pdf_short(m_cat(text,m_cat("  |  ",j_encode(j_get(point,"at")))),115));
            point=load64(point+24);n=n+1;line=line-47;
        }
        phd_pdf_issue(out,report,"jacket",id,y-305);
        pdd_pdf_line(out,145,y-333,2825,y-333);m_text(out,"S\n");
        row=load64(row+24);i=i+1;y=y-380;
    }
    return phd_pdf_footer(out,report);
}

fn phd_pdf_splices(page) {
    let out=m_buffer();
    let report=phd_pdf_header(out,page,"Splice schedule","Assembly positions in millimetres and explicitly joined wire ends");
    let row=j_integer(page,"first");let i=0;let y=1680;
    while row && i<4 {
        let id=j_string(row,"splice_id");
        pdd_pdf_text(out,145,y,11,pdd_pdf_short(m_cat(pgt_label(row,"name",id),m_cat("  |  ",id)),100));
        let method=pgt_label(row,"method","Joining method needs review");
        let spec=pgt_label(row,"specification","Splice specification needs review");
        pdd_pdf_text(out,145,y-54,9,pdd_pdf_short(m_cat(method,m_cat("  |  ",spec)),115));
        let at=j_get(row,"at");let location="Placement unresolved";
        if at {location=m_cat("Assembly XYZ  ",j_encode(at));}
        pdd_pdf_text(out,145,y-106,8,location);
        let members=j_get(row,"members");let end=load64(members+16);let k=0;
        while end && k<4 {
            let x=145;if k%2 {x=1515;}
            let text=m_cat(j_string(end,"wire_id"),m_cat("  |  ",j_string(end,"side")));
            pdd_pdf_text(out,x,y-154-(k/2)*47,8,pdd_pdf_short(text,60));
            k=k+1;end=load64(end+24);
        }
        if end {pdd_pdf_text(out,145,y-248,8,m_cat(m_int(cg_j_count(members)-4)," more wire ends in harness.json"));}
        phd_pdf_issue(out,report,"splice",id,y-305);
        pdd_pdf_line(out,145,y-333,2825,y-333);m_text(out,"S\n");
        row=load64(row+24);i=i+1;y=y-380;
    }
    return phd_pdf_footer(out,report);
}

fn phd_pdf_add(pages,report,pinout,rows,limit,schedule) {
    let number=1;let more=1;
    while more {
        let page=j_object();cg_j_int(page,"harness_report",report);
        cg_j_int(page,"first",rows);cg_j_int(page,"sheet_no",number);
        if pinout {cg_j_int(page,"pinout",pinout);}
        if schedule {cg_j_int(page,"schedule",schedule);}
        j_add(pages,0,page);
        let i=0;while rows && i<limit {rows=load64(rows+24);i=i+1;}
        number=number+1;more=rows;
    }
    return 0;
}

fn pcad_harness_pdf_append(pages,report) {
    let wires=j_get(report,"wire_schedule");let pinouts=j_get(report,"pinouts");
    if j_kind(pages)!=3 || j_kind(wires)!=3 || j_kind(pinouts)!=3 {return 0;}
    phd_pdf_add(pages,report,0,load64(wires+16),4,0);
    let jackets=j_get(report,"jacket_schedule");
    if jackets {phd_pdf_add(pages,report,0,load64(jackets+16),4,1);}
    let splices=j_get(report,"splice_schedule");
    if splices {phd_pdf_add(pages,report,0,load64(splices+16),4,2);}
    let pinout=load64(pinouts+16);
    while pinout {
        phd_pdf_add(pages,report,pinout,load64(j_get(pinout,"contacts")+16),20,0);
        pinout=load64(pinout+24);
    }
    return 1;
}

fn phd_pdf_body(page) {
    if j_integer(page,"pinout") {return phd_pdf_pinout(page);}
    let schedule=j_integer(page,"schedule");
    if schedule==1 {return phd_pdf_jackets(page);}
    if schedule==2 {return phd_pdf_splices(page);}
    return phd_pdf_wire(page);
}

// The drawing engine and native harness renderer share one PDF container.
fn pcad_harness_pdf(pages) {
    let bodies=cg_json_array();let page=load64(pages+16);
    while page {
        let body=0;
        if j_get(page,"schematic_body") {body=j_string(page,"schematic_body");}
        else if j_get(page,"harness_report") {body=phd_pdf_body(page);}
        else {body=pdd_pdf_body(page);}
        cg_json_push(bodies,j_text(body));page=load64(page+24);
    }
    return pdd_pdf_document(pages,bodies);
}
