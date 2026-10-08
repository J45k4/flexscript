# Release signing

The compiler pins an Ed25519 public key in `release_public_key()` in
`compiler/main.flex`. The same key is published in
`keys/release-ed25519.pub.pem`. Its raw 32-byte hexadecimal representation is:

```text
a7c0caa5f351e2b735dad15a832fa62d1c7834db98fee7f61c0eb941b492de05
```

The private key belongs in the GitHub Actions repository secret
`FLEXSCRIPT_RELEASE_SIGNING_KEY`, as the complete OpenSSL PKCS#8 PEM text.
This repository uses GitHub Actions. No private key belongs in source control,
build artifacts, release assets or logs. Set it from a protected file with:

```sh
gh secret set FLEXSCRIPT_RELEASE_SIGNING_KEY --repo J45k4/flexscript < private.pem
```

Only the tag-triggered release job receives this secret. After bootstrap tests
and packaging succeed, `scripts/sign-release.flex` checks both compiler hashes,
the source version and the pinned public key before signing. The Flexscript signer calls OpenSSL directly through FFI; the private key stays
in memory and is never passed to a child process or written to a temporary file.
A missing or mismatched private key fails publication. Branch and pull-request builds use
independent, temporary test keys and produce unsigned verification artifacts.

The release assets are the full compiler, static core, `SHA256SUMS` and
`SHA256SUMS.sig`. The signature is a raw 64-byte Pure Ed25519 signature over the
following UTF-8/ASCII prefix followed immediately by the exact checksum file
bytes (no normalization):

```text
Flexscript release signature v1
version=<numeric release tag>
target=linux-x86_64
```

The prefix includes a newline after the target. Binding the version and target
prevents moving a signed manifest to another release. Both asset names and their
SHA-256 digests are covered. The updater first verifies this signature, then
checks the downloaded compiler's hash. It never executes an unauthenticated
candidate, including for the version probe. Verification uses `libcrypto.so.3`
through native Flexscript FFI; it does not launch the OpenSSL CLI.

For manual verification, obtain the public key from an already trusted source,
then construct the message for the release you downloaded:

```sh
version=0.0.4  # replace with the downloaded release tag
printf 'Flexscript release signature v1\nversion=%s\ntarget=linux-x86_64\n' "$version" > signed-checksums
cat SHA256SUMS >> signed-checksums
openssl pkeyutl -verify -rawin -pubin -inkey release-ed25519.pub.pem \
  -in signed-checksums -sigfile SHA256SUMS.sig
sha256sum --check SHA256SUMS
```

Keep the public key pinned independently of the download being verified. A key
delivered alongside an untrusted binary does not establish authenticity.

The published 0.0.3 compiler predates signature enforcement. Installing 0.0.4
establishes this trust anchor; subsequent
upgrades require it. There is no unsigned fallback, automatic key download or
key rotation command. Replacing the key requires a deliberate trust migration
or a trusted manual installation. Changing only the CI secret will cause the
signer to reject publication, and a release signed only by another key will be
rejected by existing signature-verifying installations.

The signature authenticates release contents and their version; it does not
prove that the release API is showing the newest available release. Version
comparison prevents downgrades relative to the installed compiler.

References: [OpenSSL Ed25519 API](https://docs.openssl.org/3.0/man7/EVP_SIGNATURE-ED25519/),
[RFC 8032](https://www.rfc-editor.org/rfc/rfc8032),
[GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
