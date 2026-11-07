import "cnf.flex";
// This checker does not import SAT search or reuse its propagation routine.
// Caller supplies an allocated formula, node buffer, count and root, not an
// unchecked file pointer. A future file reader must validate artifact bounds.
fn pv_check_model(formula,assignment) {
    if !pv_formula_valid(formula) {return 0;}
    return pv_check_model_budget(formula,assignment,load64(formula)+load64(formula+8)+load64(formula+16)+1);
}
fn pv_check_model_budget(formula,assignment,budget) {
    if budget<=0 {return 0;}
    if !pv_formula_valid(formula) || !assignment {return 0;}let i=1;
    while i<=load64(formula) {if budget<=0 {return 0;}budget=budget-1;let v=load64(assignment+i*8);if v!=1 && v!= -1 {return 0;}i=i+1;}
    let c=0;while c<load64(formula+8) {if budget<=0 {return 0;}budget=budget-1;let row=load64(formula+48)+c*16;let j=0;let satisfied=0;
        while j<load64(row+8) {if budget<=0 {return 0;}budget=budget-1;let literal=load64(load64(formula+56)+(load64(row)+j)*8);let variable=literal;if variable<0 {variable= -variable;}
            let value=load64(assignment+variable*8);if (literal>0 && value==1) || (literal<0 && value== -1) {satisfied=1;}j=j+1;
        }if !satisfied {return 0;}c=c+1;
    }return 1;
}
// Checker state: formula, nodes, count, remaining work, assignment, trail, used.
fn pv_kernel_tick(state) {let n=load64(state+24);if n<=0 {return 0;}store64(state+24,n-1);return 1;}
fn pv_kernel_restore(state,mark) {
    let used=load64(state+48);while used>mark {used=used-1;let variable=load64(load64(state+40)+used*8);store64(load64(state+32)+variable*8,0);}
    store64(state+48,mark);return 0;
}
fn pv_kernel_set(state,variable,value) {
    let used=load64(state+48);store64(load64(state+40)+used*8,variable);store64(state+48,used+1);store64(load64(state+32)+variable*8,value);return 0;
}
fn pv_kernel_clause(state,clause,unit) {
    let formula=load64(state);if clause<1 || clause>load64(formula+8) {return 0;}
    let row=load64(formula+48)+(clause-1)*16;let seen=0;let i=0;
    while i<load64(row+8) {
        if !pv_kernel_tick(state) {return 0;}let literal=load64(load64(formula+56)+(load64(row)+i)*8);
        if unit && literal==unit {seen=1;}else {
            let variable=literal;if variable<0 {variable= -variable;}let value=load64(load64(state+32)+variable*8);
            if !value || (value==1 && literal>0) || (value== -1 && literal<0) {return 0;}
        }i=i+1;
    }return !unit || seen;
}
fn pv_kernel_node(state,id,depth) {
    if depth>128 {return 0;}let mark=load64(state+48);let formula=load64(state);let variables=load64(formula);
    while 1 {
        if !pv_kernel_tick(state) || id<1 || id>load64(state+16) {return 0;}
        let node=load64(state+8)+(id-1)*32;let kind=load64(node);let a=load64(node+8);let b=load64(node+16);let c=load64(node+24);
        if kind==3 {if b || c || !pv_kernel_clause(state,a,0) {return 0;}pv_kernel_restore(state,mark);return 1;}
        if kind==1 {
            if !pv_literal_valid(a,variables) || c<=id || c>load64(state+16) {return 0;}
            let variable=a;let value=1;if variable<0 {variable= -variable;value= -1;}
            if load64(load64(state+32)+variable*8) || !pv_kernel_clause(state,b,a) {return 0;}
            pv_kernel_set(state,variable,value);id=c;
        }else if kind==2 {
            if a<1 || a>variables || b<=id || c<=id || b>load64(state+16) || c>load64(state+16) || load64(load64(state+32)+a*8) {return 0;}
            let split_mark=load64(state+48);pv_kernel_set(state,a,1);if !pv_kernel_node(state,b,depth+1) {return 0;}pv_kernel_restore(state,split_mark);
            pv_kernel_set(state,a,-1);if !pv_kernel_node(state,c,depth+1) {return 0;}pv_kernel_restore(state,mark);return 1;
        }else {return 0;}
    }return 0;
}
fn pv_check_proof(formula,nodes,count,root,budget) {
    if !pv_formula_valid(formula) || !nodes || count<1 || count>1048576 || root!=1 || budget<0 {return 0;}
    let words=load64(formula)+1;let size=56+words*16;let state=alloc(size);if state<0 {return 0;}
    store64(state,formula);store64(state+8,nodes);store64(state+16,count);store64(state+24,budget);
    store64(state+32,state+56);store64(state+40,state+56+words*8);store64(state+48,0);
    let i=0;while i<words {store64(state+56+i*8,0);i=i+1;}
    let result=pv_kernel_node(state,root,0);syscall(11,state,size,0,0,0,0);return result;
}
