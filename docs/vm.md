# Flexscript VM

The VM, bytecode compiler and baseline JIT are implemented in Flexscript.
Build them with the published Flexscript compiler:

```sh
./build/flex compiler/main.flex -o build/flex-next
./build/flex-next run examples/hello.flex
./build/flex-next run examples/imports/main.flex
# A standalone compiler/VM entry source imports the same implementation:
./build/flex flexvm.flex -o build/flexvm
./build/flexvm run examples/hello.flex
```

`flex run myapp.flex [args...]` compiles source and imports to in-memory bytecode
and executes it in a new VM. It uses the same parser, name resolution and
language semantics as native compilation. There is no temporary executable,
external compiler or shell. The native `<source> -o <binary>` command remains
available. The original Rust seed is archived in the `0.0.1` tag.

## Execution tiers

The interpreter implements word arithmetic, globals, locals, function calls,
recursion, branches, loops, strings, guest memory and controlled host calls.
The compiler emits fixed-width 16-byte bytecode instructions with an accumulator
and operand stack. The bytecode is internal to this invocation; there is no
serialized bytecode loading API yet.

By default, eligible functions are compiled on their sixteenth call and reused
from a bounded code cache. `--jit` compiles eligible functions on the first call;
`--interpret` disables JIT. `--stats` reports instructions, JIT compilations,
JIT calls and remaining fuel.

The first JIT tier handles leaf functions containing arithmetic, local/global
accesses, comparisons, branches and loops. Functions containing calls,
allocation, guest pointer accesses or host operations remain interpreted.
This is a baseline JIT without inlining, speculative optimization or on-stack
replacement. A long-running function's first call stays interpreted in default
mode; use `--jit` to compile it before entering an eligible function.

The JIT emits x86-64 machine code directly. Code pages are writable during
construction and become read/execute before use. It uses the existing C ABI
adapter to enter native code; no external JIT library or Rust runtime is needed.
The static bootstrap core supports interpretation; its FFI shims make JIT
unavailable. Explicit `--jit` fails clearly on that core.

Interpreter and JIT charge the same bytecode instructions to the same fuel
budget, including branches and returns. Division by zero and signed division
overflow trap in both modes. Native loops check the deadline every 1,024
backedges. JIT code has a 16 MiB cache budget, individual functions are limited
to 8,192 bytecode records, and ineligible or oversized functions fall back to
interpretation.

## Trusted execution by default

`flex run app.flex` runs trusted code with native pointers, direct Linux syscalls
and raw FFI. Programs can read and write files, use TCP/TLS, read standard input,
create processes and call host libraries using the same interfaces as native
compilation. URL sources and imports are enabled by default. `--no-url-imports`
disables source downloads.

Loads and stores use host addresses in this mode, including pointers returned
by native libraries. Runtime `alloc` returns native mappings, so `munmap` and
FFI buffers retain their normal behavior. The VM accounts requested allocation
sizes against its memory budget; raw mmap/FFI allocations are outside that
budget. Trusted code has the host process's permissions. Host calls can block
or change process state, and the VM's execution deadline does not interrupt
blocking syscalls or foreign functions.

The interpreter and JIT remain available in both execution modes, with the same
fuel, deadline, call-stack and managed-memory limits. Standard output has no
VM quota in trusted mode. Guest `exit` ends the invocation.

```sh
flex run app.flex
flex run http://localhost:8080/app.flex
flex run --jit --stats examples/vm-compute.flex
```

## Restricted execution

Use `flex run --restricted app.flex` to opt into guest memory isolation and
explicit host capabilities.

Guest pointers are offsets into the VM's private, initially zeroed linear heap.
They cannot name the compiler, bytecode, local-frame storage, descriptors or JIT
pages. Loads, stores and host buffers are bounds-checked. Allocations use a
bounded bump allocator; allocation failure returns a negative value. There is
no garbage collector or individual-allocation reclamation in this first version.
Pointers can access other allocations in the same guest heap; this is isolation
between host and guest, not memory safety between guest objects.

Limits shared by both modes, followed by restricted-mode permissions:

- 16 MiB guest heap; 10,000,000 bytecode instructions; a 5-second execution deadline.
- At most 512 call frames, 4,096 local slots per function and 65,536 operand words.
- Standard output/error writes, bounded to 1 MiB combined; no standard input.
- No filesystem, networking, process creation, raw FFI or arbitrary syscalls.

```sh
flex run --interpret --fuel=100000 --memory=4m --timeout-ms=1000 app.flex
flex run --jit --stats examples/vm-compute.flex
flex run --restricted --allow-read=./data examples/vm-read.flex example.txt
flex run --restricted --allow-stdin app.flex
flex run --restricted --allow-url-imports https://example.com/app.flex
```

Resource options accept positive decimal values up to 1,000,000,000; `k` and `m`
suffixes represent KiB and MiB. Memory must be at least 4 KiB. Options precede
the source path; arguments after it are forwarded unchanged. A two-parameter
`main(argc,argv)` receives its script path as `argv[0]` and a null-terminated
guest argv array. Zero-parameter `main()` remains supported.

Restricted mode virtualizes a small syscall interface for existing Flexscript programs:
`read`, `write`, read-only `open`, `close`, `fstat`, bounded `poll`, monotonic
`clock_gettime` and guest `exit`. Host descriptors are translated through a
private table and are never accepted directly. Unknown syscalls and raw FFI
trap with a capability error. Guest exit affects this invocation only.

`--allow-read=DIR` opens a read-only directory capability. Linux `openat2` with
`RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS` confines file opens to that root,
including symlink traversal. Writable opens and file creation remain denied.
Absolute paths must begin with the root's canonical path. The guest can hold
up to 64 read-only file descriptors. This feature requires Linux `openat2`;
there is no weaker fallback if it is unavailable.
Only regular files are admitted. Opens use nonblocking mode and reject FIFOs,
devices and directories after opening.

Restricted mode disables URL imports by default. `--allow-url-imports` lets the
compiler fetch the entry source and its imports; it does not grant network
access to guest code. `--no-url-imports` disables downloads in either mode.
See [source imports](imports.md) for URL resolution and download limits.

Fuel limits computation. Poll and standard-input waits are bounded by the execution
deadline, but fuel does not meter kernel time. Filesystem operations can block
inside the kernel and need external process limits for a hard wall-clock bound.
The process's source compiler,
its memory arenas and import resolution use the host filesystem separately from
guest execution permissions. The timeout starts after source compilation, and
the guest heap quota excludes compiler and runtime storage. This experimental
runtime has not been audited as a production security sandbox. Hostile agent
code also needs process/filesystem isolation around the compiler and VM.

## Nested VMs

The same Flexscript implementation can execute inside its own interpreter:

```sh
flex run --restricted --interpret --allow-read=. --memory=256m --fuel=100000000 \
  --timeout-ms=10000 flexvm.flex run --interpret examples/hello.flex
```

The outer VM delegates only read access to the selected source tree. All inner
host calls pass through the outer VM's descriptor, memory, fuel and capability
checks. Inner allocations consume outer guest memory, and interpreting inner
instructions consumes outer fuel. Nesting grants no extra host access. This
example uses the interpreter in the inner VM: raw FFI and native code-page
creation are unavailable to guest code.

## Verification and measurement

Build `build/tools` once using the [Flexscript tooling instructions](bootstrapping.md).

```sh
build/tools/test-vm build/flex-next
build/tools/bench-vm --compiler build/flex-next --report build/vm-benchmark.json
```

The benchmark reports median nanoseconds from three complete process runs, including
startup and source compilation. Its arithmetic result is checked before timing
is reported. `--iterations N` selects the number of calls to the loop function
(default 100, with 50,000 additions per call).

The VM suite compares native, interpreted and JIT results using the language
fixtures, and checks exact fuel accounting, malformed source, arithmetic and
memory traps, resource exhaustion, filesystem confinement, inherited-descriptor
isolation, denied network/process/FFI operations, blocked input deadlines,
virtualized polling, hot-call tiering and nested VM execution.
Trusted-mode checks cover all valid language fixtures, the independent FFI ABI
corpus, filesystem writes, standard input, subprocesses, TCP echo, native
allocation/unmapping, output beyond the restricted quota and memory budgets.
It also observes generated RX mappings while a JIT loop is running and checks
that there are no writable/executable anonymous JIT mappings.

The bootstrap runs this suite against stages 1 and 2 and records `vm-tests.json`.
The empty-root verification also executes interpreted hello/import programs
using the static core without libc. Packaging requires these reports to pass.

The benchmark runs five million arithmetic loop iterations, checking the result
for native, interpreted, eager-JIT and default-tiered execution. Timings include
startup and source compilation and are reported without a hardware-dependent
performance assertion. They describe this workload, not all Flexscript programs.

Design references: [Wasmtime interruption and fuel](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html),
[Linux openat2](https://man7.org/linux/man-pages/man2/openat2.2.html).
