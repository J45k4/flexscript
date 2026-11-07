// Internal finite Boolean formulas. Literals are signed, one-based variable IDs.
// Formula: variables, clauses, literals, clause cap, literal cap, reserved,
// clause records pointer, literal storage pointer. Clause records: offset, size.
fn pv_formula(variables,clauses,literals) {
    if variables<0 || variables>262144 || clauses<0 || clauses>1048576 || literals<0 || literals>4194304 {return 0;}
    let p=alloc(64+clauses*16+literals*8);if p<0 {return 0;}
    store64(p,variables);store64(p+8,0);store64(p+16,0);store64(p+24,clauses);store64(p+32,literals);store64(p+40,0);
    store64(p+48,p+64);store64(p+56,p+64+clauses*16);return p;
}
fn pv_literal_valid(literal,variables) {return literal && literal>= -variables && literal<=variables;}
fn pv_clause(formula,literals,count) {
    if !formula || count<0 {return 0;}let clauses=load64(formula+8);let used=load64(formula+16);
    if clauses>=load64(formula+24) || count>load64(formula+32)-used {return 0;}
    let i=0;while i<count {if !pv_literal_valid(load64(literals+i*8),load64(formula)) {return 0;}i=i+1;}
    let row=load64(formula+48)+clauses*16;store64(row,used);store64(row+8,count);
    i=0;while i<count {store64(load64(formula+56)+(used+i)*8,load64(literals+i*8));i=i+1;}
    store64(formula+8,clauses+1);store64(formula+16,used+count);return 1;
}
fn pv_formula_valid(formula) {
    if !formula {return 0;}let variables=load64(formula);let capacity=load64(formula+24);let space=load64(formula+32);
    if variables<0 || variables>262144 || capacity<0 || capacity>1048576 || space<0 || space>4194304 {return 0;}
    let count=load64(formula+8);let used=load64(formula+16);
    if count<0 || count>capacity || used<0 || used>space || load64(formula+40) {return 0;}
    if load64(formula+48)!=formula+64 || load64(formula+56)!=formula+64+capacity*16 {return 0;}
    let offset=0;let i=0;while i<count {let row=load64(formula+48)+i*16;let n=load64(row+8);
        if load64(row)!=offset || n<0 || n>used-offset {return 0;}offset=offset+n;i=i+1;
    }if offset!=used {return 0;}
    i=0;while i<used {if !pv_literal_valid(load64(load64(formula+56)+i*8),variables) {return 0;}i=i+1;}return 1;
}
