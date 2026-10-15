# Native ESP32 TLS

`lib/platform/esp32-tls.flex` provides one cooperative TLS client over the
application TCP stream on the original ESP32. The platform hooks and transport
adapter are Flexscript. Crypto and certificate processing use separately built,
pinned Mbed TLS vendor archives. No ESP-IDF application or FreeRTOS is required.

TLS 1.2 and TLS 1.3 are enabled, with ECDHE, RSA/ECDSA certificates, P-256,
P-384, X25519, AES-GCM and ChaCha20-Poly1305. SHA-256, SHA-384 and SHA-512 are
available. Legacy protocol versions, CBC suites, anonymous key exchange and
0-RTT are not enabled. The library's required certificate verification and
hostname checks remain enabled; the adapter exposes no insecure mode.

## Build the vendor archives

Supply the official [Mbed TLS 3.6.7 release archive](https://github.com/Mbed-TLS/mbedtls/releases/tag/mbedtls-3.6.7).
Its SHA-256 is
`a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`.
The tool rejects other bytes before extracting or compiling them. It uses
installed tools and explicit local inputs; it does not download a compiler or
source dependency.

```sh
flexscript scripts/build-esp32-tls.flex -o build/build-esp32-tls
systemd-run --user --scope --quiet -p MemoryMax=6G \
  build/build-esp32-tls --archive /path/to/mbedtls-3.6.7.tar.bz2 \
  --prefix /path/to/xtensa-esp32-elf- --output build/esp32-tls-vendor
```

The profile is `lib/platform/esp32-mbedtls-config.h`. The vendor build compiles
upstream C sources and checks context bounds, certificate-chain layout, and
64-bit clock types against an independent C ABI oracle. It produces three
archives, their license and `flexscript-tls.json`, containing source/profile
checksums and compiler information. AES tables live in cached read-only flash,
which avoids about8.5 KiB of writable table storage in reserved SRAM.

Pass `--tls build/esp32-tls-vendor` to `scripts/build-esp32-radio.flex` alongside
its ordinary Wi-Fi inputs and application source. The radio builder verifies
the manifest target, source/profile identity and each archive checksum before
linking. Firmware remains direct native code. This profile currently targets
original ESP32 Wi-Fi firmware; S3 radio integration is still a separate task.
The upstream license is [Apache-2.0 OR GPL-2.0-or-later](licenses/mbedtls-3.6.7-LICENSE.txt).

## Firmware API

Initialize the station/IP runtime and wait for DHCP, as described in
[ESP32 networking](esp32-network.md). Resolve the server name before connecting.
Use the same application task for all networking and TLS calls.

- `esp_tls_set_time(unix_seconds)` sets a trusted UTC anchor. It advances using
  the SDK monotonic clock. The caller supplies a trustworthy time; the adapter
  does not obtain it from unauthenticated NTP or disable expiration checking.
- `esp_tls_add_ca(buffer,size)` adds an explicit DER certificate or PEM bundle.
  Input is copied as needed and can be released afterward. Failed parsing
  leaves existing trust anchors intact. At most eight additions are accepted;
  each input is bounded to16 KiB. Reconfigure trust only while inactive.
- `esp_tls_connect(ip,port,local_port,name,name_size,timeout_ms)` starts an
  authenticated client connection. It requires a trust anchor, clock, valid
  hostname and active Wi-Fi/IP link. It rejects an application TCP stream that
  is already in use. A zero return means the asynchronous operation started.
- `esp_tls_poll()` also polls the IP stack and advances connection, handshake,
  encrypted I/O and close. Keep calling it. `esp_tls_state` is0 idle,1 TCP
  connecting,2 handshaking,3 ready,4 closing,5 closed, or6 failed.
- `esp_tls_send(buffer,size)` copies and accepts up to2048 plaintext bytes when
  ready, returning the accepted count. Keep/retry the remainder. -11 means
  backpressure; internal retry buffers stay owned by the adapter.
- `esp_tls_receive(buffer,capacity)` drains authenticated plaintext, returning
  a byte count, -11 when empty, zero after peer close-notify, or a failure.
  A zero-capacity receive returns zero. TLS record authentication failures and
  transport EOF without close-notify are errors.
- `esp_tls_close()` requests close-notify after accepted output drains. Poll
  through shutdown and continue draining any buffered plaintext. The adapter
  reads the authenticated peer notification during local shutdown as well.
  A late TCP reset is accepted only once both notifications are complete and
  no application output remains; other failures stay visible. TCP's documented
  TIME-WAIT bound still applies.
- `esp_tls_reset_session()` releases the inactive connection/configuration
  while retaining trust anchors and the seeded RNG for another connection.
  Active connections reject the call with-16.
- `esp_tls_deinit()` releases vendor allocations and trust anchors once closed
  or failed. Its native8 KiB context/I/O workspace is retained for reuse.

`esp_tls_error` retains a negative failure code; Mbed TLS errors are preserved,
as are underlying TCP errors such as refusal. `esp_tls_verify_flags` contains
certificate failure flags when verification fails. `esp_tls_allocated` and
`esp_tls_peak` count requested bytes owned by TLS in the shared SDK allocator;
these exclude the reusable native workspace. The handshake and I/O inactivity
timeout is explicit and bounded to300 seconds.

The allocation callbacks and their transitive native heap helpers execute in
SRAM through `esp32_iram_callback32`. MPI operations invoke these hooks
thousands of times; cached callback code caused long cryptographic stalls and
radio-service gaps. The shared SDK arena uses a next-fit cursor, and fresh TCP
output carries pending receive/window ACKs. Firmware keeps the ordinary
`mbedtls_ssl_handshake` call; experimental phase-state access and allocator
yields are not part of the production adapter.

The entropy hook requires initialized, linked Wi-Fi, and otherwise fails. It
samples the hardware RNG with at least4096 CPU cycles between output words and
feeds the vendor DRBG. See Espressif's
[hardware RNG requirements](https://github.com/espressif/esp-idf/blob/v5.2.5/components/esp_hw_support/hw_random.c).
This is not a general entropy provider for firmware with RF disabled.

## Verification and remaining work

`scripts/test-esp32-tls.flex` requires explicit compiler, GNU prefix, QEMU,
radio archives, ROM scripts and built TLS archives. Tests use Python/OpenSSL
and the `cryptography` package only as independent peer/reference tooling.
Temporary test private keys are generated in the test workspace and never
enter firmware or source control.

The harness checks TLS1.2/RSA and TLS1.3/ECDSA exchanges, SHA384-signed chains,
wrong hostname, untrusted CA, expired and future certificates, corrupted
ciphertext, missing close-notify, partial writes/backpressure, TCP error
propagation, queued SDK-worker progress before cryptographic work, and TLS
allocation cleanup. It also checks UTC calendar reference
vectors through year9999, the C64-bit clock result beyond2100, and native/SDK
heap boundary canaries in RAM and cached-flash firmware.

QEMU has no vendor Wi-Fi radio. Its TLS peer uses a UART test transport while
retaining normal trust, hostname, crypto and TLS state handling. This is
separate from a physical Wi-Fi/TCP handshake. Two controlled public HTTPS probes on the original ESP32 complete authenticated
TLS1.3, receive HTTP200 with931 plaintext bytes, close cleanly, release all
TLS-owned SDK allocations and report zero dropped Wi-Fi frames. Handshakes take
about4.9 seconds at the configured160MHz. One probe isolates the SRAM callback
placement; the repeat imports the integrated production modules and uses the
same application that failed before the change. Both restore and
checksum-verify the original full4MiB firmware afterward. TLS1.2 and the
negative certificate/record cases have independent OpenSSL/QEMU coverage.

The native [HTTP/1.1 client](esp32-network.md#esp32-http11-client) now has its
own request/response and physical TCP/HTTPS verification, separate from the
earlier raw-GET transport probes above. The [MQTT client](esp32-mqtt.md) also
passes authenticated TLS/broker tests and physical QoS0/1/2 exchanges, including
1900-byte messages and both close notifications. TLS84 and HTTP29 checks pass
after the shutdown correction exposed by the physical MQTT probe.
S3 radio integration and its hardware verification remain separate requirements.
