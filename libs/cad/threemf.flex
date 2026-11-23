// 3MF core manufacturing package. Uses stored ZIP entries so the same
// exporter can run in the checked interpreter without a native codec.
import "project.flex";

fn mf_xml_text(buffer,text) {
    let i=0;
    while load8(text+i) {
        let c=load8(text+i);
        if c==38 {m_text(buffer,"&amp;");}
        else if c==60 {m_text(buffer,"&lt;");}
        else if c==62 {m_text(buffer,"&gt;");}
        else if c==34 {m_text(buffer,"&quot;");}
        else if c==39 {m_text(buffer,"&apos;");}
        else if c==9 || c==10 || c==13 {
            m_text(buffer,"&#");m_text(buffer,m_int(c));m_text(buffer,";");
        }else if c==239 && load8(text+i+1)==191 && (load8(text+i+2)==190 || load8(text+i+2)==191) {
            // U+FFFE and U+FFFF cannot appear in XML 1.0.
            i=i+2;
        }else if c>=32 {m_append(buffer,text+i,1);}
        i=i+1;
    }
    return 1;
}
fn mf_vertex(buffer,point) {
    m_text(buffer,"<vertex x=\"");m_text(buffer,cg_decimal(load64(point)));
    m_text(buffer,"\" y=\"");m_text(buffer,cg_decimal(load64(point+8)));
    m_text(buffer,"\" z=\"");m_text(buffer,cg_decimal(load64(point+16)));m_text(buffer,"\"/>\n");
    return 1;
}
fn mf_object(xml,part,id,vertices,count) {
    let ids=m_take(count*8);let i=0;
    while i<count {store64(ids+i*8,-1);i=i+1;}
    m_text(xml,"<object type=\"model\" id=\"");m_text(xml,m_int(id));
    m_text(xml,"\" name=\"");mf_xml_text(xml,j_string(part,"name"));m_text(xml,"\"><mesh><vertices>\n");
    let faces=m_buffer();let next=0;let corner=0;
    let entry=pc_first(j_get(part,"triangles"));
    while entry {
        let index=j_value(entry);
        if j_kind(entry)!=1 || index<0 || index>=count {return cg_fail("Invalid 3MF vertex reference");}
        let slot=ids+index*8;
        if load64(slot)<0 {
            mf_vertex(xml,load64(vertices+index*8));store64(slot,next);next=next+1;
        }
        if corner==0 {m_text(faces,"<triangle v1=\"");}
        else if corner==1 {m_text(faces,"\" v2=\"");}
        else {m_text(faces,"\" v3=\"");}
        m_text(faces,m_int(load64(slot)));
        corner=(corner+1)%3;
        if !corner {m_text(faces,"\"/>\n");}
        entry=load64(entry+24);
    }
    if corner || !next {return cg_fail("Incomplete 3MF mesh");}
    m_text(xml,"</vertices><triangles>\n");m_append(xml,m_data(faces),load64(faces+8));
    m_text(xml,"</triangles></mesh></object>\n");return 1;
}
fn mf_model(project,mesh) {
    let points=j_get(mesh,"vertices");let count=cg_j_count(points);
    let vertices=m_take(count*8);let point=pc_first(points);let i=0;
    while point {
        store64(vertices+i*8,cg_vector(point,0));point=load64(point+24);i=i+1;
    }
    if cg_error {return 0;}
    let xml=m_buffer();
    m_text(xml,"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<model unit=\"millimeter\" xml:lang=\"en-US\" xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\">\n<metadata name=\"Title\">");
    let title=j_string(cad_project_item(project),"name");
    if cad_project_is_studio(project) {title=j_string(project,"name");if !m_len(title) {title="PCAD design";}}
    mf_xml_text(xml,title);m_text(xml,"</metadata>\n<metadata name=\"Application\">PuppyCAD</metadata>\n<resources>\n");
    let part=pc_first(j_get(mesh,"parts"));let id=1;let items=m_buffer();
    while part {
        if !mf_object(xml,part,id,vertices,count) {return 0;}
        m_text(items,"<item objectid=\"");m_text(items,m_int(id));m_text(items,"\"/>\n");
        id=id+1;part=load64(part+24);
    }
    m_text(xml,"</resources><build>\n");m_append(xml,m_data(items),load64(items+8));m_text(xml,"</build></model>\n");
    return m_data(xml);
}
fn mf_u16(p,value) {store8(p,value);store8(p+1,value>>8);return 0;}
fn mf_zip_entry(archive,central,table,name,text) {
    let size=m_len(text);let n=m_len(name);let crc=0xffffffff;let i=0;
    while i<size {crc=(crc>>8)^load64(table+((crc^load8(text+i))&255)*8);i=i+1;}
    crc=crc^0xffffffff;
    let local=m_take(30);let dir=m_take(46);i=0;
    while i<46 {if i<30 {store8(local+i,0);}store8(dir+i,0);i=i+1;}
    cg_put32(local,0x04034b50);mf_u16(local+4,20);mf_u16(local+12,33);
    cg_put32(local+14,crc);cg_put32(local+18,size);cg_put32(local+22,size);mf_u16(local+26,n);
    cg_put32(dir,0x02014b50);mf_u16(dir+4,20);
    // The common fields run from 'version needed' through filename length.
    m_copy(dir+6,local+4,24);cg_put32(dir+42,load64(archive+8));
    m_append(archive,local,30);m_text(archive,name);m_append(archive,text,size);
    m_append(central,dir,46);m_text(central,name);return 1;
}
fn cad_project_3mf(project) {
    let mesh=pc_project_mesh(project,1);if cg_error {return 0;}
    if !j_value(j_get(mesh,"closed")) {return cg_fail("3MF export requires a closed solid");}
    let model=mf_model(project,mesh);if !model {return 0;}
    let zip=m_buffer();let central=m_buffer();let table=m_take(256*8);let i=0;
    while i<256 {
        let crc=i;let bit=0;
        while bit<8 {let mask=-(crc&1);crc=(crc>>1)^(0xedb88320&mask);bit=bit+1;}
        store64(table+i*8,crc);i=i+1;
    }
    mf_zip_entry(zip,central,table,"[Content_Types].xml","<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"model\" ContentType=\"application/vnd.ms-package.3dmanufacturing-3dmodel+xml\"/></Types>");
    mf_zip_entry(zip,central,table,"_rels/.rels","<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Target=\"/3D/3dmodel.model\" Id=\"rel0\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/></Relationships>");
    mf_zip_entry(zip,central,table,"3D/3dmodel.model",model);
    let offset=load64(zip+8);m_append(zip,m_data(central),load64(central+8));
    let end=m_take(22);i=0;while i<22 {store8(end+i,0);i=i+1;}
    cg_put32(end,0x06054b50);mf_u16(end+8,3);mf_u16(end+10,3);
    cg_put32(end+12,load64(central+8));cg_put32(end+16,offset);m_append(zip,end,22);
    return zip;
}
