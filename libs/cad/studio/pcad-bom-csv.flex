// Spreadsheet projections of checked product and stock reports.
import "../math.flex";

fn pdb_csv_cell(out,value) {
    let kind=j_kind(value);
    if kind==1 || kind==5 || kind==6 {m_text(out,j_encode(value));return 0;}
    if kind!=2 {return 0;}
    let text=j_value(value);let n=m_len(text);let start=0;
    while start<n && load8(text+start)==32 {start=start+1;}
    let first=load8(text+start);
    m_text(out,"\"");
    // Keep authored text inert when spreadsheet applications open the CSV.
    if first==61 || first==43 || first==45 || first==64 || first==9 || first==13 || first==10 {m_text(out,"'");}
    let at=0;start=0;
    while at<n {
        if load8(text+at)==34 {m_append(out,text+start,at-start);m_text(out,"\"\"");start=at+1;}
        at=at+1;
    }
    m_append(out,text+start,n-start);m_text(out,"\"");return 0;
}

fn pdb_csv_values(out,row,keys) {
    let key=load64(keys+16);
    while key {m_text(out,",");pdb_csv_cell(out,j_get(row,j_value(key)));key=load64(key+24);}
    return 0;
}

fn pdb_csv_header(columns) {
    let out=m_buffer();m_text(out,"manifest_sha256,source_sha256,");m_text(out,columns);m_text(out,"\r\n");return out;
}

fn pdb_csv_identity(out,manifest_hash,source_hash) {
    pdb_csv_cell(out,j_text(manifest_hash));m_text(out,",");pdb_csv_cell(out,j_text(source_hash));return 0;
}

fn cad_pcad_product_bom_csv(bom,manifest_hash,source_hash) {
    let out=pdb_csv_header("item_number,item_id,parent_id,kind,quantity,occurrence_id,part_id,component_id,board_id,wire_id,cable_id,splice_id,stock_id,reference,name,value,material,manufacturer,part_number,procurement,purchasing_identity,method,specification,length_mm");
    let fields=j_parse("[\"item_number\",\"id\",\"parent_id\",\"kind\",\"quantity\",\"occurrence\",\"part_id\",\"component_id\",\"board_id\",\"wire_id\",\"cable_id\",\"splice_id\",\"stock_id\",\"reference\",\"name\",\"value\",\"material\",\"manufacturer\",\"part_number\",\"procurement\",\"purchasing_identity\",\"method\",\"specification\",\"length_mm\"]");
    let items=j_get(bom,"items");let row=0;if j_kind(items)==3 {row=load64(items+16);}
    while row {
        pdb_csv_identity(out,manifest_hash,source_hash);pdb_csv_values(out,row,fields);m_text(out,"\r\n");
        row=load64(row+24);
    }
    return m_data(out);
}

fn cad_pcad_wire_stock_csv(stock,manifest_hash,source_hash) {
    let out=pdb_csv_header("unit,stock_id,name,manufacturer,part_number,variant,purchasing_identity,cut_count,unknown_cut_count,known_cut_mm,allowance_per_cut_mm,required_stock_mm,status,wire_ids_json");
    let fields=j_parse("[\"stock_id\",\"name\",\"manufacturer\",\"part_number\",\"variant\",\"purchasing_identity\",\"cut_count\",\"unknown_cut_count\",\"known_cut_mm\",\"allowance_per_cut_mm\",\"required_stock_mm\",\"status\"]");
    let unit=j_get(stock,"unit");let items=j_get(stock,"rows");let row=0;
    if j_kind(items)==3 {row=load64(items+16);}
    while row {
        pdb_csv_identity(out,manifest_hash,source_hash);m_text(out,",");pdb_csv_cell(out,unit);
        pdb_csv_values(out,row,fields);m_text(out,",");pdb_csv_cell(out,j_text(j_encode(j_get(row,"wire_ids"))));m_text(out,"\r\n");
        row=load64(row+24);
    }
    let unassigned=j_get(stock,"unassigned_wire_ids");
    if cg_j_count(unassigned) {
        pdb_csv_identity(out,manifest_hash,source_hash);m_text(out,",");pdb_csv_cell(out,unit);
        m_text(out,",,,,,,,,,,,,unassigned,");pdb_csv_cell(out,j_text(j_encode(unassigned)));m_text(out,"\r\n");
    }
    return m_data(out);
}
