// Acyclic named lengths in locally authored millimetres. Scale and divide use
// dimensionless literals. All math uses the same fixed-point units as CAD.
import "math.flex";

fn cp_target(index,field) {
    let id="";if j_kind(field)==2 {id=j_value(field);}
    let slot=j_integer(index,id);
    if !slot {return cg_fail(m_cat("Missing dimension parameter: ",id));}
    return cp_resolve(index,slot);
}

fn cp_operand(index,field,scalar) {
    if j_kind(field)!=4 || cg_j_count(field)!=1 {
        return cg_fail("Parameter expressions need one value per operand");
    }
    if scalar {return cg_number(j_get(field,"scalar"));}
    let reference=j_get(field,"parameter");
    if reference {return cp_target(index,reference);}
    return cg_number(j_get(field,"mm"));
}

fn cp_expression(index,row) {
    if j_kind(row)!=4 || cg_j_count(row)!=3 {
        return cg_fail("Parameter expressions need an operation and two operands");
    }
    let operation=j_string(row,"operation");
    let scale=m_eq(operation,"scale");let divide=m_eq(operation,"divide");
    let add=m_eq(operation,"add");let subtract=m_eq(operation,"subtract");
    if !scale && !divide && !add && !subtract {return cg_fail("Unsupported parameter expression operation");}
    let left=cp_operand(index,j_get(row,"left"),0);
    if cg_error {return 0;}
    let right=cp_operand(index,j_get(row,"right"),scale || divide);
    if cg_error {return 0;}
    if scale {return left*right/1000000;}
    if divide {
        if !right {return cg_fail("Cannot divide a parameter by zero");}
        return left*1000000/right;
    }
    if add {return left+right;}
    return left-right;
}

// Each slot holds the immutable authored definition, a visit state and value.
fn cp_resolve(index,slot) {
    let row=load64(slot);let state=load64(slot+8);
    if state==2 {return load64(slot+16);}
    let id=j_string(row,"id");
    if state==1 {return cg_fail(m_cat("Cyclic dimension parameter: ",id));}
    store64(slot+8,1);
    let expression=j_get(row,"expression");
    let literal=j_get(row,"mm");
    if (!literal && !expression) || (literal && expression) {
        return cg_fail(m_cat("Parameter needs a literal or an expression: ",id));
    }
    let value=0;
    if expression {value=cp_expression(index,expression);}
    else {value=cg_number(literal);}
    if cg_error {return 0;}
    if cg_abs(value)>500000000 {return cg_fail(m_cat("Parameter must resolve within +/-500 mm: ",id));}
    store64(slot+16,value);store64(slot+8,2);
    return value;
}

fn cp_catalog(rows,report) {
    if !rows {return 0;}
    if j_kind(rows)!=3 || cg_j_count(rows)>32 {return cg_fail("Use at most 32 named dimension parameters");}
    let index=j_object();let row=load64(rows+16);
    while row && !cg_error {
        let id=j_string(row,"id");let name=j_string(row,"name");
        if !cg_id(id) || j_get(index,id) || !m_len(name) || m_len(name)>96 {
            return cg_fail("Dimension parameters need unique IDs and names of 1 to 96 bytes");
        }
        let slot=m_take(24);store64(slot,row);store64(slot+8,0);
        cg_j_int(index,id,slot);
        row=load64(row+24);
    }
    row=load64(index+16);
    while row && !cg_error {
        let value=cp_resolve(index,j_value(row));
        if report && !cg_error {
            let item=j_object();
            cg_j_text(item,"id",load64(row+32));
            j_add(item,"mm",cg_json_number(value));j_add(report,0,item);
        }
        row=load64(row+24);
    }
    return index;
}

fn cp_dimension(index,row,literal,binding) {
    let reference=j_get(row,binding);
    if reference {return cp_target(index,reference);}
    return cg_number(j_get(row,literal));
}
