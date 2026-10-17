# Native BLE P-256

`lib/net/smp-p256.flex` implements the SMP byte-array boundary for P-256 public
keys, key pairs and ECDH DHKey derivation. `lib/platform/esp32-smp-p256.flex`
binds it to the same native C ABI on original ESP32 and ESP32-S3. The math is
the unmodified p256-m component of the pinned official
[Mbed TLS3.6.7 release](https://github.com/Mbed-TLS/mbedtls/releases/tag/mbedtls-3.6.7).
No compiler bootstrap, heap allocation, Rust runtime or FreeRTOS is introduced.

These primitives do not send pairing PDUs, authenticate a peer, start controller
encryption or persist a bond. The offline [SC pairing owner](esp32-ble-sc.md) now implements Just Works/
Numeric Comparison and debug/reflected-key rejection. Verified entropy
integration and the remaining T139 work are still open.

## Wire interface

All public arrays use SMP wire order:private scalar, public X, public Y and
DHKey are each32-byte little-endian integers. The vendor boundary uses
big-endian integers and performs the conversions in private staging.

| Function | Inputs | Output |
| --- | --- | --- |
| `p256_validate(peer, work, capacity)` | Public X followed by Y,64 bytes | Status only |
| `p256_public(private, out, work, capacity)` | Private scalar,32 bytes | Public X/Y,64 bytes |
| `p256_shared(private, peer, out, work, capacity)` | Private32 and peer X/Y64 | DHKey32 |
| `p256_keypair(out, work, capacity)` | Configured secure-entropy callback | Private32, public X32, public Y32 |

Every function returns0 on success or a signed error. Public keys are validated
as canonical field coordinates on P-256; private scalars must be in1..n-1.
Shared-secret derivation validates the private key before the peer point.
Mathematical point validation alone does not implement Bluetooth peer policy
or authenticate that point's owner.

Supply256 bytes of caller-owned staging. The used staging must be disjoint
from every input/output and the provider context. Original input/output ranges
also reject provider-context aliases before staging changes. Inputs and outputs may
overlap each other; the complete input is staged before output publication.
Parameter/preflight errors preserve staging and output. Once a provider
operation starts, its failure leaves output unchanged and clears all256 staging
bytes. Successful operations publish only after the full vendor operation
succeeds and clear that staging too. Outputs remain caller-owned; the pairing
owner must manage and erase ephemeral private keys during phase2.

Errors include -22 for invalid extents/aliases, -19 for an unavailable provider
or unconfigured entropy, -16 for busy/ISR access, -2 for an invalid peer point,
and -3 for an invalid private scalar. Vendor and signed callback errors retain
their value. Four rejected random scalars return -1. No entropy failure can
produce a partially published key pair.

## Xtensa provider and entropy

Initialize with `esp_smp_curve_init(context, capacity, random, argument)` using
caller-owned64-byte storage aligned to8. The context contains transient entropy
request metadata, not a vendor math context. Reserve it separately from all
inputs, outputs and staging until `esp_smp_curve_deinit()` succeeds. The provider
checks32-bit C pointer extents, direct buffer aliases, ISR depth and concurrent
calls, and preserves the caller's full PS register across operations.

`random` is zero or the private call0 address of a named one-argument Flexscript
function, obtained with `esp32_callback(function)`. It is not a C callback
pointer. `argument` is an opaque64-bit application value. Public-key validation,
public-key derivation and ECDH work without an entropy callback. Key generation
returns -19 when none is configured, before entering the vendor.

The callback receives a readonly64-byte descriptor:

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 8 | Writable random-byte buffer address |
| 8 | 8 | Required length,32 |
| 16 | 8 | Opaque application argument |
| 24 | 40 | Reserved, zero |

Fill all32 bytes from a verified cryptographically secure source and return0.
A negative error aborts generation and propagates. A positive byte count is
invalid and becomes -22. Changing descriptor fields returns -116. Do not retain
the descriptor or buffer, perform asynchronous writes, or reenter the provider.
The descriptor is cleared after the callback. A failed entropy draw clears its
partial buffer before returning to the vendor; the wire layer then wipes its
entire staging. Key generation makes up to four draws when a drawn scalar is
outside1..n-1. Each draw is a32-byte big-endian scalar at the vendor boundary;
uniform random bytes require no special encoding by the entropy producer.

The module supplies no default RNG. The deterministic streams in its tests are
not a production entropy source. Binding and verifying an actual RF/DRBG
lifecycle remains part of T139 before radio pairing activation.

The standalone vendor object imports only zeroing and entropy hooks, both
provided in Flexscript under the isolated `smp_curve_vendor_` namespace. It
shares no symbols or profile state with the AES or TLS packages. Private-scalar
validation precedes public-key derivation; the Flexscript layer wipes its own
staging and metadata on completion. Busy/ISR deinitialization is rejected.

## Package and verification

```sh
"$FLEX" scripts/build-esp32-smp-p256.flex -o build/build-smp-p256
build/build-smp-p256 --archive /path/to/mbedtls-3.6.7.tar.bz2 \
  --output build/smp-p256 --prefix /path/to/xtensa-esp32-elf-
```

For S3, add `--chip esp32s3` and its toolchain prefix. The builder checks the
official archive SHA256, compiles a typed C ABI profile, prefixes all vendor
symbols and creates `libsmpcurve.a`, a chip/source/profile/ABI/toolchain hash
manifest, the license and original component interface/provenance files. Link
the archive with `esp32-link --archive`. Builds reject unsupported chips,
wrong archives and aliases before replacing package outputs. The pinned archive
SHA256 is `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`.

`tests/esp32/smp-p256-reference.py` takes explicit compiler, stock QEMU, both
toolchain prefixes, the vendor archive, pinned Wycheproof JSON and a fresh work
directory. Independent expectations use Python cryptography/OpenSSL and the
NIST ECDH example in the pinned upstream suite. Native and both Xtensa builds
execute real p256-m math, with typed C forwarding for injected failures.

All768 cases pass on native/original/S3. They include349 raw-key cases from the
[pinned Wycheproof corpus](https://github.com/C2SP/wycheproof/blob/78898104021ebd2cd98820e4112da89b1531d999/testvectors_v1/ecdh_secp256r1_test.json),
scalar/coordinate boundaries, deterministic differential pairs, all16 PS levels
for normal operations and signed C errors, input/output aliases, capped random
rejection, callback errors and descriptor mutation. The report accounts for
all612 upstream tests:263 ASN.1/SEC1-encoding or scalar-extent cases are outside
the raw64-byte public/32-byte private API and are explicitly listed as excluded.
No ASN.1 key parser is claimed.

An additional target consumer checks736 initialization, pointer, alias,
busy/ISR, signed-error, entropy and full-PS assertions per chip. Fifteen isolated
wire/atomicity/cleanup defects are detected by the independent native corpus.
Seventeen provider defect types are detected at their intended checkpoints on
each chip, producing34 expected-failure firmware boots. Twenty-four package
rejections preserve every preexisting output; repeated packages match exactly.

All30 positive stock-QEMU boots pass. Thirty-five captured sources reproduce138
artifacts exactly, including both vendor packages, the native provider and
all30 positive firmware ELF/image pairs. No firmware memory profile or emulator
implementation is changed. Evidence:
`build/esp32-backend-smp-p256/report.json`.

Physical entropy, physical-chip key exchange, authenticated radio pairing,
encryption, key ownership and bond persistence/reconnection remain unverified
or unfinished under T139. The P-256 component completes T479/T480, not full BLE
security support.


The raw nonce API `esp_smp_curve_entropy(out, size, work, capacity)` requests
32 fresh bytes through the same guarded callback and atomically publishes the
requested1..32-byte prefix. Supply at least32 disjoint staging bytes; successful
and failed started operations clear them. Preflight errors preserve both output
and staging. No scalar rejection or fallback RNG is applied.

T481 adds an original-buffer/context alias regression and nonce tests. The
current768-case curve suite, expanded target guards and40 provider-defect boots
pass; all15 algorithm defects are detected. Current combined evidence is in
`build/esp32-backend-smp-sc/report.json`; the earlier P-256 report above records
the preceding component checkpoint.
