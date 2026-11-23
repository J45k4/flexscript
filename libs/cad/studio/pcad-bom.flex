// Authoritative product occurrence identities and numbering for both Files
// drawings and frozen native releases. Input is the resolved PCAD document.
import "pcad-mechanical.flex";
import "pcad-net-rules.flex";
import "pcad-stock.flex";

fn pdb_first(row,key,limit) {
    let rows=j_get(row,key);
    if !rows {return 0;}
    if j_kind(rows)!=3 || cg_j_count(rows)>limit {return cg_fail(m_cat("Invalid product BOM list: ",key));}
    return load64(rows+16);
}

fn pdb_row(id,kind,quantity) {
    let row=j_object();cg_j_text(row,"id",id);cg_j_text(row,"kind",kind);cg_j_int(row,"quantity",quantity);
    return row;
}

fn pdb_sourcing(row,source) {
    let maker=j_string(source,"manufacturer");let number=j_string(source,"part_number");
    cg_j_text(row,"manufacturer",maker);cg_j_text(row,"part_number",number);
    let identity="unresolved";if m_len(maker) && m_len(number) {identity="declared";}
    cg_j_text(row,"purchasing_identity",identity);
    return 0;
}

fn pdb_component(items,component,parent) {
    let id=j_string(component,"id");
    let key=m_cat("component/",id);if m_len(parent) {key=m_cat(parent,m_cat("/",key));}
    let row=pdb_row(key,"electrical-component",1);
    cg_j_text(row,"component_id",id);cg_j_text(row,"parent_id",parent);
    cg_j_text(row,"reference",j_string(component,"reference"));cg_j_text(row,"value",j_string(component,"value"));
    pcc_copy(component,"module_occurrence",row);pdb_sourcing(row,component);
    let definition=j_get(component,"definition");
    if definition {
        let origin=j_object();pcc_copy(definition,"definition_id",origin);pcc_copy(definition,"revision",origin);
        j_add(row,"component_definition",origin);
    }
    let connector=j_get(component,"connector");
    if connector {
        let origin=j_object();pcc_copy(connector,"definition_id",origin);pcc_copy(connector,"revision",origin);
        j_add(row,"connector_definition",origin);
    }
    cg_push(items,row);return 0;
}

fn pdb_board(items,components,placed,board,id,instance,name,emit) {
    let key=m_cat("pcb/",instance);
    let row=pdb_row(key,"pcb-assembly",1);
    cg_j_text(row,"board_id",id);cg_j_text(row,"occurrence",instance);
    if !m_len(name) {name=j_string(board,"name");}
    if !m_len(name) {name=id;}
    cg_j_text(row,"name",name);
    let policy="manufactured";
    if j_get(board,"procurement") {
        policy=j_string(board,"procurement");
        if !m_eq(policy,"manufactured") && !m_eq(policy,"purchased") {return cg_fail("PCB procurement must be manufactured or purchased");}
    }
    cg_j_text(row,"procurement",policy);
    if m_eq(policy,"purchased") {pdb_sourcing(row,board);}
    if emit {cg_push(items,row);}
    let placement=pdb_first(board,"placements",6);
    let seen=j_object();
    while placement && !cg_error {
        let id=j_string(placement,"component_id");let item=j_integer(components,id);
        if !item || j_get(seen,id) {return cg_fail("BOM board placements need unique assigned component IDs");}
        cg_j_int(seen,id,1);
        if !j_get(placed,id) {cg_j_text(placed,id,j_string(row,"board_id"));}
        else if !m_eq(j_string(placed,id),j_string(row,"board_id")) {
            return cg_fail("A BOM component is placed on two different boards");
        }
        if emit && m_eq(policy,"manufactured") {pdb_component(items,item,key);}
        placement=load64(placement+24);
    }
    return 0;
}

fn pdb_body(items,id,name,part) {
    let row=pdb_row(m_cat("instance/",id),"mechanical-occurrence",1);
    cg_j_text(row,"occurrence",id);cg_j_text(row,"part_id",j_string(part,"id"));
    if !m_len(name) {name=j_string(part,"name");}
    if !m_len(name) {name=id;}
    cg_j_text(row,"name",name);pcc_copy(part,"material",row);pdb_sourcing(row,part);
    return cg_push(items,row);
}

fn pdb_wire(items,wire) {
    let id=j_string(wire,"id");
    if !ph_id(id,64,1) {return cg_fail("BOM wire segments need stable wire IDs");}
    let name=j_string(wire,"name");if !m_len(name) {name=id;}
    let row=pdb_row(m_cat("wire/",id),"wire-segment",1);
    cg_j_text(row,"wire_id",id);cg_j_text(row,"name",name);
    pcc_copy(wire,"length_mm",row);pcc_copy(wire,"cable_id",row);pcc_copy(wire,"color",row);pcc_copy(wire,"stock_id",row);
    cg_push(items,row);return 0;
}

fn pdb_index(index,id,row) {
    if !m_len(id) || m_len(id)>256 || j_get(index,id) {return cg_fail("Product BOM items require unique stable identities");}
    cg_j_int(index,id,row);return 1;
}

fn pdb_number_group(out,group,number) {
    let i=0;
    while i<cg_count(group) {
        let row=cg_at(group,i);
        cg_j_int(row,"item_number",number);cg_json_push(out,row);
        number=number+1;i=i+1;
    }
    return number;
}

// The priority order applies to root items. Each manufactured PCB keeps its
// members with it, and missing order hints never rebind to a different item.
fn pdb_order(source,raw,out) {
    let groups=j_object();let roots=cg_array();let identities=j_object();let i=0;
    while i<cg_count(raw) && !cg_error {
        let row=cg_at(raw,i);let id=j_string(row,"id");let parent=j_string(row,"parent_id");
        if !pdb_index(identities,id,row) {return 0;}
        let group=0;
        if m_len(parent) {group=j_integer(groups,parent);}
        else {
            group=cg_array();cg_j_int(groups,id,group);cg_push(roots,row);
        }
        if !group {return cg_fail("Product BOM item references a missing parent");}
        cg_push(group,row);i=i+1;
    }
    let seen=j_object();let number=1;
    let order=pdb_first(source,"bom_order",512);
    while order && !cg_error {
        let id=j_value(order);
        if j_kind(order)!=2 || !pdb_index(seen,id,1) {return cg_fail("BOM order needs unique item IDs");}
        number=pdb_number_group(out,j_integer(groups,id),number);
        order=load64(order+24);
    }
    i=0;
    while i<cg_count(roots) && !cg_error {
        let id=j_string(cg_at(roots,i),"id");
        if !j_get(seen,id) {number=pdb_number_group(out,j_integer(groups,id),number);}
        i=i+1;
    }
    return !cg_error;
}

fn pdb_product(doc) {
    let output=j_object();let raw=cg_array();let items=cg_json_array();
    cg_j_text(output,"format","biscuit-pcad-product-bom-1");j_add(output,"items",items);
    cg_j_text(output,"basis","Authored occurrences and PCB population. Purchased board modules and subassemblies occupy one procurement row. Wire rows are cut segments.");
    let electrical=j_get(doc,"electrical");let mounted=j_object();let placed=j_object();
    let components=j_object();let component=pdb_first(electrical,"components",96);
    while component && !cg_error {
        pdb_index(components,j_string(component,"id"),component);component=load64(component+24);
    }
    let assembled=j_get(doc,"assembly");let layout=cah_expand(doc);
    if cg_error {return ca_error();}
    let owners=pdb_first(assembled,"instances",16);
    if layout {owners=pdb_first(layout,"instances",32);}
    if !assembled {owners=pdb_first(doc,"parts",16);}
    let included=j_object();
    while owners && !cg_error {
        let id=j_string(owners,"id");let part=owners;
        let purchased=j_integer(included,cah_parent(id));
        if m_len(j_string(owners,"assembly")) {
            let sub=j_integer(j_get(layout,"assembly_definitions"),j_string(owners,"assembly"));
            if !sub {cg_fail("BOM subassembly occurrence requires a definition");return ca_error();}
            let policy=j_string(sub,"procurement");
            if j_get(sub,"procurement") && !m_eq(policy,"purchased") && !m_eq(policy,"manufactured") {
                cg_fail("Subassembly procurement must be manufactured or purchased");return ca_error();
            }
            if !purchased && m_eq(policy,"purchased") {
                let row=pdb_row(m_cat("assembly/",id),"purchased-assembly",1);
                let name=j_string(owners,"name");if !m_len(name) {name=j_string(sub,"name");}
                if !m_len(name) {name=id;}
                cg_j_text(row,"occurrence",id);cg_j_text(row,"name",name);
                cg_j_text(row,"assembly_definition",j_string(sub,"id"));pdb_sourcing(row,sub);
                cg_push(raw,row);purchased=1;
            }
            if purchased {cg_j_int(included,id,1);}
        }else {
            if assembled {part=pcm_find(j_get(doc,"parts"),j_string(owners,"part"));}
            if !part || !cah_path_id(id) {cg_fail("BOM occurrence requires a valid part identity");return ca_error();}
            let node=pcm_find(j_get(doc,"nodes"),j_string(part,"node"));
            if m_eq(j_string(node,"type"),"pcb-board") {
                let pcb=j_string(node,"board_id");let board=pcm_board(doc,pcb);
                if !board {cg_fail("BOM board occurrence references a missing board");return ca_error();}
                pdb_board(raw,components,placed,board,pcb,id,j_string(owners,"name"),!purchased);
                if !j_get(mounted,pcb) {cg_j_int(mounted,pcb,1);}
            }else if !purchased {pdb_body(raw,id,j_string(owners,"name"),part);}
        }
        owners=load64(owners+24);
    }
    let legacy=j_get(electrical,"pcb");let board=pdb_first(electrical,"boards",8);
    if legacy {
        if j_get(electrical,"boards") || j_kind(legacy)!=4 {cg_fail("Use one PCAD board representation");return ca_error();}
        if !j_get(mounted,"legacy-board") {pdb_board(raw,components,placed,legacy,"legacy-board","unmounted/legacy-board","",1);}
    }
    let board_ids=j_object();
    while board && !cg_error {
        let id=j_string(board,"id");
        if !pdb_index(board_ids,id,board) {return ca_error();}
        if !j_get(mounted,id) {pdb_board(raw,components,placed,board,id,m_cat("unmounted/",id),"",1);}
        board=load64(board+24);
    }
    component=pdb_first(electrical,"components",96);
    while component && !cg_error {
        if !j_get(placed,j_string(component,"id")) {pdb_component(raw,component,"");}
        component=load64(component+24);
    }
    let harness=j_get(electrical,"harness");let splice=pdb_first(harness,"splices",128);
    while splice && !cg_error {
        if j_get(splice,"placement") {
            let id=j_string(splice,"id");
            if !ph_id(id,64,1) {cg_fail("BOM splices need stable splice IDs");return ca_error();}
            let row=pdb_row(m_cat("splice/",id),"harness-splice",1);
            cg_j_text(row,"splice_id",id);pcc_copy(splice,"name",row);
            let construction=j_get(splice,"construction");
            pcc_copy(construction,"method",row);pcc_copy(construction,"specification",row);
            cg_push(raw,row);
        }
        splice=load64(splice+24);
    }
    let wire=pdb_first(harness,"wires",256);
    while wire && !cg_error {pdb_wire(raw,wire);wire=load64(wire+24);}
    if cg_count(raw)>512 {cg_fail("Product BOM exceeds 512 rows");}
    if cg_error || !pdb_order(doc,raw,items) {return ca_error();}
    let stock=pdb_stock(harness);
    if cg_error {return ca_error();}
    if stock {j_add(output,"wire_stock",stock);}
    return output;
}

fn pdb_interactive(input) {
    cg_begin();
    let authored=j_get(input,"document");
    if j_integer(input,"wire_stock") {return pdb_stock_page(j_get(j_get(authored,"electrical"),"harness"),j_integer(input,"offset"));}
    let doc=pcad_resolve(authored);
    if !doc {return ca_error();}
    let bom=pdb_product(doc);
    if m_len(j_string(bom,"error")) {return bom;}
    let rows=j_get(bom,"items");let total=cg_j_count(rows);let offset=j_integer(input,"offset");
    let out=j_object();let page=cg_json_array();let order=cg_json_array();
    cg_j_text(out,"format","biscuit-pcad-product-bom-page-1");
    cg_j_int(out,"offset",offset);cg_j_int(out,"total",total);
    j_add(out,"items",page);j_add(out,"assembly_order",order);
    let row=load64(rows+16);let i=0;
    while row {
        if i>=offset && i<offset+20 {cg_json_push(page,j_parse(j_encode(row)));}
        let owner=j_string(row,"occurrence");
        if m_len(owner) && !pdb_unmounted(owner) {cg_json_push(order,j_text(j_string(row,"id")));}
        row=load64(row+24);i=i+1;
    }
    return out;
}

fn pdb_unmounted(id) {
    return m_len(id)>=10 && m_eq(m_slice(id,10),"unmounted/");
}
