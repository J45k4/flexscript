// One deterministic plain vector PDF, using only fixed operators and a base font.
fn pdd_pdf_point(out,x,y) {
    m_text(out,m_int(x));m_text(out," ");m_text(out,m_int(y));m_text(out," ");return 0;
}
fn pdd_pdf_line(out,x,y,u,v) {
    pdd_pdf_point(out,x,y);m_text(out,"m ");pdd_pdf_point(out,u,v);m_text(out,"l\n");return 0;
}
fn pdd_pdf_text(out,x,y,size,text) {
    m_text(out,"BT /F1 ");m_text(out,m_int((size*254+36)/72));m_text(out," Tf ");
    pdd_pdf_point(out,x,y);m_text(out,"Td (");
    let i=0;
    while i<m_len(text) {
        let c=load8(text+i);
        if c==40 || c==41 || c==92 {m_text(out,"\\");}
        if c>=32 && c<=126 {m_append(out,text+i,1);}
        else if c<128 || c>=192 {m_text(out,"?");}
        i=i+1;
    }
    m_text(out,") Tj ET\n");return 0;
}

fn pdd_pdf_paths(out,lines) {
    let line=load64(lines+16);
    while line {
        let a=load64(line+16);let b=load64(a+24);let c=load64(b+24);let d=load64(c+24);
        pdd_pdf_line(out,j_value(a),j_value(b),j_value(c),j_value(d));
        line=load64(line+24);
    }
    m_text(out,"S\n");
    return 0;
}

fn pdd_pdf_details(out,callouts) {
    if !callouts {return 0;}
    m_text(out,"q 0.25 0.38 0.62 rg 0.25 0.38 0.62 RG 1.6 w [14 7] 0 d\n");
    let row=load64(callouts+16);
    while row {
        let a=load64(j_get(row,"a")+16);let b=load64(j_get(row,"b")+16);
        let left=j_value(a);let right=j_value(b);
        let bottom=j_value(load64(a+24));let top=j_value(load64(b+24));
        pdd_pdf_point(out,left,bottom);pdd_pdf_point(out,right-left,top-bottom);
        m_text(out,"re S\n");
        pdd_pdf_text(out,pdd_min(left,2610),top+20,9,pdd_detail_label(j_integer(row,"number")));
        row=load64(row+24);
    }
    m_text(out,"Q\n");
    return 0;
}

fn pdd_pdf_short(text,n) {
    if m_len(text)>n {return m_cat(m_slice(text,n-3),"...");}
    return text;
}
fn pdd_pdf_curve(out,x,y,u,v,p,q) {
    pdd_pdf_point(out,x,y);pdd_pdf_point(out,u,v);pdd_pdf_point(out,p,q);m_text(out,"c\n");return 0;
}
fn pdd_pdf_balloon(out,row) {
    let anchor=load64(j_get(row,"anchor")+16);let label=load64(j_get(row,"label_at")+16);
    let x=j_value(label);let y=j_value(load64(label+24));
    m_text(out,"q 0.21 0.34 0.49 RG 1.6 w\n");
    pdd_pdf_line(out,j_value(anchor),j_value(load64(anchor+24)),x,y);m_text(out,"S 1 1 1 rg\n");
    pdd_pdf_point(out,x+36,y);m_text(out,"m\n");
    pdd_pdf_curve(out,x+36,y+20,x+20,y+36,x,y+36);
    pdd_pdf_curve(out,x-20,y+36,x-36,y+20,x-36,y);
    pdd_pdf_curve(out,x-36,y-20,x-20,y-36,x,y-36);
    pdd_pdf_curve(out,x+20,y-36,x+36,y-20,x+36,y);
    m_text(out,"B 0.21 0.34 0.49 rg\n");
    let number=m_int(j_integer(row,"item_number"));
    pdd_pdf_text(out,x-m_len(number)*7,y-9,7,number);
    m_text(out,"Q\n");
    return 0;
}
fn pdd_pdf_parts(out,balloons) {
    pdd_pdf_text(out,1550,700,11,"Parts list");pdd_pdf_text(out,2710,700,8,"Qty");
    let y=602;let row=load64(balloons+16);
    while row {
        let number="?";let name=j_string(row,"problem");let qty="";
        if j_get(row,"label_at") {
            number=m_int(j_integer(row,"item_number"));name=j_string(row,"name");
            qty=m_int(j_integer(row,"quantity"));pdd_pdf_balloon(out,row);
        }else {m_text(out,"0.61 0.14 0.11 rg\n");}
        pdd_pdf_text(out,1550,y,8,number);
        pdd_pdf_text(out,1655,y,8,pdd_pdf_short(name,38));
        pdd_pdf_text(out,2710,y,8,qty);
        m_text(out,"0.13 0.19 0.17 rg\n");
        y=y-48;row=load64(row+24);
    }
    return 0;
}
fn pdd_pdf_body(page) {
    let out=m_buffer();
    m_text(out,".283464567 0 0 .283464567 0 0 cm\n0.13 0.19 0.17 rg 0.22 0.27 0.25 RG 2.5 w 1 J 1 j\n");
    pdd_pdf_text(out,140,1940,21,j_string(page,"name"));
    let orientation=j_string(page,"axis");if m_eq(orientation,"iso") {orientation="Isometric";}
    let view=" view";let exploded=j_integer(page,"exploded");
    if exploded {view=" - Exploded assembly";}
    let title=m_cat(orientation,m_cat(view,m_cat("  |  Scale ",pdd_scale_label(page))));
    let section=j_get(page,"section_mm");
    let type="  |  Feature edges through the model";
    if m_eq(j_string(page,"visibility"),"visible") {type="  |  Visible edges";}
    if m_eq(j_string(page,"visibility"),"hidden") {type="  |  Visible and hidden edges";}
    if section {type=m_cat("  |  Section at local view depth ",m_cat(cg_decimal(cg_number(section))," mm"));}
    pdd_pdf_text(out,145,1850,10,m_cat(title,type));
    let target=j_string(page,"target");if !m_len(target) {target="Entire model";}
    pdd_pdf_text(out,145,1795,9,m_cat("Occurrence  ",target));
    pdd_pdf_line(out,145,1760,2825,1760);m_text(out,"S\n");
    if j_get(page,"detail_parent_id") {
        let label=pdd_detail_label(j_integer(page,"detail_number"));
        pdd_pdf_text(out,145,1710,9,m_cat(label,m_cat(" of ",j_string(page,"detail_parent_name"))));
    }
    let guides=j_get(page,"exploded_guides");
    if cg_j_count(guides) {
        m_text(out,"q 0.42 0.47 0.45 RG 1.2 w [18 6 4 6] 0 d\n");
        pdd_pdf_paths(out,guides);
        m_text(out,"Q\n");
    }
    let hidden=j_get(page,"hidden_lines");
    if cg_j_count(hidden) {
        m_text(out,"q 0.42 0.47 0.45 RG 1.4 w [13 8] 0 d\n");
        pdd_pdf_paths(out,hidden);
        m_text(out,"Q\n");
    }
    pdd_pdf_paths(out,j_get(page,"lines"));
    pdd_pdf_details(out,j_get(page,"detail_callouts"));
    pdd_pdf_text(out,145,700,11,"Associative dimensions");
    let balloons=j_get(page,"balloons");let split=cg_j_count(balloons)>0;
    pdd_pdf_line(out,145,650,2825,650);
    if split {pdd_pdf_line(out,1485,650,1485,246);}
    m_text(out,"S\n");
    if split {pdd_pdf_parts(out,balloons);}
    let dimension=load64(j_get(page,"dimensions")+16);
    if !dimension {pdd_pdf_text(out,145,586,9,"No dimensions on this sheet");}
    while dimension {
        let i=j_integer(dimension,"number");let y=650-i*62;
        let a=j_get(dimension,"a");let b=j_get(dimension,"b");
        if a && b {
            let p=load64(j_get(dimension,"span_a")+16);let x=j_value(p);let v=j_value(load64(p+24));
            p=load64(j_get(dimension,"span_b")+16);let u=j_value(p);let w=j_value(load64(p+24));
            p=load64(a+16);let ax=j_value(p);let ay=j_value(load64(p+24));
            p=load64(b+16);let bx=j_value(p);let by=j_value(load64(p+24));
            m_text(out,"0.16 0.40 0.35 RG 1 w\n");
            pdd_pdf_line(out,ax,ay,x,v);pdd_pdf_line(out,bx,by,u,w);m_text(out,"S\n");
            m_text(out,"0.16 0.40 0.35 RG 0.16 0.40 0.35 rg 1.6 w [11 7] 0 d\n");
            pdd_pdf_line(out,x,v,u,w);m_text(out,"S [] 0 d\n");
            pdd_pdf_line(out,x-10,v-10,x+10,v+10);
            pdd_pdf_line(out,u-10,w-10,u+10,w+10);m_text(out,"S\n");
            pdd_pdf_text(out,(x+u)/2+12,(v+w)/2+12,9,m_int(i));
        }
        m_text(out,"0.13 0.19 0.17 rg\n");
        if !a {m_text(out,"0.61 0.14 0.11 rg\n");}
        pdd_pdf_text(out,145,y,9,m_int(i));
        if split {
            pdd_pdf_text(out,240,y+9,8,pdd_pdf_short(j_string(dimension,"name"),42));
            pdd_pdf_text(out,240,y-20,8,pdd_pdf_short(j_string(dimension,"label"),42));
        }else {
            pdd_pdf_text(out,240,y,9,j_string(dimension,"name"));
            pdd_pdf_text(out,1570,y,9,j_string(dimension,"label"));
        }
        dimension=load64(dimension+24);
    }
    m_text(out,"0.13 0.19 0.17 rg 0.22 0.27 0.25 RG 1.9 w\n");
    pdd_pdf_line(out,145,224,2825,224);m_text(out,"S\n");
    let footer="Millimetres  |  Authored configuration  |  Print at actual size";
    if exploded {footer="Millimetres  |  Presentation offsets  |  Print at actual size";}
    pdd_pdf_text(out,145,161,9,footer);
    pdd_pdf_text(out,145,106,8,j_string(page,"revision"));
    pdd_pdf_text(out,2500,161,9,"A4 landscape");
    return m_data(out);
}

fn pdd_pdf_object(out,offsets,id) {
    store64(offsets+id*8,load64(out+8));
    m_text(out,m_int(id));m_text(out," 0 obj\n");return 0;
}

fn pdd_pdf(pages) {return pdd_pdf_document(pages,0);}

fn pdd_pdf_document(pages,bodies) {
    let out=m_buffer();let count=cg_j_count(pages);let size=4+count*2;
    let offsets=m_take(size*8);
    m_text(out,"%PDF-1.4\n");
    pdd_pdf_object(out,offsets,1);m_text(out,"<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    pdd_pdf_object(out,offsets,2);m_text(out,"<< /Type /Pages /Kids [");
    let i=0;
    while i<count {m_text(out,m_int(4+i*2));m_text(out," 0 R ");i=i+1;}
    m_text(out,"] /Count ");m_text(out,m_int(count));m_text(out," >>\nendobj\n");
    pdd_pdf_object(out,offsets,3);m_text(out,"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n");
    let page=load64(pages+16);let prepared=0;i=4;
    if bodies {prepared=load64(bodies+16);}
    while page {
        let body=0;
        if prepared {body=j_value(prepared);prepared=load64(prepared+24);}
        else {body=pdd_pdf_body(page);}
        pdd_pdf_object(out,offsets,i);
        m_text(out,"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 841.889763 595.275590] /Resources << /Font << /F1 3 0 R >> >> /Contents ");
        m_text(out,m_int(i+1));m_text(out," 0 R >>\nendobj\n");
        pdd_pdf_object(out,offsets,i+1);
        m_text(out,"<< /Length ");m_text(out,m_int(m_len(body)));m_text(out," >>\nstream\n");
        m_text(out,body);m_text(out,"endstream\nendobj\n");
        page=load64(page+24);i=i+2;
    }
    let xref=load64(out+8);
    m_text(out,"xref\n0 ");m_text(out,m_int(size));m_text(out,"\n0000000000 65535 f \n");
    i=1;
    while i<size {
        let offset=m_int(load64(offsets+i*8));
        m_text(out,m_slice("0000000000",10-m_len(offset)));m_text(out,offset);m_text(out," 00000 n \n");i=i+1;
    }
    m_text(out,"trailer\n<< /Size ");m_text(out,m_int(size));m_text(out," /Root 1 0 R >>\nstartxref\n");
    m_text(out,m_int(xref));m_text(out,"\n%%EOF\n");
    return m_data(out);
}
