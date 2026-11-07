# Flexscript proof checker specification

Status: implemented and locally validated for the three-stage sequential scope.
Stage-1 source verification is implemented
for the supported pure, loop-free subset, including acyclic function calls.
Stage-2 mutable globals, effect frames, inductive loops, modular summaries, and
recursive termination measures, ghost variables, proof blocks, and bounded
quantifiers, specification functions, and lemmas are also implemented. Stage-3
trusted external contracts, byte-memory predicates, checked byte/word loads and
stores, byte-region frames, lifetime-release frames, and concrete memory replay
are implemented. Memory
snapshots participate in calls, branch joins, inductive loops, ghost/spec code,
and bounded quantifiers. Explicit trusted release contracts and their transitive
effects participate in modular calls and inductive loops. Direct and inlined
source allocation, fresh-storage frame checks, and allocation replay are also
implemented, including modular/recursive allocation summaries, allocation-aware
loop abstraction, and a `fresh_bytes` predicate for contracts and invariants.
The acceptance audit is complete for this scope; local evidence is recorded below.
See the implementation status
for the exact supported behavior and limits; ordinary compilation does not prove
a program.

## Purpose

Add an optional verification layer to ordinary Flexscript. Programmers can add
contracts to selected functions, infer routine facts and effects, and gradually
verify larger call chains. Existing code remains usable without annotations.

Verification is optional to adopt, but strict about what counts as proved.
The checker proves stated properties under stated requirements and assumptions.
It does not infer the programmer's entire intent or guarantee the absence of
every possible bug.

The verifier, solver, and proof-evidence checker must be written in Flexscript.
Normal verification must not require Z3, another external solver, or a foreign
proof engine. It is a program verifier, not initially a general theorem prover.
External tools may be optional independent test oracles, never a required path
for accepting a proof.

## Opt-in behavior

- A function with `verify`, `requires`, `ensures`, `modifies`, `reads`, `releases`, or `decreases` is a
  verification root. A verifier assertion or proof construct in a function also
  requests checking of that function. `trusted` functions are the explicit
  exception described below.
- An unannotated function remains ordinary Flexscript. If reached from a
  verification root, its body can be analyzed within the supported subset.
- Adding a contract does not automatically verify every caller elsewhere in
  the program. The report must identify the checked roots and their call closure.
- Omitted effect declarations request inference; they do not imply purity.
- Unsupported behavior is reported as unproved, never silently skipped.
- Ordinary compilation may erase verification annotations without invoking a
  solver. It must still validate their syntax, attachment, names, and separation
  from executable code. Compilation success is not verification success.
- Contracts and verifier assertions do not automatically add runtime checks.
  Runtime contract enforcement would be a separate feature.

Verification entry point:

```sh
flexscript verify file.flex [--budget=N] [--no-trusted]
```

This command checks the verification roots in the resolved program and reports
their dependencies. It exits unsuccessfully if any requested obligation is
disproved or unresolved. A run with no roots must report that no verification
was requested. A result that depends on a trusted contract must be visibly
conditional. `--no-trusted` makes CI reject any checked root that uses a trusted
contract, including transitive uses. Unused trusted declarations are permitted;
conditional results are still reported, followed by a policy rejection and an
unsuccessful exit. Options may occur in either order and cannot be repeated.
`--budget=N` selects 1 through 1,000,000,000 work units for each solver query
and each evidence check (default 200,000,000); `k` and `m` suffixes multiply
by 1,024 and 1,048,576. Exhaustion remains unproved, with an unsuccessful exit.

## Contract placement and scope

Contracts appear before the function, where documentation comments commonly go:

```flex
// Increment without signed overflow.
requires x < 0x7fffffffffffffff;
ensures result == old(x) + 1;
ensures result > old(x);
fn increment(x) {
    return x + 1;
}
```

Consecutive contract clauses attach to the next function declaration. Comments
and whitespace may intervene. A contract followed by a global, import, another
unrelated declaration, or end of file is an error. Clauses cannot attach across
file boundaries. Comments use ordinary Flexscript `//` syntax.

Parameter names resolve against the following function, even though its header
appears later. Globals follow ordinary name resolution. Function-body locals
are not visible in a function contract.

Repeated `requires` and `ensures` clauses are conjunctions. Repeated `reads`,
`modifies`, or `releases` clauses combine their permitted locations; `nothing` cannot be mixed
with nonempty locations. Duplicate `verify`, `trusted`, or `terminates` markers are errors.
Function-level `decreases` appears at most once and may contain a tuple.

## Function contract vocabulary

| Form | Meaning |
| --- | --- |
| `verify;` | Request checking without an explicit behavioral contract. |
| `trusted;` | Use this declared contract as an explicit external assumption. |
| `terminates;` | Assume finite normal return for a trusted function. |
| `requires condition;` | A condition callers must establish at entry. |
| `ensures condition;` | A condition the implementation must establish on every normal return. |
| `modifies count, total;` | Restrict writes to the listed external locations. |
| `modifies nothing;` | Prohibit writes to existing external state. |
| `reads count;` | Restrict reads of external state to the listed locations. |
| `reads nothing;` | Prohibit reads of external state. |
| `releases bytes(p, n);` | Bound permission or lifetime revocation to an entry-state byte region. |
| `releases nothing;` | Preserve existing permissions and allocation identities. |
| `result` | The returned word, available only in postconditions. |
| `old(expression)` | Evaluate an expression in the function's entry state. |

Requirements are evaluated in the entry state. Postconditions are evaluated in
the return state. Parameters are mutable in Flexscript: use `old(parameter)`
when a postcondition refers to the argument originally supplied by the caller.
`old` is initially available in postconditions, not as an implicit loop-history
operator. Nested `old` expressions are rejected.

Local variables and parameter assignments do not need `modifies` declarations.
Accesses through pointers are accesses to memory, even if the pointer itself is
a local variable. Calls contribute their transitive read and write effects.

`modifies` restricts writes, not merely differences between entry and exit:
writing a forbidden location and restoring its value still violates the clause.
It does not require that every permitted location actually change.

Omitted `reads` and `modifies` are inferred from the implementation and callees.
Explicit declarations constrain that inference and detect accidental new effects.
For global-word frames, names refer to declared globals, even if a parameter
shadows that name. A frame may repeat a location; repeated clauses form a union.
The initial `reads` policy covers executable reads and specification reads,
including requirements, postconditions, assertions, and `old(global)`. This
makes it a declaration of all external state dependencies, not just executed
machine loads. `modifies` covers executable writes; permission to write does not
require permission to read the old value. Pure assignment of a constant can
therefore use `reads nothing; modifies count;`.

For byte regions, a read means a content access through `load8` or `load64`,
including accesses in contracts, frame-bound expressions, and proof code.
`readable_bytes`, `writable_bytes`, `fresh_bytes`, and `disjoint_bytes` are logical predicates
about permission metadata or address geometry; querying them does not itself
read byte contents or require a `reads bytes(...)` allowance. Thus a function
can require write permission and use `reads nothing` when it only stores data.
Frame bounds are pure entry-state expressions, evaluated after ordered entry
requirements. Every declared nonempty region must have valid nonwrapping address
geometry. Accesses made while evaluating requirements or frame bounds still
count toward the resulting read frame. A multi-byte access may be covered by
the union of adjacent declared regions; one region need not cover it alone.

Root globals are arbitrary entry values constrained only by requirements. Global
initializers are not invariants for every later call, including a verification
root named `main`; verification currently checks function contracts independently
of program startup. Each called function's `old` snapshot is taken after its
arguments have executed, in ordinary left-to-right order. Its return state is
propagated back to the caller on the paths where that call executes.

Effect checks cover the complete analyzed call chain. A write in a helper can
violate its caller's frame, even if the helper is unannotated or restores the
original value. Explicit frame obligations are guarded by the access path.
Inferred summaries are conservative and can include accesses whose paths require
a solver to show they are unreachable under the entry requirements.

Unknown effects cannot be assumed empty. Heap allocation, ownership, and region
framing require the stage-3 model before they can be checked soundly.

Example with mutable state:

```flex
global count = 0;

requires count >= 0 && count < 100;
modifies count;
ensures count == old(count) + 1;
ensures result == count;
fn increment_count() {
    count = count + 1;
    return count;
}
```

## Exact word semantics and safety

Executable expressions follow the semantics in [flexscript.md](flexscript.md):
64-bit words, wrapping addition/subtraction/multiplication, signed ordering,
masked shift counts, arithmetic right shift, and the specified division and
remainder traps. Contract expressions initially use the same word semantics.
Arithmetic must not silently become unbounded mathematical integer arithmetic.

Logical conditions interpret zero as false and nonzero as true. Boolean
operators retain short-circuit evaluation. The checker must prove expressions
well-defined on the paths where they are evaluated. Earlier requirements may
establish the safety of later requirements, provided callers establish them in
that order. A specification expression may not mutate state or perform I/O.

For the supported subset, verification checks both the explicit assertions and
the absence of modeled runtime errors, including division traps. Later memory
support adds memory-validity obligations. Wraparound itself is permitted; a
no-overflow property must be stated or follow from another obligation.

Normal-return postconditions do not by themselves prove termination. Reports
must distinguish partial correctness from correctness with termination proved.
Resource exhaustion, physical stack limits, operating-system behavior, and
hardware behavior are not implicitly covered by the abstract execution model.

Inconsistent requirements make an implication vacuously true. Reports must
identify requirements known to be unsatisfiable and distinguish that from a
function proved useful on reachable inputs. Inconclusive satisfiability checks
must not be reported as evidence that the requirements are satisfiable. The
initial command exits unsuccessfully for known-vacuous roots as well: they are
reported as `VACUOUS`, not included among successfully verified roots. Safety
obligations in earlier requirements are still checked if a later requirement
makes the conjunction unsatisfiable.

## Checks and proof-only code

| Form | Meaning |
| --- | --- |
| `assert condition;` | Prove the condition at this program point. |
| `ghost let name = expression;` | Introduce a value used only for reasoning. |
| `proof { ... }` | Group proof-only statements. |
| `spec fn name(...) { ... }` | Define a side-effect-free specification function. |
| `lemma fn name(...) { ... }` | Define a reusable proof with contracts. |

Ghost variables follow ordinary lexical scope and may be assigned in proof-only
code. Their values cannot determine executable branches, memory writes, arguments
to executable calls, or returned executable values. Proof code cannot mutate
executable state, perform I/O, or introduce runtime behavior. Erasing proof code
must preserve the executable program's behavior.

Inside `proof`, ordinary `let` declarations are ghost declarations. Assignments
may target only ghost locals, and `return` is forbidden. Nested blocks, branches,
and loops are permitted, subject to the same arithmetic-safety and inductive
obligations as executable code. `ghost let` outside a proof block retains the
surrounding lexical scope. Proof expressions can read executable state but cannot
call executable functions. Ghost computation must terminate: missing proof-loop
measures prevent both total and partial correctness claims about the enclosing
executable function and its dependent callers. Erased divergence cannot establish
a false postcondition about an executable return.

Specification functions may call other checked specification functions. State
reads must be accounted for in their read summaries and evaluated in the
appropriate snapshot. They must be well-defined and terminating on their
permitted inputs; arbitrary executable functions cannot be treated as logical
functions merely because they have no apparent writes.

Specification and lemma declarations are erased completely from ordinary native
and VM programs, and are verification roots themselves. Their parameters and
locals may be mutated internally, but globals and memory may not be written.
An explicit nonempty `modifies` frame is invalid on either kind of declaration.
Executable expressions cannot call them. Specification functions return words;
lemmas are statement-only proof calls with no meaningful return value (`return 0`
is permitted as an early proof return, and `result` is unavailable in lemma
postconditions). Within nested `proof` blocks, `return` remains forbidden.

Specification calls inside `old(...)` read the entry snapshot without restoring
or otherwise changing current executable state. Every proof-only call introduces
a termination dependency: even a partial-correctness result requires total
correctness of its proof-only dependencies. Calls in a function contract may not
form a recursive cycle back to that function; recursion belongs in checked
bodies with explicit measures, not circular contract definitions.

Lemmas are called only in proof contexts. Their requirements are obligations at
each call, and their proved postconditions become available afterward. Recursive
lemmas require a termination argument; circular contracts cannot prove themselves.
Proof blocks may contain ghost computations, assertions, and lemma calls.

Example of an intermediate assertion:

```flex
requires x >= 0 && x < 100;
ensures result == old(x) + 1;
fn increment(x) {
    ghost let initial = x;
    x = x + 1;
    assert x == initial + 1;
    return x;
}
```

## Loops and recursion

| Form | Meaning |
| --- | --- |
| `invariant condition;` | Establish and preserve a property at the loop head. |
| `decreases expression;` | Prove progress using a well-founded measure. |
| `decreases a, b;` | Use a lexicographically ordered tuple of measures. |

Loop annotations attach to the next `while`, with the same comment, whitespace,
and dangling-annotation rules as function contracts. Multiple invariants are
conjoined. A recursive function's `decreases` clause goes before its declaration.

The checker establishes an invariant before the loop and proves it is restored
by every iteration that reaches the next loop head. The body may temporarily
violate it. At normal loop exit, the invariant and false loop condition justify
subsequent reasoning.

For initial termination support, measures are nonnegative signed word values
ordered by their mathematical values. Measure expressions still obey word
arithmetic; wraparound is not accepted as artificial progress. Tuple measures
use lexicographic ordering over nonnegative components. The checker proves the
necessary lower bounds and strict decrease across back edges or recursive calls.

Function measures are evaluated at function entry after the requirements. They
can refer to parameters and globals, but not `result`, `old`, or body locals.
Every component must be nonnegative even for a nonrecursive base case. Each
executed edge within a recursive call group compares the callee's entry tuple
with its immediate caller's saved entry tuple. All functions on such edges need
measures with the same number of components; an acyclic caller may have a
different tuple. Each function may declare only one tuple, with up to 16
components. Missing or incompatible measures leave termination unproved.

Loop invariants and measures refer to the head immediately before evaluating the
condition. Measures must be well-defined and nonnegative at every such head,
including the final head whose condition is false. After a body reaches the back
edge, its tuple must again be nonnegative and lexicographically smaller than the
tuple before that iteration's condition. Condition side effects therefore count
toward progress, while effects of the final false condition occur after the last
head. An iteration that returns from the function has no back-edge obligations;
it must establish the function's normal-return postconditions instead.

```flex
requires n >= 0;
ensures result == old(n);
fn count_to(n) {
    let i = 0;
    invariant i >= 0 && i <= n;
    decreases n - i;
    while i < n {
        i = i + 1;
    }
    return i;
}
```

The checker may infer simple invariants and measures, but must prove inferred
facts. If inference fails, it reports the missing obligation. Bounded loop
unrolling alone cannot establish an unrestricted loop proof. An omitted invariant
starts as `true`; subsequent proofs must hold for arbitrary values of all locations
modified by that loop, including writes in its condition and callees. Other values
and function-entry snapshots are preserved. The initial implementation requires
an explicit measure unless it can establish termination without a back edge (the
constant-false case). Missing measures leave termination unproved and the command
unsuccessful, even when partial correctness was established.

An invariant may admit unreachable states. A countermodel to an inductive step
therefore does not automatically demonstrate an executable bug. Reports identify
such loop-head values as an inductive countermodel, with reachability unestablished.
Only a failure reproduced from concrete root inputs is labeled a program
counterexample. Concrete replay is bounded to 100,000 evaluator steps per model;
that bound affects witness reporting, never acceptance of an inductive proof.

## Quantifiers

| Form | Meaning |
| --- | --- |
| `forall i in start..end: condition` | The condition holds for every value in the half-open range. |
| `exists i in start..end: condition` | At least one value in the range satisfies the condition. |

Range bounds initially denote signed word values, with no wraparound traversal.
A range is empty when `start >= end`; universal quantification over it is true
and existential quantification is false. The bound variable is scoped to the
condition. Parentheses delimit a quantified expression when combining it with
other expressions. Quantifiers are specification-only and do not execute loops.

Both forms require the predicate to be well-defined for every member of the
range. Finding one existential witness, or one false universal instance, does
not excuse undefined expressions at other members. Ordinary short-circuit
operators inside the predicate retain their normal semantics. An empty range
does not evaluate the predicate, but its bounds must still be well-defined.
Binders can shadow outer bindings; they are unavailable in their own bounds and
outside their predicate. `result` and `old` cannot be binder names. An enclosing
`old` evaluates free parameter/global references and bounds in the entry
snapshot; a bound index denotes its quantified value in either snapshot.

The initial exact lowering supports at most 64 values per evaluated range and
4,096 instantiated predicates per root, subject also to circuit capacity.
Symbolic bounds are supported when an independently checked query proves the
range fits the limit under the current path assumptions. Larger ranges, an
inconclusive capacity query, or exhausted capacity are unproved; the checker
never treats a truncated range as the full range or calls it vacuous. These are
implementation limits, not additional requirements imposed on the program.

Use existing logical operators, including `!a || b` for implication. Unbounded
mathematical integers, collections, and richer quantifier syntax are later design
work, not implicit features of this proposal.

## Verifying call chains

At each verified call, the checker must:

1. Establish the callee's requirements using the caller's current state.
2. Use a checked implementation or an explicitly trusted contract.
3. Account for every location the callee may change, invalidating facts that
   are no longer justified.
4. Apply the callee's postconditions, interpreting `old` at that call's entry.
5. Track any assumptions and termination dependencies transitively.

Contracts enable modular proofs. Supported unannotated callees may be analyzed
directly or given inferred summaries; the checker must not invent behavioral
guarantees. Unsupported callees remain unproved unless explicitly trusted.
Recursive groups require sound inductive reasoning rather than circular claims;
termination is a separate obligation when requested or needed by proof code.

Cached results must be tied to the actual code, contracts, dependencies, semantic
model, and verifier configuration. Changed callees or assumptions invalidate
dependent evidence. A verified caller does not certify unrelated code.

## Memory specifications

Stage 3 introduces specification primitives; these are not ordinary runtime calls:

| Form | Meaning |
| --- | --- |
| `readable_bytes(p, n)` | A live region with permission to read its bytes. |
| `writable_bytes(p, n)` | A live region with permission to write its bytes. |
| `fresh_bytes(p, n)` | Every byte is live with an identity different from its identity at function entry. |
| `bytes(p, n)` | A region designator for `reads`, `modifies`, or `releases`. |
| `disjoint_bytes(p, n, q, m)` | Two regions have no overlapping bytes. |

### Sequential byte-memory model

The verification model is sequential ordinary data memory, with byte addresses,
little-endian words, and unaligned accesses as specified by Flexscript. It does
not model volatile devices, concurrent mutation, compiler metadata, executable
code, or a process's actual virtual-memory layout. A region permission promises
ordinary data storage; a numerical address inequality does not grant permission.
Pointer arithmetic remains word arithmetic, with no implicit scaling or hidden
C-style pointer provenance.

A memory snapshot maps each byte address to a byte value, an allocation identity
or zero for no live allocation, and read/write permissions. Write permission
implies read permission, and either permission implies a live allocation. Live
data addresses are positive signed words; negative words remain available as
allocation errors. Multiple pointers to the same address observe the same byte,
identity, and permissions. Regions can span adjacent live allocations, because
Flexscript accesses raw bytes rather than enforcing C object boundaries.

Region lengths are nonnegative signed words. A nonempty region must fit entirely
in the positive address domain without wrapping. A zero-length region is valid
at any pointer value, grants no access, is both readable and writable, and is
disjoint from every region. Negative lengths are invalid. Permission predicates
are false on invalid regions; `disjoint_bytes` also requires valid region descriptions.
Its geometric result grants no lifetime or access permission. Every byte of a
load or store must be live and have the required permission. `store8` truncates
only the stored byte and still returns the original full-word argument.

Initial heap contents, allocation identities, and permissions are arbitrary,
subject to the root's requirements. Overlapping requirements describe the same
memory, never automatically separate objects. Read-only regions may alias
writable regions when their actual permission state permits it. An explicit
`disjoint_bytes` requirement is necessary when an algorithm needs separation.

`alloc(n)` is an atomic modeled allocation operation: a nonpositive request
returns a negative error; a positive request may either fail with a negative
error or return a fresh positive region of exactly `n` zero-initialized bytes
with read and write permission. Successful allocations cannot overlap any live
byte and receive a fresh identity. Physical padding, page size, timing, resource
availability, and scheduler behavior are not promised by this model. Failed
allocation preserves memory. Fresh storage does not count as a write to existing
external state, so `modifies nothing` does not by itself prohibit allocation.
Accesses to a newly created live identity are exempt from `reads`, `modifies`,
and `releases` frames relative to each enclosing function's entry snapshot.
This exemption is about the accessed allocation, not the pointer variable:
reassigning a pointer does not make existing storage fresh. Storage allocated by
a caller is existing external state at its callee's entry. Reusing a released
address creates a different identity and therefore fresh storage; the release of
the original identity must still satisfy its frame. Allocating initially free
bytes can change their contents and permissions outside declared entry frames.
Proof-only functions still cannot allocate.

Byte writes and `modifies bytes(p, n)` affect contents, not permissions or
lifetimes. Checked callees infer lifetime effects from modeled operations.
Trusted callees preserve allocation identities and permissions unless a separate
`releases bytes(p, n);` frame explicitly permits revocation in an entry-state
region. Repeated release clauses form a union; `releases nothing` excludes
revocation. A release frame is an upper bound, not a guarantee that a release
occurred. Normal-return postconditions describe success and failure outcomes.
The permitted changes are monotonic: a byte may lose write permission, read
permission, or its live allocation identity; the frame does not permit granting
permissions or replacing an identity. Contents are controlled separately by
`modifies`. Checked functions may also use `releases` to constrain transitive
lifetime effects; omission requests inference. At a trusted boundary, omission
instead means lifetime preservation. Release frames contain only byte regions,
not global words, and use the same entry-state geometry and union rules as
content frames. A nonempty release frame is forbidden on proof-only functions.
Trusted calls cannot invent fresh allocation identities merely by asserting a
permission predicate; fresh allocation is provided by the modeled `alloc`
operation. Raw unmodeled allocation/free syscalls remain unproved unless isolated
behind an explicitly assumed contract with adequate lifetime effects.

Released bytes lose their access permissions. A later successful allocation may
reuse their numerical addresses but has a different identity and zeroed contents.
Pointers themselves carry no hidden allocation tag: a reused numerical pointer
can access the new allocation only when current permission is established. Old
permission facts do not survive revocation. `old` refers to the complete entry
snapshot, including contents and lifetimes, and remains meaningful after a release
or reallocation. Frames preserve existing storage outside their declared effects;
the fresh-storage exemption above still permits new allocations. Loop abstraction
must replace modified contents and revocable lifetime
state independently and re-establish the relevant invariants.

The sequential model has shared permissions, not exclusive ownership or borrow
tracking. Passing a pointer does not transfer ownership or revoke the caller's
permission. APIs needing ownership protocols must state those protocols with
ghost state and contracts. No underspecified `owns`, `fresh`, or `freed` predicate
is introduced, and no concurrent safety follows from these sequential proofs.

`fresh_bytes(p, n)` is a proof-only, two-state predicate with a specific meaning:
the region is geometrically valid and every byte currently has a nonzero live
identity different from its identity in this function's entry snapshot. It does
not itself grant read/write permission or imply zero contents. An empty region
is fresh at any pointer; an invalid region is not fresh. A nonempty region cannot
be fresh on function entry. The predicate is available in postconditions,
assertions, and loop invariants; `old(fresh_bytes(...))` evaluates both snapshots
at entry and is false for a nonempty region. Each callee uses its own entry,
including specification helpers. Thus allocating factories can promise
`result < 0 || (fresh_bytes(result, n) && writable_bytes(result, n))`, and a loop
can retain the freshness of a changing buffer variable in an invariant. Trusted
contracts do not gain an allocation effect by asserting this predicate.

Allocation summaries and loop heads use an overapproximation of any finite
sequence of allocations. They first replace permitted existing contents and
revoke permitted existing permissions. Storage fresh relative to the enclosing
function entry is eligible for the same effects without an explicit frame. An
allocation effect then permits arbitrary new storage at currently nonlive
positive addresses; it preserves every still-live byte. New storage may have
arbitrary contents and permissions consistent with write-implies-read-implies-live,
since it may have been written or released before the abstract return/head.
Postconditions and invariants constrain this deliberately broad result. In
particular, a summary never obtains zero initialization merely from its allocation
effect: the checked callee's contract must establish that fact when callers need it.

Allocation identities are internal bookkeeping, never source-visible values.
For an abstract transition, surviving new identities may be represented by one
fresh generation label. This preserves identity equality at the same address
between the retained snapshots: an unchanged byte retains its identity, a new
byte differs from every earlier generation, and a nonlive byte has identity zero.
Equality between identities at different addresses is not a source operation or
a premise of any source proof rule. Each later concrete allocation and abstract
transition receives a distinct label. This abstraction does not bound the number
of allocations in a loop or assert that newly allocated bytes form one object.
Independent interval completion checks abstract transitions, while an executable
counterexample still requires replay of actual source operations and allocation
choices. An abstract heap countermodel alone does not establish reachability.

```flex
requires length >= 0;
requires writable_bytes(buffer, length);
modifies bytes(buffer, length);
ensures forall i in 0..length: load8(buffer + i) == 0;
fn clear(buffer, length) {
    let i = 0;
    invariant i >= 0 && i <= length;
    invariant forall j in 0..i: load8(buffer + j) == 0;
    decreases length - i;
    while i < length {
        store8(buffer + i, 0);
        i = i + 1;
    }
    return 0;
}
```

The byte writes in this example preserve the buffer's lifetime and permissions;
write permission also permits its postcondition reads. The current quantifier
engine still requires a proven range of at most 64 elements, so checking this
example with that engine additionally requires a suitable length bound. Memory
regions themselves are not limited to 64 bytes: the engine reasons about the
addresses actually observed and must preserve alias consistency at all of them.

## External effects and trusted contracts

`trusted;` attaches to a function with a declared contract. The checker does not
prove its body; callers may use the declared contract only as an explicit
assumption. `trusted` and `verify` cannot annotate the same function.

Trusted boundaries must supply adequate effect summaries. Missing effects remain
unknown; they cannot be inferred empty from an unavailable or deliberately
unchecked implementation. Trusted functions must explicitly declare both `reads`
and `modifies`, including `nothing` when appropriate. These frames cover modeled
program state, not every observable property of an external environment.
Contract expressions and their checked specification helpers must also fit the
declared read frame. Parameters are passed by value and may be changed internally;
only `old(parameter)` is fixed at entry. An unavailable return relation leaves the
result unconstrained.

`terminates;` may accompany `trusted;` and assumes that every call satisfying the
requirements returns normally in finitely many steps. This is an assumption,
not a checked decreases argument. Without it, normal-return postconditions may
support conditional partial correctness, but termination remains unproved and
the command exits unsuccessfully. `terminates` is invalid on checked functions;
`decreases` is invalid on trusted functions because their bodies are not proved.
Trusted specification functions and trusted lemmas are not allowed.

Trusted declarations are not verification roots and their bodies are never
executed or symbolically analyzed by verification. Ordinary syntax and linking
still apply, and compilation retains their executable bodies. Each used boundary
replaces its result, current parameter values, and declared modified state with
arbitrary values constrained by its postconditions. Other modeled state is
preserved by an explicit frame assumption. Calls made inside the unchecked body
are outside the checked dependency closure. A modeled normally returning call
whose postconditions admit no return state on a satisfiable modeled call path is unproved;
this check is not a general consistency proof for all external assumptions.

Successful dependent roots are labeled `CONDITIONAL`, with the trusted function
names, contract locations, effect frames, and normal-return assumption listed.
They count as conditionally verified roots, and may exit successfully when all
required obligations, including termination, are discharged under those listed
assumptions. A failed proof based on arbitrary external outcomes is an abstract
contract countermodel, never a claim that the unchecked implementation reproduced
the failure. Concrete replay stops at a trusted body. Failures before entering
that body, such as a violated requirement, can still be replayed.

Every dependent proof must report the trusted functions and assumptions it uses.
Such results must be labeled conditional, not presented as assumption-free proofs.
No general-purpose `assume` statement or unchecked proof placeholder is part of
the initial design.

Syscalls, FFI, file operations, networking, and hardware registers need contracts
or models for their behavior, including errors, partial completion, nondeterminism,
and state changes. Proofs about a hardware model do not prove real hardware
conforms to that model. Interrupts and concurrency require a separate interference
and synchronization model; sequential proofs do not establish concurrent safety.

## Results and diagnostics

Distinguish these outcomes for every requested obligation:

- **Proved:** established in the supported semantics, with assumptions listed.
- **Conditional:** established only under the explicitly listed trusted contracts.
- **Counterexample found:** a model demonstrates a violation. Show relevant
  inputs, state, source location, and path. Distinguish an abstract model from
  a concretely replayed execution.
- **Unproved:** unsupported behavior, missing annotations, solver uncertainty,
  timeout, or another unresolved obligation. This is not evidence of a bug.

Reports must state checked roots, transitive dependencies, inferred effects,
trusted assumptions, vacuous requirements, safety coverage, and whether termination
was proved. A check with unresolved obligations cannot receive an overall proved
status. Verification does not establish correctness of the specification itself.

## Implementation stages

### Implementation status

- Implemented foundation: [CNF representation](libs/proof/cnf.flex), bounded
  [DPLL search](libs/proof/sat.flex), [conflict learning](libs/proof/learn.flex),
  and independent [model/tree-proof](libs/proof/check.flex) and
  [resolution-proof](libs/proof/resolution.flex) checkers, all in Flexscript.
- The public [checked decision entry point](libs/proof.flex) accepts a solver
  result only after its model or unsatisfiability evidence passes checking.
- [Proof-engine regressions](scripts/test-proof.flex) compare all 512 subsets of
  the nine canonical two-variable clauses with exhaustive evaluation, check
  1,024 additional three-variable formulas, and reject malformed evidence and
  exhausted budgets. These validate the Boolean engine, not source contracts.
- [Learning regressions](scripts/test-proof-learning.flex) also exhaust the 512
  canonical two-variable formulas and 256 subsets of full three-variable clauses,
  including malformed resolution evidence and bounded-search exhaustion.
- [Word lowering](libs/proof/word.flex) implements wrapping arithmetic, bitwise
  operators, signed comparisons, masked shifts, and signed division/remainder
  with explicit trap predicates. Its [regressions](scripts/test-proof-words.flex)
  exhaust widths 1, 2, and 4 and exercise 256 pairs of 64-bit boundary values;
  incorrect output-bit constraints require checked refutations.
- [Universal property checks](scripts/test-proof-properties.flex) prove the
  register-field, bounded-increment, and clamp examples at the circuit level,
  and decode the signed-maximum counterexample for unrestricted increment.
- The [persistent byte-memory engine](libs/proof/memory.flex) implements the
  sequential model below the source-verifier layer: aliased byte and unaligned
  little-endian word accesses, immutable entry snapshots, whole-range read/write
  permissions, content-only region havoc, conditional snapshots, fresh zeroed
  allocations with failure, exact release, and bounded permission/lifetime
  revocation, allocation closure, and effects on storage fresh relative to an
  entry snapshot. Freshness predicates use the same whole-interval machinery as
  permissions. Finite observations of maps obey address congruence; positive
  permission predicates constrain all observed addresses, and negative
  predicates supply an inaccessible-byte witness. Interval boundaries are
  observed as well, including the tail after a partial release. These constraints
  feed the existing independently checked SAT/UNSAT path. Memory capacity
  exhaustion is an error, never a successful proof.
- [Concrete memory-model replay](libs/proof/memory-model.flex) independently
  evaluates circuit gates from input assignments and constructs native interval
  maps for every exact or abstract snapshot. It checks whole permission/freshness intervals, allocation
  freshness, every observed cell, and all region predicates without calling
  symbolic memory operations or SAT search. Unobserved addresses belong to a
  complete interval map; they are not assumed valid from a few sampled bytes.
  Failure to construct or validate a completion means replay failure, never a
  confirmed source counterexample. The completion strategy is deliberately
  incomplete: it can reject a satisfiable abstract model when its proposed
  extension fails. Its current caps are 16,384 interval boundaries and 2,097,152
  concrete snapshot cells, plus an explicit work budget. These are engine APIs,
  used by source replay as its initial memory model. Native source replay then
  maintains independent persistent byte writes and allocation ranges; it never
  dereferences a program pointer on the verifier's host. Replay or model-completion exhaustion cannot
  be reported as an executable counterexample.
- [Memory regressions](scripts/test-proof-memory.flex) check alias coherence,
  byte truncation and order, overlapping stores, snapshot preservation, region
  frames, release/reallocation, allocation freshness, and permission revocation.
  Exhaustive small-width address offsets and a native interval oracle supplement
  SAT/UNSAT properties; every satisfiable test must also complete and replay as
  concrete interval memory. Corrupted observations and predicates, invalid
  allocation identities, malformed inputs, and exhausted capacities/budgets are
  rejected. The suite is registered in the tool builder and compiler CI.
- [Source memory integration](compiler/proof-memory.flex) recognizes
  `readable_bytes`, `writable_bytes`, `fresh_bytes`, `disjoint_bytes`, `reads bytes(...)`, and
  `modifies bytes(...)`. It checks `load8`, `load64`, `store8`, and `store64`
  against current permissions and every enclosing frame. Entry snapshots retain
  contents and permission metadata; per-call snapshots follow argument
  evaluation. Branches, short-circuit expressions, early returns, and inlined
  calls merge or propagate memory explicitly. Modular calls havoc declared
  byte regions and assume separately checked postconditions; trusted calls
  remain visibly conditional. Specification reads in a trusted contract also
  obey enclosing read frames.
- Inductive loops replace potentially modified contents and potentially revoked
  permissions or lifetimes independently, preserving entry snapshots. Explicit
  function byte frames bound this abstraction. Omitted checked-function frames
  conservatively allow effects over all byte memory when the syntactic call
  closure may write or revoke, respectively. Inferred memory effects are currently
  conservative read/write/release/allocation flags, not automatically inferred minimal
  regions. Precise `bytes(...)` frames can therefore be necessary for modular
  preservation proofs. Allocation closure permits arbitrary new storage at
  nonlive addresses, while separate fresh-content and fresh-release transitions
  cover storage created after function entry. Invariants can retain its origin
  with `fresh_bytes`; a writable buffer is not automatically known fresh.
- Source `releases bytes(...)` and `releases nothing` constrain transitive
  revocation effects, including checked wrappers and recursive summaries. A
  trusted boundary without a release clause preserves lifetimes. Declared
  release regions permit monotonic revocation, not permission grants or a forced
  release; postconditions may state the exact outcome. Content changes still
  require `modifies`. Old snapshots and regions outside the release frame retain
  their permissions and contents, except for separately declared content writes.
- [Source lifetime regressions](scripts/test-proof-lifetimes.flex) cover aliases,
  use after release, permission weakening, old snapshots, frame unions, recursive
  calls, mixed content/lifetime effects, and inductive loop invalidation. Trusted
  bodies are not executed by concrete source replay: failures that depend on
  their assumed state changes are abstract call countermodels, not executable
  counterexamples. Native/VM execution and byte-identical annotation erasure are
  checked separately. The [lifetime example](examples/verification/lifetime-contracts.flex)
  demonstrates a conditional proof around an explicit page-release assumption.
- Direct and acyclic inlined `alloc` calls use the exact allocation model above:
  negative failure, positive nonoverlapping zeroed storage, fresh identities,
  immutable old snapshots, and frame exemptions checked at every enclosing
  entry. Modular and recursive summaries may introduce fresh storage and use
  separately checked postconditions to describe their result, contents, and
  permissions. A writable result alone does not promise freshness: factories
  can state `fresh_bytes` when callers need that guarantee.
- [Source allocation regressions](scripts/test-proof-allocations.flex) cover
  success/failure, zero initialization, aliases, adjacent out-of-frame accesses,
  preservation of existing storage, nested call frames, branches, early returns,
  allocating/recursive summaries, loop heads, and freshness contracts.
  Independent native replay validates every
  proposed allocation against its own interval memory, updates permissions and
  byte contents, and reports the allocation choices in the trace. Freshness and
  permission checks cover entire intervals, not sampled addresses. If no usable
  choice is available or replay exhausts its budget, the result stays unproved.
  For summarized allocators, an abstract return can propose a candidate address
  or error; replay still validates the entire allocation and executes the actual
  body. This witness heuristic cannot turn an unreachable abstract countermodel
  into an executable counterexample.
  The [allocation example](examples/verification/allocation-contracts.flex)
  verifies and runs a zeroed allocation and word round-trip under `reads nothing`
  and `modifies nothing`; annotation erasure preserves native and VM behavior.
  The [allocation-loop example](examples/verification/allocation-loops.flex)
  combines a recursive allocator, a freshness contract, and an inductively
  verified byte-writing loop under empty external read/write frames.
- [Source region regressions](scripts/test-proof-regions.flex) cover aliases,
  byte order and truncation, entry snapshots, permission errors, frame unions,
  restored writes, mutable frame parameters/globals, branch and short-circuit
  effects, modular and trusted calls, proof helpers, quantified loop invariants,
  and replayed failures. Ordinary native/VM execution and byte-identical
  annotation erasure are checked. The [memory example](examples/verification/memory-contracts.flex)
  verifies a four-byte clearing loop and an unaligned word round-trip; its
  unannotated runtime entry point supplies real storage without claiming an
  allocation proof.
- [Contract parsing](compiler/proof-source.flex) uses the compiler's existing
  lexer and precedence, resolves parameters and globals, enforces attachment,
  and erases annotations while preserving source offsets. `verify`, `requires`,
  `ensures`, `result`, `old`, `assert`, and global `reads`/`modifies` frames
  are supported. Native compilation and
  VM execution erase them without invoking the solver.
- [Source verification](compiler/proof-verify.flex) implements `flexscript verify`
  for word functions, mutable parameters/locals/globals, lexical scopes, branches,
  early returns, implicit zero returns, inductive loops, and calls with
  global state. Callee requirements
  are obligations, and every return checks the function's postconditions.
  Acyclic callees without postconditions are analyzed by their bodies. Calls to
  functions with postconditions, and all recursive calls, use modular summaries.
  Each checked requirement or postcondition is available to later obligations.
  These facts never justify their own obligation, and any failed prerequisite
  keeps the enclosing root unproved. Literal equalities also substitute current
  symbolic values under the retained path predicate; entry snapshots stay intact.
- [Modular verification](compiler/proof-modular.flex) checks each needed body
  once per invocation, then finalizes roots against their transitive summary
  dependencies. No caller is reported fully proved while any used callee remains
  unproved. Recursive groups require checked entry measures on every recursive
  edge for total correctness; contracts alone cannot justify circular termination.
  Summaries replace return values, assigned parameters, and possibly modified
  globals with fresh values constrained by postconditions. Explicit effect frames
  are checked upper bounds; omitted frames use conservative transitive inference.
  Current parameter values in postconditions may differ from `old(parameter)`.
  Functional postcondition equalities can substitute symbolic values while
  retaining the original predicate. A weak contract may leave a valid caller
  unproved; strengthening the callee's contract can supply the missing fact.
  No persistent cache is used. The call graph includes both validated executable
  calls and calls in proof code and contracts, including erased declarations.
  [Modular regressions](scripts/test-proof-modular.flex) cover recursive and
  mutually recursive calls, tuple measures, invalid dependencies, changed state,
  weak contracts, erased measures, imports, and chains beyond the inline limit.
  [Recursive examples](examples/verification/recursive-contracts.flex) include
  mutable parameters, mutual recursion, and lexicographic countdown.
- Ghost declarations and proof blocks share the source verifier's exact word
  semantics, branches, and inductive loops. Syntax validation enforces the
  separation from executable state even during ordinary compilation. The
  [ghost regressions](scripts/test-proof-ghost.flex) check snapshots, lexical
  scopes, ghost assignment, proof-loop termination, frame reads, unsafe
  arithmetic, imports, rejected executable dependencies, native/VM erasure,
  and identical executable bytes.
- [Proof-function validation](compiler/proof-functions.flex) supports `spec fn`
  and `lemma fn`, validates all erased bodies, and prevents executable calls,
  global writes, nonempty write frames, and lemma use as an expression.
  Acyclic specification calls unfold their bodies; recursive specification calls
  and lemma calls use checked modular contracts. Proof-function termination is
  required even for dependent partial-correctness results. Contract-call cycles
  remain unproved rather than introducing circular logical definitions.
  `old` calls use entry globals without changing current globals. Quantified
  bindings are saved across calls. The [proof-function regressions](scripts/test-proof-functions.flex)
  cover these behaviors, false contracts, recursion, argument mutation, imports,
  read frames, native/VM erasure, and ordinary compilation of erased proof code.
  [Proof-function examples](examples/verification/proof-functions.flex) combine
  reusable specifications, lemmas, recursive measures, and state snapshots.
- A satisfiable requirement query that used proof helpers is confirmed by
  concrete evaluation of the root requirements at the model's input. Abstract
  helper returns alone cannot establish reachability. Replay exhaustion or an
  imprecise helper contract leaves requirement satisfiability unproved. A known
  inconsistent requirement is reported vacuous only after its proof-function
  dependencies have been checked; a false callee contract cannot certify vacuity.
- [Trusted boundaries](compiler/proof-trusted.flex) use explicit frames,
  arbitrary return/current-parameter values, and declared postconditions without
  analyzing their bodies. `terminates` records an explicit normal-return
  assumption; absent that assumption only conditional partial correctness is
  available. Reports list transitive assumptions and mark trusted entries as
  contract-only in the call closure. `--no-trusted` rejects their use in CI.
  The [trusted regressions](scripts/test-proof-trusted.flex) cover nondeterminism,
  frame and snapshot behavior, contract consistency, unchecked body exclusion,
  replay boundaries, effectful loop calls, imports, erasure, and strict policy.
  The [external-contract example](examples/verification/trusted-contracts.flex)
  deliberately produces a conditional proof and is rejected by `--no-trusted`.
- [Quantifier lowering](compiler/proof-quantifier.flex) expands signed half-open
  ranges exactly after checking their cardinality. Native replay independently
  evaluates every member when confirming a failure. The
  [quantifier regressions](scripts/test-proof-quantifiers.flex) cover symbolic
  bounds, nested scopes, snapshots, vacuity, modular contracts, global frames,
  arithmetic safety, signed boundaries, and rejection of oversized ranges.
  Forty-nine small intervals are compared with a native enumeration oracle.
- [Inductive loops](compiler/proof-loop.flex) establish entry invariants, replace
  assigned locations with arbitrary head values, check preservation and tuple
  measures, and continue from invariant states with false conditions. Nested
  loops, body returns, global effects, and modifying condition calls are covered
  by the [loop regressions](scripts/test-proof-loops.flex). The
  [loop examples](examples/verification/loop-contracts.flex) verify count-to and
  lexicographic countdown without bounded unrolling.
- Queries retain only their transitive Boolean dependency cone. The property
  regressions exhaust all 256 pairs of four-bit inputs for sliced addition
  queries, including checked refutations and model decoding with unused circuits.
  Word addition and subtraction also reassociate constant offsets using wrapping arithmetic;
  4,096 four-bit input/offset combinations check this against native arithmetic,
  including cancellation and Boolean-valued offsets, each with a checked positive
  model and negative refutation. Boolean conjunction absorption is separately
  checked against a complete three-input truth table.
- Checked SAT models must also reproduce the identified violation in the
  [concrete source interpreter](compiler/proof-replay.flex), which uses native
  word operations independently of circuit construction. Inductive and modular countermodels
  that fail concrete replay are reported as unproved, not executable bugs.
  Reports include input
  words, source locations, and a replayed call/branch trace. Replay failure is
  unproved, never a reported counterexample.
- [Source regressions](scripts/test-proof-source.flex) cover positive and negative
  contracts, exact arithmetic and traps, ordered and vacuous requirements,
  short-circuit guards, scopes, calls, imports, invalid annotations, unsupported
  behavior, ordinary native/VM execution, and identical executable bytes after
  annotation erasure. [Runnable examples](examples/verification/word-contracts.flex)
  prove increment, register-field updates, and clamp directly from source.
- [State regressions](scripts/test-proof-state.flex) exercise arbitrary entry
  globals, per-call snapshots, early returns, short-circuit and argument evaluation,
  state propagation, frame unions, transitive reads/writes, restored writes,
  scope errors, and frame erasure. The
  [global-state example](examples/verification/global-contracts.flex) verifies
  two chained increments with inferred and explicit state effects.
- Reports identify each root, its analyzed call closure, and conservative global
  read/write effects, with any trusted external assumptions explicitly listed. Stateful counterexamples
  include initial global values and pass concrete replay. Successful reports
  establish termination through checked recursive and loop measures, or finite
  acyclic execution when no inductive loops are needed. Missing measures are
  explicitly separated from partial-correctness results.
- Current bounds: 128 expression/block nesting, 32 nested inlined calls (modular
  chains do not consume this depth), 256 concrete replay calls, 131,072 Boolean
  gates, 65,536 symbolic words per root, 16,384 obligations and 128 inductive
  loop instances per root, 16 components in a decreases tuple, and
  200,000,000 work units each for a solver query and evidence checking. Capacity
  or work exhaustion is unproved. For example, a general symbolic division in
  a requirement can still exhaust the satisfiability budget.
  Memory adds caps of 4,096 persistent nodes, 4,096 map probes, 16,384 cached
  lookups, 1,024 range predicates, and 256 recursive snapshot-lookup levels.
- Existing function, global, and local names take precedence over statement
  annotation keywords such as `assert`, `invariant`, and `decreases`. This keeps
  ordinary calls and assignments using those names executable. An annotation
  keyword therefore needs an unshadowed name in that scope.
- Raw allocation/free syscalls remain unmodeled in checked bodies; an explicit
  trusted release contract is a conditional assumption about an external body.
  Reachable unsupported operations report unproved; unsupported annotation
  syntax is rejected with a diagnostic. Verifying extension-bearing programs
  or lowering declarations is currently unproved pending precise proof binding.
  Ordinary source validation also checks unreachable code, so undefined names
  or wrong call arities cannot hide behind a constant branch.
- The sequential byte-memory and lifetime decisions are specified above.
  Interrupt/concurrency semantics remain a separate future design; the
  sequential model does not establish those properties.

Build and run the verifier and its tests with an existing Flexscript compiler:

```sh
mkdir -p build/proof-checker
flexscript compiler/main.flex -o build/proof-checker/flexscript
build/proof-checker/flexscript verify examples/verification/word-contracts.flex
build/proof-checker/flexscript verify examples/verification/global-contracts.flex
build/proof-checker/flexscript verify examples/verification/memory-contracts.flex
build/proof-checker/flexscript verify examples/verification/lifetime-contracts.flex
build/proof-checker/flexscript verify examples/verification/allocation-contracts.flex
build/proof-checker/flexscript verify examples/verification/allocation-loops.flex
build/proof-checker/flexscript verify examples/verification/loop-contracts.flex
build/proof-checker/flexscript verify examples/verification/recursive-contracts.flex
build/proof-checker/flexscript verify examples/verification/ghost-contracts.flex
build/proof-checker/flexscript verify examples/verification/quantified-contracts.flex
build/proof-checker/flexscript verify examples/verification/proof-functions.flex
build/proof-checker/flexscript verify examples/verification/trusted-contracts.flex
flexscript scripts/test-proof-source.flex -o build/proof-checker/test-proof-source
build/proof-checker/test-proof-source build/proof-checker/flexscript
flexscript scripts/test-proof-state.flex -o build/proof-checker/test-proof-state
build/proof-checker/test-proof-state build/proof-checker/flexscript
flexscript scripts/test-proof-loops.flex -o build/proof-checker/test-proof-loops
build/proof-checker/test-proof-loops build/proof-checker/flexscript
flexscript scripts/test-proof-modular.flex -o build/proof-checker/test-proof-modular
build/proof-checker/test-proof-modular build/proof-checker/flexscript
flexscript scripts/test-proof-ghost.flex -o build/proof-checker/test-proof-ghost
build/proof-checker/test-proof-ghost build/proof-checker/flexscript
flexscript scripts/test-proof-quantifiers.flex -o build/proof-checker/test-proof-quantifiers
build/proof-checker/test-proof-quantifiers build/proof-checker/flexscript
flexscript scripts/test-proof-functions.flex -o build/proof-checker/test-proof-functions
build/proof-checker/test-proof-functions build/proof-checker/flexscript
flexscript scripts/test-proof-trusted.flex -o build/proof-checker/test-proof-trusted
build/proof-checker/test-proof-trusted build/proof-checker/flexscript
flexscript scripts/test-proof.flex -o build/proof-checker/test-proof
build/proof-checker/test-proof
flexscript scripts/test-proof-learning.flex -o build/proof-checker/test-proof-learning
build/proof-checker/test-proof-learning
flexscript scripts/test-proof-words.flex -o build/proof-checker/test-proof-words
build/proof-checker/test-proof-words
flexscript scripts/test-proof-properties.flex -o build/proof-checker/test-proof-properties
build/proof-checker/test-proof-properties
flexscript scripts/test-proof-memory.flex -o build/proof-checker/test-proof-memory
build/proof-checker/test-proof-memory
flexscript scripts/test-proof-regions.flex -o build/proof-checker/test-proof-regions
build/proof-checker/test-proof-regions build/proof-checker/flexscript
flexscript scripts/test-proof-lifetimes.flex -o build/proof-checker/test-proof-lifetimes
build/proof-checker/test-proof-lifetimes build/proof-checker/flexscript
flexscript scripts/test-proof-allocations.flex -o build/proof-checker/test-proof-allocations
build/proof-checker/test-proof-allocations build/proof-checker/flexscript
```

### All-Flexscript proof engine

Start with exact finite-word reasoning: lower word operations into Boolean
circuits and then conjunctive normal form (CNF). An in-Flexscript SAT solver
searches for a counterexample to each verification condition. A satisfying
assignment must be checked against the original CNF and decoded into source
values; executable counterexamples should also be replayed where supported.

For an unsatisfiable condition, the solver must produce evidence accepted by a
separate checker written in Flexscript. The first engine can use a bounded DPLL
search with a certificate containing unit-propagation, case-split, and conflict
steps. Conflict-driven search may instead derive learned clauses using explicit
resolution steps, with parent clauses and pivots checked independently until an
empty clause is established. The original clauses must match exactly in either
case; a solver's bare claim of unsatisfiability is insufficient. Resource limits
produce unproved, not proved. The current public decision routine spends at most
two million search work units on tree search and passes the remaining search
budget to conflict learning. General queries first spend at most a quarter of
the remaining budget (capped at 50 million units) on input-first decisions, then
use late-clause decisions for the rest. Source queries involving byte memory
without allocation use the input-first order throughout the learning phase.
Allocation obligations use the general strategy so comparison decisions can
establish preservation from freshness. Requirement consistency continues to use
input-first search for all memory programs. Both strategies use
the same independent evidence checkers and share the stated total search budget.
Evidence checking and concrete memory completion each have a separate budget.
Root requirement satisfiability is checked and replayed immediately after entry
requirements and frame bounds, before constructing the body execution graph.
Each later obligation uses the full graph's memory constraints. Diagnostics
distinguish unresolved solver/evidence checks, failed interval completion, and
failed concrete source replay.
Memory obligations first spend at most one eighth of their budget, capped at
eight million units, attempting a stronger refutation without heap axioms. This
attempt may drop whole path conjuncts involving inputs outside the asserted
predicate's input set. Only independently checked unsatisfiability is accepted;
a satisfying assignment from this weakened path is discarded. Otherwise the
full query uses the remaining budget. This preserves the stated total budget
and prevents unrelated heap conditions from overwhelming arithmetic loop ranks.

The evidence checker should not reuse the solver's search or propagation routine.
Tests must include exhaustive small formulas, satisfiable models, unsatisfiable
certificates, corrupted certificates, and budget exhaustion. Bit-vector lowering
needs separate checks for every operation and boundary; correct SAT checking does
not establish that a source expression was translated correctly.

The later stages may require additional theory reasoning, induction, and
quantifier instantiation. Those components must also be implemented in Flexscript
and feed sound, checked proof rules. Large finite domains are not an excuse to
replace quantified proofs with sampling. Unsupported obligations remain unproved.

| Stage | Scope |
| --- | --- |
| 1 | Pure, loop-free word functions; `verify`, `requires`, `ensures`, `result`, entry-value `old`, and `assert`; exact arithmetic and counterexamples. |
| 2 | Modular function chains, loops and recursion, mutable globals, inferred effects, optional `reads`/`modifies`, invariants, termination measures, ghost code, specification functions, lemmas, and bounded quantifiers. |
| 3 | Memory regions and permissions, allocation/lifetimes, explicit external-operation contracts, followed by a separately designed interrupt/concurrency model. |

Stage 1 must reject unsupported effects in the checked call closure. Supporting
simple acyclic pure calls by direct analysis is permissible before stage-2 modular
summaries. Unsupported later syntax must produce a clear diagnostic.

Reuse the existing [word IR validation](compiler/ir.flex),
[effect analysis](compiler/ir-effects.flex), and extension mechanisms where useful.
They are implementation foundations, not substitutes for a sound verification
model. Initial meaningful targets include bit-field transformations and pure
RISC-V instruction-encoding calculations.

The trusted implementation includes the semantic encoding, verification-condition
generator, evidence checker, and relevant compiler/runtime behavior. Independently
checking evidence reduces reliance on solver search, but does not formally verify
the checker itself. A source or IR proof does not independently verify optimization
or machine-code generation. A general logical kernel and verified compilation are
possible future work, not guarantees of the first three stages.

## Acceptance criteria

- Valid contracts pass; deliberate arithmetic, branch, and state errors fail.
- Counterexamples cover signed extrema, wraparound, shift masking, and traps.
- Dangling contracts, illegal scopes, and ghost-to-runtime information flow fail.
- Missing callee requirements and effects outside explicit frames fail.
- Infinite loops cannot be reported as terminating; bounded checks are identified.
- Unverified external behavior never becomes an implicit trusted assumption.
- Solver timeouts and unsupported constructs remain unproved.
- Proof erasure preserves executable behavior.
- Diagnostics identify source locations and the scope and assumptions of a proof.

### Local acceptance evidence

The current local validation uses the self-hosted `build/proof-checker/heap-stage3`
compiler. Stage 2 and stage 3 binaries are byte-identical. The proof-engine suites
were also rebuilt with that compiler and rerun. This is local implementation
evidence; no remote CI run or publication is claimed.

| Requirement | Implementation and regression evidence |
| --- | --- |
| Optional roots, contract attachment/scope, ordered requirements, exact return checking, command options, vacuity, and source diagnostics | `proof-source.flex`, `proof-verify.flex`; source suite: 163 checks; trusted suite includes strict-policy and duplicate-option checks. |
| Exact word operations, traps, finite-word counterexamples, and checked proof evidence | Word suite: 46,584 checks; universal properties: 27,293; Boolean/model/tree checking: 14,118; learning/resolution checking: 5,632. Checkers import the shared CNF representation without importing or invoking search propagation. |
| Mutable globals, entry snapshots, inferred/explicit effects, modular dependencies, recursion, and termination | State: 122 checks; modular: 123; loops: 117. Wrong ranks, missing measures, unreachable abstract states, and transitive failure/termination dependencies are exercised. |
| Ghost isolation, proof-only termination, specification functions, lemmas, and bounded quantifiers | Ghost: 113 checks; proof functions: 171; quantifiers: 128. Erasure, illegal flows, recursive contract rejection, bounds, empty ranges, and safety of every instance are covered. |
| Aliased byte/word memory, permissions, old snapshots, frames, release, allocation, freshness, and loop/call heap abstraction | Memory engine: 9,055 checks; source regions: 131; lifetimes: 132; allocations: 150. Includes independent whole-interval completion, corrupted abstraction evidence, use after release, factory/recursive allocation, fresh frames, and release/reallocation loops. |
| Explicit external assumptions and honest partial/conditional/unproved outcomes | Trusted suite: 142 checks, plus lifetime/allocation cases. Concrete replay stops at trusted bodies; impossible assumed normal-return contracts and `--no-trusted` violations are rejected. |
| Compatibility and executable behavior | Compiler: 84 checks; imports: 46; VM: 480. All 12 files in `examples/verification` verify; the allocation, allocation-loop, lifetime, and memory examples also execute successfully as native binaries and in the VM. |

The total is 104,784 checks. Logs are in `build/proof-checker/*-heap-final.log`,
with the rebuilt engine runs in `*-heap-current.log`. These counts summarize
the named suites, not a formal proof of the implementation itself. The suites
are registered in `scripts/build-tools.flex` and `.github/workflows/compiler.yml`.

The acceptance audit covers contract syntax and attachment, exact word semantics,
proof-only separation, modular dependencies, induction and termination, bounded
quantifiers, sequential memory and lifetimes, external assumptions, independent
proof-evidence acceptance, concrete counterexample replay, diagnostics, and
executable compatibility. All three stages are implemented within the documented
semantic model and resource limits. Interrupt/concurrency verification, unbounded
logical domains, and verified compilation remain the separate future designs
identified above; no claims about those domains follow from this implementation.
