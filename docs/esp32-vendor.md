# Native ESP32 vendor-library integration

Flexscript emits Xtensa instructions directly. Optional ELF output and a
Flexscript linker driver let that code call existing Xtensa windowed-ABI
objects/archives. GNU ld resolves archive dependencies and relocations; no C
source generation, ESP-IDF application, Rust runtime or FreeRTOS is involved.

The original ESP32 now has native Wi-Fi and Bluetooth OS adapters, PHY
calibration, software timers and a cooperative task runtime. A passive Wi-Fi
scan found **6 access points on the physical revision 3.0 board**. Bluetooth
controller initialization, HCI Reset, Read Local Version, Read BD_ADDR and
advertising configuration commands also passed on that board. **The laptop
received the clean example's Flexscript advertisement at the board's Bluetooth
address, with 24 fresh RSSI updates during a 20-second scan.** A separate clean
Bluetooth passive scan received **221 BLE advertising reports in five seconds,
with zero dropped host events**. Original ESP32 station association/reconnection,
DHCP acquisition/renewal,
DNS, UDP echo and ICMP now also pass on the physical board; see
[native networking](esp32-network.md). BLE connections/GATT and simultaneous
Wi-Fi/Bluetooth coexistence remain open. S3 radio integration remains open.

## Compiler and ABI

- `--target esp32-elf`: original ESP32, RAM-loadable ELF.
- `--target esp32s3-elf`: S3, RAM-loadable ELF.
- `--target esp32-radio-elf`: original ESP32, reserved radio SRAM and higher main
  stack; native functions remain in IRAM.
- `--target esp32-xip-elf`: original ESP32, SRAM vectors/startup/cache initializer,
  native functions in IROM. Import `lib/platform/esp32-xip.flex`; startup calls
  its `esp_xip_enable()` before main. Link with `--xip` and boot from flash.

- `--target esp32-btdm-elf`: original ESP32 Bluetooth-safe cached-flash layout.
  Native data moves to 0x3ffc0000 and the native heap to 0x3ffb6400 so ROM
  Bluetooth exchange memory and BSS can be initialized without overwriting
  Flexscript state. Import the XIP adapter and link with `--xip`.

`esp32_external("C_identifier")` returns a linked symbol's 32-bit address. Import
slots receive real ELF `R_XTENSA_32` relocations. Unreachable references are not
linked. `esp32_call32(address,w0,w1,w2,w3,w4,w5,w6,w7)` passes eight packed 32-bit
C argument words, six in registers and two on the C stack. The bridge dynamically aligns the C stack even when other expression words
are live. Each call isolates a fresh register-window bank in a 416-byte frame
and restores all 64 address registers and WINDOWBASE/WINDOWSTART afterward.
This preserves ancestor C frames across deeply nested C -> Flex -> C calls,
including interrupt-time calls. Its result is the zero-extended uint32 result. `esp32_call64` returns a2:a3 as a complete word.
Manually pack each uint64 argument into its ABI-aligned pair of 32-bit words;
these intrinsics do not infer C types. Pointer arguments are 32-bit values.

`esp32_callback32(function)` requires exactly eight Flexscript parameters. Its
windowed trampoline zero-extends the eight incoming C words and returns the
complete a2:a3 result. It exports a C symbol under that function's name. Use
only the parameters actually present in the C signature. The separate
`esp32_callback(function)` retains the private one-word callback ABI.

`esp32_iram_callback32(function)` and `esp32_iram_callback(function)` retain
those same callback ABIs while placing the function, its trampoline and the
transitive closure of its directly referenced native helpers in SRAM. They
share callback addresses with the ordinary form. Use them for timing-critical
interrupt/PHY callbacks in cached-flash firmware. The compiler rejects native
SRAM overflow; the linker checks the combined native/vendor SRAM size.
Indirect vendor calls retain their linked placement, and DROM constants are
not relocated by this annotation. A cache-disabled callback must use SRAM/ROM
code and SRAM data throughout its actual call path.

Overflow/underflow handlers support call4/call8/call12. Interrupt entry saves
visible address registers, loop/SAR state and, for C-enabled firmware, all 16
FPU registers and FCR/FSR/CPENABLE. An ISR can call C; native `alloc` and task
switching remain forbidden inside an ISR even when the bridge clears EXCM.

`esp32_switch(save,load)` switches full 64-AR, window, special/user-register and
FPU contexts between tasks. Both context buffers must be 512 bytes, aligned to
16 and in internal DRAM below the configured main stack. Their layouts are
implemented by `esp32-sdk-task.flex`; the active stack floor travels with the
task. Tasks must use this layout rather than inventing C stack frames.

`esp32_state()` returns the active target's native control-block base;
`esp32_irq_pc()` reads EPC1. Sample EPC1 before calling C from an ISR, because
window exceptions may subsequently change it.

## Build radio examples

```sh
flexscript scripts/build-esp32-radio.flex -o build/build-esp32-radio
build/build-esp32-radio --kind wifi --vendor /path/to/esp32/libs \
  --rom /path/to/rom-symbols --output build/wifi-scan.bin \
  --ld /path/to/xtensa-esp32-elf-ld --gcc /path/to/xtensa-esp32-elf-gcc
build/build-esp32-radio --kind bluetooth --vendor /path/to/esp32/libs \
  --rom /path/to/rom-symbols --output build/bluetooth-hci.bin \
  --ld /path/to/xtensa-esp32-elf-ld --gcc /path/to/xtensa-esp32-elf-gcc
build/build-esp32-radio --kind bluetooth --source examples/esp32-bluetooth-scan.flex \
  --vendor /path/to/esp32/libs --rom /path/to/rom-symbols \
  --output build/bluetooth-scan.bin \
  --ld /path/to/xtensa-esp32-elf-ld --gcc /path/to/xtensa-esp32-elf-gcc
```

The driver uses `flexscript` on PATH, `FLEX`, or an explicit `--compiler PATH`.
Run it from this repository. It verifies vendor archive SHA-256 values against
[the inventory](esp32-vendor-sha256.txt), compiles native Flexscript tools and
firmware, and links local vendor archives. GCC is used only to locate its
windowed-ABI libgcc; `--libgcc PATH` supplies that archive directly. No production
C source is compiled. Outputs are the image, `.bin.elf` and `.bin.map`.
`--source app.flex` overrides the example. Input/output aliases are rejected.
`esp32-data-object.flex` supplies the writable ELF objects required by the Wi-Fi
ABI without generating C.

The Wi-Fi example configures the 40 MHz crystal / 320 MHz PLL for 80 MHz
CPU/APB, initializes the vendor supplicant, disables modem sleep, and performs
a passive scan. The Bluetooth example uses 160 MHz CPU with 80 MHz APB, a
500 kHz controller clock (crystal divider 79), BLE-only VHCI, and no modem sleep.
It checks HCI command-complete statuses and keeps yielding after advertising is
requested; its PASS marker proves HCI control, not reception over the air.
The separate Bluetooth scan example configures passive reception for five
seconds and counts actual LE Advertising Report events; its PASS requires at
least one report. These clock presets require a **40 MHz crystal**.

## Linking

```sh
flexscript scripts/esp32-link.flex -o build/esp32-link
flexscript --target esp32-elf tests/esp32/vendor-library.flex -o build/vendor.elf
build/esp32-link --firmware build/vendor.elf --output build/vendor-linked.elf \
  --ld /path/to/xtensa-esp32-elf-ld \
  --archive /path/to/esp32/libs/libwpa_supplicant.a \
  --rom /path/to/esp32.rom.ld \
  --rom /path/to/esp32.rom.libc-funcs.ld \
  --rom /path/to/esp32.rom.libgcc.ld \
  --image build/vendor.bin --map build/vendor.map
```

Inputs are explicit and never downloaded by the compiler/linker. `--object`,
`--archive` and `--rom` repeat. Archives are rescanned as a group. Undefined
symbols, region overflows and malformed ELF inputs fail before replacing the
requested output. Native code/data keep their compiled addresses. Vendor BSS
is included as zero-initialized PROGBITS so RAM-only loaders initialize it too.
Code and data are coalesced and aligned for the ROM serial loader. Vendor
`.phyiram` joins SRAM code and `.dram1` joins SRAM data, including constants
that the vendor explicitly places there. The XIP writer rejects any allocated
cached section not fully covered by the emitted IROM/DROM bytes; an orphan
section cannot silently become erased flash.

The pinned original-ESP32 libraries inspected/tested are from
[`esp-rs/esp-wifi-sys` commit 5afc3a38cc1abcd463e3b5140f0ac742de44053f](https://github.com/esp-rs/esp-wifi-sys/tree/5afc3a38cc1abcd463e3b5140f0ac742de44053f/esp-wifi-sys-esp32/libs).
Their checksums are in [the inventory](esp32-vendor-sha256.txt); binaries are
not bundled. Vendor licensing applies to any firmware containing those bytes.
ROM symbols/cache declarations are pinned to Espressif ESP-IDF v5.5.1. The OS
ABI and PHY initialization were checked against
[`esp-hal` commit 0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7](https://github.com/esp-rs/esp-hal/tree/0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7).
The [MIT license](licenses/esp-hal-MIT.txt) retains that project's attribution.
No Rust runtime is linked. Window
vector instruction sequences retain the [upstream license](licenses/xtensa-window-vectors.txt).

## Original ESP32 radio layout and flash

| Region | Address | Size |
| --- | --- | --- |
| Flex vectors/startup, RAM native code, vendor `.iram1` | 0x40080000 | 128 KiB maximum |
| Flex globals and vendor writable data/BSS | 0x3ffb0000 | 32 KiB maximum when linked |
| Reserved ROM Bluetooth BSS | 0x3ffb8000 | through 0x3ffbff70 |
| Native Flex bump heap | 0x3ffc0000 | 32 KiB |
| Explicit SDK arena | 0x3ffc8000 | up to 96 KiB |
| Reserved ROM/radio DRAM | 0x3ffe0000 | below main stack |
| Main stack for radio/XIP ELF | 0x3ffe8000 | 32 KiB |
| Cached native/vendor instructions | 0x400d0000 | bounded by 4 MiB flash layout |
| Cached vendor constants | 0x3f400000 | follows code in physical flash |

For `esp32-btdm-elf`, the two native regions above change:

| Region | Address | Size |
| --- | --- | --- |
| Reserved ROM Bluetooth data | 0x3ffae6e0 | through 0x3ffaff10 |
| Reserved Bluetooth exchange memory | 0x3ffb0000 | through 0x3ffb6388 |
| Native Flex bump heap | 0x3ffb6400 | 7 KiB |
| Reserved ROM Bluetooth BSS | 0x3ffb8000 | through 0x3ffbff70 |
| Flex globals and vendor data/BSS | 0x3ffc0000 | 32 KiB |

The SDK arena and main stack retain their listed addresses. ROM initialization
data is read with aligned 32-bit accesses: instruction ROM does not support
byte reads on the physical ESP32. The linker validates this separate memory
contract; the Wi-Fi layout cannot be used for Bluetooth ROM initialization.

`--xip` requires a radio-layout ELF. The emitted `.bin` belongs at flash offset
`0x1000`: it contains the normal RAM ROM image, its checksum/SHA, padding, then
64 KiB aligned IROM/DROM bytes. IROM physical offset starts at `0x30000`; DROM
follows its final page. No partition table or IDF application bootloader is
used. This image layout overwrites ordinary firmware when written to a board.
It is not suitable for `espflash flash --ram`.

The SRAM initializer masks interrupts, disables/flushes the PRO cache, resets its MMU
table using ROM `mmu_init`, maps code/data through the ESP32 ROM MMU APIs, unmasks the buses and
re-enables cache. It also initializes the ROM flash interface using the eFuse
pin configuration. The flash instruction window at 0x400d0000 uses IBUS0 and
the hardware IRAM0 mask; it does not use the register named IROM0. APP CPU stays
inactive. Startup clears inherited ROM register windows and traps in SRAM if
mapping fails. A flash-target fail-stop prints EXCCAUSE, EPC1, EXCVADDR and PS
as four hexadecimal words after `!`, using no stack or external functions. The ROM image SHA covers only
its RAM payload; appended cached bytes have no ROM authentication in this
format. Secure boot/signing remains unsupported. The separate [application-flash driver](esp32-flash.md)
implements bounded cache-disabled writes with model/QEMU and original-ESP32
hardware evidence, including protection restoration and settings across
four boots. The optional [NVS provider](esp32-nvs.md) installs persistent
radio callbacks when initialized before Wi-Fi; ordinary examples leave it disabled.
Do not call cached functions or read DROM while cache is disabled.

## SDK runtime services

`esp32-sdk-heap.flex`, `esp32-sdk-task.flex` and `esp32-sdk-sync.flex` implement a
separate reusable 16-byte aligned arena, split/coalesced free blocks, calloc,
realloc with failure preservation, task creation/yield/delay/reaping, counting
semaphores, recursive/nonrecursive mutexes, bounded queues with front/back
insertion and event groups. They do not allocate from the native bump heap.
Allocation searches start at a reusable cursor and visit each block at most
once. Free moves that cursor to the final coalesced block, under the existing
interrupt mask. Tests with128 persistent blocks and1024 temporary allocations
visit1024 headers, compared with132096 for the previous first-fit search.
This measures search work; end-to-end TLS timings are tracked separately.

Ticks are milliseconds; 0xffffffff means an indefinite wait. Timer 2 supplies
microseconds and is reserved by this runtime. Synchronization updates mask
interrupts; blocking operations cooperate through task yields. Zero-timeout
and ISR queue operations avoid clock reads and division, with bounded wrap
arithmetic and arbitrary byte-sized queue items.

This scheduler is cooperative and round-robin. The stored task priority does
not implement priority scheduling. Deleted task memory must be reclaimed from
another task with `esp_sdk_task_reap`; handles/waiters must no longer be used.
`esp32-sdk-timer.flex` runs software timer callbacks in an 8 KiB task, supports
one-shot/repeating timers, callback deletion/rearming and zero-delay arming.
`esp32-radio-os.flex` implements the pinned 121-field Wi-Fi OSI table; the
Bluetooth adapter implements the 63-field OSI table. Both reuse the native
heap/tasks/synchronization services and route hardware/software interrupts.
The shared PHY adapter retains calibration data and configures combo-module
PHY initialization; Wi-Fi explicitly enables its RX path. Scan-done events
record completion/status. This is not a general application event queue.

The Bluetooth VHCI transport acknowledges consumed packets and has independent
bounded queues for eight H4 events (258 bytes maximum) and four H4 ACL packets
(1029 bytes maximum, including the H4/HCI header). The host uses
`esp_bt_hci_peek_packet()` / `esp_bt_hci_consume_packet()` to preserve receipt
order across both queues. Lifecycle and encryption events cannot overtake older
data. A peek remains owned until consumption; sequence checks reject stale
consumption after a slot wraps. Legacy `esp_bt_hci_next_event()` and explicit
ACL peeking remain available for a single consumer using those APIs instead.

Command Complete/Status responses use a separate buffer, so async queue overflow
cannot prevent an in-flight command response. Overflow drops the new packet
and increments `esp_bt_event_dropped` or `esp_bt_acl_dropped`; a host must treat
lost packets as requiring recovery, rather than continue with uncertain state.
No allocation is performed per packet. The application must drain the queues;
a task receive callback yields when safe so the cooperative consumer can run.
Raw outbound ACL and Host Number Of Completed Packets use retained transport
storage. VHCI send readiness releases that storage; it does not replenish HCI
ACL credits. See [native BLE host](esp32-ble.md) for the core and ownership rules.

NVS persistence is optional through [esp32-nvs.flex](esp32-nvs.md); it is disabled
unless explicitly initialized before Wi-Fi. Modem sleep is disabled. Coexistence callbacks are
standalone stubs: use separate Wi-Fi and Bluetooth images. The
[native station/IP adapter](esp32-network.md) adds connection/reconnection,
IPv4/ARP/ICMP/UDP/TCP, DHCP and DNS. Authenticated [TLS](esp32-tls.md),
HTTP and [MQTT](esp32-mqtt.md) client APIs are integrated and verified on the
original board. The BLE core and ordered ACL transport have software tests;
controller/host connection APIs are integrated and software tested, while
physical independent-peer connection/data verification remains open. The
[native GATT server](esp32-gatt.md) is integrated and software tested; phone
read/change verification, pairing/bonding and BR/EDR profiles remain open.
Native [radio shutdown/reinitialization](esp32-radio-lifecycle.md) APIs are
implemented for the standalone original-chip profiles.
S3 runtime/PHY/radio adapters also remain work; its C ABI is tested separately.

## Verification

```sh
flexscript scripts/test-esp32-link.flex -o build/test-esp32-link
build/test-esp32-link --compiler /path/to/flexscript \
  --qemu /path/to/qemu-system-xtensa \
  --prefix /path/to/xtensa-esp32-elf- \
  --s3-prefix /path/to/xtensa-esp32s3-elf- \
  --vendor /path/to/esp32/libs --rom /path/to/rom-symbols
```

GNU-generated C/assembly under `tests/esp32/abi-oracle/` are independent ABI test
oracles, never production runtime sources. The suite checks eight arguments,
nested-call stack alignment, 32/64-bit returns, 80 nested calls, call4/call8/call12 spill/fill, nested ROM
callbacks, a C-calling ISR that changes FPU registers, task switching inside a
C callback, allocator/synchronization behavior, cached native/vendor execution,
ISR-allocation rejection and malformed/unresolved link input preservation.
It also exercises deep reentrant C/Flex/C callbacks during a C-calling timer
ISR, Bluetooth reserved-memory safety, software timer cancellation/deletion/
zero-delay delivery, the UART FIFO interrupt erratum model, writable data
objects, pinned full Wi-Fi/Bluetooth image builds, persistent interrupt-mask
changes across C/Flex callbacks/calls, and output preservation.
It additionally checks SRAM callback/helper placement with cache-disabled
execution, non-power-of-two queue wrap and ISR nonblocking behavior, bounded
VHCI event overflow/command isolation/allocation failure, vendor custom section
placement, and cached orphan rejection with output preservation. The expanded
suite now passes1119 checks, including the coupled cached-flash BLE host/transport
ordering fixture. Earlier integrated compiler verification passed core84, imports46,
shaders498, Wasm907 and ESP32 ROM1103 with a byte-identical self rebuild.
QEMU cannot establish RF behavior.

The connected original ESP32 revision 3.0 / 4 MB board printed PASS for RAM-only
linked C ABI/ISR (including nested-call stack alignment), task-context/FPU and
blocking SDK-runtime tests and the actual pinned WPA helper. The clean flash
probe also printed PASS for cached native/vendor code and bare-metal C tasks.
After each temporary flash test the original firmware was restored, and the
ROM checksum of the entire 4 MiB matched the saved backup. Evidence and the
private full backup are under `build/esp32-radio-verification/`.
The clean Wi-Fi example additionally passed PHY startup and a passive scan
(status 0, 6 access points). Bluetooth initialization and HCI commands passed,
including version 8 (Bluetooth 4.2) and the board's Bluetooth address. A later
diagnostic and the clean maintained advertising example both produced
externally received Flexscript advertisements; the clean run had 24 fresh
RSSI updates (about -86 to -89 dBm) during a 20-second host scan. Earlier
coordinated scans did not receive the advertisement. The clean Bluetooth
passive scanner received 221 advertising reports in five
seconds and dropped zero host events. Interrupt timing with SRAM callbacks
measured maximum baseband/controller handler durations of about 89/74 us at
160 MHz in a separate instrumented run; those timings do not prove
transmission. Every completed physical probe restored the original full-flash checksum. Physical
Station association/reconnection, DHCP acquisition/renewal, DNS, host UDP
echo and ICMP also pass on the original board; details are in
[native networking](esp32-network.md). Physical TCP echo/half-close, authenticated
TLS1.3/HTTPS and MQTT TCP/TLS QoS0/1/2 exchanges also pass, including1900-byte
MQTT messages, keepalive and clean TLS shutdown with zero remaining TLS
allocations and zero Wi-Fi RX drops; see [TLS](esp32-tls.md) and
[MQTT](esp32-mqtt.md). Those probes also restored and verified the original4MiB.
The BLE transport/core changes have software evidence only; BLE connections,
GATT/security, coexistence and S3-board radio verification remain outstanding. `esp32-vendor-probe.flex` remains the smaller cached-code/
ABI prerequisite test; it does not initialize Wi-Fi or Bluetooth.
