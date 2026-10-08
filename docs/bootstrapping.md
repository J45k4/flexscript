# Building and verifying with Flexscript

The compiler, VM/JIT, build orchestration, test harness, local TCP/TLS fixtures,
packaging, benchmarks and release signer are written in Flexscript. The frozen
Rust seed records the original 0.0.1 bootstrap origin. A published compiler can
build the entire current toolchain without Rust or Python.

Use an existing full Flexscript compiler with imports and FFI (0.0.5 or newer)
to build the host tools, and the original 0.0.1 compiler as the independent seed:

```sh
/path/to/flexscript-0.0.5-linux-x86_64 scripts/bootstrap.flex -o /tmp/flex-bootstrap
/tmp/flex-bootstrap --compiler /path/to/flexscript-0.0.1-linux-x86_64
build/stage2 scripts/build-tools.flex -o build/build-tools
build/build-tools --compiler build/stage2
```

`--out-dir PATH` chooses another bootstrap build directory. Omit `--compiler`
only when intentionally reconstructing the origin with the frozen Rust/Cargo
seed (`--release --locked --offline`). Host tools still build with Flexscript.

The Flexscript bootstrap flattens the compiler's known import graph into
`build/core.flex`, with globals before functions and ordinary definitions of the
five FFI intrinsics that return zero. The original seed builds this standalone
core. The core rebuilds itself byte-for-byte, then compiles the real imported
compiler into stage 1. Stage 1 builds stage 2; stage 2 builds stage 3. Stages 2
and 3 must be byte-identical.

The full compiler requires the Linux x86-64 glibc loader and libc. HTTPS upgrades
load OpenSSL 3 lazily. Programs without FFI remain standalone. The static core
needs no loader, libc, OpenSSL, Rust or other compiler to run, and can build the
full compiler. Its own FFI calls return zero, so it supports interpretation but
cannot JIT or perform HTTPS upgrades.

The host harness in `scripts/lib/` provides argv-based process execution,
concurrent stdout/stderr capture, timeouts, binary comparisons, private temporary
directories, bounded buffers, JSON reports and assertions. Test suites use the
same language and fixtures as before. The seeded arithmetic corpus and malformed
HTTP responses are checked-in data under `tests/tooling/`; they require no code
generator at build or test time. `scripts/test-harness.flex` checks the harness
itself, including literal argv, pipe draining, malformed JSON and timeouts.

Bootstrap runs 1,398 compiler/runtime checks: 252 core, 92 imports, 176 upgrades,
74 signatures, 48 FFI, 76 networking, 670 VM/JIT and 10 clean-room checks. It also
runs 27 host-harness checks. Bubblewrap verifies the core's self-rebuild, native
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
available. See [VM](vm.md), [signing](signing.md), and the historical
[0.0.1 bootstrap record](bootstrap-0.0.1.md).
