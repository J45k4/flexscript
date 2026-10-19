# Native ESP32 vendor-library integration

Flexscript emits Xtensa instructions directly. Optional ELF output and a
Flexscript linker driver let that code call existing Xtensa windowed-ABI
objects/archives. GNU ld resolves archive dependencies and relocations; no C
source generation, ESP-IDF application, Rust runtime or FreeRTOS is involved.

The original ESP32 now has native Wi-Fi and Bluetooth OS adapters, PHY
calibration, software timers and a task runtime with optional timer preemption.
A passive Wi-Fi scan found **6 access points on the physical revision 3.0 board**. Bluetooth
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

The S3 vendor interrupt prerequisite lives in
`lib/platform/esp32s3-radio-irq.flex`. It binds one GNU C callback/argument pair
to MAC source0 and power source2, using CPU0 interrupt1 shared with other native
drivers. Registration checks both ownership slots and table capacity before
publishing either route. Dispatch checks each source's pending bit and route;
disabling Wi-Fi routes preserves other drivers on the shared CPU interrupt.
The plain S3 profile has a smaller independent C/IRQ probe; the full ownership,
capacity and forced software-IRQ publication fixture runs on SDK and cached
profiles. Five ROM boots and18 deliberate defects pass stock QEMU. This module
is used by the S3 OSI/PHY adapter described below; it does not establish
physical Wi-Fi or RF operation.

`lib/platform/esp32s3-radio-os.flex` now supplies the matching S3 version9 OS
adapter table:120 fields/480 bytes, including its slow-clock callback and shifted
NVS entries. The original ESP32 keeps121 fields/484 bytes. Both wrappers use
`esp32-radio-os-core.flex` for scheduler, synchronization, event and C callbacks.
Initialization prepares a temporary complete table, starts or borrows the timer
service, then commits the table and ready pointer under one interrupt mask.
Allocation failure preserves the destination and releases only ownership claimed
by that attempt. Guarded table/failure tests pass on both chips.

The S3 typed GNU C peer checks all120 offsets against the pinned vendor C header
and exercises allocation, semaphores, recursive mutexes, queues, events, timers,
MAC addresses, random-buffer bounds, NVS slots and64-bit time values. The S3 PHY
adapter uses128 initialization bytes,1904 calibration bytes and a21-word digital
backup. It retains calibration across RF shutdown, saves/restores digital state,
keeps the USB PLL configured and stops the PHY temperature sensor after closing
RF. Its native task tests and six forced preemption windows pass; copied defects
cover partial state, allocation rollback, USB/backup/RX operations and clock guards.
Clock writes are observed through an independent C word in those forced tests.
The MMIO-only helpers now live in `esp32s3-radio-hardware.flex`; common random
byte filling lives in `esp32-radio-random.flex`. A primary-header C oracle and
native call spies pass632 operand/mask/buffer checks across caller PS levels
0/1/3/7/15;20 deliberate defects are detected, including MAC byte carry.

The actual pinned S3 archives now link and execute before Wi-Fi initialization.
`examples/esp32s3-vendor-probe.flex` builds the native OS table, checks the real
Wi-Fi MAC API's not-initialized error, runs the real WPA byte converter and
recovers the SDK heap on cleanup. This proves cached vendor code execution;
Wi-Fi/Bluetooth initialization, reserved controller SRAM, physical clock gating,
calibration and RF remain unverified.

From the repository root, with a compiler containing `esp32s3-xip-elf`:

```sh
"$FLEX" scripts/build-esp32-radio.flex -o build/build-radio
build/build-radio --chip esp32s3 --compiler "$FLEX" \
  --vendor /path/to/esp32s3/archives --rom /path/to/esp32s3/rom-scripts \
  --ld xtensa-esp32s3-elf-ld --gcc xtensa-esp32s3-elf-gcc \
  --output build/esp32s3-vendor-probe.bin
```

The S3 builder verifies its archive set against `docs/esp32s3-vendor-sha256.txt`
and the four ROM scripts against `docs/esp32s3-rom-sha256.txt` (ESP-IDFv5.5.1).
It emits480-byte `g_wifi_osi_funcs` storage and retains the ELF and map beside the
image. The default S3 source is this preinitialization probe. S3 Bluetooth and
cross-chip TLS inputs are rejected until their matching startup/profile exists.
The original ESP32 remains the default `--chip`; its table is484 bytes. The
builder preserves selected checksum inventories and rejects binary/ELF/map
aliases of them, as well as its source/compiler/archive/ROM/libgcc inputs.

The station facade is shared in `lib/platform/esp32-wifi-core.flex`. Original
applications import `esp32-wifi.flex`; S3 applications import
`esp32s3-wifi.flex` with the S3 cached-flash startup. The S3 wrapper prepares
modem clocks, power, reset and isolation; teardown checks PHY references before
power-down. Before entering the vendor initializer, original ESP32 reserves one
IRQ slot and S3 reserves two. Full tables and a foreign S3 power handler reject
without calling the vendor initializer or changing application interrupt enables.

The raw S3 transaction lives in `esp32s3-radio-power.flex`; reset release reads
back the current register before clearing modem reset bits. The wrapper rejects
active ADC/PHY users before power changes and requires the Wi-Fi domain lease
before power-off. Both chips reject station initialization while PHY references
or clocks are borrowed, preserving their existing calibration buffers and heap.
Independent primary-header operand traces pass2304 assertions and19 deliberate
defects. Native firmware checks all16 interrupt levels,288 S3 power assertions,
96 borrowed-PHY cases per chip and13 deliberate admission/C-ABI defects. The
actual C delay peer receives10; physical delay duration is still unverified.
Fourteen artifacts rebuild exactly from68 frozen sources in
`build/esp32-backend-s3-power/report.json`.

`tests/esp32/s3-wifi-controls.py` checks the matching vendor's complete160-byte
init configuration and184-byte station configuration through a typed C peer,
including all52 crypto bytes, NVS off/on, canaries, WPA2/WPA3 PMF and seven
initialization-failure paths. Stop/deinit/supplicant retries, allocation failures,
full/near-full IRQ tables and12 deliberate defects also pass. These use a C
vendor peer; they establish adapter contracts independently of radio hardware.

To link the full S3 vendor initializer, add
`--source examples/esp32s3-wifi-init.flex` to the builder command above. The
builder supplies24 writable two-byte FTM coefficients required by the real
archive. `tests/esp32/s3-ftm-reference.py` compares every linked symbol and value
with the matching vendor C header and checks initialized-object bounds.
The full image links and enters actual vendor initialization. Stock QEMU then
stops progressing at ROM `0x40036a44`, polling PHY register `0x6000e050` for
ready bits24..26. Four independent samples read zero; the runtime memory map
and [matching stock QEMU source](https://github.com/espressif/qemu/blob/esp-develop-9.2.2-20260417/hw/xtensa/esp32s3.c#L419)
show that address uses its unsupported-I/O fallback, which returns zero.
The reusable `tests/esp32/s3-wifi-startup-observe.py` records raw QMP replies,
CPU/register samples and the child process exit while preserving its input
flash copy. Independent pipe tests cover coalesced and fragmented replies.
No ROM/vendor bypass or emulator change is used. Actual S3 startup/teardown,
controller SRAM reservations and RF still require an S3 board. Frozen source,
exact full-image/typed-peer/lifecycle rebuilds and the hardware-wait evidence
are retained in `build/esp32-backend-s3-wifi/report.json`.

## Compiler and ABI

- `--target esp32-elf`: original ESP32, RAM-loadable ELF.
- `--target esp32s3-elf`: S3, RAM-loadable ELF.
- `--target esp32s3-sdk-elf`: S3, RAM-only SDK layout with192KiB IRAM,16KiB
  globals/vendor data,8KiB native heap and a40KiB SDK arena; see [memory layout](esp32.md#sram-layout).
- `--target esp32s3-xip-elf`: S3 cached-flash layout with96KiB IRAM,32KiB
  globals/vendor data,8KiB native heap and a120KiB SDK arena. Import
  `lib/platform/esp32s3-xip.flex` and link with `--xip`. IROM starts at
  `0x42000000`, DROM at `0x3c400000`; see [memory layout](esp32.md#sram-layout).
  Cache startup, C ABI and preemption pass stock QEMU. This does not initialize
  S3 PHY/controller memory or establish working S3 RF.
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

Original-chip applications import `esp32-sdk-task.flex`, `esp32-sdk-sync.flex`
and `esp32-sdk-timer.flex`. S3 applications use their `esp32s3-sdk-*` counterparts.
Both entry modules select their chip's timer/IRQ driver and share the
`esp32-sdk-*-core.flex` runtime implementations. Import entry modules directly;
the core files are internal implementation units. Task initialization rejects
an entry module for the other chip with -95 before creating runtime state.

Initialize the S3 SDK profile arena with
`esp_sdk_heap_init(0x3fcc6000,40960)`; the smaller `esp32s3-elf` uses
`esp_sdk_heap_init(0x3fcc8000,32768)`. Original plain `esp32-elf` can use
`esp_sdk_heap_init(0x3ffc8000,32768)`; its lower main-stack floor prevents using
the radio profile's96KiB arena. Arena bounds are checked against both the
selected heap region and active stack floor before writing any headers.

Radio lifecycle ownership is shared through `esp32-radio-lifecycle-core.flex`.
`esp32-radio-lifecycle.flex` selects the original69-source interrupt matrix;
`esp32s3-radio-lifecycle.flex` selects S3's99-source matrix. S3 now also exposes
`esp_irq_reserve(additional)` for masked multi-source registration preflight.
The ownership core restores saved routes and CPU enable bits, reaps exited
radio tasks, clears their thread-semaphore references, and frees only tagged
objects/timers while retaining application handlers and timer users.

Identical original/S3 firmware fixtures pass89 assertions each across eight
complete cleanup cycles, including MAC/power/end-source routes, a full IRQ
handler table and retained application state. Eight S3 defect controls, eight
original lifecycle controls and12 original C/IRQ publication controls pass;
the combined vendor suite passes1136 checks/46 stock-QEMU boots. Evidence is
in `build/esp32-backend-s3-radio/report.json`.

The S3 ownership entry module supplies domain services. The Wi-Fi/Bluetooth
vendor adapters and RF initialization remain under integration. The pinned
S3 OSI-v9 table is480 bytes, with no `_phy_common_clock_enable/disable` slots
and an added `_slowclk_cal_get` slot; the original484-byte table cannot be
reused. [S3 archive/bindings checksums](esp32s3-vendor-sha256.txt) identify the
upstream inputs. S3 ADC now imports the same analog ownership state and masks
its complete shared-register transaction. ADC2 rejects every API while a radio,
PHY or PHY-clock reference is active; ADC1 restores shared fields after each
read. Primary-header350829 checks/24 defects and native guard/deadline fixtures
pass. Actual ADC/radio overlap and analog values still need S3 hardware; see
[the ADC contract](esp32.md#esp32-s3-peripheral-adapters) and
`build/esp32-backend-s3-adc/report.json`.

Ticks are milliseconds; 0xffffffff means an indefinite wait. Timer 2 supplies
microseconds and is reserved by this runtime. Synchronization updates mask
interrupts; blocking operations cooperate through task yields. Yield, delay,
low-level task waits, self-deletion and software-timer polling reject a masked
caller or interrupt context with -16 before publishing task/deadline state.
`esp_sdk_can_block()` reports whether the caller is an ordinary unmasked task.
A semaphore/queue/event wait in a critical section or ISR performs one immediate
try without a deadline clock read: an unavailable semaphore or queue returns0,
and an unsatisfied event wait returns the current bits without clearing them.
Mutexes retain their ISR rejection; in a masked task, an available/recursive
mutex can be acquired immediately and an unavailable one returns0. Deleting a
different task remains possible under the mask for native service teardown.
Raw Wi-Fi and Bluetooth lifecycle calls also reject masked entry before vendor
C work. Timer callbacks remain task-context operations.

Firmware starts with interrupts masked. After setting up its runtime and any
required IRQ ownership, an application must explicitly call `esp_irq_enable()`
(or `esp32_irq_restore(0)`) before yielding, blocking or entering radio lifecycle
calls. SDK initialization never silently unmasks an existing critical section.
The legacy cooperative fixtures and vendor/NVS probes now make this startup
transition explicit. Radio event hooks remain bounded/nonblocking; attempts to
switch or block from their masked context cannot expose the borrowed payload
view to another task. Existing QEMU tests cover54 independent C cases at
INTLEVEL1/3/15, exact TCB/object preservation, real peer nonexecution, IRQ/hook
entry, immediate operations and ordinary wakes. Nineteen isolated defects verify
those checks; no physical radio behavior is established by them.

Zero-timeout
and ISR queue operations avoid clock reads and division, with bounded wrap
arithmetic and arbitrary byte-sized queue items. The pinned radio adapters pass
an optional one-byte boolean wake flag. ISR operations accumulate this flag:
a previous true value stays true, null pointers are supported, and failure or
semaphore-take paths leave it unchanged. Successful semaphore give and queue
send/receive request scheduling independently of whether a flag was supplied.

For a false flag, a matching blocked higher-priority waiter can set it true.
The query uses bounded task-graph scans with scratch priorities at TCB offset
632, preserving exact effective priorities at offset 624. It performs no clock
read, allocation or task switch. Inheritance and pending timeout expirations
can produce a conservative extra request: the waiter's possible priority is an
upper bound and the current base priority a lower bound. The IRQ-return
scheduler then checks current time and exact inherited priorities. The flag is
a request to reconsider scheduling, not a promise that a switch will occur.
This follows the pinned adapter's bool/request contract, rather than assuming
a FreeRTOS `BaseType_t` output. See the
[pinned Bluetooth ABI](https://github.com/esp-rs/esp-hal/blob/0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7/esp-radio/src/ble/btdm/os_adapter_esp32.rs)
and [wake-request contract](https://github.com/esp-rs/esp-hal/blob/0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7/esp-radio-rtos-driver/src/wait_queue.rs).

The wake fixture verifies 448 guarded C calls with aligned/unaligned booleans,
null/previously-set flags, operation failure and inherited-priority cases. A
separate phase wakes three real blocked tasks from timer ISRs before the next
scheduler tick. The independent graph oracle runs 47,866 checks with nine
defect controls; eight emitted-firmware controls detect clearing, wide stores,
lost hints and missing IRQ-return requests. These tests use existing QEMU and
establish neither physical interrupt latency nor preemptive radio RF behavior.

The single-core scheduler selects the highest-priority ready task at each
yield or blocking operation. Priorities range from 0 to 24; main starts at 0.
Equal-priority tasks rotate. `esp_sdk_task_get_priority(task)` reads the base
priority and `esp_sdk_task_set_priority(task,priority)` changes it; task 0 selects
the current task. Invalid handles or priorities return -22 without mutation.
The setter rejects ISR use. Lower-priority ready tasks do not displace a
higher-priority task merely because it calls `esp_sdk_yield()` or delay 0.

Semaphore, queue, event and mutex waits publish a blocked predicate and deadline.
Blocked tasks do not compete with the task that must satisfy their wait. The
scheduler rechecks predicates under the interrupt mask, including an IRQ that
arrived between the failed operation and publication. Device interrupts stay
enabled during an ordinary idle wait. Mutex waiters donate effective priority
through owner chains; each selection recomputes donations so release, timeout
and task deletion remove stale inheritance. Recursive depth retains ownership
until the final unlock. Waited-on objects must remain valid until their waiters
have exited, and tasks must release their owned mutexes before returning.

Scheduling is cooperative by default. Original ESP32 imports
`lib/platform/esp32-sdk-preempt.flex`; S3 imports
`lib/platform/esp32s3-sdk-preempt.flex`. Call
`esp_sdk_preempt_start(quantum_us)` after initializing the SDK task runtime.
Quanta range from 1,000 to 1,000,000 microseconds. Enable interrupts separately
with `esp_irq_enable()`. The driver leases idle Timer 3 and interrupt source19 on original ESP32 or54
on S3;
an active timer, pending timer interrupt or existing handler returns -16 before
changing ownership. Timer 2 remains the SDK clock. `esp_sdk_preempt_stop()`
restores the stopped timer's counter/configuration, alarm/load words, route and
owned interrupt-enable state. Repeated start/stop reuses its native save buffer.
ISR use is rejected. The timer is rearmed with a future one-shot deadline, so a
long masked section cannot leave the next alarm behind the current counter.
Missed quanta are not replayed.

Once preemption is enabled, a newly created higher-priority task can run before
`esp_sdk_task_create()` returns. A busy worker can then starve its creator.
Construct mutually dependent peers and publish their shared handles under one
short saved interrupt mask, then restore the mask after setup. The preemption
fixtures use this setup transaction; their C busy loops still run unmasked.

A tick or successful synchronization wake requests selection at interrupt return.
An ordinary device ISR can therefore wake a higher-priority task before the next
tick. ISR callbacks finish before any task switch; `esp_sdk_yield()` remains
forbidden inside callbacks. CPU-bound tasks can be interrupted without calling a
yield function. Interrupt masks defer preemption; this provides no measured hard
real-time latency guarantee. The IRQ tail returns to the interrupted idle wait
when every task is blocked, allowing other device IRQs to satisfy their waits.

This requires the compiler's `esp32_preempt_supported()` intrinsic (returns 1 on
ESP32 targets). A named one-argument `esp_irq_epilogue(interrupted_ps)` function,
when present, becomes an IRAM interrupt-return hook; it requires
`esp_irq_dispatch`. The compiler invokes it after ISR depth reaches zero, with
interrupts masked and the complete exception frame retained on the interrupted
task's stack. Its reachable native functions are placed in IRAM for cached-flash
firmware. The scheduler uses the full task context, preserving windowed C
registers, loop/SAR state, FPU state and thread pointers across a suspended IRQ
return. C-calling IRQs also preserve the interrupted THREADPTR independently of
whether preemption is enabled.

The RAM busy-task probe and cached GNU C/assembly stress test pass existing
Espressif QEMU. The stress test covers recursion depths 0/16/40, all 16 FPU
registers, live hardware loop registers, an ISR that clobbers floating-point and
thread state, immediate semaphore wake, all-blocked waits and timer restoration.
Five isolated defect controls reject missing switches/restores/wakes and a stale
alarm. The complete C stress matrix also passes on S3 with
`esp32s3-sdk-elf`, without removing assertions or recursion cases. S3 tests also
exercise the smaller RAM busy-task profile, the512-operation allocator churn
matrix, cooperative synchronization and software-timer callback deletion.
The combined vendor suite passes1089 checks/44 ROM boots; separate memory and
header checks cover five profiles, S3 timer routing and12 rejection/defect
controls. Masked-call, lifecycle, C-wake and compiler-context defect controls
remain part of the regression evidence. These checks use unchanged Espressif
QEMU and do not establish physical timing or preemptive Wi-Fi/Bluetooth RF
operation. The saved report is `build/esp32-backend-s3-sdk/report.json`.

Domain begin/ready/end, software-timer service creation/destruction, radio task
ownership/handle publication and allocation tagging now hold the CPU0 interrupt
mask throughout each transition. Wi-Fi/Bluetooth facade admission claims are
also atomic; they restore the caller's mask before invoking vendor setup or
teardown. These are single-core protections; they do not implement CPU1 locking.
A separate lifecycle fixture exercises 32 lifetimes with exact heap recovery.
An isolated source-copy test raises a real software IRQ at each publication
window: all 32 protected cases pass, and eight individually unprotected controls
fail. A GNU C lifecycle peer rejects vendor calls made with interrupts masked.
Its own deliberately masked-call control fails as expected.

Original-ESP32 radio ISR registration now publishes callback, argument, owned
routes and handler-table entries under one interrupt mask. Multi-source Bluetooth
registration checks both sources and table capacity before changing any binding.
An application handler cannot be overwritten even when a domain previously
claimed its source. Capacity/ownership failures preserve bindings, claims,
routes and CPU enables; native allocation exhaustion is covered separately.
Radio enable-mask updates also preserve unrelated enables changed by an IRQ.

An independent C argument guard observes 28 forced software-IRQ publication
windows. The external Wi-Fi/Bluetooth cases use a software observer to inspect
the published pairs; they do not claim radio hardware delivery. Bluetooth's
software path uses its actual native dispatcher. All 28 protected windows pass;
twelve isolated defects expose mixed pairs, lost enable bits, dropped pending
events and partial registration. On original ESP32 and S3, replacing an existing
software handler preserves its pending event; first installation clears stale
unowned state. Both chips separately pass 64 exact deliveries/rejections, and
both dropped-pending controls fail. This remains single-core behavior.

The broader radio concurrency audit and physical verification remain T402/T157.
The pinned ISR wake-result ABI is covered by T407. Radio examples retain their existing
cooperative startup. Successful software lifecycle checks do not establish
preemptive Wi-Fi/Bluetooth RF operation.

The deterministic lifecycle test uses the existing QEMU executable without
changing its instruction or peripheral models:

```sh
flexscript scripts/test-esp32-preempt.flex -o build/test-esp32-preempt
python3 tests/esp32/lifecycle-preempt-reference.py \
  --compiler /path/to/current-esp32-compiler --driver build/test-esp32-preempt \
  --prefix /path/to/xtensa-esp32-elf- --qemu /path/to/qemu-system-xtensa \
  --work build/lifecycle-controls
```

Use a fresh work directory to retain earlier logs and firmware. Optional
`--before /path/to/saved-repository-root` tests pre-fix function bodies instead
of removing the corresponding critical section from current source.

Deleted task memory must be reclaimed from another task with
`esp_sdk_task_reap`; handles/waiters must no longer be used.
`esp32-sdk-timer.flex` runs software timer callbacks in an 8 KiB task, supports
one-shot/repeating timers, callback deletion/rearming and zero-delay arming.
`esp32-radio-os.flex` implements the pinned 121-field Wi-Fi OSI table; the
Bluetooth adapter implements the 63-field OSI table. Both reuse the native
heap/tasks/synchronization services and route hardware/software interrupts.
The shared PHY adapter retains calibration data and configures combo-module
PHY initialization; Wi-Fi explicitly enables its RX path. PHY reference/clock
updates, calibration/wakeup/close, Wi-Fi RX transitions and final buffer release
share a saved interrupt mask on the original chip. This follows the pinned
[PHY state lock](https://github.com/esp-rs/esp-hal/blob/0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7/esp-phy/src/lib.rs)
and its [interrupt-masking mutex](https://github.com/esp-rs/esp-hal/blob/0f0ebd92bc76d351092fe4f4f1b7ddd7bca7bfa7/esp-sync/src/lib.rs).
Callers must balance their PHY references and any independent clock guards.

`esp_radio_phy_buffers_init()` prepares the 1904-byte calibration buffer and
128-byte initialization data as a pair. Failure returns -12 and restores the
arena without acquiring clocks or publishing either pointer. Preparation is
idempotent; it does not mark the PHY calibrated. Wi-Fi prepares this pair before
vendor initialization, whose void PHY callback cannot report allocation failure.
Bluetooth checks the direct enable result before recording its PHY ownership.
The first successful enable calibrates; later zero-to-one transitions wake with
the retained data. `esp_radio_phy_result` retains the vendor calibration result
as a diagnostic value. Final release rejects outstanding PHY or clock references
with -16, then frees both buffers and clears the calibration state. The controller
must already be quiescent before this release.

The independent C PHY peer checks all initialization bytes, retained calibration
bytes, nested masks, reference balance and actual software-IRQ deferral during
vendor calls. Six forced transaction windows and sixteen isolated defects cover
these transitions, allocation rollback and clock masks. Existing QEMU reads the
original PHY clock register as zero; a copied-firmware operand probe targets a C
word to verify mask preservation. This is software evidence, without physical
clock-gating or RF verification. Scan-done events record completion/status.
This is not a general application event queue.

Radio event publication now holds one saved interrupt mask across the event
count, last-event identifier, scan status/completion and hook invocation. A peer
can observe either side of that transaction. Scan completion with a missing or
short payload retains status -1. The hook's `esp_radio_event_data` and
`esp_radio_event_size` are borrowed only for its duration. Nested posts restore
the outer payload view before it resumes; event count, last-event and scan
state retain the newest publication. Events without a hook still update those
globals. Hooks must remain bounded and nonblocking, and callers' interrupt
levels are restored exactly. Both C posting entry points share this path.
An independent C producer/observer verifies ordered concurrent posts, nested
payloads, null/short scan data and interrupt levels0/3/15. Three forced
publication windows and twelve isolated defects pass on existing QEMU. This
establishes software publication behavior, without physical RF verification.

The Wi-Fi packet bridge now pins native RX consumers, whole receive/free
callbacks and concurrent TX C frames against lifecycle changes. Packet copies
run unmasked; ring construction, admission and FIFO publication are atomic.
Stop/deinit retain allocations and return -16 while a packet lease is active,
including an RX-free callback that outlives vendor stop. The independent C
rendezvous, ten forced windows and seventeen defects are described with the
[network packet APIs](esp32-network.md). Connection-physical radio verification and the wider scheduler/radio audit remain
outstanding.

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
storage. A submission lease covers the availability query, packet copy and
return from the vendor send function. An early readiness callback clears the
in-flight flag while the C frame keeps its lease, so another task cannot reuse
its packet buffer prematurely. Both vendor calls run with interrupts unmasked,
as required by the [pinned VHCI API](https://github.com/espressif/esp-idf/blob/v5.5.1/components/bt/include/esp32/include/esp_bt.h).
Concurrent TX returns -11; lifecycle ownership, ISR use and callers already in a
critical section return -16. Readiness does not replenish HCI ACL credits.
Transport construction, allocation rollback, callback validation/copy and final
release are atomic with respect to single-core task preemption. Release and
controller stop reject an active submission. Callbacks arriving after release
are ignored.

Only one ordinary HCI command may own admission and its response buffer.
A submitted command that times out returns -110 and retains a quarantine token;
new ordinary commands and transport release return -16 until its late response
arrives or controller teardown succeeds. The late response enters the async
event queue and clears the token, including when that queue is full. A reply
received before submission cannot satisfy the waiting command. Command credits
are rechecked at submission. Host Number Of Completed Packets (opcode 0x0c35)
uses the raw packet API without ordinary command credits; the ordinary command
API rejects that opcode with -22. Its Complete/Status events leave those credits
unchanged. Scalar command status is captured before releasing admission.
The legacy `esp_bt_rx` response view still needs a single coordinated consumer,
since a later command or legacy event read can replace it.

An independent C VHCI peer verifies borrowed packet identity across actual timer
preemption, early readiness, unmasked vendor calls, timeout recovery and heap
recovery in existing QEMU. Five forced transaction windows and sixteen isolated
defect controls cover admission, callback lifetime, quarantine and scalar status.
These software checks do not establish physical preemptive RF operation.
See [native BLE host](esp32-ble.md) for the core and ownership rules.

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
S3 SDK task/synchronization/timer/preemption services and its C ABI now pass
software verification. S3 PHY, controller memory/cache layout, radio adapters
and physical S3 radio verification remain work.

## Priority scheduling verification

`tests/esp32/sdk-priority-reference.py` exercises the canonical selection policy
against an independent wait-for-graph oracle: 77,282 checks over 4,877 cases and 12
defect controls cover priority ordering, peer rotation, delays, blocked-object
predicates, timeout boundaries, chained donation and stale-inheritance removal.
`tests/esp32/sdk-priorities.flex` executes actual emitted Xtensa firmware in the
existing Espressif QEMU test setup. It verifies task order, all blocking kinds,
recursive-mutex inheritance, an IRQ waking the sole blocked task, exact heap
recovery and FPU/thread-state preservation across context switches.

The complete priority and radio-resource fixtures use cached flash because the
expanded combined tests exceed 128 KiB of IRAM. RAM runtime/context/task/timer/queue
fixtures remain in the vendor-link suite; target memory bounds are unchanged.
These tests establish software behavior, not physical radio or power behavior.
Physical repeat awaits the original ESP32 USB connection.

## Verification

```sh
flexscript scripts/test-esp32-link.flex -o build/test-esp32-link
build/test-esp32-link --compiler /path/to/flexscript \
  --qemu /path/to/qemu-system-xtensa \
  --prefix /path/to/xtensa-esp32-elf- \
  --work build/esp32-sdk-verification --report build/esp32-sdk-verification.json \
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
