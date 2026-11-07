import "cnf.flex";
// Bounded DPLL search. Results: -1 invalid input, 0 unknown, 1 SAT, 2 UNSAT.
// Context: formula, assignments, trail, trail size, nodes, node count, node cap,
// work budget, work used, result, root, maximum split depth, variable capacity.
// Certificate nodes (32 bytes): unit=(1,literal,clause,child),
// split=(2,variable,positive child,negative child), conflict=(3,clause,0,0).
// Clauses and nodes are one-based. Children always follow their parent.
fn pv_search(formula,node_capacity) {
    if !pv_formula_valid(formula) || node_capacity<1 || node_capacity>1048576 {return 0;}
    let words=load64(formula)+1;let p=alloc(104+words*16+node_capacity*32);if p<0 {return 0;}
    store64(p,formula);store64(p+8,p+104);store64(p+16,p+104+words*8);store64(p+24,0);
    store64(p+32,p+104+words*16);store64(p+40,0);store64(p+48,node_capacity);
    store64(p+56,0);store64(p+64,0);store64(p+72,0);store64(p+80,0);store64(p+88,128);store64(p+96,load64(formula));return p;
}
fn pv_tick(search) {
    let used=load64(search+64);if used>=load64(search+56) {return 0;}store64(search+64,used+1);return 1;
}
fn pv_value(search,literal) {
    let variable=literal;if variable<0 {variable= -variable;}let value=load64(load64(search+8)+variable*8);
    if literal<0 {return -value;}return value;
}
fn pv_assign(search,literal) {
    let variable=literal;let value=1;if variable<0 {variable= -variable;value= -1;}
    store64(load64(search+8)+variable*8,value);let used=load64(search+24);
    store64(load64(search+16)+used*8,variable);store64(search+24,used+1);return 0;
}
fn pv_rewind(search,mark) {
    let used=load64(search+24);while used>mark {used=used-1;let variable=load64(load64(search+16)+used*8);store64(load64(search+8)+variable*8,0);}
    store64(search+24,mark);return 0;
}
fn pv_node(search,kind,a,b,c) {
    let count=load64(search+40);if count>=load64(search+48) {return 0;}
    let p=load64(search+32)+count*32;store64(p,kind);store64(p+8,a);store64(p+16,b);store64(p+24,c);
    store64(search+40,count+1);return count+1;
}
fn pv_link(search,parent,child) {if parent {store64(load64(search+32)+(parent-1)*32+24,child);}return 0;}
fn pv_finish(search,mark,head,tail,node) {
    pv_link(search,tail,node);pv_rewind(search,mark);if head {return head;}return node;
}
fn pv_branch(search,depth) {
    let mark=load64(search+24);let head=0;let tail=0;let formula=load64(search);let changed=1;let candidate=0;
    while changed {
        changed=0;candidate=0;let clause=0;while clause<load64(formula+8) {
            if !pv_tick(search) {return 0;}let row=load64(formula+48)+clause*16;let start=load64(row);let n=load64(row+8);
            let i=0;let unknown=0;let last=0;let satisfied=0;
            while i<n {if !pv_tick(search) {return 0;}let literal=load64(load64(formula+56)+(start+i)*8);let value=pv_value(search,literal);
                if value==1 {satisfied=1;i=n;}else {if !value {unknown=unknown+1;last=literal;}i=i+1;}
            }
            if !satisfied {
                if !unknown {let node=pv_node(search,3,clause+1,0,0);if !node {return 0;}return pv_finish(search,mark,head,tail,node);}
                if unknown==1 {let node=pv_node(search,1,last,clause+1,0);if !node {return 0;}
                    pv_link(search,tail,node);if !head {head=node;}tail=node;pv_assign(search,last);changed=1;
                }else {candidate=last;}
            }clause=clause+1;
        }
    }
    if !candidate {
        let i=1;while i<=load64(formula) {if !load64(load64(search+8)+i*8) {store64(load64(search+8)+i*8,1);}i=i+1;}
        store64(search+72,1);return 0;
    }
    if depth>=load64(search+88) {return 0;}if candidate<0 {candidate= -candidate;}
    let node=pv_node(search,2,candidate,0,0);if !node {return 0;}let split_mark=load64(search+24);
    pv_assign(search,candidate);let yes=pv_branch(search,depth+1);if !yes {return 0;}pv_rewind(search,split_mark);
    pv_assign(search,-candidate);let no=pv_branch(search,depth+1);if !no {return 0;}pv_rewind(search,split_mark);
    let p=load64(search+32)+(node-1)*32;store64(p+16,yes);store64(p+24,no);
    return pv_finish(search,mark,head,tail,node);
}
fn pv_solve(search,budget) {
    if !search {return -1;}store64(search+72,0);store64(search+80,0);store64(search+40,0);store64(search+24,0);store64(search+64,0);
    if !pv_formula_valid(load64(search)) || load64(load64(search))!=load64(search+96) || budget<0 {store64(search+72,-1);return -1;}store64(search+56,budget);
    let i=0;while i<=load64(load64(search)) {store64(load64(search+8)+i*8,0);i=i+1;}
    let root=pv_branch(search,0);if root {store64(search+80,root);store64(search+72,2);}return load64(search+72);
}
