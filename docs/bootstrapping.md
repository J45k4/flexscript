# Building the compiler with FFI

Use the original published native compiler or the frozen Rust seed:

```sh
python3 scripts/bootstrap.py --compiler /path/to/flexscript-0.0.1-linux-x86_64
# Or: python3 scripts/bootstrap.py
```

The compiler implementation, networking, HTTPS and signature-verification libraries are Flexscript.
Python orchestrates builds and verification. The Rust seed stays frozen at 0.0.1.
Compilation emits machine code and ELF linking metadata directly.

The build first flattens the compiler's known imports into `build/core.flex`,
placing all globals before functions. Ordinary Flexscript shim definitions for
the five FFI intrinsics let the original compiler build `build/core`. This core
has working imports and FFI code generation, but its own foreign calls return
zero. Its source is rebuilt byte-for-byte before continuing.

The core compiles `compiler/main.flex`, including its real library imports, into
`build/stage1`. That full compiler builds stage 2, which builds stage 3. Stages 2
and 3 must be byte-identical. The core can be rebuilt from `build/core.flex` by
any of these compilers: named functions take precedence over FFI intrinsics.

The full compiler requires the glibc loader and `libc.so.6`. HTTPS upgrades load
OpenSSL 3 lazily; ordinary compilation does not need OpenSSL installed. Programs
without FFI remain standalone. The separate static core itself needs no loader,
libc, OpenSSL, Rust or other compiler to run. It can build programs using FFI and
can build the full compiler, but cannot perform HTTPS upgrades.

Verification runs core language tests, imports, C ABI tests, local TCP/TLS/HTTPS
integration tests, Ed25519 verification/signing tests and atomic-upgrade tests. Bubblewrap then verifies the static
core's self-rebuild, native hello program and nested imports in an empty root
with an empty environment and no network, toolchain or libc.

Build verification requires Python, bubblewrap, OpenSSL's CLI and a C compiler
for the independent ABI fixture. `libssl.so.3` is required to run the local TLS
tests. These test tools are not invoked by the Flexscript compiler.

The bootstrap report records all source-file hashes, the static core hash,
three full compiler hashes and verification results. Packaging requires a clean
committed source tree matching the report and publishes both the full compiler
and static core, with SHA-256 checksums. The tag-driven CI release workflow
signs the version-bound checksums with its private Ed25519 key and uploads both
binaries, checksums and the detached signature. Branch and pull-request builds
run signature tests using disposable test keys and never need the release secret.
