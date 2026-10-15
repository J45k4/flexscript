# Original ESP32 application flash

`lib/platform/esp32-flash.flex` provides bounded application storage on the
original ESP32 while native code runs from cached flash. It requires the
original-ESP32 XIP linker profile, one active PRO CPU, internal SRAM and a
JEDEC NOR chip using24-bit addresses. Explicit write windows temporarily
change array protection through volatile status writes on the verified Puya
profile. The driver does not initialize PSRAM, write nonvolatile status bits,
support encrypted storage or provision eFuses.

## Firmware and hardware protection

`esp_flash_region(start,size,cycles)` configures an explicit, sector-aligned
region and returns0 or a negative error. It reads the physical JEDEC identity
and accepts densities1..16MiB. The entire region must fit the detected chip.
Invalid reconfiguration preserves the previously configured region.

The region must begin beyond both the first MiB and the linked firmware's end:
`max(0x100000, _flex_drom_flash + _flex_drom_pages*65536)`. This protects large
cached images as well as ROM-loaded segments and the ordinary boot/partition
area. The linker already bounds its XIP layout to4MiB; the data region may use
additional confirmed chip capacity. The application must separately reserve
the chosen region against its other data, OTA layout or future partitions.
No fixed partition address is silently assigned by the driver.

The driver rejects calls from interrupt context, a running APP CPU, any
provisioned flash-encryption count or either secure-boot completion bit. It
reads eFuses to reject unsupported configurations and never writes them.
A single-owner guard prevents nested flash operations. It preserves the
caller's interrupt mask and SPI1 configuration on normal/error returns.

## API

Offsets are relative to the configured region. Every call validates offsets,
lengths and pointer ranges before sending commands. Return values are the
transferred/erased byte count or a negative error.

- `esp_flash_read(offset,buffer,size,cycles)` reads arbitrary byte ranges into
  internal SRAM, in chunks of at most64 bytes.
- `esp_flash_program(offset,buffer,size,cycles)` accepts internal SRAM or cached
  DROM input. It copies data into an internal bounce buffer before disabling
  cache, splits at64-byte and256-byte page boundaries, and verifies each chunk.
  It first checks the entire requested range for forbidden zero-to-one bit
  transitions; those return-30 before any program command is issued.
- `esp_flash_erase(offset,size,cycles)` requires4KiB alignment and a positive
  multiple of4KiB. It erases one sector at a time and reads back all4096 bytes
  to verify erased values.
- `esp_flash_write_access(enable,cycles)` opens/closes an explicit write window.
  It snapshots the original status, temporarily clears array-protection bits,
  and restores those bits on close. Firmware-region checks remain active.
  The confirmed Puya P25Q32H profile (`85 20 16`, native integer `0x162085`)
  uses Volatile Status Write Enable50h immediately followed by Write Status01h.
  WREN06h is never used for a status update. QE and all unrelated status bits
  are preserved and verified. Already-unprotected NOR parts need no status
  write; other protected parts return-95 until a verified profile is added.
  Region reconfiguration returns-16 while a window is open.
- `esp_flash_protected_end()` exposes the computed first writable address.

`esp_flash_start`, `esp_flash_size`, `esp_flash_capacity` and
`esp_flash_jedec` describe the configured region/chip. `esp_flash_status`
captures SR1 in its low byte and SR2 in the next byte during initialization.
The low JEDEC byte is manufacturer, followed by memory type and density. A reusable320-byte native
workspace is allocated at the first successful attempt to configure a region;
source/destination buffers may not overlap it. Caller pointers must reference
actual readable/writable memory; the range checks do not map new pages.

Bounds/arguments return-22, allocation failure-12, unsupported chip identity-19,
unsafe runtime/nested use-16, unsupported security configuration-95, missing
write-enable-13 and readback failure-5. Underlying media failures after writes
start can leave a partial request; atomic settings use the separate two-bank
protocol rather than treating a multi-chunk program as a transaction.

## Cache-off execution and timing

The critical routine and direct helper closure are placed in internal SRAM
with `esp32_iram_callback`. It masks interrupts, disables CPU0 cache through
ROM, configures SPI1 for single-wire mode0 at APB/4, issues commands and waits
for the flash to become ready. Then it restores SPI1, flushes/enables cache,
and restores the previous interrupt state. SPI0 cache configuration and ROM
pad routing are retained. Ordinary transfers use Read Status1/2, JEDEC ID,
Read, Write Enable/Disable, Page Program and4KiB Sector Erase. No
ROM unlock or nonvolatile status write is used. The explicit Puya write
window additionally uses50h/01h for verified volatile-only protection changes.

`cycles` must be1..2^31-1 and should cover the chip's maximum sector erase time
at the configured CPU frequency. It bounds each controller/flash-ready wait;
`80000000` is used by the fixtures. A timeout while the flash/controller is
still busy cannot safely return to cached instructions. The SRAM routine
records `esp_flash_fatal` (1 controller,2 flash busy,3 status restoration),
emits a short SRAM-only UART diagnostic (`!F1`, `!F2` or `!F3`) and halts with
interrupts masked. Reset/recovery is then required. It never resumes cached
code against
an unavailable flash chip or after a failed restoration of cache-relevant
status bits. This is distinct from an ordinary recoverable API
error after a completed command.

Calls are synchronous and block interrupts during each critical operation,
including a complete sector erase. There is no erase suspend, background
flash worker, or bound on radio packet loss during a commit. Applications must
account for this latency when scheduling persistence. The initial radio NVS
integration and coexistence/power work remain separate requirements.

Register/cache provenance is Espressif ESP-IDF v5.5.1
[`spi_reg.h`](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32/register/soc/spi_reg.h),
[`cache.h`](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_rom/esp32/include/esp32/rom/cache.h),
and the documented ROM unlock bug in
[`esp_rom_spiflash.c`](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_rom/patches/esp_rom_spiflash.c).
The volatile status protocol is specified in Puya
[P25Q32H datasheet v1.4](https://www.puyasemi.com/download_path/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/Flash%20%E8%8A%AF%E7%89%87/P25Q32H_Datasheet_V1.4.pdf),
sections10.4/10.8/10.9. A two-byte status update preserves SR2. The compatible
one-byte fallback is accepted only when both previous and desired SR2 are
zero; an unsupported format cannot silently clear QE or lock bits.
The runtime/driver is Flexscript; GNU C fixtures are independent read-only
source/image-layout test artifacts.

## Settings backend and verification

`lib/platform/esp32-settings.flex` connects this driver to the
[native settings core](esp32-settings.md). The application supplies a workspace
of `kv_size(bank)` bytes and calls
`esp_settings_init(start,bank,workspace,capacity,cycles)`. Initialization reads
both banks and returns the core's mount status; it never erases unknown media.
On two erased banks, explicit `esp_settings_create()` commits an empty store.
Use `kv_set/get/delete/rollback` for RAM changes and
`esp_settings_commit()` to complete the full verified media transaction.
The backend opens and closes its own write window around a real commit;
unchanged settings require no protection update. An application-owned window
remains owned by the application. After a failed commit,
`esp_settings_reload()` restores any unresolved settings-owned protection
window before reloading both banks and resolving the durable version.
`esp_settings_restore_error` exposes a failed close; ownership remains with
the backend until restoration succeeds. This backend owns the configured
flash region; changing it externally makes commits/reloads fail until reinitialized.

`scripts/test-esp32-flash.flex` accepts explicit `--compiler`, `--gcc`, `--ld`,
`--rom`, `--qemu` and `--report` paths. Its57 checks include an independent
native SPI1/NOR/cache model, write-enable/protected-media errors, complete
request preflight, state restoration, encrypted/secure/multicore/ISR rejection,
controller/flash timeout fail-stops, volatile-only status writes, QE
preservation, compatible status formats, suspended-operation rejection and
retry of a failed protection restore. The old settings backend reproduces
an ownership failure at checkpoint50; the integrated backend passes. The
model makes cached source pages inaccessible while cache is disabled. It substitutes only the target-specific
SRAM placement annotation for native-host execution.

Real Xtensa/cache placement is verified separately by ROM-booted QEMU images,
including a true GNU DROM source and an image exceeding1MiB. Every flash byte
outside the explicit8KiB data region is checked, including the whole linked
image. Four independent ROM boots verify600-byte settings, two durable
transactions and rejection of a newer uncommitted bank. A separate four-boot
serial-gated path executes the exact combined raw-flash/settings probe,
including erase of previously programmed data. The portable core's
8187 independent format/power-cut cases are a separate regression.

Physical driver and reboot verification is tracked in T196/T197/T198.
The initial flash-boot probes reached the real chip but its program was
blocked by SR1=0x1c. The same exact algorithm writes successfully from SRAM,
where SR1=0x00; independent ROM reads verify the bytes. A read-only cached
state probe confirms the differing protection state. The physical Puya
volatile-window control then verifies protect1c, unlock00, successful17-byte
program, relock1c and original-status restoration, followed by restoration and
checksum of the original full4MiB. The final cached image then passes actual
erase/program/readback, page/sector crossings, cached-DROM input and the>1MiB firmware exclusion. Four physical
boots preserve600-byte values, commit two updates and twice recover the old
transaction after an interrupted inactive-bank header. Every boot restores
SR1=0x1c. An independent RAM-loader full4MiB read verifies the settings
snapshot and every byte outside the explicit8KiB region against the original
backup plus the exact probe image. Finally, both image/storage regions are
restored, the original full4MiB MD5 is verified, and the board is reset.

This verifies the original ESP32/Puya852016 profile. Mid-command power cuts
remain modeled in the8187-case portable suite; the hardware interruption is
a reset between completed operations before the commit marker. Radio NVS
callbacks and BLE bond persistence remain separate integration requirements.
