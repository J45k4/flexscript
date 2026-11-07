import "lib/host.flex";
import "../libs/proof.flex";
global tp_checks=0;
global tp_sat=0;
global tp_unsat=0;
fn tp_check(ok,message) {h_assert(ok,message);tp_checks=tp_checks+1;return 0;}
fn tp_add(formula,a,b,count) {
    let words=h_take(16);store64(words,a);store64(words+8,b);return pv_clause(formula,words,count);
}
// Independent exhaustive oracle: evaluate the original disjunctions directly
// on every integer bit mask. Do not call search or model/certificate checking.
fn tp_brute(formula) {
    let mask=0;while mask<(1<<load64(formula)) {let all=1;let clause=0;
        while clause<load64(formula+8) {let row=load64(formula+48)+clause*16;let some=0;let j=0;
            while j<load64(row+8) {let lit=load64(load64(formula+56)+(load64(row)+j)*8);let v=lit;if v<0 {v= -v;}
                let bit=(mask>>(v-1))&1;if (lit>0 && bit) || (lit<0 && !bit) {some=1;}j=j+1;
            }if !some {all=0;}clause=clause+1;
        }if all {return 1;}mask=mask+1;
    }return 0;
}
fn tp_case(search) {
    let formula=load64(search);let expected=tp_brute(formula);let result=pv_decide(search,1000000,1000000);
    tp_check(result==2-expected,"SAT result differs from exhaustive oracle");
    if result==1 {tp_check(pv_check_model(formula,load64(search+8)),"invalid SAT witness");tp_sat=tp_sat+1;}
    else {tp_check(pv_check_proof(formula,load64(search+32),load64(search+40),load64(search+80),1000000),"invalid UNSAT certificate");tp_unsat=tp_unsat+1;}
    return 0;
}
fn tp_exhaustive() {
    let formula=pv_formula(2,9,18);let search=pv_search(formula,4096);let literals=h_take(16);let subset=0;
    // Each variable is absent, positive or negative: nine distinct clauses,
    // including the empty clause. Check all 512 sets of those clauses.
    while subset<512 {store64(formula+8,0);store64(formula+16,0);let clause=0;
        while clause<9 {if subset&(1<<clause) {let pattern=clause;let v=1;let count=0;
            while v<=2 {let sign=pattern%3;pattern=pattern/3;if sign {let lit=v;if sign==2 {lit= -v;}store64(literals+count*8,lit);count=count+1;}v=v+1;}
            tp_check(pv_clause(formula,literals,count),"cannot build exhaustive clause");
        }clause=clause+1;}tp_case(search);subset=subset+1;
    }return 0;
}
fn tp_randomized() {
    let formula=pv_formula(3,16,64);let search=pv_search(formula,4096);let literals=h_take(32);let seed=127;let case_id=0;
    while case_id<1024 {store64(formula+8,0);store64(formula+16,0);let clause=0;let count=(case_id%16)+1;
        while clause<count {seed=(seed*1664525+1013904223)&0xffffffff;let length=1+seed%4;let j=0;
            while j<length {seed=(seed*1664525+1013904223)&0xffffffff;let lit=1+((seed>>8)%3);if seed&0x8000 {lit= -lit;}store64(literals+j*8,lit);j=j+1;}
            tp_check(pv_clause(formula,literals,length),"cannot build randomized clause");clause=clause+1;
        }tp_case(search);case_id=case_id+1;
    }return 0;
}
fn tp_certificate(search) {return pv_check_proof(load64(search),load64(search+32),load64(search+40),load64(search+80),1000000);}
fn tp_corruption() {
    let formula=pv_formula(2,4,8);tp_add(formula,1,0,1);tp_add(formula,-1,0,1);let search=pv_search(formula,32);
    tp_check(pv_solve(search,1000)==2 && tp_certificate(search),"unit contradiction");let nodes=load64(search+32);
    store64(nodes+8,2);tp_check(!tp_certificate(search),"accepted wrong unit literal");store64(nodes+8,1);
    store64(nodes+16,2);tp_check(!tp_certificate(search),"accepted wrong unit reason");store64(nodes+16,1);
    store64(nodes+24,1);tp_check(!tp_certificate(search),"accepted cyclic proof");store64(nodes+24,2);
    store64(nodes+40,1);tp_check(!tp_certificate(search),"accepted satisfied conflict");store64(nodes+40,2);
    store64(nodes,99);tp_check(!tp_certificate(search),"accepted unknown proof rule");store64(nodes,1);
    tp_check(!pv_check_proof(formula,nodes,1,1,1000),"accepted truncated certificate");
    tp_check(!pv_check_proof(formula,nodes,2,2,1000),"accepted non-root entry");
    tp_check(!pv_check_proof(formula,nodes,2,1,0),"accepted exhausted checker budget");
    tp_check(tp_certificate(search),"restored certificate rejected");
    tp_check(pv_decide(search,1000,0)==0 && !load64(search+80),"unchecked proof must not escape public API");
    tp_check(pv_solve(search,0)==0 && !load64(search+80),"search budget must be unknown");
    let tiny=pv_search(formula,1);tp_check(pv_solve(tiny,1000)==0,"node budget must be unknown");
    store64(formula+8,0);store64(formula+16,0);
    tp_add(formula,1,2,2);tp_add(formula,1,-2,2);tp_add(formula,-1,2,2);tp_add(formula,-1,-2,2);
    tp_check(pv_solve(search,1000)==2 && tp_certificate(search),"split contradiction");
    let yes=load64(nodes+16);let no=load64(nodes+24);store64(nodes+16,no);store64(nodes+24,yes);
    tp_check(!tp_certificate(search),"accepted swapped split branches");store64(nodes+16,yes);store64(nodes+24,no);
    store64(nodes+8,0);tp_check(!tp_certificate(search),"accepted variable zero");store64(nodes+8,2);
    store64(search+88,0);tp_check(pv_solve(search,1000)==0,"depth limit must be unknown");store64(search+88,128);
    // Change the problem after obtaining a proof: never trust the old status.
    tp_check(pv_solve(search,1000)==2,"restore split search");store64(formula+8,1);store64(formula+16,2);
    tp_check(!tp_certificate(search),"accepted certificate for changed satisfiable formula");tp_case(search);
    tp_check(pv_decide(search,1000,0)==0,"unchecked model must not escape public API");
    store64(load64(search+8)+8,-1);store64(load64(search+8)+16,-1);
    tp_check(!pv_check_model(formula,load64(search+8)),"accepted false SAT witness");return 0;
}
fn tp_inputs() {
    tp_check(!pv_formula(-1,1,1) && !pv_formula(262145,1,1),"variable bounds");
    let formula=pv_formula(1,1,2);let words=h_take(16);store64(words,0);
    tp_check(!pv_clause(formula,words,1),"zero literal rejected");store64(words,2);
    tp_check(!pv_clause(formula,words,1),"out of range literal rejected");store64(words,0x8000000000000000);
    tp_check(!pv_clause(formula,words,1),"minimum signed literal rejected");store64(words,1);store64(words+8,1);
    tp_check(pv_clause(formula,words,2),"duplicate literal accepted");let search=pv_search(formula,16);tp_case(search);
    tp_check(!pv_clause(formula,words,1),"clause capacity enforced");store64(formula,2);
    tp_check(pv_solve(search,1000)== -1,"changed variable capacity rejected");store64(formula,1);
    store64(load64(formula+48),1);tp_check(!pv_formula_valid(formula),"malformed offset rejected");
    let empty=pv_formula(0,1,0);let es=pv_search(empty,4);tp_case(es);
    tp_check(pv_clause(empty,0,0),"empty clause construction");tp_case(es);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);tp_exhaustive();tp_randomized();tp_corruption();tp_inputs();
    h_print(1,h_cat3("PASS: ",h_int(tp_checks),h_cat3(" proof-engine checks; SAT formulas=",h_int(tp_sat),h_cat3("; checked UNSAT formulas=",h_int(tp_unsat),"\n"))));return 0;
}
