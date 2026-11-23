import "cad/product-bom.flex";

fn bom_contains(text,needle) {
    let n=m_len(needle);let length=m_len(text);let at=0;
    while at+n<=length {
        if load8(text+at)==load8(needle) && m_eq(m_slice(text+at,n),needle) {return 1;}
        at=at+1;
    }
    return 0;
}

fn bom_request(document,offset,stock) {
    let input=j_object();j_add(input,"document",j_parse(j_encode(document)));
    cg_j_int(input,"offset",offset);
    if stock {cg_j_int(input,"wire_stock",1);}
    return pdb_interactive(input);
}

fn bom_local() {
    let document=j_parse("{\"format\":\"puppycorp.pcad\",\"schema_version\":1,\"units\":\"mm\",\"nodes\":[{\"id\":\"block\",\"type\":\"box\",\"size\":[24,16,9]}],\"parts\":[{\"id\":\"enclosure\",\"node\":\"block\",\"name\":\"Enclosure\"}],\"electrical\":{\"harness\":{\"wire_stock\":[{\"id\":\"red\",\"name\":\"Red wire\",\"unit\":\"mm\",\"allowance_mm\":2.5,\"manufacturer\":\"Example\",\"part_number\":\"#24\"},{\"id\":\"black\",\"name\":\"Black wire\",\"unit\":\"mm\",\"allowance_mm\":3.5}],\"wires\":[{\"id\":\"first\",\"stock_id\":\"red\",\"length_mm\":12.25},{\"id\":\"second\",\"stock_id\":\"red\",\"length_mm\":20},{\"id\":\"unknown\",\"stock_id\":\"black\"}]}},\"bom_order\":[\"wire/second\",\"wire/obsolete\"]}");
    let harness=j_get(j_get(document,"electrical"),"harness");let wires=j_get(harness,"wires");let i=1;
    while i<=20 {
        let wire=j_object();cg_j_text(wire,"id",m_cat("loose-",m_int(i)));cg_j_text(wire,"name"," =1+\"test ä\"");j_add(wires,0,wire);i=i+1;
    }
    let original=j_encode(document);let bom=cad_pcad_product_bom(document);
    m_assert(!cg_error && m_eq(j_string(bom,"format"),"biscuit-pcad-product-bom-1"),j_string(bom,"error"));
    let items=j_get(bom,"items");let first=load64(items+16);
    m_assert(cg_j_count(items)==24 && m_eq(j_string(first,"id"),"wire/second") && j_integer(first,"item_number")==1,"Order hints prioritize roots and skip missing IDs");
    m_assert(m_eq(j_encode(document),original),"BOM evaluation preserves the authored document");
    let stock=j_get(bom,"wire_stock");let groups=j_get(stock,"rows");
    let red=load64(groups+16);let black=load64(red+24);
    m_assert(m_eq(j_string(red,"status"),"ready") && j_integer(red,"cut_count")==2 && m_eq(j_encode(j_get(red,"required_stock_mm")),"37.250000"),"Sum manual cuts and per-cut allowance exactly");
    m_assert(m_eq(j_string(black,"status"),"cut-incomplete") && j_integer(black,"unknown_cut_count")==1 && !j_get(black,"required_stock_mm"),"Unspecified cut length stays unknown");
    m_assert(cg_j_count(j_get(stock,"unassigned_wire_ids"))==20,"Unassigned wires retain their IDs");

    let page=bom_request(document,20,0);
    m_assert(j_integer(page,"total")==24 && cg_j_count(j_get(page,"items"))==4 && j_integer(load64(j_get(page,"items")+16),"item_number")==21,"Pages use original global item numbers");
    m_assert(m_eq(j_encode(j_get(page,"assembly_order")),"[\"instance/enclosure\"]"),"Keep the full occurrence ordering on every page");
    let stock_page=bom_request(document,0,1);
    m_assert(m_eq(j_string(stock_page,"view"),"wire-stock") && j_integer(stock_page,"total")==2 && m_eq(j_encode(j_get(stock_page,"items")),j_encode(groups)),"Stock view matches the product report");

    let bom_csv=cad_pcad_product_bom_csv(bom,"manifest","source");
    m_assert(bom_contains(bom_csv,"\r\n\"manifest\",\"source\",1,\"wire/second\"") && bom_contains(bom_csv,"\"' =1+\"\"test ä\"\"\""),"CSV binds source and manifest and quotes formula-like authored names");
    let stock_csv=cad_pcad_wire_stock_csv(stock,"manifest","source");
    m_assert(bom_contains(stock_csv,"37.250000,\"ready\",\"[\"\"first\"\",\"\"second\"\"]\"\r\n") && bom_contains(stock_csv,",unassigned,\"[\"\"loose-1\"\""),"Stock CSV preserves declared cut totals and unassigned IDs");
    cg_j_text(red,"name","Only the report is mutable");
    m_assert(m_eq(j_encode(document),original),"A report never aliases authored inputs");
    cg_j_text(load64(wires+16),"stock_id","unknown-stock");
    let invalid=cad_pcad_product_bom(document);
    m_assert(m_eq(j_string(invalid,"error"),"Wire references an undeclared stock item"),"Invalid stock assignment reports its original diagnostic");
}

fn bom_sensor(path) {
    let document=j_parse(m_read_file(path));m_assert(document,"Load the standalone three-wire fixture");
    let bom=cad_pcad_product_bom(document);m_assert(!cg_error,j_string(bom,"error"));
    let stock=j_get(bom,"wire_stock");let rows=j_get(stock,"rows");let row=load64(rows+16);
    m_assert(cg_j_count(rows)==3 && cg_j_count(j_get(stock,"unassigned_wire_ids"))==0,"Three sourced stock variants stay distinct");
    while row {
        m_assert(j_integer(row,"cut_count")==1 && m_eq(j_encode(j_get(row,"required_stock_mm")),"215.000000"),"Each harness cut gets its own allowance");
        row=load64(row+24);
    }
    let items=j_get(bom,"items");let modules=0;let boards=0;row=load64(items+16);
    while row {
        if j_get(row,"module_occurrence") {modules=modules+1;}
        if m_eq(j_string(row,"kind"),"pcb-assembly") {boards=boards+1;}
        row=load64(row+24);
    }
    m_assert(modules==2 && boards==2,"Preserve both authored PCB occurrences and expanded module provenance");
}

fn main(argc,argv) {
    bom_local();
    if argc==2 {bom_sensor(load64(argv+8));}
    return 0;
}
