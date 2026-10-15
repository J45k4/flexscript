# Native ESP32 NVS provider

`lib/storage/nvs.flex` adds bounded namespaces, typed values and opaque handles
to the [native settings store](esp32-settings.md). The optional
`lib/platform/esp32-nvs.flex` connects it to the pinned original-ESP32 Wi-Fi
OSI-v9 table. All provider/runtime code is Flexscript. The stored bytes use
the Flexscript two-bank snapshot format, not ESP-IDF NVS partitions.

## Initialization and ownership

Initialize the SDK heap and application task first. Reserve two flash banks
outside the linked image and other application partitions, then call
`esp_nvs_init(start,bank_bytes,create)`. Each bank is4096..65536 bytes, in4096-byte
increments. The backend checks alignment, chip capacity and linked-image
exclusion. A successful call installs all12 NVS callbacks. Initialize before
`esp_wifi_station_init()`; that function enables the vendor `nvs_enable` flag
only when a provider is installed. Applications that omit this module or its
initialization keep radio persistence disabled.

`create=0` only loads existing media. `create=1` additionally permits creating
a store when both complete banks are erased. Neither mode formats unknown or
corrupt media. Initialization can fail after allocating buffers; retry the same
or a smaller bank size, or call `esp_nvs_release()` to free retained resources.

The provider allocates `kv_size(bank_bytes)` plus a576-byte16-handle workspace,
a48-byte callback table and an SDK mutex from the shared SDK heap. Allocator
metadata is additional. Radio and NVS share the96KiB SDK arena, so a valid
bank size can still fail allocation; the4KiB-bank profile is physically tested.
The flash driver retains its native scratch allocation.
The settings backend is global: the provider owns it while active. Do not
rebind it or call raw `kv_*`/`esp_settings_*` operations behind the provider's
mutex. Calls belong to an SDK task and cannot run inside an ISR.

`esp_nvs_reload()` discards pending changes, reloads both banks and invalidates
all handles. Use it to recover after an I/O failure. `esp_nvs_release()` is
supported before an OSI table is live and refuses to invalidate live radio
callbacks. It frees only owned SDK resources and clears only owned global
bindings. Repeated release does not disturb another settings user. Full radio
shutdown/reinitialization is a separate lifecycle requirement.

## Namespace and value API

Names and keys contain1..15 nonzero bytes, plus a terminating NUL for platform
functions. Namespace names are case sensitive. Each namespace consumes one
stored marker entry; keys are isolated between namespaces. The total is bounded
by the underlying128-entry limit and bank payload capacity. At most16 handles
can be open through the platform provider. Handles are32-bit opaque tokens;
closed/reloaded tokens are invalid and are not reused within a boot.

- `esp_nvs_open(name,mode,out_u32)` opens a namespace. Mode0 is read-only; mode1
  permits creation and writes. Output is exactly four bytes and changes only
  on success. `esp_nvs_close(handle)` releases its handle without committing.
- `esp_nvs_set_i8`, `esp_nvs_set_u8`, `esp_nvs_set_u16` and matching `get`
  functions implement the scalar callbacks required by the pinned vendor ABI.
  Getters write exactly the scalar width.
- `esp_nvs_set_blob(handle,key,buffer,size)` copies a blob, including an empty
  blob with null pointer and zero size.
- `esp_nvs_get_blob(handle,key,out,length_u32)` uses a four-byte length pointer.
  Null output queries the required size. A short output returns
  `ESP_ERR_NVS_INVALID_LENGTH` and updates the required size without modifying
  output bytes. Other lookup/type errors preserve output and length.
- `esp_nvs_set_value(handle,key,type,buffer,size)` and `esp_nvs_get_value`
  provide the same length-query convention for the complete native type set:
  U8/I8=1/17, U16/I16=2/18, U32/I32=4/20, U64/I64=8/24, string=33, blob=66.
  Scalar buffers contain exactly their little-endian width. String lengths
  include their final NUL; embedded NULs before it are rejected.
- `esp_nvs_erase_key(handle,key)` removes a key.
  `esp_nvs_erase_all(handle)` removes values only in that handle's namespace,
  preserving its marker and values in other namespaces.
- `esp_nvs_commit(handle)` durably publishes the shared pending snapshot for
  a writable handle. Read-only commit is an accepted no-op, matching the
  pinned upstream implementation. Close alone does not commit.

Reads see pending changes immediately. Handles share one staging transaction;
a writable commit includes pending changes from other handles/namespaces.
There is no per-handle transaction isolation. Replacing a key with another
type is allowed; reading through the wrong type returns a type mismatch.

Platform callbacks validate accessible input/output ranges and reject aliases
into provider workspaces. The portable `nv_*` core uses explicit lengths and
caller-owned memory; callers must serialize it and provide valid, separate
input buffers. It does no hardware I/O itself. It validates NVS-owned records
when binding a mounted store; raw application keys whose first byte exceeds15
remain outside the NVS key space.

The C callback signatures match the pinned Espressif OS adapter: signed/unsigned
8-bit and unsigned16-bit get/set, open, void close, commit, blob get/set, erase
key. NVS errors preserve the `0x1101..` Espressif values. A failed media commit
returns `ESP_FAIL` (-1), records the raw backend error in `esp_nvs_io_error`
and blocks further operations until reload succeeds. `esp_nvs_calls` and
`esp_nvs_commits` count accepted provider calls and successful writable commits.

The Wi-Fi facade keeps `WIFI_STORAGE_RAM` for station configuration, so ordinary
SSID/password configuration does not request persistence. The settings format
has CRCs and atomic commit recovery; it has no encryption, tamper protection or
wear leveling across additional banks. BLE pairing and bond serialization
remain separate work.

## Verification

Compile `scripts/test-esp32-nvs.flex`, then run it with explicit `--compiler`,
`--gcc`, `--ld`, `--rom` and `--qemu` inputs. Optional `--report` and `--controls-report` preserve the
independent-reference and broken-source-control JSON. The runner freshly compiles the native fixtures,
reference oracle, GNU windowed-C fixture and cached-flash firmware. It does
not flash hardware.

The native core has19 targeted checkpoints and19112 independent model checks
in1344 requests. Guard pages follow request, settings and handle workspaces;
64-byte prefix canaries check both workspaces. Cases include namespaces,
all type widths, invalid schema/media records, name/key bounds, strings/blobs,
read-only access, capacity, closed/stale handles, shared commits, reload and
failed-state recovery. Four deliberately broken implementations are rejected
for missing read-only checks, type checks, unique tokens and namespace-scoped
erasure. The cached-flash C fixture checks all12 callback signatures, exact
scalar/handle/length widths, output canaries, copied600-byte blobs, commit/reload,
and release ownership/partial-init cleanup. The runner passes35 checks without optional archives, or60 with the combined
NVS/IP/TLS link gate enabled.

`tests/esp32/nvs-wifi.flex` is a separate physical fixture. It reserves8192 bytes
at0x3e0000, stores a600-byte payload and two generations, then starts the actual
vendor Wi-Fi station and performs a passive scan. This fixed reservation must
be checked against the target application's partition layout before use.
Physical results and restoration evidence are recorded separately; QEMU has
no vendor RF model.

The runner always compiles `tests/esp32/nvs-tls-build.flex` to catch name
collisions across NVS, IPv4 and TLS. Supply `--vendor DIRECTORY --tls DIRECTORY`
to also link its complete firmware against the pinned radio and Mbed TLS
archives and verify image layout/integrity. This is a build-composition check;
the physical NVS probe exercises NVS plus Wi-Fi, while TLS physical evidence
is documented separately. The original flash/settings suite still passes57
checks after renaming its private range helper to avoid an IPv4 global.

The integrated original-ESP32 probe passes three hardware boots. The saved
600-byte payload is recovered across resets and advances through two committed
application generations. Each boot completes vendor Wi-Fi initialization with
93 real NVS callback calls and a passive scan (7,6,8 access points). Independent
full4MiB readback verifies application values, vendor namespaces/metadata and
all bytes outside the image/reserved8KiB region. The original full firmware and
storage are restored, checksum-verified and reset. The canonical fixture and a
freshly compiled radio builder reproduce the exact tested image. Evidence is
in `build/esp32-goal-verification/nvs-verification.json`. The parent vendor/runtime
suite also passes1091 checks after optional callback installation was added.
