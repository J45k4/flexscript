# Full VM, JIT, and compiler verification plan

The verification goal is active. Current work covers the interpreter's call
and return invariants and the x86-64 JIT's relocation and publication path.
The [coverage ledger](docs/vm-verification.md) records each obligation's status.
Updated 2026-11-23.

## Goal and completion rule

Establish machine-checked confinement and semantic preservation for the actual
Flexscript restricted VM, its JITs, and the compiler that produces the executed
artifacts, using the in-repository proof engine. Extend that engine as necessary.
Use the production [guest address translation](vm/address.flex) and its
[checked proof roots](vm/proofs/address.flex) as the starting point for the
VM memory boundary.

The final argument must start with untrusted source and inputs, pass through the
actual compiler representations and emitted artifacts, and cover arbitrary VM/JIT
execution, including errors, traps, suspension, resource exhaustion, and permitted
host effects. Proofs must bind to the exact implementation and artifacts executed.

For each supported compilation path, prove that successful compilation produces
an artifact whose execution refines the declared source semantics. Starting from
a valid restricted VM state with host-selected capabilities, prove that every
execution prefix limits guest-directed reads and writes to authorized memory and
emits only authorized host effects, whether it uses the interpreter, the JIT, or a
fallback.
Specify and check the allowed error and resource-exhaustion behavior along the
same path.

An isolated helper proof, successful test, sampled execution, unresolved query,
or unchecked function contract does not establish this goal. Keep the goal open
until the complete supported scope has a checked composition and every remaining
assumption or exclusion is explicit and reviewed. Do not silently reduce scope
to the components that already pass.

Work on `master`, without creating branches. Preserve unrelated concurrent work.
Obtain renewed explicit authorization before committing or pushing this proof work.

## Next milestones

1. Complete interpreter call entry.
   - Establish the input state of the function-record writes from parsing.
     Use the checked header emission, slot patch, body append, and jump patch
     to establish preservation through the parser's body and fixup loops and
     through optimization. Use the checked bounds and distinct placement
     of live map entries to prove preservation of header words and liveness
     through the full optimizer. Then connect the header and record to the
     first complete `vm_enter`.
     The startup-to-record composition establishes heap separation and the
     exact results of the two function-record loads.
     Complete the optimizer worklist induction for successor discovery,
     distinct queue entries, queue capacity and termination. Use the
     checked flag preservation and cleanup rules to carry the established
     marks into layout.
   - Derive the active-floor read grant and cursor premises of `vm_enter`
     from the initialized and preserved VM state invariant.
     See the [remaining call-entry obligations](vm/proofs/pending/call-entry.flex).
   - Connect the checked backing-buffer and accepted-entry results to the
     pointwise argument-copy observer. Derive its selected read grants and
     separation from the live VM allocations.
   - Extend the immediate call-and-return proof to apply when bytecode executes
     between entry and return. Reuse the checked preservation of the older frame
     prefix and ordered-floor extension. Prove the entry, return, and operand
     operations preserve the shared invariant established at initialization.
     Close the milestone when these proofs run against the production functions
     with `--no-trusted` and the VM gate checks their mutation controls.
2. Extend the interpreter proof to initialization, every opcode and dispatcher
   path, and capability-mediated host effects. Use the resulting step theorem to
   prove confinement for arbitrary restricted executions.
3. Connect the checked x86-64 normal binary instruction models to the emitted
   division and remainder guards, their branch relocations, and error exits.
   Prove that the production emitter and relocator always direct zero divisors
   and signed overflow to the safe VM error exit, and direct all other inputs to
   the division setup. Establish the normal-path premises at the JIT dispatcher,
   compose opcode admission with the validation loops and emitters, and bind
   the result to the exact bytes published and executed. Extend to the remaining
   x86-64 JIT paths and verify ARM64 separately.
4. Prove preservation through the compiler's supported frontends, transforms,
   IR, optimizations, bytecode, and native backends. Compose these results with
   the VM and JIT proofs and audit the trusted assumptions and coverage.

## Current evidence

The detailed coverage ledger is [docs/vm-verification.md](docs/vm-verification.md).
Every claim there must identify its premises, dependencies, and semantic layer.

| Area | Current state |
| --- | --- |
| Restricted address translation | Source proofs exist for rejection, exact translation, and acceptance under heap/mode/state premises. |
| Bump allocator | Source proofs cover rounding, allocation behavior, and the combined bump/native budget under entry premises. Mapping, initialization, and native allocation/unmap accounting remain open. |
| Shared startup | Production `vm_initialize_buffers` establishes the writable extents for all startup buffers and the pairwise separation of the heap, operand stack, locals, and frames. It establishes the fresh descriptor table apart from the core buffers, checks its pointwise initial values, and preserves existing memory and the incoming scalar cursors and budgets. Failure cleanup, JIT host setup, and caller establishment of the full VM invariant remain open. |
| Compiler function records | The checked composition follows shared startup with the production code and function-table allocations and source compiler record writes. The successful path preserves the heap's writable span, separates it from both compiler buffers, and checks the exact entry offset and arity at the two production load sites. Parser establishment of the metadata and the full call transition remain open. |
| VM function header | The checked normal emitter writes exactly two words, binds the function record to opcode 18 at the emitted offset, and preserves the recorded arity. A separate checked slot patch retains the opcode and the record's offset and arity. The parser and function-body compiler must establish and preserve the premises of these checks. |
| VM body emission | Under separate backing-buffer premises, one in-bounds instruction append preserves the existing header and function record's offset and arity. A jump-operand patch preserves those fields under its selected-span premises. The emit-and-patch proof checks the opcode choice and the exact target when patching to the next instruction. The parser's repeated writes, valid fixup offsets, and optimization remain open. |
| Optimizer compaction | The checked map builder terminates, writes within its region, and stores the aligned compacted size in the final map word. The checked scan-step profile is generated from the production loop. It records the current offset, adds 16 bytes exactly for a live flag, proves a just-recorded live offset passes the VM guard, and preserves an earlier disjoint map word. The copy preserves the opcode and ordinary operands and remaps branch operands. Given a copied header and valid map entry, rebinding preserves the header and arity and supplies a PC that passes the production instruction-bounds guard. For an arbitrary live input slot, the complete production layout scan preserves its assigned offset through the sentinel write. The actual map accessor and VM bounds guard accept that offset. The complete scan places any earlier live slot strictly before every later slot. A later copy to a different aligned offset preserves both words of an earlier header. A checked composition copies a selected live header, writes its new offset to the function table, preserves arity, and passes the VM bounds guard. For a selected header, the copy, relocation, and size assignment feed the actual PC, opcode, arity, and slot reads in the VM entry prefix. The checked capacity composition accepts a selected relocated call that fits the operand and local bounds, with separate proofs for an empty frame stack and an active caller. In the active case the two optimizer writes preserve the disjoint saved operand floor. The selected accepting path now composes those optimizer writes with production frame installation and the local-copy loop. Separate roots for empty and active caller stacks verify the exact cursor and PC updates and all five saved frame fields for the return PC, caller local base and top, remaining operand position, and function index. Writes remain within the selected optimizer words, new frame record, locals span, and VM state fields. The selected capacity rejection path follows the same optimizer writes and production metadata reads, returns zero with error 9, and excludes operand, frame, and local updates. Relocated call entry followed immediately by production return restores the exact caller depth, return PC, local base and top, and operand position after consuming arguments. The return sentinel sets completion, and ordinary return preserves its incoming value. Header liveness through the full optimizer, the complete copy and relocation loops, and exact argument values across the whole handoff remain open. A checked iteration uses the production live-bit reader and map lookup. It preserves the destination on dead paths and checks the exact opcode and ordinary or remapped operand on live paths under the stated buffer and map premises. For any complete eight-byte window in the older frame prefix, selected relocation and accepted entry preserve the exact bytes. The immediate return preserves the same word. The production layout scan also assigns offsets at, at+16, and at+32 to any three consecutive live input slots. The proof checks loop termination, entry preservation through the size sentinel, and room for all three instructions. The VM gate compares native artifacts from the annotated scan and the production body. The VM gate connects the production scan and both instruction copies for the selected live PUSH and RETURN. It derives the writable spans and exact map targets, passes those lookup results to the writer, and preserves the raw instructions, the final map size word, and the header map entry needed by relocation. The native regression follows the scan with the three writes in optimizer order and then relocates the record across 1,398 layouts. The body-copy proof also carries the scan’s aligned size and verifies it fits the original output capacity. The checked relocation reads the old PC from the record, installs the compacted PC, and preserves arity and both raw body instructions. The native interpreter regression runs 36 layouts before and after optimization and checks the relocated call, arguments, zeroed locals, restored state, and fuel. The checked scan-to-ordered-copy composition derives the three map entries and destination spans from the production scan, the three selected live flags, and disjoint backing regions. It preserves the exact header, PUSH, and RETURN words in production order. The same proof composition follows the production relocation and preserves all six words and record arity while updating the record PC. Optimizer liveness, the complete loops, and the connection to VM entry remain open. The checked relocation and accepted entry also compose with the selected interpreter PUSH and RETURN sequence when the two instructions are already present immediately after the relocated header and the stated buffer grants and fuel premises hold. Both instructions remain readable and preserve their opcodes across entry. The sequence writes the accumulator into the operand slot, charges two fuel units, and restores the caller state. The proof derives the word grant and separation from the frame allocation, its separation from the local allocation, and its separation from the selected output instruction and function PC field. A checked downstream proof starts with an already relocated record, copied header and body, and the compacted size. It checks the production size assignment, framed call entry, and selected PUSH and RETURN. The proof that connects those premises to the ordered optimizer writes remains open. |
| Operand stack | Source case proofs exist for push, pop, frame-floor rejection, exact returned values, and buffer/slot permission composition. Whole-execution invariants remain open. |
| Frame return | Source proofs exist for exact restoration, bounded saved metadata, completion behavior, buffer permissions, and supplied nested-floor invariants. Call entry and initialization still must establish those premises. |
| Call capacity | Production `vm_call_capacity` passed all ten roots in `vm/proofs/call-capacity.flex` with `--no-trusted`. This covers valid-state framed/unframed acceptance and rejection, negative arity, exact-fit witnesses, and checked available-argument/saved-cursor equivalence lemmas. |
| Confirmed VM defect | Original call entry counted caller-owned operands below the active frame floor as arguments. A checked counterexample and native reproduction are retained under `vm/proofs/counterexamples/` and `vm/proofs/regressions/`. The local guard fix rejects this call. This is a frame-boundary violation; no host escape has been demonstrated. |
| Call-entry integration | The gate checks selected metadata values and derives the read grants from bounded buffers. For a valid header and bounded VM state, the production guard prefix verifies the exact capacity decision on the loaded arity and slots, including the framed operand-floor check. The complete rejection path returns zero and changes only the error flag to 9. Slot-read and error-code mutations replay. Exact contents across the complete accepted path remain open in `vm/proofs/pending/call-entry.flex`. |
| Accepted call-entry buffer grants | Six checked profiles derive the readable argument span, writable destination, writable frame record, and pairwise separation from the accepted production guard prefix and corresponding backing-buffer grants. The full transition still needs to use these results across the frame and local updates. |
| Call-frame save | The production save statements have checked proofs for all five saved fields, the local cursor updates, and preservation of the caller's saved floor. Checked lemmas derive individual permissions from the writable frame allocation. The VM gate replays a wrong-field mutation. The accepted entry path still needs to establish the premises and compose this transition with local initialization and return. |
| Call-copy tail | The VM gate derives the argument and destination subspans from successful core allocations and checks the production tail's copy effects, operand cursor, depth, and PC updates. The complete accepted call path still needs to compose the metadata checks, frame save, and copy tail. |
| Saved frame after local copy | The VM gate checks each of the five new frame fields and every word of the older frame prefix after the composed frame-save and local-copy stages under disjoint buffer and post-guard premises. The complete accepted entry path remains open. |
| Argument copy and local initialization | Under disjoint spans and `0 <= count <= slots <= 4096`, checked proofs establish memory safety, bounded effects, and termination for `vm_copy_call_locals`. Pointwise induction proves that each argument slot equals its source word at helper entry and every other slot contains zero. The caller's establishment of the helper's premises remains open. |
| Accepted suffix contents | Under validated bounds and selected-span premises, a checked composition proves that frame saving preserves the arbitrary observed argument word, then copying writes that entry value to its local slot. A separate root checks unused slots receive zero. Both check the final cursor values. |
| Complete successful entry effects and saved frame | The production `vm_enter` calls the checked `vm_enter_accepted` stage. Under valid metadata, bounds and selected-span premises, the composed proof checks success, preservation of the error flag, exact cursor updates, all five newly saved frame words, and the write footprint for depths 0 through 1023. |
| Accepted local contents | Two pointwise proofs follow production calls from metadata through local initialization. Every unused slot receives zero, and each copied slot receives its argument word from function entry, under the selected-span premises. Connecting the argument observer grants to the caller invariant remains open. |
| Accepted entry preserves older frames and extends the floor chain | Separate profiles check every complete eight-byte window in the old frame prefix and show that the newly saved nested operand floor is at or above the old caller floor. A live-frame overwrite mutation replays. |
| Accepted entry uses backing-buffer grants | A checked wrapper derives the complete accepted call's selected frame, operand and local permissions from the backing allocations and their separation. It checks exact saved fields and cursor updates. Compiler metadata and active-floor grants still need to follow from the VM state invariant. |
| Immediate call and return | A checked composition of `vm_enter` and `vm_return` restores caller depth, local cursors, and return PC. The operand cursor excludes consumed arguments, and completion follows the return sentinel. It uses the backing-buffer, selected metadata, and active-floor premises and has no intervening guest instructions. |
| Word operations | Eighteen checked source roots cover the production interpreter and constant-folding helpers, including signed division and remainder traps. Dispatch, surrounding optimizer rewrites, and emitted code still need composition proofs. |
| Binary opcode admission | Both JITs and constant-folding paths use one checked predicate for the exact set of sixteen binary opcodes. A second root checks agreement with interpreter acceptance and rejection at nontrapping operands. Validation-loop and emitter composition remain open. |
| Proof engine | Regression coverage has been extended for arithmetic, memory, source execution, and checked SAT/UNSAT evidence. The checker defaults to 131,072 gates per root and supports up to 524,287 with `--circuit-gates`. The engine and semantic encoding remain in the trusted computing base. |
| Interpreter, host calls, arbitrary execution | Full preservation and confinement theorems remain unproved. |
| JITs and compiler | Sixteen checked roots cover the shared production x86-64 binary emitter's exact output bytes in uncached mode and the corresponding buffer and state effects. JIT dispatcher premises, the separate division guard, instruction semantics, executed-artifact binding, and full preservation remain open. |
| x86-64 arithmetic and bitwise instruction models | The checked models read the actual emitted bytes at symbolic code addresses and match interpreter addition, subtraction, AND, OR, XOR, and both shifts from symbolic stack addresses. The proofs require disjoint spans and cover normal register and cursor effects. Code publication and the caller's establishment of these premises remain open. |
| x86-64 comparison instruction model | All six comparison sequences match the production interpreter for symbolic disjoint spans and arbitrary word operands. The checked flag lemma supplies signed and equality conditions, and the decoded final move zero-extends the result. Code publication and the caller's establishment of the premises remain open. |
| x86-64 multiplication instruction model | The checked model links the production pop and `IMUL` bytes to interpreter multiplication and the modeled truncation flags. The wide-product formula has independent native regression evidence. Code publication and the caller's establishment of the premises remain open. |
| x86-64 division and remainder instruction model | All sixteen uncached binary opcodes now have checked normal-path models. Division and remainder check the actual emitted `CQO` and `IDIV` setup and output under nontrapping operand premises. The modeled guard decision is checked for arbitrary operands. Emission and relocation of its branches, error exits, and executable publication remain open. |

The focused frame-preservation bundle passed 39 theorem roots. Under validated
call bounds and disjoint owned buffers, it checks the five newly saved fields
and preserves an arbitrary eight-byte word in any earlier 40-byte frame record
across the production frame-save and local-copy blocks. The full transition
from function metadata through capacity checks and composition with the local
contents theorem remains open. The bootstrap run produced three byte-identical compiler stages
and passed 960 interpreter/JIT checks across two stages.

The full VM proof gate passed 512 checks on the function-header snapshot. That
snapshot also passed 960 native VM/JIT checks and 918 WebAssembly checks. The
receipt and logs are in `build/vm-verification-20261118/function-header/`.

Earlier full-suite results are historical checkpoints, not verification of every
subsequent edit. Rebuild and rerun the relevant gates for the final worktree.
Root counts measure theorem roots, not percentage coverage of the VM.

The confirmed call-frame defect was in the production VM. Verifier soundness is
a separate obligation because a checker that accepts an invalid proof gives
false assurance about the sandbox. Track the proof engine and its semantic
encoding in the trusted computing base until those obligations are discharged.

## 1. Define semantics, authority, and the trusted foundation

- Specify word widths, wraparound, signed operations, division traps, shifts,
  evaluation order, memory observations, function calls, and host-visible effects.
- Specify valid source, bytecode, machine-code artifacts, initial states,
  capability configurations, errors, termination, and suspension behavior.
- Define guest/host separation, metadata ownership, allowed I/O, and resource
  accounting. State exactly what confinement guarantees about each host effect.
- Distinguish trusted execution, which deliberately grants native authority, from
  restricted execution. Keep compiler-correctness obligations for both modes.
- Enumerate the verifier, semantic encoding, evidence checkers, bootstrap/compiler
  binaries, external implementations/toolchains, ISA/ABI, OS mappings/syscalls,
  scheduling, and hardware assumptions. Shrink this foundation through checked
  results; do not describe `--no-trusted` as removing all trust assumptions.
- Preserve the full language and target scope. Begin composition on restricted
  Linux x86-64 bytecode/JIT, then discharge each remaining path below. Work order
  does not exclude other paths from the final objective.

Deliverable: reviewed theorem statements, explicit assumptions, and a coverage
ledger that distinguishes proved, conditional, unresolved, unsupported, and unproved.

## 2. Finish initialization, mappings, and resource invariants

- Prove buffer mappings are live, correctly sized, nonwrapping, and separated:
  guest heap, operand stack, frames, locals, globals, code, compiler tables, host
  descriptors, and JIT state.
- Prove reserved guest prefixes, alignment, limits, initial cursors, error flags,
  argument/string setup, and capability configuration.
- Cover partial initialization, allocation failures, cleanup, invocation reset,
  nested VM setup, and native allocation/unmap accounting.
- Compose allocator contracts with initialization and every allocation caller.
  Keep the discharged mixed bump/native budget theorem in the passing allocation
  bundle and establish its entry premises at every real caller.

Deliverable: an initial-state theorem and preserved ownership/accounting predicates
used by later steps, rather than repeatedly assumed without a checked origin.

## 3. Complete stacks and call-frame preservation

- Integrate the call-underflow proof, native reproduction, and mutation controls
  into `scripts/test-proof-vm.flex` and the existing CI gate.
- Check malformed floors, negative arity, missing arguments, exact stack/local
  fits, and rejection without changing frames, locals, or cursors.
- Prove the complete production `vm_enter`: table/header accesses, frame saves,
  argument copying, zero initialization, loop bounds and termination, saved PC,
  local layout, depth, operand cursor, and successful state transition.
- Establish and preserve the full saved-frame prefix and ordered floor chain.
  Compose call entry, operand operations, and return with shared invariants.
- Apply the checked available-argument/saved-cursor bridge in
  `vm/proofs/call-capacity.flex` to the full call-entry transition. Passing
  capacity checks do not by themselves prove frame saves or the copy loop.

Deliverable: checked call/pop/return preservation from the complete state invariant,
including failure paths, with no unexplained saved-field premises.

## 4. Prove every interpreter instruction and execution driver

- Enumerate every production opcode and dispatcher path in `vm_continue`,
  `vm_binary`, and `vm_builtin`; give each a precise step relation.
- Prove fetch/decode bounds, PC alignment and control flow, stack effects,
  local/global indexing, guest loads/stores, arithmetic, calls, and returns.
- Cover malformed opcodes/metadata, arithmetic traps, error propagation, exits,
  suspension/resumption, fuel, deadlines, and cleanup.
- Prove each step preserves the state/ownership invariant or traps safely.
- Compose initialization and step preservation by induction for arbitrary-length
  executions. Separate partial correctness, termination/fuel, and wall-clock
  claims with their actual OS/scheduling assumptions.

Deliverable: arbitrary interpreter execution preserves confinement and implements
the declared bytecode semantics.

## 5. Prove capability-mediated host effects

- Model and verify descriptor translation, host buffer ranges, guest path handling,
  filesystem roots, read/write permissions, polling/waits, clocks, and output limits.
- Prove denied network, process, write, FFI, and other capabilities cannot be
  recovered through another handler or nested invocation.
- Prove host-call failures, invocation-local exit, blocking behavior, and resource
  accounting preserve the same boundary.
- Give every external operation explicit semantics or a clearly conditional
  contract with an identified implementation assumption.

Deliverable: each observable host effect is authorized by the original host-selected
capability set, composed with the interpreter theorem.

## 6. Verify actual JIT code

- Define the machine-instruction and ABI semantics used by each supported JIT,
  beginning with x86-64 and separately covering ARM64.
- Prove bytecode eligibility and translation, or build a checked validator for the
  actual emitted code. Bind the result to the exact bytes executed.
- Cover registers, native stack, scratch/context buffers, branches/relocations,
  guest/global memory accesses, arithmetic/traps, and ABI/host transitions.
- Prove metering, deadlines, suspension, and observable behavior agree with the
  selected bytecode semantics, including fallback and code-cache behavior.
- Prove code publication changes writable mappings to executable mappings safely,
  executed code remains immutable, and cleanup/failure paths preserve ownership.

Deliverable: JIT execution refines bytecode execution and preserves confinement for
every supported JIT path, not just sampled interpreter/JIT agreement.

## 7. Verify compiler preservation through every representation

- Specify and prove lexing, parsing, name/arity resolution, imports, module loading,
  source validation, and failure behavior on malformed/adversarial inputs.
- Cover Flexscript, SetaScript, FIR, compile-time transforms, custom frontends,
  platform modules, registered lowerings, and extension execution. Add the missing
  post-expansion/lowering proof binding rather than excluding these features.
- Prove source-to-IR and IR-to-IR preservation, including folding, CSE, branches,
  reachability, liveness, relocation, memory/host effects, and traps.
- Prove bytecode construction preserves semantics and well-formedness for the
  exact immutable code and metadata consumed by the VM/JIT.
- Cover supported native and remaining backends: x86-64, Linux/Android ARM64,
  WASM, CPU C++, shader/GPU paths including PTX/SASS/HIP/RDNA, bare-metal,
  ESP32/RISC-V, and the supported linking/object-generation paths.
- State external-toolchain assumptions or validate their actual output. Add the
  execution models needed for threads, interrupts, and GPU concurrency.

Deliverable: preservation across every included compiler path to its executed
representation, including compile-time effects before restricted guest execution.

## 8. Strengthen proof-engine assurance and repeatable evidence

- Keep source proofs attached to shared production functions; avoid proving a
  copied model while a different implementation executes.
- Extend semantics, effect tracking, memory/alias reasoning, loop invariants,
  quantified reasoning, and target models where required by the full objective.
- Accept SAT/UNSAT results only through checked evidence; require concrete source
  replay before reporting a counterexample as an executable source defect.
- Validate encoding changes with independent native references, exhaustive small
  domains, boundary cases, and corrupted-evidence tests. These support assurance
  but do not replace a proof of verifier/encoding correctness.
- Retain reproducible counterexamples. Seed mutations in temporary copies of the
  actual implementation and require checked, replayed counterexamples; a timeout
  or unresolved result does not count as successful bug detection.
- Record source/artifact hashes, theorem/dependency coverage, tool/bootstrap
  provenance, assumptions, and results for each final verification run.
- Run appropriate proof, compiler, interpreter/JIT, and end-to-end regression gates.
  Check self-hosted compiler stages for reproducibility. Integrate new proof gates
  into CI and preserve incomplete claims visibly outside passing gates.

Deliverable: reproducible evidence tied to the current implementation, with the
remaining verifier/bootstrap trust clearly identified and reduced where possible.

## 9. Compose and audit the final result

- Compose source semantics, compiler preservation, artifact binding, VM/JIT
  execution, initialization, host effects, and resource/failure behavior.
- For every language feature, backend, opcode, host handler, theorem premise,
  external contract, and execution path, inspect current authoritative evidence.
- Resolve every ledger row or obtain explicit review of any remaining assumption
  or exclusion; do not silently treat an unsupported construct as completed.
- Independently review the composed theorem and its trusted foundation. Confirm
  exact-artifact execution evidence and all required regression/CI gates.
- Mark the goal complete only when this audit proves the full objective has been
  achieved. Until then, report concrete progress and the remaining gaps honestly.

## Verification checkpoints

The VM gate checks the selected production layout scan, ordered header and body
copies, and function-record relocation in one theorem. The focused run passed
76 theorem roots and 38 checks. The published-seed bootstrap produced three
identical compiler binaries and passed 960 native VM/JIT checks. The source
manifest and logs are under
`build/vm-verification-20261119/ir-layout-composed-ordered-relocation/`.

A separate selected-path proof checks that the scan's returned size matches the
layout sentinel and stays aligned and within the original capacity through the
ordered copies and production size assignment. It preserves all six selected
instruction words and shows the compacted instruction offset fits the published
size. The VM gate checks this theorem alongside selected function-record
relocation. Its focused run passed 77 theorem roots and 44 checks. This
publication projection omits the table relocation loops. The handoff proof
still needs to carry the size and copied code across those loops into VM entry.
The proof and receipt are under
`build/vm-verification-20261119/ir-layout-size-publication-gate/`.

The forward copy used by call-record relocation now has a checked pointwise
result for any byte in a 32-byte record. It covers identical source and destination
and disjoint spans with the destination below the source. The annotated and
production binaries match and passed 144 native cases. Omitting the last byte
produced a replayed counterexample and failed the native fixture. The receipt is under
`build/vm-verification-20261119/ir-call-record-copy/`.

A checked production call-record relocation iteration composes that copy with
the actual live-bit reader and PC rewrite. A live record receives the mapped
PC plus eight and advances the retained count. For any observed byte the proof
checks the relocated PC encoding or preserved metadata. A dead record leaves
the selected destination byte and retained count unchanged. Both paths preserve
the published-size scalar. The VM gate checks the iteration and its dependencies. The focused run
passed 20 theorem roots and 21 checks, and the byte-identical native test
variants passed 240 cases. A wrong PC rewrite was replayed and
failed the native fixture. The receipt is under
`build/vm-verification-20261119/ir-call-record-relocation-gate/`.

The optimizer now checks each old call PC against the instruction extent before
reading the liveness flags or layout map. The VM gate proves that the guarded
loop terminates for 0–65,536 records with a readable layout and writable call
table. Each iteration derives the write grants for the selected eight-byte PC
field and 32-byte destination record from the full call-table grant. The
selected-step theorem also preserves any readable eight-byte word disjoint
from both of those writes. A separate checked composition uses
the production publication assignments after success and preserves an
arbitrary readable word disjoint from the call table. On a rejected offset,
the call-record helper reports failure and the optimizer aborts before size
publication. The VM gate now checks that an arbitrary selected call record reaches its
iteration with its original PC. This applies whenever execution reaches that
iteration. Establishing the published header, record, and VM entry premises
in one theorem remains open. The focused,
native, bootstrap, and source proof receipts are under
`build/vm-verification-20261119/ir-guarded-call-relocation/`. The stronger
iteration and frame proofs, path-sensitive store regression, and rebuilt
compiler are recorded in
`build/vm-verification-20261119/ir-precise-call-record-frames/`. The unread-PC
loop proof and its replayed overwrite control are in
`build/vm-verification-20261119/ir-unread-call-record-pcs/`. Three companion
proofs check the name pointer, name length, and arity at the same point in the
production loop. Each checked projection compiles to the same native bytes
as its production counterpart and passes 642 fixture cases. Their evidence
is in `build/vm-verification-20261119/ir-unread-all-call-record-fields/`.

Two checked projections of the production call-record loop cover the steps
before a selected input record and the steps after a selected output slot has
been filled. The prefix preserves the input PC and bounds the retained count
by the selected input index. The suffix preserves the already-compacted PC and
proves the retained count cannot decrease on success. The checker passed 29
prefix roots and 30 suffix roots with `--no-trusted`. The projections matched
their corresponding native artifacts byte for byte and passed 642 prefix and
5,122 suffix fixture cases. The sources and logs are in
`build/vm-verification-20261119/ir-call-relocation-windows/`.

The selected live-call profile composes the prefix, the production
retained-record copy, and the suffix. Under the recorded grants, separation,
and selected-PC liveness premises, a successful run leaves each byte of the
relocated PC at the destination selected by the prefix count. The profile uses
an arbitrary byte observer and returns the selected slot. The VM proof gate
checks all 52 roots with `--no-trusted` and compares native artifacts with
the production bodies projected at the same boundaries. Its 27,600 native
cases compare the entire resulting table against the unsplit production loop,
including failure on an invalid PC before or after the selected call. The
focused gate passed 58 checks. A separate mutation that overwrites an
already-compacted PC produced a checked counterexample with concrete replay.
The receipt is in `build/vm-verification-20261119/ir-selected-live-call-relocation/`.
The retained sequence and its handoff through publication remain open.

The selected internal CALL profile connects the production bytecode emitter,
call-record append, and successful resolver patch. Given owned, separate code
and record spans and a selected in-range function with matching arity, the
proof checks CALL opcode 8, the exact function index in its operand, and all
four call-record words. Resolution writes only the eight-byte operand. The
focused VM gate passed 22 checks and all 11 proof roots with `--no-trusted`.
The native profiles compiled to identical bytes and passed 144 cases, and the
checker concretely replayed a wrong-index patch. A restricted nested-call
fixture also passed with both interpreter and JIT, with optimization enabled
and disabled. The lookup that selects the function and the full resolution loop
remain open. Evidence is in
`build/vm-verification-20261119/internal-call-link/`.

The compiler-to-fetch proof now carries that selected CALL through the
interpreter's production bounds check, operand reads, and callee metadata
validation. Given an existing, separate callee header and function record,
the fetch reads the exact resolved index and its matching PC, arity, and local
slot count. The fetch advances the return PC by 16 bytes, charges one fuel
unit, increments the step count, and preserves the error state. The focused
VM gate passed 45 checks, including all 16 roots with `--no-trusted`. The
native projections matched over 864 cases, and
a change that reads the opcode as the CALL operand produced a replayed
counterexample. Evidence is in
`build/vm-verification-20261119/internal-call-fetch/`. Composition through the
whole optimizer, call capacity, frame installation, and JIT dispatch remains
open.

The post-layout CALL proof checks the production live-bit test, map lookup,
and instruction copy. Under the stated writable and separate spans and an
already-relocated callee header and record, the proof carries the exact CALL
opcode and resolved index through size publication into the interpreter fetch.
An ordered profile also copies the callee header and rebinds its function
record when the callee precedes the CALL. It preserves the callee arity and
checks the fetched PC and slot count. All 29 roots passed with `--no-trusted`.
Identical native projections compared selected words with the full production
copy loop across 6,138 cases. A wrong-index write produced a replayed
counterexample. A restricted fixture with earlier and later callees passed
under the interpreter and JIT with optimization enabled and disabled.
See `build/vm-verification-20261119/compacted-call-fetch/` for the evidence.
The focused gate checks both CALL and callee orders together. When the
CALL comes first, the later header copy preserves the CALL and the callee
record. The proof then rebinds the callee PC and fetches the selected CALL
after publication. All 33 gate checks passed, including all 31 roots with
`--no-trusted`. The native projections for both orders matched over 8,184
cases, and the gate replayed a wrong-index write. Evidence is in
`build/vm-verification-20261119/compacted-call-both-orders/`. Deriving the
selected map and liveness premises from the full optimizer remains open.

The production layout scan now has a two-live-slot proof. For any two ordered
live input slots under the map and flag ownership premises, both final map
offsets are nonnegative, 16-byte aligned, distinct, and bounded by the
published compacted size. The earlier slot keeps the smaller offset, and both
live bits survive the scan. The focused gate passed 22 checks, including all
26 roots with `--no-trusted`. Native fixtures matched byte for byte across
18,943 cases and checked the whole map.
The checker replayed a mutation that sets the later offset to the final size.
Evidence is in `build/vm-verification-20261119/ir-layout-live-pair/`.

The proof engine now derives write permission and separation for a symbolic
prefix of an owned span. The rule applies to the optimizer's allocated
capacity and smaller published code extent. The checker discharged the
prefix lemma with `--no-trusted` and replayed one-byte extensions past the
allocation and into an adjacent span. The rebuilt compiler passed the existing
52-check layout and CALL gate. Results are in
`build/vm-verification-20261119/symbolic-output-prefix/`.

The standalone scan-to-CALL bundle passed all 59 roots with `--no-trusted`.
Given two selected live slots and the stated backing allocations, it derives
both map offsets and both output write bounds from the production scan. It
then checks the CALL and callee copies in input order, callee PC relocation,
size publication, and interpreter fetch and metering. The verifier uses
whole-span containment to check effects covered by one region of a
multi-region frame. The expanded focused gate passed all 52 checks,
including both proof and native controls. The worktree compiler rebuilt
byte-identically to the tested verifier. The evidence is in
`build/vm-verification-20261119/scan-call-composed/`. Deriving liveness from
the full optimizer and connecting this result to frame installation remain
open.

The native scan-to-CALL fixture exercises both input orders across 4,092 cases.
The exact annotated wrappers and production projections compile to
byte-identical binaries. Each case initializes every map word to -1 before
the scan and checks the complete map, the selected CALL and callee record,
and the interpreter's fetch and metering. The fixture rejects a wrong CALL
index and a missing size sentinel. The native receipt is in
`build/vm-verification-20261119/scan-call-both-orders-native/`.

Both post-layout relocation proofs expose the exact CALL words, callee
header words, and function-record PC and arity after fetch. The strengthened
standalone bundle passed all 31 roots with `--no-trusted`.
The selected interpreter CALL proof passes all nine roots through frame
installation and local initialization. It checks the fuel and step charge,
the exact cursors, the five saved frame fields, and the declared write
regions, assuming an accepting callee and the selected buffer grants. The
native fixture passed 480 cases, including argument copying and preservation
of an older frame, and rejects a shifted saved return PC. The transition
still needs to derive those premises from optimizer publication and the VM
state invariant. Evidence is in
`build/vm-verification-20261119/selected-call-dispatch/`.

The production successor scan returns the first live instruction or the
end of the range. Its two proof roots check arbitrary observed slots in a
nonempty aligned window with readable flags. The applied gate passed 16
checks, including a replayed mutation that skips a live slot and 14,846
native cases. The selected queue step and its dependencies passed all eight
roots and 28 combined gate checks. Given a live witness and the stated
flag and worklist grants, the step excludes the failure exit and preserves
the witness's live bit. An already marked successor leaves the queue word
and cursor unchanged. A new entry holds an aligned in-range PC with both
live and visited bits set. The native queue fixture passed 29,692 cases,
and the checker replayed a wrong-bit mutation. The complete reachability
loop remains open. Evidence is in
`build/vm-verification-20261119/ir-live-successor/` and
`build/vm-verification-20261119/ir-live-enqueue/`.

The production reachability cleanup has a checked pointwise proof for any
flag before the end of the owned range. It preserves flags before the
active interval and preserves marked flags. Within the active interval it
clears only the live bit of unmarked flags. The combined focused gate
passed 43 checks and all 10 roots, including a replay of an inverted mark
check. The native projections were byte-identical and matched over 61,440
cases. The remaining proof must derive the marks from the complete
worklist and carry them through cleanup. Evidence is in
`build/vm-verification-20261119/ir-live-sweep/`.

A standalone nine-root proof shows that a later queue insertion preserves
the full byte of any earlier marked flag in the readable prefix. The native
fixture compares both projections over 29,692 cases and rejects a mutation
that clears an earlier mark. The worklist induction still needs this
preservation result and a proof that all reachable successors enter the
queue. Evidence is in
`build/vm-verification-20261119/ir-enqueue-preserve-marked/`.

The integrated insertion proof now observes an arbitrary readable flag.
It preserves all bits except the visit mark and preserves the entire byte
when the visit mark was already set. The updated focused gate passed 47
checks, including 220,180 cases per positive queue artifact and a replayed
mutation that flips an earlier live bit. Evidence is in
`build/vm-verification-20261119/ir-enqueue-preserve-flags/`.
An additional standalone proof checks that a newly appended PC differs
from any observed PC whose visit mark was already set. Applying this
pointwise fact to every occupied row remains part of the worklist
induction.

A standalone composition checks selected queue insertion followed by the
production cleanup loop. All 13 roots passed with `--no-trusted`. An
already visited successor leaves the queue cursor unchanged. A new queue
entry still points to a live, marked instruction after cleanup. The two
native projections were byte-identical and matched over 29,692 cases.
Evidence is in `build/vm-verification-20261119/ir-enqueue-sweep/`.

The conditional worklist step passed 17 roots with `--no-trusted`. Given
valid live witnesses for both successors and two reserved queue words, the
actual branch and fallthrough path keeps the consumed queue word, advances
the read cursor by one, and appends zero, one, or two entries within the
reserved span. The checker replayed a skipped-fallthrough mutation, and
the matched native projections passed 138,816 cases. The combined focused
gate passed 67 checks and all 22 roots in both the isolated snapshot and
the applied worktree. Evidence is in
`build/vm-verification-20261119/ir-worklist-two-successors/`.

Standalone checks cover the production single-successor and return steps.
The single-successor step requires a live witness and one available queue
word. The return step advances the read cursor without writing to the queue,
including at full capacity. A separate proof shows that an append preserves
an arbitrary earlier marked row and adds a different PC if it adds an entry.
Both profiles passed 12 roots with `--no-trusted`. The corresponding native
projections matched over 104,134 and 23,522 cases per artifact. The expanded
gate passed 82 checks and all 30 roots in both the isolated snapshot and
the applied worktree, including a replay of a return incorrectly given a
fallthrough successor. Evidence is in
`build/vm-verification-20261119/ir-worklist-routes/`.

A standalone composition derives both live witnesses for the conditional
step from an aligned live return at the end of the region, with the branch
target in range. It passed all 22 roots with `--no-trusted`. The native
projections were byte-identical and matched in 90,048 cases per artifact.
The two reserved queue words remain a premise. The remaining worklist proof
must establish witnesses for all accepted inputs, lift pointwise distinctness
to the entire queue, derive capacity, and prove traversal through cleanup.

Two standalone profiles each passed eight roots with `--no-trusted` for
worklist initialization. The production flag initialization loop terminates,
stays within its writable span, and sets any selected flag in range to one.
Given a live, unvisited entry, insertion marks the entry and writes its PC to
the first queue row. The reachability initializer starts with read position
zero and one occupied row and preserves both function-header words. The
native projections were byte-identical over 512 initialization layouts and
13,440 queue-seeding cases per artifact. Proving that boundary marking, folding,
CSE, and branch threading preserve the required entry properties remains open.
Evidence is in `build/vm-verification-20261119/ir-worklist-routes/`.

The expanded worklist gate integrates these initialization and witness proofs.
It passed 101 checks and all 44 positive proof roots in both the isolated
snapshot and the applied worktree. Separate checked proofs show that boundary
marking preserves live and visited bits and that an already visited, live
first successor uses no queue storage, including when the queue is full.

The optimizer scratch growth loop and successful allocation passed with
`--no-trusted`. The reuse path preserves the existing arena grant. The proof
checker established the full set of 17 admitted power-of-two capacities and
the actual address assignments at each one. The resulting code, flag, map,
and queue spans are writable and pairwise disjoint. A three-root lemma
derives a disjoint writable two-word append span from the backing spans
when two physical slots are available. The whole traversal must still show
that each new entry has room and that it terminates for arbitrary admitted
graphs. Evidence is in
`build/vm-verification-20261119/ir-worklist-admission/`.

The scratch allocation, reuse, and 17 layout profiles are now in the VM gate.
The focused scratch run passed 17 checks and all 21 roots, including a concrete
replay for layout that overlaps the queue and map. A separate composition
derives the consumed queue read, two append writes, and their separation
from the backing spans. It passed all 30 standalone roots and matched the
byte-identical native projections over 90,048 cases per artifact. The combined
focused gate passed 123 checks on both the isolated snapshot and the applied
worktree.

Another standalone profile passed 24 roots and shows that both conditional
appends preserve an arbitrary earlier marked queue row and its exact flag
byte when the two successors share a valid live witness. The native projections
matched over 138,816 cases per artifact. Evidence is in
`build/vm-verification-20261119/ir-worklist-owned/`.

The full VM gate passed 918 checks on the earlier compaction snapshot.
Both the compiler and gate binaries rebuilt byte-identically from that
snapshot. Its result is recorded in
`build/vm-verification-20261119/compacted-call-fetch/`. The separate full
run on the sweep snapshot stopped when its argument-copy proof hit the default
circuit limit. The exact failed fixture then passed all 14 roots at the larger
capacity. The VM gate now uses that capacity for the affected profile, and the
remainder of the suite passed 48 checks in a focused rerun. The full suite has
started on a pinned snapshot of the updated worktree.

The call-entry effects checkpoint passed 411 VM proof-gate checks and all 17
local proof suites. The published-seed bootstrap produced three byte-identical
compiler stages and passed 960 interpreter/JIT checks. A mutation that passes
the wrong PC to `vm_enter_accepted` produced a checked counterexample with
concrete replay. The local receipt and logs are under
`build/vm-verification-20261118/call-entry-accepted/`.

With `--defer-memory-aliases`, the checker verifies eight roots for the complete
saved-frame profile, nine for zero-filled locals, and seventeen for copied
arguments. These profiles use the selected-span premises. The gate also checks
seventeen roots for preservation of the old frame prefix and nine for extending
the ordered operand floor. The combined backing-buffer and immediate-return
profile checks thirty roots with `--circuit-words=131072`. Deriving the
remaining premises from the VM state invariant and preserving it through
intervening guest execution remain open.

The shared startup profiles each check twelve roots, including their allocation
and descriptor dependencies. The startup proof establishes buffer extents and
descriptor isolation before interpreter and JIT setup diverge. The gate replays
a changed stdin guard from the loop-exit state and checks the mutation against
the native descriptor initializer.

Progress recorded 2026-11-13/14: proof gate 183 checks, interpreter/JIT
regression 480 checks, two-stage self-host fixed point, full three-stage
bootstrap against the published 0.0.1 seed, commits 7a453c1 and cf793a6
pushed to master.

Progress recorded 2026-11-18: reproduced the failing shared-minuend subtraction
identity, then fixed it by reusing a matching earlier expression with a bounded
metadata lookup. Broad reassociation and adder reordering were rejected after
they made established VM proofs unresolved. All 17 local proof suites passed
with the retained change, including the 183-check VM gate; interpreter/JIT
regressions passed 480 checks, and self-hosted stages were byte-identical.
This resolves the recorded local property-suite failure, not remote CI or the
full proof objective. At that checkpoint the malformed-header profile still
hit the circuit limit. The separate alias-selection experiment stayed outside
the worktree. New work remains uncommitted and unpushed.

Local validation artifacts for this checkpoint are retained in
`build/vm-verification-20261118/receipt.json` and its companion logs and compiler
binaries. They are generated local evidence, not a checked end-to-end theorem.

Later on 2026-11-18, the malformed-header proof passed against production
`vm_enter`. The runtime now checks the opcode before reading arity and slot
counts. The verifier finds an exact branch condition inside a bounded path
conjunction, which avoids constructing the unreachable copy loop. The gate
includes a replayed counterexample for a temporary wrong error code.
All 17 local proof suites passed, with 189 VM proof checks and 480 interpreter/JIT
checks. Two self-hosted stages were byte-identical. The capacity rejection and
successful entry roots still hit the circuit limit while modeling input metadata.
The validation receipt is in `build/vm-verification-20261118/call-entry/`.

The next checkpoint checks 16-byte instruction bounds at call entry and
interpreter fetch. The interpreter keeps its check inline to avoid an extra
call for every instruction. A checked rejection profile requires permission
for the function-table PC field alone. A checked composition now derives
permission for an accepted instruction from the full symbolic-length code
buffer. The remaining entry roots still reach the circuit limit while relating
multiple metadata reads. A separate copy-loop prototype checked bounds, effects
and termination for symbolic counts up to 4,096 after normalizing read/write
permission queries to their content-independent snapshots. It needs production
integration and a value-preservation proof.

The current compiler passed all 17 local proof suites, including 196 checks in
the VM proof gate. Interpreter and JIT regressions passed 480 checks, and the
two self-hosted compiler stages were byte-identical. The receipt and isolated
copy-loop probe are in `build/vm-verification-20261118/instruction-bounds/`.

`vm_enter` now calls the checked production copy loop in `vm/call-locals.flex`.
The verifier reuses permissions across content-only snapshots. Native regression
covers a copied argument, zeroing dirty unused locals, and a preserved neighboring
word. The bootstrap bridge can erase the new proof blocks and lemma definitions
for the published seed; the self-hosted stages compile the annotated runtime.
The full entry theorem still has to establish the helper's premises and prove
its exact effects on values and the caller frame.

All 17 proof suites passed locally, including 204 VM proof checks and a replayed
empty-span write in the mutated copy helper. The published-seed bootstrap and
clean-room build passed with three byte-identical compiler stages, including
960 interpreter/JIT checks across two stages. Compiling the annotated copy
fixture and the bootstrap-erased fixture produced identical executables.
The receipt is in `build/vm-verification-20261118/call-locals/`.

The production interpreter arithmetic and constant-folding helpers now have
18 checked source roots. The normal cases cover all 16 binary operation
codes for arbitrary operands, with division and remainder trap premises.
Separate cases check the shared folding guard declines trapping operations,
the interpreter reports their error, and unsupported opcode words reject.
The checks bind to the handlers used by VM dispatch, the IR optimizer and the
native literal folder. The surrounding dispatch, rewrites and emitted machine
code still need independent proofs.

The exact copy-value probe remains open. Moving alias congruence to checked
countermodel refinement got past circuit construction in an isolated build,
but the resulting memory obligations still exhausted search. An alternative
compact encoding still exhausted circuit capacity. Neither experiment is in
the production verifier.

All 17 local proof suites passed, including 215 VM proof checks. The full
seed bootstrap produced three byte-identical stages and passed 960 VM/JIT
checks across two stages. The shared IR suite passed 8,775 differential and
oracle checks. The receipt is in `build/vm-verification-20261118/word-operations/`.

An exploratory source root checked the four bytes written by the production
x86 binary emitter for the uncached addition case, under explicit buffer
ownership and emitter state premises. The entire imported proof bundle remains
7/8 because the relocated copy root runs out of circuit capacity there. The
probe and log are retained with the receipt. JIT dispatcher composition,
instruction semantics and the executed-code binding remain open.

The shared production x86-64 emitter now has a standalone passing bundle of
16 roots with `--no-trusted`. Each checks exact bytes, cursor advance, and
effects for uncached emission under buffer and limit premises. The existing
CI proof gate checks this bundle and replays a counterexample for a changed
addition byte. A separate runtime regression exercised each operation on 12
word pairs, with 192 confirmed JIT calls. Interpreter, JIT, and independent
oracle results agreed, and fuel consumption matched across the VM tiers.
The published-seed bootstrap passed with three byte-identical compiler stages
and 960 interpreter/JIT checks. Logs and source hashes are recorded under
`build/vm-verification-20261118/x86-emission/`.

Both JITs now use the checked binary-opcode predicate instead of maintaining
separate admission rules. The x86-64 check previously reused parser
precedence, which also accepted the short-circuit tokens. The proof checks
the exact sixteen-member set against every 64-bit opcode word, and a second
root checks agreement with the interpreter at nontrapping operands. Both
constant-folding paths now decline unsupported opcodes, with checked rejection
for arbitrary operands. Runtime-generated ARM64 code passed 4,842 cases under
QEMU, including 4,830 native calls in the emulated process. The validation
receipt is in `build/vm-verification-20261118/word-operator-admission/`.

The x86-64 addition model now composes with the production emitter and
interpreter for symbolic code and stack addresses. The verifier expands small
fixed disjoint spans into byte inequalities. A load can skip a store when
its current path contains the corresponding nonalias fact. A regression
checks that reading the same symbolic cell on an overlapping path still
observes the write. The model is included in the existing VM proof gate.
The validation receipt is in `build/vm-verification-20261118/x86-addition-model/`.

The x86-64 byte-to-instruction refinement now also covers subtraction and all
three bitwise operations. The bitwise models check carry and overflow clearing
and accept either value for the undefined auxiliary flag. The subtraction proof
covers the full seven-byte sequence, including the move back to the accumulator.
The left and arithmetic right shift proofs cover the register exchange, six-bit
count mask, and preservation of all flags when the effective count is zero.
The VM proof gate also checks that treating OR as XOR produces a replayed
counterexample. The receipt is in `build/vm-verification-20261118/x86-word-model/`.

The x86-64 comparisons now compose with the actual emitter and interpreter.
The proof reads the live stack word after emission and checks it matches the
pre-emission word before reusing it on both sides. The CMP status lemma relates
the modeled flags to each interpreter comparison. The checked sequence includes
the byte write by SETcc and its zero extension, bringing the instruction model
coverage to thirteen of the sixteen binary opcodes. The two-operand multiplication
proof brings the count to fourteen. The receipt is in
`build/vm-verification-20261118/x86-compare-model/`.

Nontrapping x86-64 division and remainder now compose with the production
emitter and interpreter. The verifier walks deeper bounded conjunctions to
recover the separation facts needed to preserve a stack word across the longer
sequences. The memory suite exercises a 128-level path and an overlapping
path. The division proof gate also checks the guard predicate and replays the
mutation that leaves the quotient in RAX for a remainder operation. The
receipt is in `build/vm-verification-20261118/x86-division-model/`.

Six live restricted-JIT samples captured the relocated quotient and remainder
guards in their RX mappings. Hardware breakpoints confirmed the published bytes
were unchanged at the sampled execution points. Normal inputs reached `IDIV`
setup and both trap inputs reached the exit that records error 2. The sample
captures accompany the receipt.

The selected x86-64 error-record proof verifies that the production relocation
body chooses the division handler, writes four little-endian displacement
bytes through native `patch32`, and preserves the branch opcode and both
record words. Decoding the forward displacement lands exactly at the supplied
handler offset. All six roots passed with `--no-trusted`, and the checker
replayed a mutation that selects the bounds handler. The equivalent native
projections passed 104,728 cases per artifact. The focused gate passed all
17 checks on the worktree. Guard emission, establishment
of the record premises across the relocation loop, the handler's effects,
and executable publication remain open. Evidence is in
`build/vm-verification-20261119/x86-jit-division-relocation/`.

The expanded x86-64 guard gate passed 64 checks and all 18 positive roots
on the worktree. The native branch and record proofs check the opcode, the
four-byte displacement placeholder, and the kind-2 record. The immediate
writer checks the signed-minimum constant. Under the fixed opcode and target
premises, the byte-reading model selects the division handler exactly for zero
divisors and signed overflow over arbitrary operand words. The checker replayed
a zero divisor incorrectly sent to normal setup. The native projections were
byte-identical across 64 emitted layouts and 20,480 operand cases per artifact.

A separate 14-root proof checks the complete 20-byte middle sequence emitted
before relocation. That sequence compares with the signed minimum and returns
the local skip branch's displacement offset. Its native projections matched across 64
placements. Connecting all three emitter phases, both relocated records, the
normal and trap effects, and the published executable bytes remains open.
Evidence is in `build/vm-verification-20261119/x86-jit-division-guard/`.

The x86-64 publication gate passed 17 checks and all 11 positive roots. The
production sizing decision admits exact fits, rounds the size to a whole
page, and stays within the per-function and shared cache limits. Given
disjoint writable destination and readable staging spans, the production
copy loop terminates and preserves the exact staged value at every byte in
the output. The gate replays a rejected exact fit and a skipped final byte.

A standalone cache decision model checks the production update under supplied
allocation and protection outcomes. It permits a cache entry only after
successful outcomes and sufficient budget. Failure preserves the prior
entry and counters. The checker replayed a fault that permits publication
after a protection failure. Binding the checked copy and decision to the
actual OS mapping, protection and release, then to instruction fetch,
remains open. Evidence is in
`build/vm-verification-20261119/x86-jit-publication/`.

Twelve runs of the production x86-64 JIT traced quotient and remainder with
ordinary operands, signed overflow, and division by zero. In all six allowed
runs, the staged image matched the initially writable copy and the bytes at
the first native instruction and the selected normal or error destination
after the mapping became read-execute. In all six forced protection failures,
the runtime unmapped the buffer and the interpreter produced the same exit
status as the interpreter-only reference. The trace confirmed unmapping in
all twelve runs. Reproduction commands, raw traces and byte captures are in
`build/vm-verification-20261119/x86-jit-publication/os-boundary/receipt.json`.

The expanded publication gate passed 23 checks and all 13 positive roots.
Given an admitted positive mapping, disjoint spans and a supplied protection
outcome, the composition proves that any selected byte after the cache
decision equals the original staging byte. A positive result points to the
mapping recorded in the cache. The decision preserves the cache on rejection
and restores the bytecode state. The gate projects the production copy loop
and cache decision with supplied OS outcomes, compares the native artifacts,
and replays a mutation that publishes after failed protection. The checked
byte observation on rejection applies while the mapping still exists.

The end-to-end JIT proof still needs to connect the production caller to the
mapping, lifetime and instruction-fetch assumptions. Cleanup discards the
return from `munmap`, so release and ownership if unmapping fails remain open.

The x86-64 entry guard now stops when the clock read sets a VM error. The
previous guard used the returned time alone. The clock returned zero on failure
and the native result could overwrite the pending deadline error.

Two checked roots cover the clock-result handling and the pre-call context
setup. With clock status and the timespec supplied, the guard rejects an
absent entry pointer, a clock failure, a pending VM error, or a reached
deadline and preserves the five context words. On acceptance it prepares the
exact locals pointer, fuel, zero error and backedge counters, and deadline.
The combined publication and entry gate passed 42 checks. It replayed the
missing clock-error check and caught the exact-deadline mutation in the native
projection. The rebuilt compiler passed 480 runtime regression checks and
matched the next self-hosted stage byte for byte. The 12 publication traces
also passed on this build. Evidence is in
`build/vm-verification-20261119/x86-jit-entry-deadline/receipt.json`.

Cache selection, clock syscall effects, and native execution and writeback
still need to compose with the pre-call proof. The first cached-entry
composition exhausted the solver budget on cache preservation.

The cached lookup and context writer now have separate checked proofs. Given
an existing positive pointer and valid cache storage, the lookup returns the
exact cached pointer and increments the call count. A disabled record
returns zero and keeps its call count. Both paths preserve the pointer,
extent, and disabled marker. The five context stores preserve all four words
of a disjoint cache record. The verifier now follows enough disjoint writes
to cover the full 40-byte context. Its regression also checks that it still
observes an earlier overlapping store.

The production trace observed 26 native entries in six runs, including 20
uses of an existing mapping. Each entry used the same RX image as the first
publication and supplied the expected arguments and context. Six denied
publications exercised interpreter fallback. All twelve runs matched the
interpreter's exit status, VM steps, and remaining fuel. Evidence is in
`build/vm-verification-20261119/x86-jit-cached-entry/receipt.json`.

The verifier now retains the incoming path when a short-circuit expression
rejoins. Disjointness facts from before the expression remain usable after
callee contracts refine the path. The source suite checks effects on both
the evaluated and bypassed branches and replays a false claim that the
bypassed call updated state.

The composed cached-entry proof now discharges the cache-preservation
obligations. Given an existing positive entry, the required buffer grants,
and modeled clock results, it follows production selection, the deadline
stage, and context setup. It checks the exact pointer and context on
successful entry, the preserved context on rejection, the three preserved
cache fields, and the exact call count on both paths. It proves that an
enabled, error-free entry with a successful clock read before the deadline
reaches the prepared context. A checked assertion on that path establishes
the deadline comparison before the context writes. All six roots passed.

The publication, deadline, and cache gates passed 61 checks. The annotated
and production-derived split projections compiled to identical native
artifacts. Each of those artifacts and the unsplit production projection
passed 120 cases. The rebuilt compiler passed 480 runtime checks. Evidence
is in `build/vm-verification-20261119/x86-jit-cache-composition/receipt.json`.
The executable mapping lifetime, cold compilation, and composition across
the native invocation remain open.

The x86-64 writeback proof supplies the pre-call fuel, the native result
word, and the returned context. It checks exact accumulator, error, fuel
and step updates without counter wrap under the declared bounds. Successful
calls use production frame restoration and honor the completion sentinel.
Traps leave the current frame in place, including cases with no frame read
grant. The proof checks the saved frame contents at writeback entry. Native
execution still needs to establish the fuel range and preserve those
contents across the call.

Hardware traces of 26 native returns observed the expected result and
error words, five consumed fuel units on normal paths, and four on division
traps. All sampled returns reached the saved caller address with the stack
and preserved registers restored. The leaf mapping was RX. The current
x86-64 compiler executable has a writable and executable ELF load segment.
Separation of that host segment from guest memory remains a proof obligation.

The writeback profile passed all four roots. The focused JIT gate passed
80 checks and the rebuilt VM passed 480 runtime checks. The checker replayed
charging unused fuel and restoring a frame after a trap. Evidence is in
`build/vm-verification-20261119/x86-jit-native-writeback/receipt.json`.

The x86-64 fuel meter model decodes the saved context slot and the branch
displacement, reads the current fuel, and checks the next instruction.
Under the stated byte and memory premises, zero takes the decoded branch and
keeps fuel at zero. Positive fuel decreases by one and falls through. The
selected kind-1 relocation proof checks that the production writer encodes
the exact fuel-handler destination.

The native projection checks all 4,097 supported context-slot positions and
16,388 model executions. Separately, 12 hardware traces checked the emitted
bytes and the budget boundary for quotient and remainder. Ten runs took
the error-1 path with zero through four units at native entry. Two completed
the leaf with five units. The interpreter agreed on total steps, remaining
fuel, and final guest exit in every case. The complete fuel-handler effects
and preservation of the meter's premises across a native function remain
open.

The standalone meter and fuel relocation passed seven roots. The combined
guard and meter gate passed 103 checks. A checked control replayed an
attempt to decrement zero fuel. An isolated model of the fuel handler also
checks the error word, zero result, and saved frame and return address. Its
production binding and composition with the meter remain open. Evidence is
in `build/vm-verification-20261119/x86-jit-meter/receipt.json`.

The selected fuel exhaustion path now composes the meter, handler, and
production VM writeback. Given the published bytes, zero fuel at the
selected meter, and the declared memory and counter bounds, the proof
checks error 1, a zero result, restoration of the native frame pointer
and stack pointer, and the exact saved native continuation. The VM
records the trap and accounts for the saved fuel while preserving all
guest frame and cursor fields. The source proof of the path starts at
the selected meter. It still needs the full native function, publication,
and FFI proofs to establish its premises.

The native fixture emits the meter and handler with the production
sequences and runs the modeled exhaustion path across all 4,097 supported
context-slot offsets. Ten hardware traces also read the saved context,
frame pointer, and continuation at the fuel handler and confirmed the
corresponding hardware return. Both interpreter and JIT had the same
guest exit status and fuel accounting in all twelve traced runs.

All seven roots passed. The fuel-path gate passed 50 checks and the
combined guard, meter, and exhaustion gate passed 122. The checker replayed
using the saved frame pointer as the return address. The two native
projections compiled to identical bytes and each passed 8,194 modeled
paths. Evidence is in
`build/vm-verification-20261119/x86-jit-fuel-path/receipt.json`.

The selected x86-64 fuel path now takes its four branch-displacement bytes
from the production kind-1 relocation writer. The checked composition starts
with an error record identifying the selected meter, a forward handler
location, the opcode and handler bytes, and disjoint buffer, frame, and
context grants. It checks the write through `patch32` and uses those bytes
to reach the fuel handler at zero remaining fuel. The native return model
and VM writeback establish error 1, the saved native continuation, exact
fuel accounting, and preservation of guest frames and cursors.

The relocation contract refers to the entry offset when it states that the
record is preserved. The checker can then carry the exact written bytes
into the meter's requirements. All 14 proof roots passed with no unchecked
contracts. Both byte-identical native fixture builds passed 8,194 paths
each, and the combined x86-64 guard, meter, relocation, and exhaustion
gate passed 125 checks. The complete relocation loop, executable
publication, and the compiled leaf's obligation to establish the opcode,
handler, frame, and context premises remain open. Evidence is in
`build/vm-verification-20261119/x86-jit-fuel-relocation-path/receipt.json`.

The production x86-64 error relocation loop now validates its count, patch
intervals, and forward targets before publication. It rejects overlapping
and out-of-order patches. A rejected relocation restores the bytecode
pointer, size, and VM mode and discards the staged native bytes.

The checker proves memory safety and termination for the whole error
relocation loop under the native-mode and buffer premises, including the
real four-byte writer. All nine roots in the generated profile passed
without unchecked contracts. The gate replays a change that accepts a
negative count. The byte-identical native fixtures cover a full table of
32,768 mixed records plus malformed cases and detect removal of the overlap
check. The combined relocation, meter, and execution-model gate passed
140 checks, and the rebuilt VM passed all 480 runtime checks. A test build that
injects an invalid count at the production call site produced no JIT
compilations or calls and matched the interpreter's fuel, step count, and
exit status.

The proof that a selected displacement retains its exact bytes through the
whole loop, the composition with ordinary branch relocation, and executable
publication remain open. Evidence is in
`build/vm-verification-20261119/x86-jit-error-relocation-loop/receipt.json`.

One later native `patch32` now has a checked preservation proof. Given the
granted four-byte spans and ordered offsets, the later write preserves all
four bytes of the earlier displacement. It also preserves both words of an
observed error record disjoint from the write. The production relocation
and preservation profile passed all 14 roots without unchecked contracts.

The checker now retains a path fact at a disjunction when it finds the same
fact on both arms within the search budget. This lets the symbolic memory
reader preserve a disjoint record after a branch rejoins. The word,
memory, region, loop, and modular suites passed. A control that incorrectly
used a fact from one arm failed the regression.

A separate checker prototype also retains the entry path at branch joins
and represents conditional memory separation when reading a snapshot. It
passed the full-loop observation proof independently for each of the four
displacement bytes. Each annotation profile produced the same native
fixture bytes as the unannotated production projection, and the fixture
passed with 32,768 records. Those two checker changes and the full-loop
profiles still need integration and validation in the production proof
gate. Evidence is in
`build/vm-verification-20261119/x86-jit-error-observer/receipt.json`.

The branch and snapshot changes from the prototype are now in the checker.
One production-derived proof observes all four displacement bytes together
through the complete error relocation loop. Given the native-mode and
backing-buffer premises and a disjoint watched kind-1 record, a successful
loop writes the exact displacement to the supplied fuel handler and
preserves it through all later rows.

All 19 roots passed without unchecked contracts. The wrong-target control
replayed against the production-derived loop. The annotated and raw native
projections compiled to identical bytes and each passed the 32,768-record
fixture. The focused gate passed 46 checks, the combined JIT gate passed
154, and the rebuilt VM passed all 480 runtime checks. The region suite
also checks a conditional snapshot read on both separated and overlapping
inputs and replays the bad overlap claim. Evidence is in
`build/vm-verification-20261119/x86-jit-fuel-loop/receipt.json`.

A separate checked publication projection carries an arbitrary byte of the
selected displacement into the modeled mapped image and cache entry. It
requires zero ordinary branch relocation records and supplied mapping and
protection outcomes. Every exit restores the original bytecode pointer,
size, and VM mode. This projection checks the successful path inside its
branch to keep the staging buffer identity explicit. It passed all 34
roots and a native fixture with 12 successful observations and one
rejected relocation. General ordinary branch relocation, operating-system
effects, and integration of this projection into the production gate
remain open.

The production x86-64 ordinary branch relocation loop now validates its
record count, ordered displacement intervals, initialized map indices,
and mapped targets. Rejection restores the interpreter's bytecode state
and discards the staged image. An integration control injected an invalid
ordinary record count and observed zero JIT compilations and calls, with
the interpreter's exact step count, fuel, and exit status.

The checked loop establishes safety and termination under the backing
buffer and native-mode premises. Given an arbitrary selected row and its
mapped target, the full-loop observer checks all four staged bytes on
success. The composed decoder sign-extends the displacement and recovers
the map target for forward and backward branches. The gate replays
admission of the first uninitialized map index and a shifted target. Both
native projections match the production projection and pass 8,192 mixed
branch records. The combined JIT gate passed 183 checks, and the rebuilt
VM passed 480 runtime checks.

A separate checked publication projection starts at a nonempty ordinary
branch table and carries an arbitrary selected byte into the modeled
image and cache entry. Its mapping and protection outcomes are supplied.
It passed 41 roots and the native fixture covered twelve observations and
one rejection. Cross-table preservation of an earlier fuel displacement,
establishment of the emission premises, and actual executable publication
remain open. Evidence is in
`build/vm-verification-20261119/x86-jit-branches/receipt.json`.

In one restricted runtime trace, the actual compiling leaf emitted two
ordinary branches and 24 error branches with disjoint displacement
intervals. The forward and backward ordinary displacements decoded to
their map entries, and the error branches decoded to the expected
handlers. The staging buffer, copied page, and executable page had
identical bytes. The trace observed native entry and both ordinary branch
destinations on the RX page and observed successful unmapping. The
interpreter and JIT agreed on steps, remaining fuel, and exit status.

The production x86-64 JIT now scans the combined displacement intervals
before either relocation table writes to staging. The checked scan terminates,
reads within the granted tables, and writes no memory. For any chosen ordinary
record and any chosen error record, success establishes that both offsets
are valid and the two four-byte intervals are disjoint. The general bounds
profile passed all 8 roots and the cross-table profile passed all 12 roots
without unchecked contracts.

The focused gate passed 34 checks and the combined JIT gate passed 217.
The gates replayed controls that accept overlapping intervals or an invalid
offset. The annotated and raw native
fixtures compiled to identical bytes and each exercised both full tables, empty
tables, boundary offsets, and malformed records. A separate runtime fixture
injected an overlap just before the production guard. The JIT recorded no compilations or native
calls and matched the interpreter's exit status, steps, and fuel. The rebuilt VM
passed 480 runtime checks. The normal restricted JIT trace still reached both
ordinary branch destinations on the RX page and matched the staging bytes.

The single-write composition is now in the proof gate. On success, any one
selected ordinary branch write preserves all four bytes at the selected error
site. The gate checks the production scan, record load, and native writer
with the target supplied as a premise.

A candidate loop merges the interval scan into ordinary relocation after
the error patches. Its bounds profile passed 13 roots, the selected-byte
preservation profile passed 28, and a composition through the copy and cache
steps passed 43. The last proof starts with an arbitrary byte of an already
staged error displacement and assumes the stated buffer grants, address
equality, and mapping and protection outcomes.

The candidate's annotated and raw relocation fixtures compiled to identical
native bytes. The candidate compiler ran in a temporary build and passed all
480 VM runtime checks. One restricted trace matched the existing JIT's
executable image byte for byte, reached the same two ordinary branch targets
on the RX page, and observed successful unmapping. An overlap fixture
fell back to the interpreter with its exact step count and remaining fuel.
At fuel limits of 1,000 and 50,000, the candidate JIT, existing JIT, and
interpreter agreed on steps, remaining fuel, and exhaustion exit status.
The full candidate composition passed 58 roots without unchecked contracts.
Given a chosen fuel record, the production error-patch loop establishes its
relative displacement. The candidate ordinary pass preserves a selected byte
of that displacement and the modeled publication places it in the mapped
image and records the mapping in the cache. The proof assumes the stated
table and buffer grants, selected address equalities, and mapping and
protection outcomes. The native fixture for this composition passed and
matched the earlier checked fixture byte for byte.

The merged pass now runs in the production x86-64 JIT, directly after the
error pass. The 58-root composition's relocation bodies match the current
production bodies after erasing annotations and adopting the production
names. Its copy and cache projections match the production publication code
under the documented substitutions for OS outcomes. The rebuilt production
VM passed 480 runtime checks. A restricted normal run reached both traced
ordinary branch destinations. At fuel budget 1,000, a traced native run
reached the decoded fuel handler with zero fuel on the RX page and exited
with status 70. The staged and executed bytes matched in both traces, and
both runs unmapped the executable page.

The production-source profiles passed 39 roots for ordinary displacements
and signed target reconstruction, 19 for cross-table intervals, 13 for
relocation bounds, and 58 for the fuel-to-publication composition. Replays
caught acceptance of an invalid site, acceptance of an overlap, acceptance
of an uninitialized map index, and a changed branch target. The annotated
and raw relocation fixtures produced identical native binaries.

The emission follow-up checked the production leaf admission condition and
one selected map write in four roots. An accepted leaf has between one and
8,192 sixteen-byte slots. Given a valid selected slot and writable map word,
the write records the emitter's current offset and the instruction cursor
advances by 16 bytes. A separate five-root profile connects the production
branch target guard to the emitted map index. Given an aligned function
start and an admitted leaf extent, the index is in the body-slot range and
converts back to the original bytecode destination. The remaining
composition must establish the complete map's initialization and the table
and staging grants from emission and allocation, then account for actual
executable mapping effects. Evidence is in
`build/vm-verification-20261121/x86-jit-relocation/receipt.json`.

The production emitter now iterates by map slot. The same slot count
bounds initialization and the later relocation read. The 11-root
map-prefix proof uses the actual slot initialization, instruction cursor,
map store and increment. It assumes an immutable trace of emission
offsets and proves that the complete body-slot range is initialized to
those offsets. The 20-root composition adds the production branch target
guard and shows that a successful lookup returns the selected initialized
entry. A control that skips the first body slot reproduced an invariant
failure. Native model fixtures covered an empty body and the full 8,191
body slots, including the untouched header and tail, and the annotated
and raw projections compiled to identical binaries.
The focused allocation, map, and lookup gate passed 30 checks.

The initial scratch allocation proof establishes fresh writable regions
for the staging buffer, map, branch table and error table. All six pairs
are disjoint under the verifier's allocation model. The gate replays an
aliased-map control. A separate projection checks separation from the
compiler's allocated bytecode buffer when the two allocation stages run
in sequence. It still needs the intervening compiler and VM steps to carry
the live allocation forward to JIT entry. Allocation failure cleanup and
allocation reuse also need composition proofs.

The rebuilt VM passed 480 runtime checks. On the normal and fuel-exhaustion
traces, both executable images matched the corresponding earlier images
byte for byte. The fuel path reached the expected RX handler at zero fuel.
The older merged-relocation checkpoint finished with 218 combined checks.
The current evidence is in
`build/vm-verification-20261121/x86-jit-map/receipt.json`.

The x86-64 relocation counters now have a checked projection for the
complete leaf body. Each instruction contributes one fuel record, and
the checked dispatch accounts for additional indexed-memory, division,
and backedge deadline records. For up to 8,191 body instructions the
projection bounds the totals at 24,573 error records and 8,191 ordinary
branch records. The checked grants fit the 16-byte rows in the allocated
tables. The projection assumes the erased emitter operations preserve
the counters and the readable bytecode extent. The gate checks the
production slices and replays an error-counter double advance.

The source-derived x86-64 metered local emission proof checks the
production map write and emitter calls for local loads and stores. The
sequence records the incoming code cursor, advances it by 30 bytes,
and appends one error record. Under the stated buffer separation and
capacity premises it preserves the newly written offset and any
selected earlier map entry. The staging write frame has a replayed
out-of-span control. Carry these effects through the remaining opcode
emitters, derive their code headroom, and compose with the full map
loop and relocation before treating the production map trace as proved.

The focused scratch, map, relocation-count, and metered local emission gate
passed 96 checks. Native fixtures for a local load and store preserved the
map entries and produced byte-identical binaries with and without the
proof annotations. The preceding combined relocation and map gate passed
240 checks, and the VM runtime suite passed 480. Evidence is in
`build/vm-verification-20261121/x86-jit-emitter/receipt.json`.

The map preservation gate also checks the production immediate, push,
negate, logical-not, and complement emission arms. It proves their exact
unmetered byte counts, the bounded metered cursor advance, and the
preservation of a just-written or earlier selected map entry. The proof
uses the writable staging and error grants and the map separation
premises. The focused gate with these arms passed 109 checks.

Eleven boundary values ran under both the restricted interpreter and
the x86-64 JIT, including either side of each 32-bit encoding boundary
and both signed 64-bit extremes. The runs matched all eight output
bytes, VM step counts and fuel usage, and the JIT reported native calls.
The immediate-model composition checks all three native MOV encodings
for arbitrary words. It reads the exact emitted staging bytes, recovers
the source word in RAX, and preserves stack and flags. Replacing signed
extension with zero extension replayed a counterexample. A debugger
captured one instance of each encoding from the read-execute mapping.
The general connection through relocation and publication remains open.

The corresponding emission-frame proof now covers direct and indexed
memory loads and stores under the restricted-heap and writable-buffer
premises. It calls the production direct address translator and proves
the code sizes and relocation record counts together with preservation
of the current or earlier selected map entry. A restricted Seta fixture
confirmed that its leaf contained all four opcodes, ran natively 48
times, and matched the interpreter's result, steps and fuel.

The focused map, memory and immediate-encoding gate passed 141 checks.
The emission profiles require a staging capacity of 64 MiB. FIR6 loading
can set the shared compiler output limit to 256 MiB, so JIT entry still
needs a checked link between the temporary emitter limit and its actual
64 MiB allocation. General code headroom and the remaining opcode
templates are also open. Evidence is in
`build/vm-verification-20261121/x86-jit-emitter/map-memory-mov-receipt.json`.

The x86-64 JIT now saves the frontend output limit, uses the 64 MiB
staging limit while emitting, and restores the saved limit before
relocation. The checked projection composes successful scratch
allocation, staging setup and the actual entry prologue. It proves
that staging is fresh and disjoint from the map and relocation tables.
The loop terminates and emits exactly 21 plus 14 bytes per local slot,
at most 57,365 bytes for 4,096 slots. The byte-store guard rejects the
full cursor before a store. The focused gate passed 46 checks,
including replayed controls for retaining the inherited limit and
failing to restore it.

A rebuilt, reproducible compiler passed all 480 VM regressions. A
large FIR6 artifact returned 42 in both restricted execution modes
with identical step and fuel counts. A watchpoint observed the
256 MiB frontend limit change to 64 MiB at JIT staging and return
to 256 MiB before publication. The JIT compiled one leaf and executed
it natively 48 times. This closes the staging-limit premise for the
checked emission path. Native stack effects, the full body cursor
bound, and whole-image confinement remain open.

The combined staging, publication, relocation-count, and map checks
passed 198 checks on the rebuilt compiler. A separate full VM proof
run reached the optimizer scratch suite and left its reuse-grant
postcondition unresolved. The reuse proof now checks that entry
capacity excludes the growth path, then carries the original writable
grant to return. Its 21 roots and 17 focused checks passed. The latest
full proof suite is running. Staging, FIR6, and scratch evidence is in
`build/vm-verification-20261121/x86-jit-staging/receipt.json`.

The source-derived backedge clock emitter checks a 107-byte staging
advance, two error records, and a four-byte internal skip patch
starting 22 bytes from the beginning of the sequence. Its write
frames stay inside staging and the error table. Carry these effects
into the ordinary branch path and then the full emission loop. The
focused emitter gate passed 66 checks with the clock proof included.

The ordinary branch projection now checks the complete emitter step
with metering. The record contains the displacement offset and the
bytecode target slot. A forward branch emits five or nine body bytes
according to its opcode, and a backedge prepends the 107-byte clock
check and adds two error rows. The checked map store initializes the
current slot and preserves any selected earlier slot through this
step. The division guard also has a checked 39-byte extent, two error
rows and an in-staging skip patch. The exit proof checks normalization
and the 110-byte trailer, including the exact five handler offsets
under the native register replay premise.

A restricted Seta branch fixture exercised all three branch opcodes
and matched the interpreter on exit result, steps and fuel. A native
trace saw 48 deadline clock calls from the executable mapping. The
live staged and executable bytes matched. All five ordinary branch
records decoded to their recorded map targets, and the 40 error rows
landed at the corresponding handler offsets. This is artifact evidence
for that execution. The general proof must still link every emitted
iteration to the full relocation and publication passes.

The focused branch and exit gate passed 86 checks. A separate
nine-check gate verified that the production branch append writes only
its own 16-byte row and replayed a control that shifts the stored
displacement offset by one byte. Evidence is in
`build/vm-verification-20261121/x86-jit-staging/branch-exit-receipt.json`.

The metered branch composition now also preserves both words of any
selected earlier branch row through the map store and native emission.
The shape of the new row comes from the production stores. The source-derived
shared binary emitter has a checked staging advance of four through seventeen
bytes, including operand acquisition and the selected opcode arm. That size
bound covers both operand modes. Using the uncached instruction semantics
still requires establishing the JIT entry state.

The combined emitter gate checked 52 roots and passed 127 harness checks
including the branch-row controls and a three-root staging arithmetic proof.
The controls replay a shifted displacement and a write to an earlier row.
The arithmetic proof checks the body cursor invariant given a 23- to
139-byte advance per iteration. Starting from a prologue of at most 57,365
bytes, its conservative bound for 8,191 slots is 2,154,261 bytes, leaving
room for the 110-byte trailer. The production dispatch and loop must still
establish and preserve the premises, including admitted operands, table
grants and the checked emitter modes. Evidence is in
`build/vm-verification-20261121/x86-jit-staging/emitters-and-headroom-receipt.json`.

The checked body dispatch now supplies the 23- to 139-byte step bound
under the admitted opcode, mode and region premises. It also bounds the
appends to one through three error rows and zero or one ordinary branch
row. The metered step and all dependencies passed the 50-root focused
profile. The combined gate binds the source arm sequence and passed
59 roots and 128 harness checks, including the selected map and branch-row
observers, mutation controls and staging arithmetic.
The full loop still needs bytecode read and admission proofs at each
slot and must carry earlier relocation records and map values to the
end of emission.

The full VM proof run stopped at the optimizer worklist flag-read grant.
The updated lemma starts with equality of the stored and chosen PC and
derives the read grant for the aliased flag byte. The full 50-root
worklist profile and all 106 focused checks passed with the change,
including the native equivalence and mutation controls. The updated full
VM suite is running.

The x86-64 leaf admission gate passed eight roots and 16 harness checks.
The checked interval guard bounds an accepted function by 8,192 complete
slots within the original bytecode buffer, including the 256 MiB frontend
limit. With a readable header, the header guard accepts opcode 18 and
an exact local count from zero through 4,096. The selected opcode guard
supplies the restricted emitter's input conditions. The gate replays
removal of the direct heap lower bound.
The selected reads are checked given a readable function span. Connecting
that grant to the function record and carrying successful admission for
every slot into the emission loop remain open.

The metered slot now composes with the cursor and relocation-count
invariants and establishes the next prefix state. The focused 56-root
profile passed. The checked conditional-jump append records the precise
displacement location and error kind and preserves both words of a
selected earlier row under its readable and disjoint span premises.
The error-row profile passed nine roots, including positive evidence
for the append's write frame, and its gate replays an extra store to
the preceding row. The production loop still needs selected-row grants
and a checked induction over all map and relocation records.

The combined prefix and admission gate passed 153 checks, including the
65-root emitter and prefix profile and the error-row mutation. The
header-inclusive admission gate passed separately. The prototype
admission-loop proof follows the production scan and tracks an arbitrary
selected instruction. Address normalization for the bytecode reads and
preservation of the selected admission predicate at loop boundaries
remain unresolved.

The production admission-scan proof now discharges those address and
loop obligations. For any selected body slot, successful completion of
the scan establishes the full operand and opcode predicate for the words
read at that slot. The 19-root profile follows the production loads,
guards and cursor update. Its gate passed 23 checks and replayed a scan
that skips a body slot. The result relies on a readable function span
and the stated interval, header and restricted-heap premises.

The verifier now recognizes a shifted subrange even when both lengths
are symbolic. Shared address expressions select candidate regions. The
existing containment implication still checks both actual addresses,
the lengths, the permission modes and a common permission snapshot.
The 64-bit shifted-range obligation was unresolved with the previous
checker and passed with the rebuilt one. The rebuilt compiler passed
26,366 memory-model checks, 187 region checks and all 480 VM runtime
checks. The two compiler stages built from the updated sources matched
byte for byte.

The function-table projection derives the exact accepted function extent
from the current record and the following record or the bytecode end.
The owned bytecode grant supplies readability of the header and the
entire accepted function. The projection checks the header type and
local count. The combined metadata and scan gate passed 34 checks,
including replay of the wrong next-record choice and the skipped scan slot.

The checked single-slot handoff retains the production order of map
store, metering and operand reads. Under the stated grants, its reads
see the admitted opcode and operand and emission preserves both words.
The selected map entry captures the incoming staging cursor and the
cursor and relocation counts satisfy the next prefix bounds. The
remaining loop proof must derive the separated grants from scratch
ownership and preserve admission, map values and relocation records
across all iterations.

The staging and prologue projection now preserves the enclosing bytecode
read grant and both words of an arbitrary selected instruction under
the separated staging premise. Its 15-root profile passed. The combined
metadata and prefix gate passed 172 checks on the rebuilt compiler.
Evidence is in
`build/vm-verification-20261121/x86-jit-staging/admission-handoff-receipt.json`.

The handoff wrapper now derives the selected instruction and map-word
permissions and the required separation from the backing regions. The
66-root profile passed under those backing grants. A separate checked
projection establishes that the four successful fresh scratch allocations
are disjoint from the already-live bytecode extent and preserve its read
grant. The 75-root emitter profile passed in the 129-check handoff gate,
and the combined fresh scratch and prologue gate passed 56 checks. The
compiler entry must still carry ownership through scratch reuse and
connect the admission scan, staging and emission loop.

The earlier full proof run terminated while checking the VM frame
profiles. The aggregate run on the rebuilt shifted-range checker was
terminated with status 143 and produced no final report.

The scratch admission proof supplies the same writable, pairwise
disjoint staging and table regions on successful fresh allocation and
on reuse of live scratch. The production cache-return tail keeps those
grants and restores the incoming bytecode view. The gate passed 69
checks, including concrete replay of a return that clears the map
pointer. A two-leaf program returned 42 in both execution modes. The
JIT compiled and ran both leaves in one process, and both modes used
30 VM steps and ended with 9,999,970 fuel. Mapping and cleanup
lifetimes still need to connect these boundaries.

The x86-64 body-emission loop now has a checked write frame for leaves
of 1 through 8,192 slots including the header, with mode and backing
regions supplied at entry. The proof checks that the production slot
count equals the induction bound and uses the production PC calculation
and increment. It bounds staging at 2,154,261 bytes and the error and
branch tables at 24,573 and 8,191 rows. The emission gate passed 130
checks with 82 verified roots. The scratch-to-prologue proofs establish
the region grants and the two zero counters for this induction after
successful fresh allocation or reuse. The staging and publication gate
passed 94 checks with 18 verified roots in its prologue profile.

With 1,022 arithmetic updates in a leaf, the JIT ran
it natively and both execution modes returned 44 after 8,188 VM steps.
With 1,023 updates, the JIT fell back to interpretation and both modes
returned 3 after 8,196 steps. Both comparisons also matched remaining
fuel.

The first attempt to carry a selected map entry through every later
iteration left solver obligations unresolved. The branch and error
record handoff to relocation, the all-slot admission handoff, and
composed native execution remain open.

The focused reports and runtime receipts are in
`build/vm-verification-20261121/x86-jit-staging/admission-handoff-receipt.json`.

One complete emission step now has a checked preservation proof for a
readable word separated from staging, the error table, the current
branch row and the current map word. The emission gate passed 130 checks
with 83 verified roots. A reduced loop checks that a
frame beginning immediately after an observed map slot preserves its
word. The counterexample control writes to the preceding slot and
replays a write-frame violation in the 23-check map-prefix gate.

A restricted leaf with 1,025 iterations and an internal conditional
returned 6 in both modes. The JIT compiled the leaf and ran it once.
Both executions used 25,130 VM steps and retained 9,974,870 fuel.
The receipt is in
`build/vm-verification-20261121/x86-jit-staging/relocation-inputs-receipt.json`.

The source-bound map trace passed 131 checks with 95 verified roots.
It partitions the ascending slot traversal before and after an arbitrary
selected slot. The selected step stores its incoming cursor, and the
suffix's map writes start at the next slot. The checked result leaves that
exact cursor in the selected map word, between the prologue start of the
body and the final body cursor. The proof binds the PC and increment
to the production loop and uses the existing checked dispatch.
The remaining relocation work is to carry branch and error row values
and ordering through all emissions and into the checked patch passes.

The per-slot proof now follows the loaded instruction through the full
metered emitter. A branch advances the cursor by one row, records the
four-byte displacement at the end of its emitted jump, and stores the
exact target index `(arg-start)/16` from the bytecode operand. The
combined emission and branch-row gate passed 147 checks, with 96 roots
in the emission profile. A changed target index replays a row
postcondition violation.

A restricted leaf with nested conditionals and a loop returned 63 in
both modes. Both used 31,224 steps and retained 9,968,776 fuel. The JIT
compiled the leaf once and called it twice. The evidence is in
`build/vm-verification-20261121/x86-jit-staging/branch-relocation-receipt.json`.

Two successive checker builds agree byte for byte. The checker now
considers a containment check when two addresses use different symbolic
offsets from the same base. It still verifies the interval bounds. The
memory and source-region suites passed 26,367 and 187 checks. With that
checker, the source-derived branch-range loop verifies a branch-table
write frame starting at its entry cursor. It carries that lower cursor
bound across every iteration. The combined emission and branch-row gate
passed 147 checks with 99 roots in the emission profile. The VM runtime
suite passed 480 checks with its loopback fixture enabled.

The ordinary patch proof now checks all four displacement bytes together.
For aligned bytecode within the 256 MiB extent, the production branch
guard and target-index calculation relate the operand to its exact slot.
The relocation handoff carries the selected row and map entry through
the error pass and then the ordinary pass. On success, the signed
displacement in the staged bytes reaches the selected map offset.
The combined gate passed 57 checks, with 51 verified handoff roots
and 22 roots in the map and index profile. The wrong-destination mutation
replayed and the annotated ordinary patch projection produced the same
native test artifact as its production source. This handoff still needs
the branch record and its target's map observation from the same emission
traversal. The evidence is in
`build/vm-verification-20261121/x86-jit-staging/branch-patching-receipt.json`.

The selected branch emission proof now follows the original operand
through the production prefix, selected instruction, and suffix. The
final branch row holds the exact target index and a displacement site
within the emitted body. The combined emission and branch-row gate
passed 147 checks with 112 roots in the emission profile. The suffix
now declares writes only to the map entries at or after its first
slot. The focused closure with this frame checked 82 roots.

For a branch to its own slot, the slot step supplies both the map cursor
and the branch row. The suffix preserves that cursor and both row words.
The focused self-target profile passed all 88 roots with no trusted
external contracts. The production-source gate with the final bound
`site <= output_size - 4` passed 147 checks across 115 proof roots.
The report is in
`build/vm-verification-20261121/x86-jit-staging/jit-branch-own-map-bounded-source-gate-report.json`.
The self-target proof now includes the emitted exit trailer, restoration
of the bytecode limit, and both production relocation passes. On success,
the signed displacement in staging lands at the exact native entry
observed during body emission. The production-source gate passed 171
checks across 174 roots with no trusted external contracts. The report
is in `build/vm-verification-20261121/x86-jit-staging/jit-self-emission-relocation-source-gate-report.json`.

Runtime checks used the production restricted interpreter and JIT for
opcodes 10, 11, and 12 with targets before, at, and after the branch.
All nine taken-branch pairs and six fallthrough pairs matched fuel,
step counts and outcomes. Each published native displacement matched
its four staged bytes and decoded to the recorded target. Evidence is in
`build/vm-verification-20261121/x86-jit-staging/jit-branch-target-order-runtime.log`
and `build/vm-verification-20261121/x86-jit-staging/jit-branch-fallthrough-runtime.log`.
The later-target staging case passed a focused 99-root check with no
trusted external contracts. The version sharing the prefix with the
self-target case also passed 99 roots. The production gate now checks
the shared prefix, later target slot and suffix alongside the
self-target relocation theorem. It passed 171 checks across 182 proof
roots with no trusted external contracts, including a rerun with
the freshness change. The report is in
`build/vm-verification-20261121/x86-jit-staging/jit-later-target-fresh-source-gate-report.json`.
The earlier-target case and relocation through arbitrary targets remain
open.

The publication gate now checks all four displacement bytes through
one production copy traversal and the modeled cache update. A positive
publication result retains the complete staged word in the mapped
image and restores the bytecode view. Given the signed staged
displacement for a target, the corresponding mapped displacement
decodes to that target in the mapped image. The gate passed 37 checks,
including the 26-root displacement publication profile. The report is
in `build/vm-verification-20261121/x86-jit-staging/jit-branch-delta-publication-source-gate-report.json`.
Carrying the relocation theorem into this publication result and
proving kernel mapping lifetimes and execution remain open.

The checker now transfers freshness to a contained span when both
predicates compare the same current and entry snapshots. A symbolic
fresh prefix that exhausted the old checker verifies with the new
rule. The negative control replays a callee trying to use freshness
from the caller's entry snapshot. The allocation model proves an
admitted image extent, its displacement span and its separation from
the live cache record. It composes the modeled allocation with the
production copy and cache update. That gate passed 38 checks across
31 roots with no trusted external contracts. The report is in
`build/vm-verification-20261121/x86-jit-staging/jit-fresh-publication-source-gate-report.json`.
Kernel mapping and protection remain open. Memory, region, lifetime
and allocation regressions passed, and the 30 runtime branch cases
matched with the rebuilt compiler.

The ordinary branch instruction model checks the TEST flags, signed
near displacement, target and fallthrough decisions, and preservation
of RAX and RSP. The interpreter projection checks the production
branch cases after fetch. The source gate passed 16 checks across
10 positive proof roots and replayed a reversed zero-branch decision.
The report is in
`build/vm-verification-20261121/x86-jit-staging/jit-branch-transfer-control-source-gate-report.json`.
The model takes the instruction bytes as premises until the emitted
opcode bytes are carried through publication to this step.

The composed self-target projection passed 214 roots with no trusted
external contracts. On modeled publication success, the selected
displacement in the cached image decodes to the native entry recorded
for the same bytecode slot. On failure, the projection restores the
bytecode view and its limit. This proof uses the allocator model and a
supplied protection outcome. The replayable projection and log are in
`build/vm-verification-20261121/x86-jit-staging/jit-self-branch-dynamic-publication.flex`
and `build/vm-verification-20261121/x86-jit-staging/jit-self-branch-dynamic-publication.log`.
The production-source gate includes this composition and the
earlier-target staging proof. The combined gate is pending verification.

## Interpreter call-entry state checkpoint (2026-11-23)

The milestone-1 state link now has checked, static proof bundles. Shared
startup on the zero-cursor initial state establishes the writable operand
stack, local memory, and frame buffers and their pairwise separation through
contracted stage wrappers, preserving the zero cursors
(`vm/proofs/entry-initialized.flex`, 10/10 roots). Core initialization
followed by the production installer writes the five saved fields and advances
the cursors (`vm/proofs/entry-install.flex`, 11/11). On that initialized
state the checked span lemmas derive every selected-span premise of the
accepted path from the live allocations, and the accepted stage installs the
first frame record and advances depth, cursors, and PC
(`vm/proofs/entry-state.flex`, 16/16). All roots pass with `--no-trusted` at
524,287 gates. Mutation controls replay concretely: a shifted local-cursor
advance violates a witnessed installer root, and a shrunken operand-stack
allocation fails the initialized-state grant through the allocator's own
contract. The descriptor-initialization loop now carries its invariants and
termination measure in the production source with a checked source contract;
the VM gate's startup profile stays green on top of it. The focused call-entry
gate driver passed every section, including the new bundle checks and both
mutation controls. Still open for this milestone: parser establishment of the
function-record values (the bundles take them as premises), the single-circuit
composition of full startup with the local-copy loop, which exceeds the
engine's maximum circuit, and extending the composed entry to executions with
intervening guest instructions. Committed and pushed to master on
2026-11-23 with renewed explicit user authorization.
