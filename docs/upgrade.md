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
TCP/HTTP libraries and OpenSSL 3 through C FFI. Install `libssl.so.3` and a trusted
CA certificate store. Curl and shell subprocesses are not used. Compilation
emits machine code directly; the full compiler requires the glibc loader and libc.
Programs without FFI retain standalone native executables. The separate static
bootstrap core can build the full compiler but cannot perform HTTPS upgrades.
A failed download returns an error and leaves the compiler intact.

Before installation, Flexscript calculates SHA-256 itself and compares the binary
with the release's `SHA256SUMS`. It checks the native Linux x86-64 ELF layout, stages
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
64 MiB, and each download or version probe to 30 seconds. Downloads run in worker processes so the deadline also bounds DNS resolution. HTTPS and the published checksum protect the download;
there is no separate release-signature verification.

The published 0.0.2 binary predates this command. Install 0.0.3 manually once;
future releases can be installed with `flex upgrade`. Rename the downloaded
binary to `flex` if desired. The static core cannot perform HTTPS upgrades.

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
cleanup. SHA-256 is independently checked against Python's `hashlib`, including
padding boundaries, binary messages and a million-byte message.

The bootstrap script runs the upgrade suite against stages 1 and 2. Its report
and the separate `upgrade-tests.json` are included in CI build artifacts; packaging
requires both stages to pass.
