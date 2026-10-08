# Building and using the bootstrap compiler

Version 0.0.1 targets Linux x86-64. The language specification is in
`docs/language-0.0.1.md`, and the complete self-hosted compiler is
`compiler/main.flex`. `bootstrap/src/main.rs` is a standalone, mechanical Rust
port of the original 0.0.1 compiler algorithm. It compiles Flexscript directly to native ELF;
it never invokes another compiler to compile a Flexscript program.

The 0.0.2 compiler additionally supports [local imports](imports.md).
The Rust seed and published 0.0.1 binary remain the original bootstrap point;
they build the extended compiler, whose source still uses only original core
syntax. Build the current compiler before compiling programs containing imports.

## First bootstrap from source

Requirements on the host: Rust/Cargo, Python 3, and bubblewrap (`bwrap`), with
unprivileged user namespaces available for the clean-room check. The Rust seed
has no Cargo dependencies and builds offline.

```sh
python3 scripts/bootstrap.py
```

The command builds the Rust seed, compiles the Flexscript compiler to stage 1,
uses stage 1 to build stage 2, and uses stage 2 to build stage 3. It checks that
stages 2 and 3 match byte for byte, runs shared behavioral and invalid-input
tests against the seed and native compilers, checks imports against the newly
built native compilers, and runs the clean-room check.
Reports and binaries go to ignored `build/`.

The clean-room check runs the compiler inside an empty filesystem with an empty
environment and no network. Only the native compiler, input source, and output
directory are mounted. There is no Rust, Cargo, shell, dynamic loader, libc, or
other compiler inside. It rebuilds the compiler, uses that rebuilt binary to
compile the sample and a program with nested imports, and runs both in the same empty environment.

The release artifact is the verified stage 2 binary.

## Use the published 0.0.1 binary

Download `flexscript-0.0.1-linux-x86_64` and `SHA256SUMS` from the GitHub release
for tag `0.0.1`. In the download directory:

```sh
sha256sum -c SHA256SUMS
chmod +x flexscript-0.0.1-linux-x86_64
./flexscript-0.0.1-linux-x86_64 --version
./flexscript-0.0.1-linux-x86_64 examples/hello.flex -o hello
./hello
./flexscript-0.0.1-linux-x86_64 compiler/main.flex -o flexscript
./flexscript --version
```

The compiler and its generated binaries require only the Linux x86-64 kernel.
Rust is not needed. To repeat the full verification with a downloaded compiler:

```sh
python3 scripts/bootstrap.py --compiler /path/to/flexscript-0.0.1-linux-x86_64
```

Python and bubblewrap orchestrate verification on the host; they are not
dependencies of the compiler or generated programs.

## Extend the compiler after the bootstrap point

Implement the next language features using the syntax supported by the previous
release. Compile the updated compiler with that released binary. After the new
compiler supports the feature and passes self-compilation and language tests,
the compiler source can start using it. Keep each release's binary and checksums
so the version-to-version bootstrap chain remains reproducible.

## Package a verified release

Build from a clean committed tree, then run:

```sh
python3 scripts/package.py
```

This copies stage 2 to `dist/flexscript-0.0.2-linux-x86_64`, writes `SHA256SUMS`,
and writes release notes with the source commit, target, verification results,
and artifact checksum. Publication is a separate GitHub release operation.

## Automated builds and releases

The GitHub Actions workflow `.github/workflows/compiler.yml` verifies pushes to
`master` and pull requests. It downloads and checks the original 0.0.1 compiler,
builds the current compiler through three native stages without Rust, runs core
and import tests, verifies an empty-filesystem rebuild, and tests the examples.

A pushed version tag such as `0.0.2` must match `VERSION`. After the same checks
pass, the release job publishes the native Linux x86-64 compiler and `SHA256SUMS`
to that tag's GitHub release. Release notes come from `docs/releases/<version>.md`
and the verified build report. The original 0.0.1 tag and binary stay unchanged.
