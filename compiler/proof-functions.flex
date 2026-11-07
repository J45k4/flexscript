// Function flags share the annotation-scan field: bit 1 marks a spec function,
// bit 2 a lemma; bit 0 still marks bodies needing annotation parsing.
fn ph_kind(f) {if !f {return 0;}return load64(f+104)&6;}
fn ph_error(node,message) {pf_select(load64(node+40));token_start=load64(node+32);fail(message);return 0;}
fn ph_call(kind) {return kind==7 || kind==24 || kind==25 || kind==26;}
fn ph_walk(owner,node,graph,depth) {
    if !node {return 0;}if depth>128 {ph_error(node,"proof function expression depth exceeded");}let kind=load64(node);
    if ph_call(kind) {
        let f=pf_function(load64(node+8),load64(node+16));
        if graph {if f {pm_set(pm_graph,pm_index(owner),pm_index(f));}}
        else {
            let primitive=vm_primitive(node);
            if primitive {vm_validate(owner,node,primitive);}
            else if kind==7 {if ph_kind(f) {ph_error(node,"executable code cannot call spec functions or lemmas");}}
            else {
                if !f || !ph_kind(f) {ph_error(node,"specification calls require a supported spec function");}
                if ph_kind(f)==4 && kind!=25 {ph_error(node,"lemmas may be called only as proof statements");}
                if load64(f+56)!=load64(node+56) {ph_error(node,"wrong proof function argument count");}
            }
        }
        let argument=load64(node+24);while argument {ph_walk(owner,argument,graph,depth+1);argument=load64(argument+48);}
    }else if kind==3 {ph_walk(owner,load64(node+16),graph,depth+1);ph_walk(owner,load64(node+24),graph,depth+1);}
    else if kind==4 || kind==11 || kind==12 {ph_walk(owner,load64(node+16),graph,depth+1);}
    else if kind==6 || kind==13 || kind==17 || kind==18 {ph_walk(owner,load64(node+8),graph,depth+1);}
    else if kind==14 || kind==21 || kind==22 {ph_walk(owner,load64(node+8),graph,depth+1);ph_walk(owner,load64(node+16),graph,depth+1);ph_walk(owner,load64(node+24),graph,depth+1);}
    else if kind==15 {
        ph_walk(owner,load64(node+8),graph,depth+1);ph_walk(owner,load64(node+16),graph,depth+1);let clause=load64(node+24);
        while clause {let part=load64(clause+8);while part {ph_walk(owner,part,graph,depth+1);part=load64(part+48);}clause=load64(clause+48);}
    }else if kind==16 {let child=load64(node+8);while child {ph_walk(owner,child,graph,depth+1);child=load64(child+48);}}
    else if kind==8 && ph_kind(owner) {ph_error(node,"strings are not supported in proof functions");}
    return 0;
}
fn ph_function(f,graph) {
    if !graph || !pt_trusted(f) {ph_walk(f,load64(f+80),graph,0);}let clause=load64(f+64);
    while clause {let kind=load64(clause);
        if !graph && ph_kind(f) && kind==5 && load64(clause+8) {ph_error(clause,"proof functions cannot declare nonempty modifies frames");}
        if !graph && ph_kind(f) && kind==9 && load64(clause+8) {ph_error(clause,"proof functions cannot declare nonempty releases frames");}
        if kind==1 || kind==2 || kind==6 {let part=load64(clause+8);while part {ph_walk(f,part,graph,0);part=load64(part+48);}}
        if kind==4 || kind==5 || kind==9 {let item=load64(clause+8);while item {if load64(item)==10 {ph_walk(f,load64(item+8),graph,0);ph_walk(f,load64(item+16),graph,0);}item=load64(item+48);}}
        clause=load64(clause+48);
    }return 0;
}
fn ph_validate() {let i=0;while i<pf_count {let f=pf_functions+i*128;ph_function(f,0);pt_validate(f);i=i+1;}return 0;}
fn ph_save_bindings(values) {if !values {return 0;}let copy=alloc(128*8);if copy<0 {fail("cannot save quantified call bindings");}net_copy(copy,values,128*8);return copy;}
fn ph_restore_bindings(values,copy) {if copy {net_copy(values,copy,128*8);syscall(11,copy,128*8,0,0,0,0);}return 0;}
