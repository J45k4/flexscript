# Flexscript 0.0.1 bootstrap plan

## Objective

Release the first native Flexscript compiler built from compiler source written
in Flexscript. Publish its binary under Git tag `0.0.1` so future development can
use that binary as the bootstrap compiler.

Flexscript is a general-purpose language. Version 0.0.1 implements the core
needed to write and compile its own compiler. This is a fresh design.

The first milestone is a complete bootstrap and release, including successful
self-recompilation. Small example programs are supporting checks along the way.

This file is the plan; creating it does not perform the implementation or
publish the release. Do not edit `readme.md` without an explicit request.

## Initial scope

- Proposed first platform: Linux x86-64, matching the development machine.
- Both compilers compile Flexscript source into native machine code.
- Proposed first backend: emit x86-64 instructions and ELF executables directly.
- The released compiler runs and compiles without Rust, Cargo, an interpreter,
  or another language compiler installed.
- Rust is needed to build the seed compiler during this initial bootstrap.
- Syntax, file extension, type rules, memory management, and the runtime
  interface must be defined in step 1. Paths using `.flex` below are provisional.
- Additional platforms and language features follow after the bootstrap point.

## 1. Write the compiler in Flexscript

- [x] Define a small language core sufficient to express the compiler itself.
      Specify syntax and semantics alongside the compiler source.
- [x] Settle the representations and operations needed for integers, booleans,
      source bytes, compiler data, buffers, and memory allocation.
- [x] Specify functions, local variables, control flow, and error behavior.
- [x] Specify the minimal operating-system interface for command-line arguments,
      file input/output, executable permissions, diagnostics, and process exit.
- [x] Write the compiler source in Flexscript, starting at `compiler/main.flex`.
- [x] Implement source loading, tokenization, parsing, semantic checks, native
      code generation, and executable output.
- [x] Define the CLI: `flexscript <source> -o <binary>`, `--help`, and `--version`.
- [x] Add valid and invalid language fixtures with expected results.

The compiler source defines the concrete requirements for the Rust seed compiler.
Write the Flexscript implementation first, even though it cannot run yet. Avoid
relying on language features that have not been specified.

**Completion:** a complete compiler implementation exists in Flexscript source,
with a specified core language and fixtures. Its executable behavior will be
verified after the seed compiler exists.

## 2. Build the Rust seed compiler

- [x] Create the Rust compiler project under `bootstrap/`.
- [x] Implement the core defined in step 1, including the operations and runtime
      facilities used by the Flexscript compiler source.
- [x] Compile that core to native machine code and produce runnable executables.
- [x] Produce useful diagnostics and a nonzero exit status for invalid input.
- [x] Run the language fixtures through the Rust compiler and check generated
      programs against their expected results.
- [x] Keep the two implementations aligned when integration exposes missing
      features or semantic inconsistencies.

The Rust compiler is stage 0. It must compile the actual Flexscript compiler
source; compiling only demonstration programs does not complete this step.

**Completion:** stage 0 can compile the full compiler source to a native binary.

## 3. Bootstrap the first native Flexscript compiler

- [x] Use stage 0 to compile the Flexscript compiler source into stage 1.
- [x] Run stage 1 and verify its CLI and compilation behavior.
- [x] Use stage 1 to compile the same compiler source into stage 2.
- [x] Use stage 2 to compile that source again into stage 3.
- [x] Run the shared valid and invalid fixtures through stages 0, 1, and 2.
- [x] Verify that programs produced by the compiled Flexscript compiler behave
      correctly, including programs using the runtime and file operations.
- [x] Keep code generation deterministic and compare stage 2 and stage 3
      binaries. They should be byte-identical for identical source and options.

```text
Rust seed compiler (stage 0) + compiler source -> stage 1 native compiler
Stage 1 native compiler     + compiler source -> stage 2 native compiler
Stage 2 native compiler     + compiler source -> stage 3 native compiler
```

Successful self-recompilation and language tests are required. Matching binaries
alone do not prove that the implementation is correct.

**Completion:** the compiler built from Flexscript source can rebuild itself and
passes the language tests without depending on the Rust compiler at runtime.

## 4. Prepare and verify the bootstrap release

- [x] Freeze the 0.0.1 core specification and record its supported features and
      known limitations in versioned documentation outside `readme.md`.
- [x] Add a repeatable bootstrap verification command covering steps 2 and 3.
- [x] Commit the compiler source, Rust seed, fixtures, build instructions, and
      bootstrap verification tooling on `master`.
- [x] Build the release from that exact committed tree and verify the embedded
      version is `0.0.1`.
- [x] Select the verified stage 2 binary as the bootstrap release artifact.
- [x] Verify the artifact in a clean environment with Rust and Cargo absent:
      compile a sample program, run it, and rebuild the Flexscript compiler.
- [x] Prepare the executable asset `flexscript-0.0.1-linux-x86_64` and its checksum
      in `SHA256SUMS`.
- [x] Record the target platform, source commit, bootstrap commands, and results
      in the release notes.

**Completion:** a verified native compiler binary and release notes are ready to
publish, and the source tree used to produce them is committed.

## 5. Tag, release, and upload the bootstrap binary

- [x] Create Git tag `0.0.1` at the verified release commit.
- [x] Push the release commit and tag to `J45k4/flexscript`.
- [x] Create the GitHub release for tag `0.0.1`.
- [x] Upload `flexscript-0.0.1-linux-x86_64` and `SHA256SUMS` to that release.
- [x] Download the published binary and verify its checksum and version.
- [x] Use that downloaded binary to compile the compiler source from tag
      `0.0.1`, then run the rebuilt compiler and the language fixtures.
- [x] Verify the remote tag points to the intended commit and the release assets
      are accessible.

**Completion:** release `0.0.1` provides a downloadable, verified bootstrap
compiler built from the tagged Flexscript source.

## Development after 0.0.1

Download and verify the 0.0.1 compiler binary, then use it to compile subsequent
Flexscript compiler source. The normal bootstrap path no longer needs Rust.
The Rust seed and initial build instructions are archived in the `0.0.1` tag
to reproduce the first bootstrap from source. Current builds require an existing
Flexscript compiler and do not include the Rust seed.

When extending the language, first implement new features using syntax supported
by the previous released compiler. Build and verify an updated compiler before
using those new features in the compiler's own source. Preserve that sequence so
every release has a working bootstrap path from an earlier release.

## Completion evidence

- Published release: https://github.com/J45k4/flexscript/releases/tag/0.0.1
- Tag `0.0.1` points to source commit
  `eae21182ac95392e4ceb252a2a5e526ace792dc6`.
- Uploaded stage 2 asset: `flexscript-0.0.1-linux-x86_64` (34,429 bytes), plus
  `SHA256SUMS`.
- Compiler SHA-256:
  `5384cb7725746a49957ab732a230b9cb1a6ac70a2495c103f72028aadc0e3124`.
- Rust-seed bootstrap: stages 1, 2, and 3 are byte-identical; 252 checks passed
  across the Rust seed, stage 1, and stage 2.
- The clean-room test rebuilt the compiler, compiled the sample with the rebuilt
  compiler, and ran that sample in an empty root with no Rust, Cargo, libc, or
  other compiler.
- The downloaded release binary matched its published checksum, rebuilt the
  compiler source extracted from tag `0.0.1` three times identically, and passed
  168 checks against the tagged fixtures together with its rebuilt compiler.
- The documented `--compiler` bootstrap command was run with the downloaded
  binary: no Rust invocation, another 252 checks passed, and the clean-room
  verification passed.
- `readme.md` remained unchanged.

The release tag preserves the exact source used for the binary. This completion
record is a subsequent documentation update on `master`.
