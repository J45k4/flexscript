# Building and verifying with Flexscript

The compiler, VM/JIT, build orchestration, test harness, local TCP/TLS fixtures,
packaging, benchmarks and release signer are written in Flexscript. A published
compiler builds the entire current toolchain without Rust or Python. The original
Rust seed is archived in the `0.0.1` tag; it is no longer part of the current tree.

Use an existing full Flexscript compiler with imports and FFI (0.0.5 or newer)
to build the host tools, and the original 0.0.1 compiler as the independent seed:

```sh
/path/to/flexscript-0.0.5-linux-x86_64 scripts/bootstrap.flex -o /tmp/flex-bootstrap
/tmp/flex-bootstrap --compiler /path/to/flexscript-0.0.1-linux-x86_64
build/stage2 scripts/build-tools.flex -o build/build-tools
build/build-tools --compiler build/stage2
```

`--compiler PATH` is required and selects an existing Flexscript compiler.
`--out-dir PATH` chooses another bootstrap build directory. To reconstruct the
original Rust bootstrap, use a separate checkout of the `0.0.1` tag and follow
the [historical build instructions](bootstrap-0.0.1.md).

The Flexscript bootstrap flattens the compiler's known import graph into
`build/core.flex`, with globals before functions and ordinary definitions of the
five FFI intrinsics that return zero. The original seed builds this standalone
core as `core-seed`. It builds `core-rebuilt`, which builds the final `core`;
the latter two must be byte-identical. This permits an older seed to emit
different instructions while still checking the new emitter's fixed point.
The final core then compiles the real imported compiler into stage 1. Stage 1
builds stage 2; stage 2 builds stage 3. Stages 2 and 3 must be byte-identical.

The full compiler requires the Linux x86-64 glibc loader and libc. HTTPS upgrades
load OpenSSL 3 lazily. Programs without FFI remain standalone. The static core
needs no loader, libc, OpenSSL, Rust or other compiler to run, and can build the
full compiler. Its own FFI calls return zero, so it supports interpretation but
cannot JIT or perform HTTPS upgrades.

Native Linux builds from Flexscript source validate every function, then emit
only functions reachable from `main`. Unused functions, their string literals
and FFI adapters are omitted; errors in unused functions still fail compilation.
The default native pipeline parses shared IR, optimizes it, then emits x86-64
through `compiler/native-ir.flex`. `--native-pipeline direct` retains the
original source-emitter path for reference comparisons.
`--native-link all` retains every function for diagnostics and size comparisons;
`--native-link reachable` explicitly selects the default. This linking option
does not apply to VM/JIT, FIR, SetaScript, GPU or freestanding output.

The x86-64 emitter uses shorter immediate and stack displacement encodings when
their values fit, and reads uncached parameters directly from incoming argument
slots. `build/tools/test-native-size build/stage2` checks reachability, diagnostics,
FFI removal, recursion and stack/argument encoding boundaries.

Native Flexscript functions also relax local branches to the two-byte x86-64
encoding when the final distance fits -128 through +127 bytes. The compiler
records branch boundaries and targets, repeatedly selects newly fitting jumps,
then re-emits the function with its normal symbol and data fixups. Embedded
strings and assets are never decoded as instructions. Planning is bounded to
131,072 branches per function and 64 relaxation rounds; larger functions retain
valid long branches, and the round limit may leave some fitting branches long.
`FLEX_COMPILER=build/stage2 python3 scripts/test-short-branches.py` checks exact
forward/backward boundaries, cascading size reductions, execution and fallback.

Native source `if` and `while` conditions consume comparison flags directly,
omitting the intermediate `SETcc`, boolean widening and `TEST` when the value
is only needed for the branch. Stored and returned comparisons remain canonical
0/1 values. Logical negation can invert the existing condition, and `&&`/`||`
reuse flags while retaining the boolean value needed on their skipped path.
The emitter tracks the immediately preceding boolean producer and invalidates
that information at every emitted instruction and control-flow join. This is
an x86-64 instruction-selection optimization reused by both native source
pipelines. Verify it with
`FLEX_COMPILER=build/stage2 python3 scripts/test-condition-branches.py`.

The host harness in `scripts/lib/` provides argv-based process execution,
concurrent stdout/stderr capture, timeouts, binary comparisons, private temporary
directories, bounded buffers, JSON reports and assertions. Test suites use the
same language and fixtures as before. The seeded arithmetic corpus and malformed
HTTP responses are checked-in data under `tests/tooling/`; they require no code
generator at build or test time. `scripts/test-harness.flex` checks the harness
itself, including literal argv, pipe draining, malformed JSON and timeouts.

Bootstrap runs 1,822 compiler/runtime checks: 252 core, 92 local imports,
200 HTTP/HTTPS imports, 176 upgrades, 74 signatures, 48 FFI, 76 networking, 894 VM/JIT
and 10 clean-room checks. It also
runs 29 host-harness checks. Bubblewrap verifies the core's self-rebuild, native
hello and imported hello, and VM interpretation in an empty root with an empty
environment and no network, toolchain or libc.

Run the native application drivers separately:

```sh
build/tools/test-tetris --compiler build/stage2
build/tools/test-todo --compiler build/stage2
build/tools/test-http --compiler build/stage2
# Optional GUI checks on an isolated X11 display:
xvfb-run -a -s '-screen 0 1280x960x24 -nolisten tcp' \
  build/tools/test-todo --compiler build/stage2 --gui
```

Host verification needs bubblewrap, OpenSSL 3 libraries and the OpenSSL CLI,
Git and ordinary filesystem utilities. A C compiler builds only the independent
ABI test fixture; no C code generates or implements the Flexscript compiler or
host harness. Tetris tests use a private PTY. Optional Todo GUI tests call Xlib
and libpng through Flexscript FFI and save only their synthetic window.

The report records the source revision and every source file hash, seed/core/
stage hashes and suite results. Packaging requires a clean committed tree and
an exact matching report; it checks coverage and hashes before copying assets:

```sh
build/tools/package
```

CI downloads and checks the released 0.0.5 tool-building compiler and frozen
0.0.1 seed, builds the bootstrap tool with Flexscript, then runs the same stages,
tests, application drivers and packaging. Tagged releases build the signer with
the verified compiler and sign version-bound checksums through OpenSSL FFI.
The CI private key stays in memory. Branch and pull-request tests use disposable
keys and never receive the release secret.

The VM/JIT live in `vm/runtime.flex` and `vm/jit.flex`; native compilation remains
available. Resolved word IR passes through the shared
[IR optimization pipeline](ir-optimization.md) before backend lowering.
See [VM](vm.md), [signing](signing.md), and the historical
[0.0.1 bootstrap record](bootstrap-0.0.1.md).
