# Full VM, JIT, and compiler verification plan

Status: work in progress. Updated 2026-11-13.

## Goal and completion rule

Establish machine-checked confinement and semantic preservation for the actual
Flexscript restricted VM, its JITs, and the compiler that produces the executed
artifacts, using the in-repository proof engine. Extend that engine as necessary.

The final argument must start with untrusted source and inputs, pass through the
actual compiler representations and emitted artifacts, and cover arbitrary VM/JIT
execution, including errors, traps, suspension, resource exhaustion, and permitted
host effects. Proofs must bind to the exact implementation and artifacts executed.

An isolated helper proof, successful test, sampled execution, unresolved query,
or unchecked function contract does not establish this goal. Keep the goal open
until the complete supported scope has a checked composition and every remaining
assumption or exclusion is explicit and reviewed. Do not silently reduce scope
to the components that already pass.

Work on `master`, without creating branches. Preserve unrelated concurrent work.
Obtain renewed explicit authorization before committing or pushing this proof work.

## Current evidence

The detailed coverage ledger is [docs/vm-verification.md](docs/vm-verification.md).
Every claim there must identify its premises, dependencies, and semantic layer.

| Area | Current state |
| --- | --- |
| Restricted address translation | Source proofs exist for rejection, exact translation, and acceptance under heap/mode/state premises. |
| Bump allocator | Source proofs exist for rounding, allocation behavior, and restricted accounting with zero native usage. Mapping, initialization, and mixed native/bump accounting remain open. |
| Operand stack | Source case proofs exist for push, pop, frame-floor rejection, exact returned values, and buffer/slot permission composition. Whole-execution invariants remain open. |
| Frame return | Source proofs exist for exact restoration, bounded saved metadata, completion behavior, buffer permissions, and supplied nested-floor invariants. Call entry and initialization still must establish those premises. |
| Call capacity | The current production `vm_call_capacity` passed all ten roots in `vm/proofs/call-capacity.flex` on 2026-11-13, with `--no-trusted`. This covers valid-state framed/unframed acceptance and rejection, negative arity, exact-fit witnesses, and the checked available-argument/saved-cursor equivalence lemmas. It does not prove the complete `vm_enter` function or its copy loop. |
| Confirmed VM defect | Original call entry counted caller-owned operands below the active frame floor as arguments. A checked counterexample and native reproduction are retained under `vm/proofs/counterexamples/` and `vm/proofs/regressions/`. The local guard fix rejects this call. This is a frame-boundary violation; no host escape has been demonstrated. |
| Call-entry integration | The gate now verifies the ten-root capacity bundle, six replayed guard-mutation controls with three fixed positive witnesses, the native regression (exit 0), and the native floor-guard mutation (exit 1). The first production-bound entry path (out-of-range index/full-frame-stack rejection) passed in `vm/proofs/call-entry.flex`; the remaining entry paths and the copy loop are retained open in `vm/proofs/pending/call-entry.flex` with their exact blockers. |
| Mixed bump/native budget | The former pending obligation discharged on 2026-11-13: `vm_allocate`'s strengthened checked contract maintains `vm_heap_used + vm_native_used <= vm_heap_limit`, proved as `mixed_allocation_budget` in the passing allocation bundle. |
| Proof engine | Regression coverage has been extended for arithmetic, memory, source execution, and checked SAT/UNSAT evidence; the verification circuit budget was widened to 524,288 gates (capacity only). The engine and semantic encoding are not themselves fully formally verified. |
| Interpreter, host calls, arbitrary execution | Full preservation and confinement theorems remain unproved. |
| JITs and compiler | Full semantics, preservation, and executed-artifact binding remain unproved. |

Earlier full-suite results are historical checkpoints, not verification of every
subsequent edit. Rebuild and rerun the relevant gates for the final worktree.
Root counts measure theorem roots, not percentage coverage of the VM.

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
  Retain and resolve the mixed bump/native budget obligation at
  `vm/proofs/pending/allocation-total-budget.flex`.

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
- Resolve the available-argument versus saved-cursor arithmetic bridge retained at
  `vm/proofs/pending/call-argument-equivalence.flex`. Passing capacity checks do
  not by themselves establish the subsequent saved-cursor invariant.

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

## Immediate next actions

1. Slim the verifier's membership-query encoding: the position-addressed
   permission lemma's query builds 12,637 SAT variables where the natural
   circuit is a few hundred (one distance adder, two comparisons, the region
   grant), and its transitivity through a rest-bound compound term still
   exceeds the 192M search budget. Profiling and reducing
   `pb_member`/region-query construction in `libs/proof/memory.flex`, plus
   the constant-shift/transitivity comparison rules in
   `libs/proof/word.flex`, are the two recorded engine targets. The full
   position-addressed assembly needs no further design work; it is written
   down with measured numbers in `vm/proofs/pending/call-entry.flex`.
2. Prove the complete call-entry state transition from the shared caller
   invariant (bounded aligned cursors, host-owned frame buffer, caller operand
   span, free local tail, compiler-owned metadata), then connect it to
   initialization and the existing stack/return proofs.
3. Run the relevant proof suites, interpreter/JIT regressions, and self-host
   checks on the resulting current worktree. Done 2026-11-13: proof gate 183
   checks, interpreter/JIT regression 480 checks, and a two-stage self-host
   fixed point (identical stage binaries). A globals-only module in the WIP
   (`compiler/program-state.flex`) had broken the shared flattener
   (`scripts/lib/build.flex`); the splitter now treats such modules as pure
   globals, which unblocked the interpreter suite's nested-VM sandbox check.
   A full three-stage bootstrap run remains owed before any commit.
