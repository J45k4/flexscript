# Compiler upgrades

The new compiler supports:

```sh
flex upgrade --check
flex upgrade
```

`--check` reports whether a newer stable release is available. `upgrade` downloads
and installs it, replacing the running compiler's executable. Both commands
query the latest stable release of `J45k4/flexscript` on GitHub. Tags must have
the numeric form `major.minor.patch`; an equal or older release is never installed.

The executable can have any name. For a local build, for example:

```sh
./build/flex upgrade --check
```

This command is implemented in Flexscript. HTTPS downloads use the Flexscript
TCP/HTTP libraries and OpenSSL 3 through C FFI. Install `libssl.so.3`, `libcrypto.so.3` and a trusted
CA certificate store. Curl and shell subprocesses are not used. Compilation
emits machine code directly; the full compiler requires the glibc loader and libc.
Programs without FFI retain standalone native executables. The separate static
bootstrap core can build the full compiler but cannot perform HTTPS upgrades.
A failed download returns an error and leaves the compiler intact.

Before downloading the candidate compiler, Flexscript verifies the release's
`SHA256SUMS.sig` with the Ed25519 public key hardcoded into the compiler. The signed
message includes the release version, `linux-x86_64` target and exact `SHA256SUMS`
bytes. This prevents substituting checksums or reusing a signature for another
version or target. Missing, malformed or invalid signatures stop the upgrade;
there is no unsigned fallback or downloaded-key trust. `--check` only queries
release metadata; it reports availability without authenticating release assets.

Flexscript then calculates SHA-256 itself and compares the binary with the signed
`SHA256SUMS`. It checks the native Linux x86-64 ELF layout, stages
the executable beside the installation, and requires its `--version` output to
match the release tag. It then preserves the installation's owner and permission
bits and atomically renames the staged file over the installed compiler.

You need write access to the compiler's directory. The command does not invoke
sudo. A symlink launcher updates its resolved executable and keeps the symlink.
Concurrent upgrades are locked, changes to the installed inode are rejected, and
handled interruptions clean up the staging directory. Setuid/setgid installations
are rejected. Like other atomic file replacements, existing hard links continue
to refer to the old executable.

Release metadata and checksum files are limited to 64 KiB, compiler downloads to
64 MiB, detached signatures to exactly 64 bytes, and each download or version
probe to 30 seconds. Downloads run in worker processes so the deadline also
bounds DNS resolution. Signature verification happens before the candidate is
executed, including its `--version` probe. See [Release signing](signing.md).

Signature enforcement begins with 0.0.4. The published 0.0.2 binary predates
the upgrade command. The published 0.0.3 updater
checks HTTPS and checksums but does not enforce release signatures. Install the
0.0.4 through a trusted one-time installation;
later upgrades enforce the pinned key automatically. Updating from 0.0.3 uses
its older checks, so that first transition does not gain signature enforcement
retroactively. Rename the binary to `flex` if desired. The static core cannot
perform HTTPS upgrades.

## Verification

```sh
python3 scripts/test-upgrade.py build/stage2
```

Tests use disposable installations and a local HTTPS release server, exercising
actual native compiler binaries and OpenSSL without touching a user installation
or the public network.
They cover successful upgrades, imports after an upgrade, symlink launchers,
permission preservation, check-only operation, version comparison, invalid
metadata, download failures, checksums, ELF validation, failed version probes,
concurrent upgrades, target replacement, staging collisions and interruption
cleanup. Signature tests reject missing, truncated, oversized, corrupted and
wrong-key signatures, changed manifests, and signatures for another version or
target before fetching the binary. Successful signed upgrades work with an empty
executable search path. SHA-256 is independently checked against Python's `hashlib`, including
padding boundaries, binary messages and a million-byte message.

The bootstrap script runs the upgrade suite against stages 1 and 2. Its report
and the separate `upgrade-tests.json` are included in CI build artifacts; packaging
requires both stages to pass. `scripts/test-signature.py` additionally checks
RFC 8032 Ed25519 vectors, non-canonical signatures and the CI signing helper.
