// Purchasing projection over exact manual cuts and declared stock identities.
import "pcad-length.flex";

fn pdb_stock_text(row,key,optional) {
    let value=j_get(row,key);
    if !value && optional {return 1;}
    if j_kind(value)!=2 {return 0;}
    let text=j_value(value);let n=m_len(text);
    if !n || n>80 || !m_utf8(text) || load8(text)==32 || load8(text+n-1)==32 {return 0;}
    let i=0;
    while i<n {
        let c=load8(text+i);
        if c<32 || c==127 {return 0;}
        i=i+1;
    }
    return 1;
}

fn pdb_stock(harness) {
    let catalog=j_get(harness,"wire_stock");
    let wires=pdb_first(harness,"wires",256);
    if !catalog {
        let wire=wires;
        while wire {
            if j_get(wire,"stock_id") {return cg_fail("Wire references an undeclared stock item");}
            wire=load64(wire+24);
        }
        return 0;
    }
    let item=pdb_first(harness,"wire_stock",32);
    if cg_error {return 0;}
    let groups=j_object();let rows=cg_json_array();let identities=j_object();
    while item {
        let id=j_string(item,"id");let allowance=pcd_length(j_get(item,"allowance_mm"),1000000);
        if !ph_id(id,48,1) || j_get(groups,id) || !m_eq(j_string(item,"unit"),"mm") || allowance<0
            || !pdb_stock_text(item,"name",0) || !pdb_stock_text(item,"manufacturer",1)
            || !pdb_stock_text(item,"part_number",1) || !pdb_stock_text(item,"variant",1) {
            return cg_fail("Wire stock needs a unique ID, name, millimetre units and an explicit allowance per cut");
        }
        let maker=j_string(item,"manufacturer");let part=j_string(item,"part_number");let variant=j_string(item,"variant");
        if m_len(maker) && m_len(part) {
            let key=m_cat(maker,m_cat("\n",m_cat(part,m_cat("\n",variant))));
            if j_get(identities,key) {return cg_fail("Assign wires with the same purchasing identity to one stock item");}
            cg_j_int(identities,key,1);
        }
        let group=m_take(40);store64(group,allowance);store64(group+8,0);store64(group+16,0);
        let links=cg_json_array();store64(group+24,links);
        let row=j_object();store64(group+32,row);
        cg_j_int(groups,id,group);cg_json_push(rows,row);
        cg_j_text(row,"stock_id",id);pcc_copy(item,"name",row);pcc_copy(item,"variant",row);
        pdb_sourcing(row,item);
        j_add(row,"wire_ids",links);j_add(row,"allowance_per_cut_mm",cg_json_number(allowance));
        item=load64(item+24);
    }
    let unassigned=cg_json_array();let seen=j_object();
    while wires {
        let id=j_string(wires,"id");let stock=j_get(wires,"stock_id");
        if !ph_id(id,64,1) || j_get(seen,id) {return cg_fail("Wire stock links need unique stable wire IDs");}
        cg_j_int(seen,id,1);
        if !stock {cg_json_push(unassigned,j_text(id));}
        else {
            let group=j_integer(groups,j_string(wires,"stock_id"));
            if !group {return cg_fail("Wire references an undeclared stock item");}
            let length=pcd_length(j_get(wires,"length_mm"),1000000);
            cg_json_push(load64(group+24),j_text(id));
            if length<=0 {store64(group+16,load64(group+16)+1);}
            else {store64(group+8,load64(group+8)+length);}
        }
        wires=load64(wires+24);
    }
    let out=j_object();
    cg_j_text(out,"unit","mm");j_add(out,"rows",rows);j_add(out,"unassigned_wire_ids",unassigned);
    let entry=load64(groups+16);
    while entry {
        let group=j_value(entry);let row=load64(group+32);let missing=load64(group+16);
        let cut=load64(group+8);let count=cg_j_count(load64(group+24));
        cg_j_int(row,"unknown_cut_count",missing);cg_j_int(row,"cut_count",count);
        j_add(row,"known_cut_mm",cg_json_number(cut));
        let status="ready";
        if !count {status="unused";}
        else if m_eq(j_string(row,"purchasing_identity"),"unresolved") {status="identity-unresolved";}
        if missing {status="cut-incomplete";}
        else {j_add(row,"required_stock_mm",cg_json_number(cut+count*load64(group)));}
        cg_j_text(row,"status",status);
        entry=load64(entry+24);
    }
    return out;
}

fn pdb_stock_page(harness,offset) {
    let stock=pdb_stock(harness);
    if cg_error {return ca_error();}
    let rows=j_get(stock,"rows");let row=0;
    if rows {row=load64(rows+16);}
    let out=j_object();let items=cg_json_array();
    cg_j_text(out,"format","biscuit-pcad-product-bom-page-1");
    cg_j_text(out,"view","wire-stock");cg_j_text(out,"unit","mm");
    cg_j_int(out,"offset",offset);cg_j_int(out,"total",cg_j_count(rows));
    j_add(out,"items",items);j_add(out,"assembly_order",j_array());
    let missing=j_get(stock,"unassigned_wire_ids");
    if !missing {
        missing=cg_json_array();let wire=pdb_first(harness,"wires",256);let seen=j_object();
        while wire {
            let id=j_string(wire,"id");
            if !ph_id(id,64,1) || j_get(seen,id) {cg_fail("Wire stock links need unique stable wire IDs");return ca_error();}
            cg_j_int(seen,id,1);cg_json_push(missing,j_text(id));wire=load64(wire+24);
        }
    }
    j_add(out,"unassigned_wire_ids",missing);
    let index=0;
    while row {
        if index>=offset && index<offset+20 {cg_json_push(items,j_parse(j_encode(row)));}
        row=load64(row+24);index=index+1;
    }
    return out;
}
