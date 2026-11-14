import "lib/host.flex";
import "../libs/proof.flex";
global tlp_checks=0;
global tlp_seed=1729;
fn tlp_check(ok,message) {h_assert(ok,message);tlp_checks=tlp_checks+1;return 0;}
fn tlp_random() {tlp_seed=(tlp_seed*1103515245+12345)&0x7fffffff;return tlp_seed;}
fn tlp_oracle(formula) {
    let mask=0;while mask<(1<<load64(formula)) {let c=0;let okay=1;
        while c<load64(formula+8) {let row=load64(formula+48)+c*16;let i=0;let sat=0;
            while i<load64(row+8) {let literal=load64(load64(formula+56)+(load64(row)+i)*8);let variable=literal;if variable<0 {variable= -variable;}
                let value=(mask>>(variable-1))&1;if (value && literal>0) || (!value && literal<0) {sat=1;}i=i+1;
            }if !sat {okay=0;}c=c+1;
        }if okay {return 1;}mask=mask+1;
    }return 2;
}
fn tlp_case(formula) {
    let expected=tlp_oracle(formula);let mode=0;while mode<3 {
    let p=pl_context(formula,4096,1000000);tlp_check(p,"learning context");store64(p+144,mode);let result=pl_solve(p);
    if result!=expected {
        h_print(2,h_cat3("learning result=",h_int(result),h_cat3(" expected=",h_int(expected),"\n")));
        let clause=0;while clause<load64(formula+8) {let row=load64(formula+48)+clause*16;let i=0;
            while i<load64(row+8) {h_print(2,h_cat(h_int(load64(load64(formula+56)+(load64(row)+i)*8))," "));i=i+1;}h_print(2,"0\n");clause=clause+1;
        }
    }
    tlp_check(result==expected,"learning disagrees with exhaustive oracle");
    if result==1 {tlp_check(pv_check_model(formula,load64(p+16)),"learning model rejected");}
    else {
        tlp_check(pr_check(formula,load64(p+8),load64(p+80),load64(p+88),load64(p+128),1000000),"learning proof rejected");
        if load64(p+88) {let steps=load64(p+80);let saved=load64(steps+16);store64(steps+16,0);
            tlp_check(!pr_check(formula,load64(p+8),steps,load64(p+88),load64(p+128),1000000),"corrupt resolution pivot accepted");store64(steps+16,saved);
            saved=load64(steps);store64(steps,load64(load64(p+8)+8));
            tlp_check(!pr_check(formula,load64(p+8),steps,load64(p+88),load64(p+128),1000000),"forward proof reference accepted");store64(steps,saved);
            saved=load64(steps+8);store64(steps+8,load64(steps));
            tlp_check(!pr_check(formula,load64(p+8),steps,load64(p+88),load64(p+128),1000000),"same-polarity resolution accepted");store64(steps+8,saved);
            let work=load64(p+8);let first=load64(work+48)+load64(formula+8)*16;
            if load64(first+8) {let literal=load64(work+56)+load64(first)*8;saved=load64(literal);store64(literal,-saved);
                tlp_check(!pr_check(formula,work,steps,load64(p+88),load64(p+128),1000000),"incorrect resolvent accepted");store64(literal,saved);
            }
            if load64(formula+16) {let literal=load64(work+56);saved=load64(literal);store64(literal,-saved);
                tlp_check(!pr_check(formula,work,steps,load64(p+88),load64(p+128),1000000),"changed original formula accepted");store64(literal,saved);
            }
            tlp_check(!pr_check(formula,work,steps,load64(p+88),load64(p+128),0),"resolution checker budget ignored");
            tlp_check(pr_check(formula,work,steps,load64(p+88),load64(p+128),1000000),"restored resolution evidence rejected");
        }
    }pl_release(p);mode=mode+1;}return 0;
}
fn tlp_watch_cases() {
    let literals=h_take(64);let trial=0;
    while trial<256 {
        let variables=4+tlp_random()%5;let clauses=12+tlp_random()%25;
        let formula=pv_formula(variables,clauses,clauses*8);tlp_check(formula,"watch fixture allocation");
        let i=0;while i<clauses {
            let count=1+tlp_random()%8;let j=0;
            while j<count {let literal=1+tlp_random()%variables;if (tlp_random()>>13)&1 {literal= -literal;}store64(literals+j*8,literal);j=j+1;}
            tlp_check(pv_clause(formula,literals,count),"watch fixture clause");i=i+1;
        }
        tlp_case(formula);
        syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);trial=trial+1;
    }
    // Every four-variable full clause is needed to refute this formula. This
    // exercises moving watches, learned asserting clauses and backtracking.
    let formula=pv_formula(4,16,64);let clause=0;while clause<16 {
        let variable=1;while variable<=4 {let literal=variable;if clause&(1<<(variable-1)) {literal= -literal;}store64(literals+(variable-1)*8,literal);variable=variable+1;}
        pv_clause(formula,literals,4);clause=clause+1;
    }
    tlp_case(formula);syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);
    // Regression: counting [-1,-1] as two unknowns used to miss its unit
    // implication, then return unresolved when conflict analysis double-counted
    // the decision variable. Keep original clause bytes for certificate checks.
    formula=pv_formula(1,3,7);store64(literals,-1);store64(literals+8,-1);pv_clause(formula,literals,2);tlp_case(formula);
    store64(literals,1);store64(literals+8,-1);store64(literals+16,1);pv_clause(formula,literals,3);tlp_case(formula);
    store64(literals,1);store64(literals+8,1);pv_clause(formula,literals,2);tlp_case(formula);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);
    // Two distinct positions containing the same literal are not two distinct
    // watches. This satisfiable XOR used to repeat the same bad decision until
    // exhaustion when clause rescanning was removed.
    formula=pv_formula(2,2,6);store64(literals,2);store64(literals+8,1);store64(literals+16,2);pv_clause(formula,literals,3);
    store64(literals,-2);store64(literals+8,-1);store64(literals+16,-2);pv_clause(formula,literals,3);tlp_case(formula);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);
    // An already registered asserting clause has no new-registration event.
    // Backjumping must enqueue its last unknown literal immediately.
    formula=pv_formula(2,1,3);pv_clause(formula,literals,3);
    let asserting=pl_context(formula,4096,1000000);tlp_check(pl_watch_new(asserting)==0,"asserting watch registration");
    store64(asserting+56,1);pl_set(asserting,1,0);store64(asserting+56,2);pl_set(asserting,2,0);pl_backjump(asserting,1);
    tlp_check(pl_value(asserting,-2)==1 && load64(asserting+56)==1,"existing clause was not asserted after backjump");
    tlp_check(pl_solve(asserting)==1 && pv_check_model(formula,load64(asserting+16)),"asserting-clause model rejected");pl_release(asserting);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);
    formula=pv_formula(2,1,3);store64(literals,2);store64(literals+8,2);store64(literals+16,1);pv_clause(formula,literals,3);
    let distinct=pl_context(formula,4096,1000000);pl_set(distinct,-1,0);store64(distinct+56,1);pl_set(distinct,2,0);
    tlp_check(pl_watch_new(distinct)==0,"satisfied duplicate watch registration");
    let watches=load64(distinct+160);let left=load64(watches+8);let right=load64(watches+32);
    tlp_check(load64(literals+left*8)!=load64(literals+right*8),"satisfied clause lost its distinct false watch");
    tlp_check(pl_solve(distinct)==1 && pv_check_model(formula,load64(distinct+16)),"distinct-watch model rejected");pl_release(distinct);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);
    formula=pv_formula(2,1,2);store64(literals,1);store64(literals+8,2);pv_clause(formula,literals,2);
    let zero=pl_context(formula,4096,1000000);store64(zero+144,2);tlp_check(pl_solve(zero)==1,"zero-first decision failed");
    tlp_check(load64(load64(zero+16)+8)==-1 && load64(load64(zero+16)+16)==1,"zero-first decision order was not used");
    tlp_check(pv_check_model(formula,load64(zero+16)),"zero-first model rejected");pl_release(zero);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);let f=pv_formula(2,9,18);let literals=h_take(24);let subset=0;
    while subset<512 {store64(f+8,0);store64(f+16,0);let clause=0;
        while clause<9 {if subset&(1<<clause) {let pattern=clause;let n=0;let v=1;while v<=2 {let sign=pattern%3;pattern=pattern/3;
            if sign {let literal=v;if sign==2 {literal= -v;}store64(literals+n*8,literal);n=n+1;}v=v+1;
        }tlp_check(pv_clause(f,literals,n),"exhaustive clause");}clause=clause+1;}tlp_case(f);subset=subset+1;}
    // All subsets of the eight full three-variable clauses, including the
    // minimally unsatisfiable conjunction requiring decisions and learning.
    f=pv_formula(3,8,24);subset=0;while subset<256 {store64(f+8,0);store64(f+16,0);let clause=0;
        while clause<8 {if subset&(1<<clause) {let v=1;while v<=3 {let literal=v;if clause&(1<<(v-1)) {literal= -v;}store64(literals+(v-1)*8,literal);v=v+1;}pv_clause(f,literals,3);}clause=clause+1;}
        tlp_case(f);subset=subset+1;
    }
    tlp_watch_cases();
    let no_work=pl_context(f,4096,0);tlp_check(pl_solve(no_work)==0,"learning budget exhaustion");pl_release(no_work);
    let no_space=pl_context(f,1,1000000);tlp_check(pl_solve(no_space)==0,"resolution capacity exhaustion");pl_release(no_space);
    h_print(1,h_cat3("PASS: ",h_int(tlp_checks)," conflict-learning and independent resolution checks\n"));return 0;
}
