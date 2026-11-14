# VM, JIT, and compiler verification

The objective is a composed, machine-checked confinement and semantic-preservation
argument for the production restricted VM, its JIT, and the compiler that creates
the executed artifacts. This ledger records the whole objective. A passing
helper proof does not discharge callers, initialization, the compiler, or native
instruction execution. Updates must identify the implementation, checked theorem,
entry premises, executable-artifact binding, and remaining dependencies.

## Claims and scope

The confinement claim starts with untrusted source and arguments, a host-selected
restricted configuration and capability set, and an explicit host-state invariant.
Compilation either fails safely or produces an artifact whose execution preserves
host/guest separation. Execution may return, trap, suspend through a host-enabled
safe point, or exhaust a budget. Every permitted host effect must be authorized by
the original capability set. Failure paths must preserve the same boundary.

The semantic-preservation claim relates source behavior to each compiled
representation and its executed instructions, including word wraparound, signed
division traps, evaluation order, memory effects, calls, and observable host I/O.
Fuel counts the selected bytecode stream: optimization may change instruction
counts, but every execution tier must implement that stream's specified metering.
Deadline and kernel-blocking guarantees must state their scheduling/OS premises.

The current implementation distinguishes trusted execution from restricted
execution. Trusted execution deliberately grants native pointers, raw system calls,
and FFI; its compiler-correctness obligations remain in scope, while the guest
confinement theorem applies to restricted execution. Foreign implementations need
explicit semantics or visibly conditional external contracts.

The full compiler surface remains in scope: Flexscript, SetaScript, FIR, imported
modules, compile-time transforms, custom frontends/platform modules, registered
lowerings, optimizations, and supported native/shader/GPU/embedded targets. Initial
work proceeds through Linux x86-64 restricted bytecode and its x86-64 JIT. Other
paths remain **unproved** until their own semantics and preservation evidence exist;
this order does not exclude them from the final objective. Thread, interrupt, and
GPU concurrency require execution models beyond the current sequential verifier.

## Evidence vocabulary

- **Proved under premises:** all named source obligations and dependencies passed
  the checked evidence path. List premises and the semantic layer actually checked.
- **Conditional:** a claim uses an unchecked external function contract or other
  specifically identified assumption beyond the listed semantic foundation.
- **Unresolved:** a concrete attempted obligation exhausted a budget/capacity or
  could not be decided/replayed. Preserve a reproducible input and reason.
- **Unproved:** the theorem or implementation coverage has not been established.
- **Unsupported:** the verifier cannot currently model a required construct.

Regression tests, mutation checks, executable comparisons, and manifest hashes
support the argument but do not independently prove semantic preservation.

## Coverage ledger

| Component / obligation | Implementation | Current evidence and outstanding work |
| --- | --- | --- |
| Restricted range rejection and exact address calculation | `vm/address.flex`: `vm_address` | **Proved under premises** by `vm/proofs/address.flex`: nonzero restricted mode, used prefix 16..1,000,000,000, positive/nonwrapping host heap span, and initially clear error. Accepted offsets/lengths are contained in the used prefix, translation is exact, and rejection sets error 3. Arbitrary signed 64-bit offsets and lengths. |
| Acceptance of admissible ranges | Same production helper | **Proved under premises** by `restricted_address_accepts`, including zero-length end access and no global writes. Entry heap/mode premises still require initialization and preservation proofs. |
| Address proof negative controls | `scripts/test-proof-vm.flex` | Five temporary broken guards produce checked, concretely replayed counterexamples. Positive heap state is symbolic; negative scenarios use a fixed small heap and symbolic 64-bit inputs. CI runs the suite. |
| Heap mapping, separation, initialization | `vm/runtime.flex`: `vm_initialize`, argument/string setup, module loading | **Unproved.** Show host mappings are live, distinct, correctly sized, and initialized; reject partial initialization safely; bind configured limits and keep host metadata outside the guest heap. |
| Bump allocation | `vm/allocation.flex`: `vm_allocate`, `vm_round_allocation` | **Proved under premises** for both execution modes: live positive/nonwrapping heap, 16..CLI-limit cursor, and native usage within the entry budget. Cursor stays monotone and within the heap limit, retains alignment, covers successful requests, and is unchanged on failure; results use the correct mode's address representation and only the specified failure codes. Every positive request whose rounded size fits is accepted, including exact fits. Rounding has its own checked modular summary. The checked postcondition also maintains the combined bump/native budget against the limit in both modes. Mapping/separation premises remain unproved. |
| Restricted combined managed budget | `vm/proofs/allocation.flex` | **Proved under premises**: zero native usage remains zero, and bump cursor plus native usage stays within the limit. Initialization and dispatch must establish/preserve restricted mode's zero-native-usage premise. |
| Mixed bump/native combined budget | `vm/proofs/allocation.flex`: `mixed_allocation_budget` | **Proved under premises** (moved out of pending on 2026-11-13): with native usage inside the remaining budget at entry, the strengthened checked allocator postcondition closes `vm_heap_used + vm_native_used <= vm_heap_limit` in both execution modes. Initialization and the native allocator's own accounting must establish and preserve the entry premise. |
| Allocation proof negative controls | `scripts/test-proof-vm.flex` | Four additional temporary faults require checked, replayed counterexamples: missing rounded-size check, rounding down, unconditional rejection, and cursor mutation on failure. |
| Native allocation accounting | `vm_native_allocate`, `vm_native_unmap` | **Unproved.** Needed for trusted execution semantics, compiler/runtime self-use, and resource accounting; unrestricted execution grants host authority intentionally. |
| Operand push and buffer ownership | `vm/operand-stack.flex`: `vm_push`; `vm/proofs/operand-stack.flex`, `operand-stack-region.flex` | **Proved under premises.** Local writable top-slot ownership yields exact stored value and an eight-byte cursor increment; a full cursor rejects with error 4 without byte access. A checked subregion lemma derives slot ownership from a full writable stack buffer. The composed buffer profile covers aligned cursors 0..524,288, both outcomes, correct data on success, unchanged cursor on rejection, and bounded write effects. Native mapping/separation and initialization remain premises. |
| Operand pop primitive and unframed composition | `vm/operand-stack.flex`: `vm_pop_value`, `vm_pop`; `vm/proofs/operand-stack.flex` | **Proved under premises.** Given an eight-byte readable old top slot and cursor 8..524,288, the production read primitive decrements exactly eight, returns the old slot value, preserves the error flag and writes no bytes. The composed depth-zero nonempty profile establishes the same behavior with initially clear error. The depth-zero empty case rejects with error 4 without byte access. |
| Framed operand underflow | Same production `vm_pop` and operand proof roots | **Proved under premises.** Depth 1..1,024, cursor 0..524,288, and ownership of the readable saved-floor field whose signed value is at least the cursor. Rejection preserves the cursor, sets error 4, returns zero, and does not read stack bytes; no stack-byte permission is supplied. Frame mapping, geometry, saved-floor initialization and their preservation remain premises. |
| Successful framed pop | `operand_pop_frame` and checked scalar order lemma in `vm/proofs/operand-stack.flex` | **Proved under premises.** Depth 1..1,024, cursor 8..524,288, clear error, readable saved floor and old top slot, and saved floor in 0..cursor-8. The same production `vm_pop` returns the exact old top word, decrements the cursor by eight and preserves clear error. An erased checked proof derives strict floor order and nonzero depth without narrowing the entry domain. The formerly unresolved root is now in the passing gate. |
| Unified pop step and whole caller invariant | stack/frame profiles and interpreter callers | **Unproved.** Assemble the case profiles from complete buffer ownership and the aligned-cursor/floor invariant; initialization and call entry must establish those premises. Completed local profiles do not prove that every interpreter caller supplies valid metadata, cursor bounds or permissions. |
| Frame return and empty-stack rejection | `vm/frame-state.flex`: production `vm_return`; `vm/proofs/frame-state.flex` | **Proved under premises.** Depth zero rejects with error 9 and no byte access. At depth 1..1,024, ownership of the four saved fields yields exact restoration of PC, local base/top and operand cursor, decrements depth once, preserves error, and sets completion on saved PC -1 while otherwise preserving completion. No byte memory is written. Saved words may be arbitrary in this exact-restoration profile. |
| Frame metadata bounds and buffer ownership | Same production helper and frame proof roots | **Proved under premises.** A separate checked profile preserves supplied saved-PC bounds/alignment, local base/top order and 8 MiB bound, and operand cursor bounds/alignment, with exact saved-cursor restoration. Any positive aligned code size at least 16 is permitted; PC equal to code size is a possible next-fetch trap, not an executable instruction. Checked stride bounds and a subregion lemma derive the four-field grant from the full 40,960-byte frame buffer at every depth 1..1,024, and the buffer profile composes that grant with exact restoration. Initialization, valid mapping/separation and call-entry metadata remain unproved. |
| Nested return and caller-floor preservation | `frame_return_floor`, `frame_return_state`, checked specification readers/predicates in the frame proof module | **Proved under premises.** At depth 2..1,024 with a readable full frame buffer and saved floors `0 <= parent <= callee <= 524288`, return restores a bounded cursor at or above the newly active caller's saved floor. The composed state profile also preserves the supplied PC/local/cursor metadata bounds and completion/error behavior. Specification functions establish read grants before evaluating metadata predicates; they are checked dependencies, not trusted external contracts. Call entry must establish/preserve the saved-floor chain; the whole frame-prefix and local-layout invariant is still unproved. |
| Frame proof negative controls | `scripts/test-proof-vm.flex` | Five temporary production faults require checked replay: missing underflow rejection, decrementing depth twice, restoring local base from the wrong field, missing main-return completion, and restoring cursor zero below a nonzero caller floor. The floor witness also checks the original production implementation first. Fixed witness profiles specialize old slot addresses consistently with the selected entry globals; the positive roots retain symbolic frame state. |
| Call capacity guard | `vm/call-frame.flex`: `vm_call_capacity`; `vm/proofs/call-capacity.flex` | **Proved under premises** (10/10 bundle including the `vm_pop_value` dependency root): depth 1..1023, cursor 0..524,288, local top 0..8,388,608, clear error, readable frames buffer, and a readable saved floor within 0..cursor. Rejection happens exactly for malformed count/slots bounds, a short unframed span, local-area overflow, a saved floor outside 0..cursor, or a short available framed span `count*8 > cursor-floor`; exact unframed/framed/local fits are accepted, negative arity is rejected before metadata access, and rejection sets error 9 without other writes. The checked `call_argument_capacity_equivalence`/`call_argument_accept_order` lemmas (added to the passing bundle 2026-11-13, resolving the former pending arithmetic bridge) derive the saved-cursor invariant from the available-argument span: acceptance is exactly the condition under which the new saved floor is a bounded operand position at or above the caller floor. |
| Call capacity negative controls and native regression | `scripts/test-proof-vm.flex`, `vm/proofs/regressions/call-argument-underflow.flex`, `vm/proofs/counterexamples/call-argument-underflow.json` | **Checked 2026-11-13.** Six temporary guard faults require concretely replayed counterexamples: ignoring the active caller floor, rejecting an exact unframed fit, rejecting an exact framed fit, rejecting exact local capacity, ignoring the argument-count bound, and accepting excessive slots. Three fixed-witness positive profiles check the original guard first. The native regression fixture passes with the current guard (exit 0), and removing the floor guard reproduces the original defect's exit (1) natively, matching the retained counterexample record. The suite also verifies that mutation checks leave the real VM source unchanged. |
| Production call entry, first path | `vm/call-frame.flex`: `vm_enter`; `vm/proofs/call-entry.flex` | **Proved under premises** (2026-11-13): out-of-range index or depth at/over 1024 rejects with error 4 before touching byte memory, preserving every other global. The remaining entry paths (header/capacity rejection with symbolic metadata, and the acceptance state transition including the argument-copy loop) are retained with their exact postcondition sets in `vm/proofs/pending/call-entry.flex`; the verifier currently builds the whole production body's circuit for any root that passes the header check, and the copy loop's symbolic-store iterations are unresolved under every tried invariant set. Discharging them needs a checked loop summary or membership reasoning over loop-carried sums (an engine extension the full objective requires). |
| Interpreter state and remaining bytecode steps | `vm_enter`, `vm_continue`, `vm_builtin`, `vm_binary` and stack/frame dependencies | **Unproved.** Specify valid PC/opcodes, operand-stack floors, frame geometry, local/global memory, arithmetic/traps, fuel, errors, and suspension; prove each step preserves separation or traps. In particular, call entry must establish the saved-field premises used by return, preserve the existing frame prefix through argument/local initialization, and establish saved-floor order for nested calls. Direct table operations and composition of the proved stack/return cases still need coverage. |
| Operand proof negative controls | `scripts/test-proof-vm.flex` | Nine temporary faults require checked replay: accepting a full stack, incorrect push/pop strides, incorrect pushed/popped values, missed empty-stack underflow, ignoring the saved frame floor, reading the wrong frame field, and discarding a nonempty framed pop's result. The result witness also checks the original implementation first. These checks select the affected theorem, constrain a small VM/data witness state, and may use a one-billion-unit query budget; the positive gate checks every root with symbolic state under its stated premises. |
| Capability-mediated effects | `vm_address`, `vm_host_fd`, `vm_guest_path`, `vm_open_file`, `vm_poll_guest`, `vm_syscall` | Address helper proof only. **Unproved** policy theorem: descriptor translation, bounded host buffers, filesystem-root authority, denied writes/network/process/FFI, output limits, waits, clock, and invocation-local exit. OS calls need precise models and explicit assumptions. |
| Arbitrary VM execution | initialization + interpreter + host-call dependencies | **Unproved.** Compose initial invariant, step preservation and host effect policy for arbitrary guests. Prove traps and fuel exhaustion preserve confinement; separate partial correctness from termination and real-time guarantees. |
| x86-64 JIT | `vm/jit.flex` | **Unproved.** Formal instruction/ABI semantics, bytecode eligibility validation, register/native-stack discipline, branch relocation, memory/global accesses, fuel/deadline/trap behavior, RW-to-RX publication and immutable executed-code binding. Code-cache fallback and cleanup need the same safety argument. |
| ARM64 JIT | `vm/jit-arm64.flex` | **Unproved.** Separate ISA/ABI semantics and emitted-code validation/preservation, including caller-owned code/context/scratch buffers and errors. |
| Lexing, parsing, resolution, source/module loading | `compiler/main.flex`, module/import helpers, frontends | **Unproved.** Include malformed/adversarial inputs, parser memory safety and limits, namespace/arity handling, evaluation semantics, and compile-time effects before guest execution. |
| Extension and lowering proof binding | `compiler/transforms.flex`, `extensions.flex`, `lowering.flex` | **Unsupported** in current source verification: extension-bearing programs and lowering declarations are rejected pending post-expansion/operation proof binding. Must bind verified declarations to actual emitted operations and host-approved expansion/configuration. |
| IR construction, validation and optimization | `compiler/ir*.flex`, `native-ir.flex` | **Unproved.** Establish source/IR and IR/optimized-IR relations; include folding, CSE, branches, reachability, relocation, liveness, memory/host effects and trap preservation. Existing structural validators require proofs of their own claims. |
| Bytecode construction and execution binding | VM source emitter, frontend VM emitters, IR-to-VM paths | **Unproved.** Prove well-formedness and semantics for the exact compiler-owned bytecode consumed by the interpreter/JIT; protect immutable bytecode and metadata from guest writes. |
| Native and remaining target emission | `compiler/backends/`, `cpu-cxx.flex`, `gpu-codeobject.flex`, native linking/relocation | **Unproved.** Linux/Android ARM64, x86-64, WASM, shader languages, PTX/SASS/HIP/RDNA, CPU C++, bare-metal and ESP32/RISC-V paths each need target semantics, lowering and code-generation evidence. External toolchains require explicit assumptions or verified/validated output. |
| End-to-end composition | source → actual compiled artifact → VM/JIT/native observations | **Unproved.** No current end-to-end theorem or proof-carrying executed artifact. Every included path above must supply the appropriate checked dependency. |

## Proof foundation and external assumptions

The current source-verification foundation includes the parser's annotation/source
binding, symbolic execution, bit-vector and memory encodings, obligation generation,
and evidence checkers. Search is checked using satisfying assignments or
unsatisfiability certificates; a search answer alone is insufficient. The semantic
encoding and checkers themselves have not been formally proved correct.

The compiler and bootstrap executable running those checkers, emitted machine code,
host ABI, kernel syscall behavior, mapping/protection behavior, and hardware also
remain part of the current trusted foundation. A source proof does not verify those
layers. `--no-trusted` excludes unchecked function contracts; it does not eliminate
these implementation assumptions. The ledger must shrink this foundation through
explicit preservation/validation results and retain all unavoidable assumptions in
the final theorem statement.

On 2026-11-13 the verification circuit context was widened from 131,072 to
524,288 gates (`compiler/proof-verify.flex`, `libs/proof/word.flex` validation).
This is a capacity-only change to the still-unverified engine: no rule, encoding,
or checker logic changed, and all previously passing bundles re-verified. The
widened budget is required by call-entry roots whose paths reach the whole
production body's circuit; the remaining open roots are documented in
`vm/proofs/pending/call-entry.flex`.

Two further engine behaviors were characterized on 2026-11-13 and are recorded
in `vm/proofs/pending/call-entry.flex`. An earlier suspicion of cross-root
degradation was a misdiagnosis: a step lemma with assert-scaffolded shift
reasoning verifies next to loops. The real remaining gap is that loop
preservation queries cannot perform constant-shift and product-shift
identities (`d+8 <= c` implying `d <= c-8` under the nonwrapping conjunct, and
`(s-1)*8 == s*8-8`), while every other piece of the copy-loop assembly
(scaffolded step lemmas, the sweep pattern with a permission invariant on the
exact store-address term, the entry facts) has a standalone-proved shape. Two
bounded word-circuit comparison changes are identified as candidates; neither
has been changed yet.

The arithmetic encoding now specializes signed division by a positive constant
power of two using a sign-dependent bias and arithmetic shift, with a general
fallback for other divisors. Constants are normalized to the circuit width before
classification. Signed comparisons use the exact sign/difference rule, and
subtraction reassociates symbolic sums modulo the word width with bounded metadata
descent. Native-reference and exhaustive small-width circuit checks cover these
rules; their implementation remains within the semantic-encoding foundation.

Constant offsets are pulled out of either symbolic addend and distributed through
multiplication by a constant, modulo the word width. This gives adjacent frame
records a common symbolic base without assuming nonoverflow. Addition's recursive
metadata rewrite has a bounded depth and an exact raw-adder fallback. Exhaustive
small-word native arithmetic, signed/wrapped constants, and native 64-bit boundary
products (including zero, one and minimum-word strides) check the rules.

Positive constant dividend one also has an exact quotient/remainder encoding:
divisors +1 and -1 yield quotients +1 and -1 and remainder zero; other nonzero
divisors yield quotient zero and remainder one. Division by zero remains unsafe.
Width normalization excludes width one's negative raw `1`. Exhaustive small-width
divisors, wrapped raw constants, native 64-bit boundaries, and checked wrong-output
refutations cover the shortcut. It removes an expensive general division circuit
from the existing specification-function reciprocal proofs.

Arithmetic metadata must refer only to older words. A new normalization bug was
reproduced when cancellation returned a shared input/expression and rewrote its
description using newer words, creating a cycle. `pw_note` now preserves shared
descriptions in that case; input and shared-expression alias regressions check
the allocation-order invariant and subsequent arithmetic. This is a checked
regression within the still-unverified encoding implementation.

For valid nonwrapping regions, membership uses the exact unsigned modular
distance `address - start < length`, after extracting constant offsets. This
allows nested addresses to cancel a common symbolic base. A native interval
matrix, wrapped-offset cases, 64-bit boundary cases and the existing independent
memory-completion/corruption tests cover this encoding. It discharges the full
stack-buffer to top-slot permission lemma without assuming a trusted lemma.

Initial-memory congruence constraints are constructed only when two observed
addresses might be equal. When exact address simplification already yields false,
the implication is true and its byte/identity equality circuits are unnecessary.
Avoiding those unused circuits discharges full frame-buffer return composition
within the existing capacity limit. A bounded 32-byte observation regression
checks both a concrete writable model and a checked read-permission refutation;
the existing alias, memory-completion and corruption tests remain in force.

The source executor propagates callee globals and heap on the successful return
path. A function's first returned state requires no merge with an unreachable
entry-state placeholder; later returns still merge with all prior return paths.
Branches and short-circuit operators explicitly preserve their bypass globals
and heaps. The logical-operator snapshot is taken after the left operand, so its
effects survive when the right operand is skipped. Regression cases cover ordinary
and summarized global/heap-writing calls, both logical operators, early returns,
left-operand effects, native behavior and replayed negative cases.
When exact Boolean simplification makes one branch path false, the executor
uses the surviving state directly. A checked proof assertion can expose an
entailed branch fact; a regression confirms that a false assertion still yields
a replayed counterexample and cannot certify the resulting unreachable code.

Boolean circuits factor common masks and simplify an XOR between a mask and
one of its operands using exact identities. Independent truth tables cover
signed literal positions; universal 64-bit queries cover comparisons against
selected word arms. These rules discharge the previously unresolved unframed
pop return composition without changing production behavior or its premises.
Nested selections sharing a bypass value also collapse to one selection with
the corresponding combined selector. Independent truth tables cover both
selector signs, negated inner choices and all four shared-arm positions;
universal 64-bit queries cover both resulting word arms. This permits exact
frame-field restoration through nested call/return state joins.

Conflict learning uses watched literals while retaining independently checked
resolution certificates. Expanded exhaustive/oracle checks exposed a pre-existing
incompleteness defect: repeated unit literals such as `[-1,-1]` were counted as
multiple unknown/current-level variables, causing an immediate satisfiable query
to remain unresolved. The working clauses retain their original bytes; occurrence
tracking counts duplicates once and recognizes tautologies. Dedicated regressions
check SAT, UNSAT, all three decision modes, corrupted certificates and exhaustion.
Input-oriented search chooses unassigned watched variables after draining the
propagation queue instead of rescanning every clause for each decision. General
refutations retain a bounded preliminary phase and preserve the remaining budget
for late-clause selection. Consistency queries may use their full bounded
learning budget and initially prefer zero bits.
This exposed two further incompleteness defects: duplicate occurrences could
occupy both watches, and an existing asserting clause was not enqueued after
backtracking because no new-clause registration occurred. Watches now prefer
distinct literals, replacements cannot duplicate the partner literal, and the
backjump explicitly enqueues an asserting unit. Dedicated regressions and
exhaustive/native formula oracles check the changes. All search answers retain
the same bounded independent model/certificate checks. Unresolved source obligations
also report formula size and search work. Construction failures report used/maximum
circuit gates/words and memory nodes/probes/lookups/regions once per root. A source
regression exhausts the circuit and checks that the result remains unproved.

## Reproduction and acceptance gates

Build a current compiler and run the initial proofs and negative controls:

```sh
mkdir -p build
flexscript compiler/main.flex -o build/flex-proof
build/flex-proof verify vm/proofs/address.flex --no-trusted
build/flex-proof verify vm/proofs/allocation.flex --no-trusted
build/flex-proof verify vm/proofs/operand-stack.flex --no-trusted
build/flex-proof verify vm/proofs/frame-state.flex --no-trusted
build/flex-proof verify vm/proofs/call-capacity.flex --no-trusted
build/flex-proof verify vm/proofs/call-entry.flex --no-trusted
build/flex-proof scripts/test-proof-vm.flex -o build/test-proof-vm
build/test-proof-vm build/flex-proof
```

Reproduce the open call-entry obligations separately:

```sh
build/flex-proof verify vm/proofs/pending/call-entry.flex --no-trusted
```

These commands are expected to remain unsuccessful until the loop summary and
the acceptance transition are discharged; a circuit-capacity or unresolved
report is the documented blocker, not a counterexample against the guard.

For each new production component, add theorem roots, state premises and effects,
counterexample/negative controls, current-implementation/artifact binding, and CI
coverage. Report an unresolved query as unresolved and preserve its input. A
general checked-in incomplete theorem must remain visibly outside passing proof
gates until it is discharged; do not weaken its intended claim to obtain green CI.

Completion requires a reviewed statement of the entire supported scope, checked
composition across its actual executed representations, explicit remaining
assumptions/exclusions, and current runtime regression evidence. Every open ledger
row must be discharged or explicitly reviewed as a remaining assumption; a smaller
proved subset cannot establish completion of this goal.
