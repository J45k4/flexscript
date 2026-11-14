import "../../call-frame.flex";

// OPEN: the remaining call-entry paths. The passing gate carries only
// enter_rejects_bad_index (vm/proofs/call-entry.flex). These roots are checked
// against the production vm_enter and currently stop for documented engine
// reasons; each entry records the exact blocker so the next attempt starts
// from evidence, not guesswork.
//
// Findings that constrain every formulation (reproduced in /tmp scratch runs
// on 2026-11-13, engine gate capacity 524288):
// - The verifier inlines the whole production body's circuit for every root,
//   so any root whose path passes the header check pays for the argument-copy
//   loop's circuit even when that loop is unreachable on the checked path.
// - Memory regions must have CONSTANT lengths; symbolic lengths do not
//   establish membership (subregion relations go unresolved).
// - Address cancellation works for a shared single-symbolic base, not for a
//   shared two-term base (vm_stack+vm_sp+... vs vm_stack+vm_sp).
// - Address 0 is uninstantiable: any region containing it makes the
//   requirements inconsistent, and models pick zero otherwise.
// - Every global referenced anywhere in a contract (requires expressions
//   included) must be declared in that contract's reads clause.
// - Premises must exclude wraparound explicitly; the checker correctly
//   exhibits wrapped-span counterexamples otherwise.
// - The copy loop's symbolic-store iterations are unresolved under every
//   tried invariant set (bounds-only, relational, running pointers with
//   per-iteration permission facts, single-word offsets). Discharging the
//   loop needs an engine extension: checked loop summaries for symbolic
//   stores, or membership reasoning over loop-carried sums.
//
// Correction (2026-11-13, later probes): the earlier "root isolation" claim
// was a misdiagnosis. The step lemma with the assert-scaffolded shift
// (let e=d+8; assert e <= bound; assert d <= bound-8) verifies next to loops;
// the unscaffolded postcondition caps out alone as well. There is no
// cross-root degradation.
//
// The real remaining gap, isolated by probe-run5 and probe-sweepstep: inside
// loop-preservation queries the checker cannot perform constant-shift and
// product-shift identities, for example `d+8 <= c` implying `d <= c-8` (given
// the nonwrapping conjunct) and `(s-1)*8 == s*8-8`. Every other piece of the
// assembly has a standalone-proved shape:
// - slot_readable/slot_writable with the nonwrapping conjuncts and rest-bound
//   scaffolding (4/4 standalone; the scaffolded forms also verify next to
//   loops);
// - the sweep loop with a permission invariant on the exact store-address
//   term, established by a step lemma whose membership is a direct comparison
//   (probe-direct: 3/3, including the loop root);
// - the entry facts (base >= 0, base+count*8 == vm_sp) and the two-product
//   monotonicity facts (mono_a/b/d) outside loops.
// Two candidate engine extensions would close the gap: normalize `x+k <= c`
// to `x <= c-k` under the nonwrapping conjunct, and/or recognize the product
// shift `(s-1)*k == s*k-k` for constant k in the comparison paths. Both are
// bounded changes to the word-circuit comparison handling; neither has been
// changed yet.
//
// Refinement (2026-11-13, final probes): the write side is fully solved —
// probe-direct proves a sweep loop whose permission invariant is carried on
// the exact store-address term and established one step ahead by a lemma
// whose membership is a direct comparison (`requires i >= 0 && i <= 4095;
// ensures writable_bytes(buf+(i+1)*8,8)`; 3/3 with the loop root). The read
// side still needs one arithmetic fact per iteration: the next slot's
// containment `d+16 <= 524288` (or the constant-valued span sum
// `base+8*left <= 524288`, whose value never changes across the loop but
// whose shift-exactness the checker cannot yet see). Premises must also
// exclude product wraparound explicitly (`8*left` overflows for large left;
// bound the multiplier by a constant range as the proved sweep lemma does).
//
// Final architecture (2026-11-13, position-addressed lemmas): the base and
// count are entry constants and the position is the loop variable, so no
// quantity ever shifts inside the loop and every call-site check is an entry
// assert or a branch fact:
//   requires readable_bytes(stk,524288);
//   requires d0 >= 0 && d0 <= 524288 && cnt <= 8191 && d0+8*cnt <= 524288;
//   requires k >= 0 && k < cnt;
//   ensures readable_bytes(stk+d0+8*k,8);
// (the write counterpart over mem/w0/8388608), called as
//   read_at(vm_stack,vm_sp-count*8,count,i)
//   write_at(vm_local_memory,vm_local_base,slots,i)
// with the ensured addresses equal to the production address expressions.
// The loop invariant reduces to the position alone
// (`invariant i >= 0 && i <= slots;`), whose preservation is trivial. The
// lemma bodies proved their containment asserts once the premises bounded
// d0, w0 and cnt against wraparound.
//
// Remaining wall, measured: the copy root's own formula (the loop analysis
// over the four-term production load address plus two lemma calls and the
// branch) reaches ~167k SAT variables / ~524k clauses, and inside it even the
// entry asserts (`d0 >= 0`, the `d0+8*count == vm_sp` identity, the
// containment chain through a bound intermediate) exceed the 192M search
// budget, although every one of them is a standalone-proved shape. The two
// candidate engine changes are now: (a) the constant-shift/product-shift
// comparison rules, and (b) a smaller encoding for loop-analysis memory
// states (or per-loop query splitting) so the checker's own entry facts stay
// decidable inside the loop root's formula.
//
// Final precise diagnosis (2026-11-13, last probes): even the standalone
// position-addressed lemma caps. Its membership query builds 12,637
// variables and 34,607 clauses where the natural circuit is a few hundred
// (one 64-bit distance adder, two comparison circuits, the region grant).
// Within it the containment assert `d0+8*k+8 <= d0+8*cnt` discharges, but the
// transitivity through that shared compound term (`... <= span <= 524288`,
// with span rest-bound to a single word) still exceeds the 192M search
// budget. So the two concrete engine targets, in order of leverage: (1) slim
// the membership query encoding in `pb_member`/the region machinery (the
// 25x variable bloat is the root cause; every downstream derivation then
// fits the budget), and (2) add the shift/transitivity comparison rules so
// the remaining chain steps are propagation rather than search. All scratch
// probes live in /tmp/opencode/vmscratch (probe-position.flex is the final
// assembly; probe-direct.flex is the proved write-side sweep).

// Malformed function header: only table/header metadata is read; frames,
// stack and locals are untouched. Blocked by the whole-body circuit demand
// above; feasible once the loop summary exists.
requires index >= 0 && index < function_count && function_count >= 0;
requires vm_depth >= 0 && vm_depth <= 1023;
requires vm_error == 0;
requires readable_bytes(functions+index*32,32);
requires pc == load64(functions+index*32+16);
requires pc >= 0 && pc+16 <= output_size && (pc & 15) == 0 && output_size >= 16;
requires readable_bytes(output+pc,16);
requires load64(output+pc) != 18;
reads vm_depth,vm_error,vm_pc,function_count,functions,output,output_size,bytes(functions+index*32,32),bytes(output+pc,16);
modifies vm_error;
ensures result == 0 && vm_error == 9;
ensures vm_depth == old(vm_depth);
ensures vm_pc == old(vm_pc);
fn enter_rejects_opcode(index,return_pc,pc) {return vm_enter(index,return_pc);}

// Capacity rejection with valid metadata: before any frame write.
requires index >= 0 && index < function_count && function_count >= 0;
requires vm_depth >= 1 && vm_depth <= 1023;
requires vm_error == 0;
requires readable_bytes(functions+index*32,32);
requires pc == load64(functions+index*32+16);
requires pc >= 0 && pc+16 <= output_size && (pc & 15) == 0 && output_size >= 16;
requires readable_bytes(output+pc,16);
requires load64(output+pc) == 18;
requires count == load64(functions+index*32+24);
requires slots == load64(output+pc+8);
requires vm_sp >= 0 && vm_sp <= 524288;
requires vm_local_top >= 0 && vm_local_top <= 8388608;
requires readable_bytes(vm_frames,40960);
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= vm_sp;
requires !(count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp-load64(vm_frames+(vm_depth-1)*40+24) && vm_local_top+slots*8 <= 8388608);
reads vm_depth,vm_error,vm_sp,vm_local_top,function_count,functions,output,output_size,vm_frames,bytes(functions+index*32,32),bytes(output+pc,16),bytes(vm_frames,40960);
modifies vm_error;
ensures result == 0 && vm_error == 9;
ensures vm_depth == old(vm_depth);
ensures vm_sp == old(vm_sp);
ensures vm_local_base == old(vm_local_base);
ensures vm_local_top == old(vm_local_top);
fn enter_rejects_capacity(index,return_pc,pc,count,slots) {return vm_enter(index,return_pc);}

// Acceptance state transition (framed): the composed entry theorem the plan's
// step 3 asks for. The postcondition set below is the design; the root is
// blocked by the copy-loop circuit demand. The caller invariant stated here
// is the shared invariant initialization and the interpreter must establish
// and preserve: bounded aligned cursors, the host-owned frame buffer, the
// caller's operand span, the free local tail, and compiler-owned metadata.
requires index >= 0 && index < function_count && function_count >= 0;
requires vm_depth >= 1 && vm_depth <= 1023;
requires vm_error == 0;
requires readable_bytes(functions+index*32,32);
requires pc == load64(functions+index*32+16);
requires pc >= 0 && pc+16 <= output_size && (pc & 15) == 0 && output_size >= 16;
requires readable_bytes(output+pc,16);
requires load64(output+pc) == 18;
requires count == load64(functions+index*32+24);
requires slots == load64(output+pc+8);
requires vm_sp >= 0 && vm_sp <= 524288 && (vm_sp & 7) == 0;
requires vm_local_base >= 0 && vm_local_base <= vm_local_top;
requires vm_local_top >= 0 && vm_local_top <= 8388608 && (vm_local_top & 7) == 0;
requires readable_bytes(vm_frames,40960);
requires writable_bytes(vm_frames,40960);
requires load64(vm_frames+(vm_depth-1)*40+24) >= 0 && load64(vm_frames+(vm_depth-1)*40+24) <= vm_sp;
requires readable_bytes(vm_stack,524288);
requires writable_bytes(vm_local_memory+vm_local_top,32768);
requires count >= 0 && count <= slots && slots <= 4096 && count*8 <= vm_sp-load64(vm_frames+(vm_depth-1)*40+24) && vm_local_top+slots*8 <= 8388608;
requires return_pc == -1 || (return_pc >= 0 && return_pc <= code_size && (return_pc & 15) == 0);
requires code_size >= 16 && (code_size & 15) == 0;
reads vm_depth,vm_error,vm_sp,vm_local_base,vm_local_top,vm_pc,vm_finished,function_count,functions,output,output_size,vm_stack,vm_frames,vm_local_memory,bytes(functions+index*32,32),bytes(output+pc,16),bytes(vm_frames,40960),bytes(vm_stack,524288);
modifies vm_depth,vm_error,vm_sp,vm_local_base,vm_local_top,vm_pc,bytes(vm_frames,40960),bytes(vm_local_memory+vm_local_top,32768);
ensures result == 1 && vm_error == 0;
ensures vm_finished == old(vm_finished);
ensures vm_depth == old(vm_depth)+1;
ensures vm_pc == pc+16;
ensures vm_sp == old(vm_sp)-count*8;
ensures vm_sp >= 0 && vm_sp <= 524288 && (vm_sp & 7) == 0;
ensures vm_sp >= old(load64(vm_frames+(vm_depth-1)*40+24));
ensures vm_local_base == old(vm_local_top);
ensures vm_local_top == old(vm_local_top)+slots*8;
ensures vm_local_top <= 8388608 && (vm_local_top & 7) == 0;
ensures vm_local_base >= 0 && vm_local_base <= vm_local_top;
ensures load64(vm_frames+old(vm_depth)*40) == return_pc;
ensures load64(vm_frames+old(vm_depth)*40+8) == old(vm_local_base);
ensures load64(vm_frames+old(vm_depth)*40+16) == old(vm_local_top);
ensures load64(vm_frames+old(vm_depth)*40+24) == old(vm_sp)-count*8;
ensures load64(vm_frames+old(vm_depth)*40+32) == index;
ensures load64(vm_frames+(old(vm_depth)-1)*40+24) == old(load64(vm_frames+(vm_depth-1)*40+24));
ensures readable_bytes(vm_frames,40960);
ensures readable_bytes(vm_stack,524288);
ensures writable_bytes(vm_local_memory+vm_local_base,32768);
fn enter_accepts_framed(index,return_pc,pc,count,slots,code_size) {return vm_enter(index,return_pc);}
