import "lib/host.flex";
import "../libs/proof.flex";
global tlp_checks=0;
fn tlp_check(ok,message) {h_assert(ok,message);tlp_checks=tlp_checks+1;return 0;}
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
    let expected=tlp_oracle(formula);let p=pl_context(formula,4096,1000000);tlp_check(p,"learning context");let result=pl_solve(p);
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
    }pl_release(p);return 0;
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
    let no_work=pl_context(f,4096,0);tlp_check(pl_solve(no_work)==0,"learning budget exhaustion");pl_release(no_work);
    let no_space=pl_context(f,1,1000000);tlp_check(pl_solve(no_space)==0,"resolution capacity exhaustion");pl_release(no_space);
    h_print(1,h_cat3("PASS: ",h_int(tlp_checks)," conflict-learning and independent resolution checks\n"));return 0;
}
