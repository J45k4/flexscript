import "cnf.flex";
// Bounded conflict-driven search with explicit resolution derivations.
// Context: original, working CNF, values, levels, reasons, trail, trail size,
// level, work used, work budget, derivations, derivation count/cap, marks,
// scratch literals, result, final empty clause, allocation size, branch mode.
fn pl_context(original,capacity,budget) {
    if !pv_formula_valid(original) || capacity<1 || capacity>65536 || budget<0 {return 0;}
    let vars=load64(original);let words=vars+1;let size=152+words*48+capacity*24;let p=alloc(size);if p<0 {return 0;}
    let extra=capacity*words;if extra>1048576 {extra=1048576;}
    let work=pv_formula(vars,load64(original+8)+capacity,load64(original+16)+extra);if !work {syscall(11,p,size,0,0,0,0);return 0;}
    store64(p,original);store64(p+8,work);store64(p+16,p+152);store64(p+24,p+152+words*8);store64(p+32,p+152+words*16);
    store64(p+40,p+152+words*24);store64(p+48,0);store64(p+56,0);store64(p+64,0);store64(p+72,budget);
    store64(p+80,p+152+words*48);store64(p+88,0);store64(p+96,capacity);store64(p+104,p+152+words*32);store64(p+112,p+152+words*40);
    store64(p+120,0);store64(p+128,0);store64(p+136,size);store64(p+144,0);
    let i=0;while i<words {store64(load64(p+16)+i*8,0);store64(load64(p+24)+i*8,0);store64(load64(p+32)+i*8,0);i=i+1;}
    i=0;while i<load64(original+8) {let row=load64(original+48)+i*16;pv_clause(work,load64(original+56)+load64(row)*8,load64(row+8));i=i+1;}return p;
}
fn pl_tick(p) {let n=load64(p+64);if n>=load64(p+72) {return 0;}store64(p+64,n+1);return 1;}
fn pl_value(p,literal) {let v=literal;if v<0 {v= -v;}let value=load64(load64(p+16)+v*8);if literal<0 {return -value;}return value;}
fn pl_set(p,literal,reason) {
    let variable=literal;let sign=1;if variable<0 {variable= -variable;sign= -1;}let n=load64(p+48);
    store64(load64(p+16)+variable*8,sign);store64(load64(p+24)+variable*8,load64(p+56));store64(load64(p+32)+variable*8,reason);
    store64(load64(p+40)+n*8,variable);store64(p+48,n+1);return 0;
}
// Positive = conflict clause, zero = all clauses satisfied, negative = a
// variable needing a decision. The reserved minimum word indicates exhaustion.
fn pl_propagate(p) {
    let f=load64(p+8);let changed=1;let candidate=0;
    while changed {changed=0;candidate=0;let clause=0;
        while clause<load64(f+8) {if !pl_tick(p) {return 0x8000000000000000;}let row=load64(f+48)+clause*16;
            let unknown=0;let last=0;let choice=0;let satisfied=0;let i=0;
            while i<load64(row+8) {if !pl_tick(p) {return 0x8000000000000000;}let literal=load64(load64(f+56)+(load64(row)+i)*8);let value=pl_value(p,literal);
                if value==1 {satisfied=1;i=load64(row+8);}else {if !value {unknown=unknown+1;last=literal;
                    let variable=literal;if variable<0 {variable= -variable;}if !choice || variable<choice {choice=variable;}
                }i=i+1;}
            }
            // Mode 1 tries earlier input variables; mode 0 retains late-clause
            // branching, which is often better for arithmetic refutations.
            if !satisfied {if !unknown {return clause+1;}if unknown==1 {pl_set(p,last,clause+1);changed=1;}else if load64(p+144) {if !candidate || choice<candidate {candidate=choice;}}else {candidate=last;if candidate<0 {candidate= -candidate;}}}
            clause=clause+1;
        }
    }return -candidate;
}
fn pl_resolve(p,left,right,pivot) {
    let count=load64(p+88);if count>=load64(p+96) {return 0;}let f=load64(p+8);let vars=load64(f);let marks=load64(p+104);let out=load64(p+112);
    let i=0;while i<=vars {store64(marks+i*8,0);i=i+1;}let side=0;let sign_left=0;
    while side<2 {let parent=left;if side {parent=right;}let row=load64(f+48)+(parent-1)*16;let j=0;let pivot_sign=0;
        while j<load64(row+8) {if !pl_tick(p) {return 0;}let literal=load64(load64(f+56)+(load64(row)+j)*8);let variable=literal;let sign=1;if variable<0 {variable= -variable;sign= -1;}
            if variable==pivot {if pivot_sign && pivot_sign!=sign {return 0;}pivot_sign=sign;}
            else {let prior=load64(marks+variable*8);if prior && prior!=sign {return 0;}store64(marks+variable*8,sign);}j=j+1;
        }
        if !pivot_sign {return 0;}if !side {sign_left=pivot_sign;}else if pivot_sign!= -sign_left {return 0;}side=side+1;
    }
    let n=0;i=1;while i<=vars {let sign=load64(marks+i*8);if sign {store64(out+n*8,i*sign);n=n+1;}i=i+1;}
    if !pv_clause(f,out,n) {return 0;}let step=load64(p+80)+count*24;store64(step,left);store64(step+8,right);store64(step+16,pivot);store64(p+88,count+1);return load64(f+8);
}
fn pl_analyze(p,clause) {
    let f=load64(p+8);let level=load64(p+56);let done=0;
    while !done {
        let row=load64(f+48)+(clause-1)*16;let n=load64(row+8);if !n {return clause;}
        let current=0;let i=0;while i<n {let lit=load64(load64(f+56)+(load64(row)+i)*8);if lit<0 {lit= -lit;}
            if load64(load64(p+24)+lit*8)==level {current=current+1;}i=i+1;
        }
        if level && current<=1 {done=1;}else {
            let at=load64(p+48);let pivot=0;while at>0 && !pivot {at=at-1;let v=load64(load64(p+40)+at*8);
                if load64(load64(p+24)+v*8)==level && load64(load64(p+32)+v*8) {i=0;while i<n {let lit=load64(load64(f+56)+(load64(row)+i)*8);if lit==v || lit== -v {pivot=v;}i=i+1;}}
            }
            if !pivot {return 0;}clause=pl_resolve(p,clause,load64(load64(p+32)+pivot*8),pivot);if !clause {return 0;}
        }
    }return clause;
}
fn pl_backjump(p,clause) {
    let f=load64(p+8);let row=load64(f+48)+(clause-1)*16;let current=load64(p+56);let target=0;let i=0;
    while i<load64(row+8) {let v=load64(load64(f+56)+(load64(row)+i)*8);if v<0 {v= -v;}let level=load64(load64(p+24)+v*8);
        if level<current && level>target {target=level;}i=i+1;
    }
    let n=load64(p+48);while n>0 && load64(load64(p+24)+load64(load64(p+40)+(n-1)*8)*8)>target {
        n=n-1;let v=load64(load64(p+40)+n*8);store64(load64(p+16)+v*8,0);store64(load64(p+24)+v*8,0);store64(load64(p+32)+v*8,0);
    }store64(p+48,n);store64(p+56,target);return 0;
}
fn pl_solve(p) {
    if !p {return 0;}while 1 {
        let status=pl_propagate(p);if status==0x8000000000000000 {return 0;}
        if !status {let i=1;while i<=load64(load64(p)) {if !load64(load64(p+16)+i*8) {store64(load64(p+16)+i*8,1);}i=i+1;}store64(p+120,1);return 1;}
        if status<0 {store64(p+56,load64(p+56)+1);pl_set(p,-status,0);}
        else {let clause=pl_analyze(p,status);if !clause {return 0;}let row=load64(load64(p+8)+48)+(clause-1)*16;
            if !load64(row+8) {store64(p+120,2);store64(p+128,clause);return 2;}if !load64(p+56) {return 0;}pl_backjump(p,clause);
        }
    }return 0;
}
fn pl_release(p) {
    if p {let f=load64(p+8);syscall(11,f,64+load64(f+24)*16+load64(f+32)*8,0,0,0,0);syscall(11,p,load64(p+136),0,0,0,0);}return 0;
}
