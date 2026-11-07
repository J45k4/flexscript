import "proof/sat.flex";
import "proof/check.flex";
import "proof/word.flex";
import "proof/learn.flex";
import "proof/resolution.flex";
// Public checked decision: raw search results are never sufficient evidence.
// -1 malformed input; 0 unresolved (including evidence-check budget exhaustion);
// 1 checked satisfying assignment; 2 checked unsatisfiability certificate.
fn pv_decide_order(search,search_budget,check_budget,input_first) {
    if !search || check_budget<0 {return -1;}
    let initial_budget=search_budget;if initial_budget>2000000 {initial_budget=2000000;}
    let result=pv_solve(search,initial_budget);let remaining=search_budget-load64(search+64);
    if result==0 && remaining>0 {
        // A short input-first attempt finds concrete word/memory witnesses.
        // Keep the established late-clause strategy for the remaining budget:
        // refutations often benefit from deciding comparison outputs first.
        let trial=remaining/4;if trial<1 {trial=1;}if trial>50000000 {trial=50000000;}
        if input_first {trial=remaining;}
        let learned=pl_context(load64(search),16384,trial);if !learned {return 0;}store64(learned+144,1);result=pl_solve(learned);
        if !result {let spent=load64(learned+64);store64(search+64,load64(search+64)+spent);remaining=remaining-spent;pl_release(learned);
            if remaining<=0 {return 0;}learned=pl_context(load64(search),16384,remaining);if !learned {return 0;}result=pl_solve(learned);
        }let accepted=0;
        if result==1 {accepted=pv_check_model_budget(load64(search),load64(learned+16),check_budget);}
        else if result==2 {accepted=pr_check(load64(search),load64(learned+8),load64(learned+80),load64(learned+88),load64(learned+128),check_budget);}
        if accepted && result==1 {let i=0;while i<=load64(load64(search)) {store64(load64(search+8)+i*8,load64(load64(learned+16)+i*8));i=i+1;}}
        store64(search+64,load64(search+64)+load64(learned+64));pl_release(learned);
        if !accepted {result=0;}store64(search+72,result);store64(search+80,0);return result;
    }
    if result<1 {return result;}
    let accepted=0;
    if result==1 {accepted=pv_check_model_budget(load64(search),load64(search+8),check_budget);}
    else {accepted=pv_check_proof(load64(search),load64(search+32),load64(search+40),load64(search+80),check_budget);}
    if !accepted {store64(search+72,0);store64(search+80,0);return 0;}return result;
}
fn pv_decide(search,search_budget,check_budget) {return pv_decide_order(search,search_budget,check_budget,0);}
// Requirement consistency seeks a concrete witness, so it may spend its whole
// bounded learning phase on input decisions. Both result kinds still require
// the same independent evidence checker as the general entry point.
fn pv_decide_inputs(search,search_budget,check_budget) {return pv_decide_order(search,search_budget,check_budget,1);}
