# ESP32-C3 and C6 RISC-V targets

`esp32c3` and `esp32c6` emit RV32IM machine code directly from the shared word
IR. They package two SRAM segments in an Espressif ROM image. The matching
`esp32c3-elf` and `esp32c6-elf` targets emit ELF32 executables with symbols, SRAM profile metadata and
optional vendor import slots for the explicit linker tool. The compiler invokes no assembler, linker or SDK build.
The firmware contains no interpreter, Linux runtime or RTOS. The explicit
`esp32c3-xip-elf` and `esp32c6-xip-elf` targets additionally support cached native
and vendor code through the linker profile described below.

T164 remains partial C3/C6 platform support.
The released official QEMU binary used for C3 has no C6 machine. An unmodified
build of official Espressif commit `febae182e132e4055529be423a818225ebddaa3a`
executes C6 ROM boots, native runtime, ILP32 calls, task contexts, static TLS,
cached-flash, newlib/ROM stdio, atomic and interrupt/preemption checks. Other C6 adapter and radio families retain separate
package, primary-header or model evidence.
Neither physical board has been verified by this implementation.

```sh
flexscript compiler/main.flex -o build/flexscript-riscv
build/flexscript-riscv --target esp32c3 examples/esp32c3-uart.flex -o build/c3.bin
build/flexscript-riscv --target esp32c6 examples/esp32c6-uart.flex -o build/c6.bin
```

The raw ROM images belong at flash offset `0x0`, replacing the ordinary
second-stage bootloader. Compilation and tests do not flash a physical device.
There is no partition table, OTA/rollback strategy or secure provisioning in
these initial profiles. UART0 retains the ROM's pin routing, clock and baud;
native USB Serial/JTAG is not initialized as this target's console.

## Language and calling convention

All word arithmetic remains 64-bit: wrapping add/subtract/multiply, bitwise
operators, signed comparisons, arithmetic right shift, six-bit shift masking,
and signed division/remainder truncating toward zero. Division by zero and
`MIN / -1` or `MIN % -1` fail-stop. Bytewise unaligned `load64`/`store64` preserve
the full word. Both stores return their complete input word.

The private convention uses a0:a1 for values, s0 for the frame, ra for returns
and eight-byte stack arguments. C interoperability uses separate ILP32 bridges. Named one-argument
`esp32_callback`/`esp32_call` callbacks use this same convention. Ordinary calls,
recursion, globals, strings, compacted locals, SetaScript, saved FIR, external
frontends and trusted `--platform` initialization use the existing compiler.
Only reachable functions enter the output.

`esp32_callback32(fn)` and `esp32_iram_callback32(fn)` return C-callable thunks
for a function with exactly eight parameters. Each C `uint32_t` argument becomes
a zero-extended Flexscript word; the full word result returns as C `uint64_t` in
a0:a1. They follow the selected SRAM or cached placement policy below.

`esp32_call32(ptr,a,b,c,d,e,f,g,h)` passes the low 32 bits of eight arguments in
a0..a7 and zero-extends the C result. `esp32_call64` retains both result registers.
Use these APIs for an eight-word ILP32 signature; larger values and structures
must be passed through explicitly laid-out memory or wrappers. The bridges align
C stacks to 16 bytes, preserve callee-saved registers and carry interrupt-mask
changes made by C or callbacks. Private stack descent is checked; arbitrary
vendor C code must manage its own stack use. The convention follows the
[RISC-V integer ABI](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/#_integer_calling_convention).

Local frames retain at most 2,048 read slots (16 KiB). Unread stores are omitted
while their expressions still execute. Stack descent is checked on function
entry and expression pushes. `alloc` is an eight-byte-aligned, zeroing bump heap, 32 KiB in the default
profile and 16 KiB in the radio profile; zero requests return -22, invalid/exhausted requests return -12.
Pointers carry 32-bit physical addresses in 64-bit words; a nonzero high word
traps before memory or indirect callback access.

Supported hardware intrinsics are `esp32_load32`, `esp32_store32`,
`esp32_cycles`, `esp32_halt`, `esp32_state`, `esp32_callback`, `esp32_call`,
`esp32_irq_save`, `esp32_irq_restore`, `esp32_irq_pc`, `esp32_wait`, the C call/
callback bridges above, `esp32_switch`, `esp32_preempt_supported` and
`esp32_external("symbol")` in ELF link targets.
IRQ save/restore carries RISC-V **mstatus**, and IRQ PC reads **mepc**.
These values are architecture-specific. Startup masks interrupts; synchronous
faults record a fail-stop marker. The matching `-irq.flex` module installs the
vectored peripheral dispatcher. `esp32_irq_pending`, `esp32_irq_mask`,
`esp32_irq_enabled`, `esp32_irq_raise` and `esp32_irq_clear` use CPU-line bitmaps.
Line0 is disconnected; software raise/clear accept bit7 or zero, with zero a
no-op. Unsupported bits or high pointer/mask words fail-stop. Linux syscall/FFI
requests reject compilation. Radio and wider peripheral adapters remain open.

## Linking explicit C objects and archives

`esp32_external("symbol")` records an eight-byte pointer slot. The ELF exports
C callback thunks and globals, plus undefined import symbols. The linker converts
these slots to `R_RISCV_32` relocations and resolves explicit objects/archives or
ROM symbol scripts. Raw ROM targets reject reachable imports; unused functions'
imports do not require a definition. The tool never fetches vendor libraries.

```sh
build/flexscript-riscv scripts/esp32-link.flex -o build/esp32-link
build/flexscript-riscv --target esp32c3-elf app.flex -o build/app.elf
build/esp32-link --firmware build/app.elf --archive vendor.a \
  --ld /path/to/riscv32-esp-elf-ld \
  --output build/linked.elf --image build/app.bin --map build/app.map
```

The default RISC-V linker is `riscv32-esp-elf-ld` from PATH; `--ld` can select an
installed GNU linker or LLVM LLD. The tool disables relaxation, groups archives,
checks the chip/architecture/layout and bounds code and static data below the
native heap and stack. C3 instruction/data aliases share the same bounds.
`.bss` is included as zeroed ROM data; `.srodata` is retained in the data segment.
Failed linking preserves existing ELF/image/map destinations and rejects output
aliases, including hard links.

These SRAM profiles support explicit freestanding ILP32 C integration and
static TLS. They do not initialize an ESP-IDF scheduler, C++ constructors, cached
flash or radio reservations. A plain SRAM ELF cannot become a cached image by
adding `--xip`; use an explicit XIP compiler target. Use C compiled
without gp-relative small-data assumptions, such as `-msmall-data-limit=0`; gp/tp are
preserved across calls and task switches. Static TLS initializes tp as described
below; vendor-library and SDK startup acceptance remain separate gates.

## Cached native and C code

Import `lib/platform/esp32c3-xip.flex` or `esp32c6-xip.flex`, compile with the
matching `esp32c3-xip-elf` or `esp32c6-xip-elf` target, then link with `--xip`.
Pass the same explicit C objects, archives or ROM symbol map used by the
application. Startup calls `esp_xip_enable()` from SRAM before platform/main,
checks its result and executes `fence.i` before entering cached code. The
adapter initializes the ROM cache/MMU and SPI0 interface from the pinned IDF
boot configuration. Repeated initialization, ISR use, enabled interrupts,
invalid chip identity and invalid page layout are rejected before remapping.

| Region | C3 virtual address | C6 virtual address | Bound |
| --- | --- | --- | --- |
| Native ordinary code and linked C text | `0x42000000` | `0x42000000` | 3 MiB |
| Linked C constants and small rodata | `0x3c400000` | `0x42400000` | 3 MiB |
| Startup, IRQ entry and native IRAM closure | existing SRAM code base | existing SRAM code base | unchanged 128 KiB |

Both mappings use 64 KiB pages. Constants start at virtual page64 so they cannot
overwrite the instruction translations. C6 shares its instruction/data address
window and uses the seven-argument ROM MSPI mapper; C3 uses separate six-argument
instruction/data mapper entries. The explicit layout keeps physical code at
flash offset `0x30000`, followed by page-aligned constants, within a 4 MiB image.
Static data, TLS, native heap, SDK arena and stacks retain the existing SRAM
layout. The combined RAM payload and ROM headers must fit before offset
`0x30000`; oversized combinations reject before replacing any output. ELF TLS/GOT sections are assigned before switching the linker location
to cached windows.

Native functions marked through `esp32_iram_callback` or
`esp32_iram_callback32`, their direct calls and named function references stay in
SRAM. IRQ dispatch and epilogue are additional roots. All shared machine helpers
also remain in SRAM, including helpers used only by flash functions. Ordinary
native functions and C thunks use their actual cached addresses for direct
calls, branches and function pointers. Task context validation accepts either
the bounded SRAM code region or the cached instruction region. Dynamic external
C pointers retain the caller's placement contract: cache-disabled C code and
its constants must use suitable `.iram1`/`.dram1` sections.

The stock C3/C6 suite checks over 224000 bytes of generated native flash code, a C
function spanning multiple pages, every byte of a 143373-byte constant array,
bidirectional callbacks and software IRQs during ROM cache-disabled intervals.
Six C build modes additionally cover actual ROM tasks under timer preemption
and linked integer/64-bit/floating-point formatting. Cached TLS tasks reclaim
the exact heap; a Seta platform initializer verifies TLS and cache readiness
before main. The independent image peer compares appended cache bytes and
padding against ELF sections. The ROM SHA checks only the SRAM image;
appended cache bytes have no secure-boot signature in this format.

C6 executes these cached-flash cases with the explicit official QEMU option.
Physical flash timing, board pin configuration and radio-controller memory
reservations remain open. This profile is a prerequisite for actual vendor
radio startup, not a claim that radio startup is complete.

## Radio memory and atomic prerequisites

`esp32c3-radio-elf` and `esp32c6-radio-elf` are explicit cached profiles with a
128 KiB SDK arena. Import the matching `-xip.flex` module and link with `--xip`
as above. The target selects memory capacity; full vendor Wi-Fi/BLE/PHY startup
is still unfinished. This profile does not initialize radio hardware.

| Region | C3 radio | C6 radio | Capacity |
| --- | --- | --- | --- |
| Startup, IRQ and IRAM closure | `0x40380000..0x40390000` | `0x40800000..0x40810000` | 64 KiB |
| Control/globals/TLS | `0x3fc90000..0x3fc98000` | `0x40810000..0x40818000` | 32 KiB |
| Native bump heap | `0x3fc98000..0x3fc9c000` | `0x40818000..0x4081c000` | 16 KiB |
| SDK arena | `0x3fc9c000..0x3fcbc000` | `0x4081c000..0x4083c000` | 128 KiB |
| Main stack | `0x3fcbc000..0x3fcc4000` | `0x4083c000..0x40844000` | 32 KiB |
| IRQ stack | `0x3fcc4000..0x3fcc8000` | `0x40844000..0x40848000` | 16 KiB |

Cached code/constants retain the XIP windows and flash bounds above. The early
mapper binds the chip adapter to the selected data, TLS and buffer limits before
platform/main. A mismatched chip wrapper rejects startup. Use
`esp_sdk_heap_min()` and `esp_sdk_heap_max()` to initialize the selected SDK
arena. The linker independently checks exact profile metadata and physical C3
instruction/data alias overlap. Task resume PCs, native allocations and both
startup/task TLS validation use the selected capacities.

Primary IDF SRAM definitions, reserved ROM bounds and every exported RAM symbol
in the pinned C3/C6 ROM maps are checked against these ranges. These checks do
not establish the controller's complete hidden allocation requirements. Actual
C3/C6 tests allocate and verify 120000 SDK bytes while retaining a separate 16 KiB
native guard, exercise cached TLS/stdio/ROM tasks, and reject task execution
from a heap instruction alias. C6 uses the explicit official QEMU option.

Import `esp32c3-atomics.flex` or `esp32c6-atomics.flex` and call
`esp_atomics_bind()` before linking C users of these four GNU libatomic exports:

- `__atomic_exchange_4`, `__atomic_fetch_add_4`, `__atomic_fetch_sub_4`.
- `__atomic_compare_exchange_1` with the five-argument library ABI (the C
  compiler consumes the source operation's `weak` argument).

These helpers implement all requested memory orders with sequentially consistent
single-CPU IRQ exclusion and full fences. They preserve the full incoming
mstatus in tasks, masked regions and interrupts; byte CAS updates `*expected`
on failure and preserves adjacent bytes. Word pointers must be aligned and all
operands must lie in application SRAM after the control prefix. Invalid pointers
fail-stop before mutation. The binder keeps the helper thunks and complete
native call closure in IRAM, including for cache-disabled callers. C callers
running with the cache disabled must also place their own code/constants in RAM.
This supplies four required exports, rather than a complete C11 atomic library;
it does not synchronize DMA or another CPU.

The acceptance inputs pin `esp-rs/esp-wifi-sys` revision
`5afc3a38cc1abcd463e3b5140f0ac742de44053f`, the same vendor revision used by the
existing Xtensa path. The runner verifies all 28 C3/C6 archives and the GNU14.2
size-specific ABI sources. No Rust runtime is added. It extracts the actual WPA
`eloop.c.obj`, exposes three private lifecycle symbols without changing allocated
section bytes, and exercises its lock/unlock across preempting tasks. Six C
build modes also cover edge arithmetic, byte CAS, saved mstatus, interrupt
contention, exact task reaping and cache-disabled calls. A directed real C3 IRQ
and deliberately broken copies detect a missing mask, wrong old value, wrong
mstatus restore, missing expected update and adjacent-byte corruption.
The OSI table and native chip-policy work below extend these prerequisites;
complete vendor startup and physical RF acceptance remain under T529/T501.

## Pinned radio OSI integration

Import `esp32c3-radio-os.flex` or `esp32c6-radio-os.flex` from `lib/platform/`
under the matching radio target. Initialize the selected SDK arena, then call
`esp_libc_stdio_init()`, `esp_libc_rom_init()` and `esp_sdk_task_init()` in that
order. `esp_radio_os_init()` builds the OSI table after these prerequisites.
A missing libc/ROM initialization returns `-19` and preserves the table, owner,
timer state and available SDK heap. Reinitialization and ISR use reject.

The C3 v9 table has 120 fields/480 bytes; C6 has 127 fields/508 bytes. Both use
NVS offset268. All offsets and sizes are checked against the pinned primary C
header and generated vendor ABI. Common callbacks reuse the existing SDK tasks,
allocator, synchronization, events and timers. The radio uses the initialized
RISC-V newlib exports; Xtensa keeps its previous allocator/console exports in a
separate module. Timer/table publication and allocation-failure cleanup remain
one masked transaction.

MAC0 and PWR2 share the vendor ISR/argument. The adapter publishes both sources
only after checking ownership and reserving space for the complete pair.
Masking their routes leaves the shared CPU interrupt enabled for other users.
An enabled raw source route can belong to a C/ROM user even when the native
handler table has no entry; registration/masking rejects that route before
changing the callback, route or CPU mask. C3 firmware checks the protected pair
through a real software IRQ, source-capacity failure, foreign handler/raw-route
refusal and exact resource cleanup. Radio pending-bit dispatch additionally has
primary-header model checks for both controllers.

Native C3 power/clock setup, chip RNG/MAC/slow-clock reads and PHY buffer/call
sequencing follow the pinned IDF/esp-hal references. PHY initialization uses a
1904-byte calibration record and the chip's 128 default init bytes; C3 additionally
backs up/restores 84 digital-register bytes across close/wakeup. Native policy
models check partial-allocation rollback, reference counts, calibration arguments,
clock-field preservation and reuse. The vendor PHY functions are linked, but
these models use explicit call stubs and do not perform real calibration or RF.
The C6 hardware initializer currently returns `-95` before writes: HP/LP modem
base clock/power setup is still T536. Its PHY-policy model explicitly injects a
ready state; no production startup path claims that state.

Use these OSI tables for standalone Wi-Fi with coexistence and modem/light
sleep disabled. C6 reports that disabling 11ac/11ax is unsupported (`false`), and its disabled MAC/BB
retention callbacks return1 as required by the pinned driver. The two unported
REGDMA/retention-link callbacks fail-stop if invoked. These tables do not supply
the remaining sleep/coexistence implementation.

The explicit builder accepts local pinned inputs:

```sh
build/flexscript-riscv scripts/build-esp32-radio.flex -o build/build-radio
build/build-radio --chip esp32c3 --kind wifi \
  --compiler build/flexscript-riscv \
  --vendor /path/to/pinned/esp32c3/archives \
  --rom /path/to/pinned/esp32c3/rom/scripts \
  --libc /path/to/pinned/libc.a --libgcc /path/to/pinned/libgcc.a \
  --ld /path/to/riscv32-esp-elf-ld --nm /path/to/riscv32-esp-elf-nm \
  --source examples/esp32c3-vendor-probe.flex --output build/c3-probe.bin
```

Use `esp32c6` and its corresponding probe/inputs for C6 packaging. C3/C6 require
an explicit source while full radio startup is being integrated; Bluetooth and
TLS vendor builds reject. The probe initializes the OS table, executes the actual
vendor MAC pre-init guard and WPA byte conversion, then reclaims its resources.
It does not initialize RF. C3 executes this probe through stock ROM; C6 has
package checks only.

The builder checks all 14 archives and every chip ROM map against the inventories
under `docs/`, plus the exact newlib/libgcc hashes used by the runtime ABI. It
creates architecture-correct writable `WIFI_EVENT`/`g_wifi_osi_funcs` objects,
filters ROM aliases against defined firmware/archive symbols and uses `PROVIDE`
for remaining aliases. This prevents ROM assignments from replacing native libc
state or the linked C library. The source, tool, archive, inventory and output
alias checks run before publication; linking preserves existing ELF/image/map
outputs on failure. `esp32-data-object` defaults to the original Xtensa bytes;
`--arch riscv32` selects ELF machine243. No input or compiler is downloaded.

The typed C3 suite covers six C build modes, NVS slots, allocator/queue/semaphore/
event/timer/time callbacks, initialization failures and cleanup. C6 layouts also
have a native table-construction model whose callback addresses are explicitly
instrumented IDs. C6 now executes radio IRQ ownership, newlib-order, analog-domain
refusal guards and the actual vendor MAC-preinit/WPA probe. Its six full typed
OSI modes still require the missing LP_AON STORE1 model described below. Other
C6 runtime/cache families execute separately. Real PHY/calibration/RF, complete
vendor startup, hidden controller memory and physical acceptance remain open
under T529/T531/T536 and T499.

## Cooperative tasks and the shared SDK core

Import `lib/platform/esp32c3-sdk-sync.flex` or `esp32c6-sdk-sync.flex`; the
matching `-sdk-timer.flex` entry adds software timers. These wrappers use the
same priority scheduler, allocator, wait predicates, queues, semaphores, mutexes
and timer core as the Xtensa targets. Only architecture state, initial frames
and the monotonic clock differ.

Initialize the SDK arena at `0x3fcb8000` for C3 or `0x40848000` for C6, size
32 KiB, then call `esp_sdk_task_init()` and `esp_sdk_task_unmask()`. Startup
leaves MIE clear; blocking/yielding requires ordinary task context with MIE set.
The scheduler leases TIMG1 timer0, uses a 40 MHz XTAL divided by 40, and polls
a 54-bit microsecond counter. This profile requires a 40 MHz crystal. An active
timer, enabled timer IRQ or pending timer event rejects initialization; failed
initialization releases its TCB. This clock does not enable peripheral IRQs.

`esp32_switch(from,to)` switches between 16-byte-aligned 512-byte contexts in
bounded SRAM. It preserves private frames, C callee-saved registers, gp/tp,
mstatus and the task's stack floor; it returns zero on resume. Caller-saved
registers are scratch. A self-switch consumes its arguments and returns zero.
Pointers, nonoverlapping context areas, target PC, SP and stack-floor bounds
are checked before saving the old context. Switching from an ISR fail-stops.

| Context field | Byte offset | Width |
| --- | --- | --- |
| ra, sp, gp, tp | 4, 8, 12, 16 | 32 bits each |
| s0, s1, s2..s11 | 32, 36, 72..108 | 32 bits each |
| Resume PC | 256 | 32 bits |
| mstatus | 272 | 32 bits |
| Stack floor | 304 | 32 bits |
| SDK newlib record pointer (SDK contexts only) | 320 | 64 bits |

The shared TCB still occupies 640 bytes and its scheduler fields retain their
existing offsets after byte 512. Fresh SDK tasks start with zero gp, a task-owned
TLS instance when linked TLS exists, and a private stack frame for the common task entry. Saving/restoring tp
is verified across C yields. Vendor-library startup remains separate work.
`esp32_preempt_supported()` returns one when the dispatcher and scheduler IRQ
epilogue are linked; without both hooks it returns zero.

The compiler shares checked push, word-operation and hardware-intrinsic machine
helpers across reachable code. This allows the complete shared SDK regression
program, including allocator churn, to fit the 128 KiB code region. Every
expression push and function entry still checks the selected task's stack floor.
All RISC-V helpers remain in SRAM. Xtensa's checked push helper also stays in
SRAM for callbacks and cached code.

## Dynamic newlib locks

Import `lib/platform/esp32c3-libc-locks.flex` or `esp32c6-libc-locks.flex` and call
`esp_libc_locks_bind()` to export the dynamic lock callbacks for explicit C
linking. These wrappers include the chip platform and SDK synchronization core.
Initialize the SDK arena before explicit lock initialization; initialize/unmask
the task scheduler before using locks for task exclusion.

The [pinned ESP-IDF declarations](https://github.com/espressif/esp-idf/blob/v5.5.1/components/newlib/platform_include/sys/lock.h)
and [newlib adapter](https://github.com/espressif/esp-idf/blob/v5.5.1/components/newlib/src/locks.c)
define two different ABIs. Legacy `_lock_*` calls take a pointer to a four-byte
handle slot. `__retarget_lock_init*` also take that slot, while the other
`__retarget_lock_*` calls take the handle value. The module exports normal and
recursive init/close/acquire/try-acquire/release for both interfaces. Successful
try-acquire returns zero; contention returns C `-1`. Callers must use the same
normal/recursive interface throughout a lock's lifetime.

Explicit init overwrites an uninitialized slot with a newly allocated SDK
mutex. A zero legacy slot initializes lazily after scheduler startup. Before
startup, acquiring/releasing legacy zero slots or valid initialized locks is a
no-op. Blocking acquisitions use the shared wait predicates and priority
inheritance; recursive owners retain exclusion until their final release.
Nonblocking try-acquire preserves the caller's interrupt mask. Legacy close
zeros its handle slot; retarget close takes a value, so the caller must clear
its own dangling copy. Close is allowed only after all users and waiters have
quiesced. Live reinitialization and copying ownership of a handle are unsupported.

Invalid handle/storage/type, allocation failure, release by a different owner,
closing a held lock, ISR calls and an acquisition that cannot block fail-stop.
They cannot silently return through a void C API as if a lock succeeded.
All lock calls are task-only, including nonblocking attempts; ISR clients must
use the existing explicit ISR-safe queue/semaphore APIs.

The C fixture includes unmodified newlib declarations and the pinned ESP-IDF
wrapper, compiled as RV32 ILP32 with O0/O2/Os and compressed/uncompressed code.
C3/C6 ROM tests cover both handle ABIs, adjacent-slot guards, lazy initialization,
recursive depth, contention/inheritance, timer preemption, reclamation and
fail-stop exclusions when C6 execution is selected. The lock storage is an SDK
mutex, not a FreeRTOS static object. This does not initialize ROM common mutexes,
ROM syscall tables, newlib `_reent`/errno state or static `__lock_*` objects.
The following optional profiles supply those layers; complete vendor startup
remains T501 work.

## Task-local newlib standard-library state

Import `lib/platform/esp32c3-libc.flex` or `esp32c6-libc.flex`. After initializing
the SDK arena, call `esp_libc_reent_init()` before `esp_sdk_task_init()`. Link the
explicit `riscv32-esp-elf` newlib archive from ESP-IDF 5.5.1's pinned
`esp-14.2.0_20241119` toolchain. The verification artifact records the official
toolchain archive SHA-256 and the extracted RV32IMC/ILP32 `libg.a` bytes; the
archive's `libc.a` name is a hard link to those same bytes. No tool is downloaded
by the compiler or linker. The installed Flexscript compiler remains independent.

This profile provides newlib 4.3's small, backward-compatible 240-byte ILP32
`struct _reent`. A C probe against the actual RISC-V target headers verifies its
size, alignment and relevant field offsets. Main owns one zeroed arena record;
every SDK task created after initialization owns a separate record. The TCB
remains 640 bytes: its RISC-V architecture-owned context bytes320..327 retain the
record pointer, beyond CPU register/PC/status/stack-floor save fields. Static ELF
TLS remains independent and is initialized/copied normally.

`__getreent()` selects the current record. `_impure_ptr` changes under the IRQ
mask at both cooperative and preemptive task switches, so C header macros that
access it directly also see task-local state. `_global_impure_ptr` retains main's
record. The bridge exports `malloc/calloc/realloc/free` and their `_r` forms over
the SDK arena. Allocation failure sets the selected record's errno to `ENOMEM`;
explicit `_r` calls use their supplied record. Failed realloc preserves its old
allocation. Zero allocation requests may return null without changing errno.
Invalid free/realloc pointers, invalid reent buffers and ISR calls to these
state/allocator bridges fail-stop.

Reaping unlinks the dead task before calling the actual linked newlib
`_reclaim_reent()` in the reaper's task context. It then frees the record and
stack. This releases lazy `rand()` and `strtok()` state even when C task entries
return normally. Failed task creation restores the exact heap when allocation
of its record fails after TCB, stack and TLS setup. SDK task init/create/delete/
reap reject ISR callers before modifying the allocator or task list. Delete/reap
validate list membership under the IRQ mask before reading a supplied TCB.
Foreign, high, unaligned and already reaped handles return `-22`; an uninitialized
scheduler has no valid handles.

The C3/C6 ROM matrix executes actual archive members for errno, `strtol()`,
`rand()`, `strtok()` and reclamation. Six C build modes test cooperative switches,
real timer preemption, static TLS, per-task errno/tokenizer/random-state isolation,
allocator failure/retry and exact reclamation. Real software IRQ callbacks verify
both libc fail-stop exclusions and nonmutating task-lifecycle rejection with
explicit C6 execution enabled. Native C3/C6 peripheral oracles and earlier compiler
matrices remain separate evidence.

The stdlib-only entry initializes thread state without standard streams or
static libc lock objects. The optional stdio profile below supplies those
objects and console callbacks. The ROM profile below installs syscall tables
and common-mutex overrides. Filesystem and full vendor/radio startup remain
T501 work. The arena and main record live until
reboot; initialization after scheduler startup or repeated initialization returns
`-16`, an absent arena returns `-19`, and allocation exhaustion returns `-12`.

## Pinned newlib stdio and console profile

Import `esp32c3-libc-stdio.flex` or `esp32c6-libc-stdio.flex` under `lib/platform/`.
After `esp_sdk_heap_init`, call `esp_libc_stdio_init()` before the scheduler or
other libc initialization. Link with `--newlib-stdio` and explicit pinned
`riscv-libc.a`; full floating-point formatters also require the matching
`riscv-libgcc.a`. The linker constructs an ELF data object in Flexscript: a
240-byte `_impure_data` and nine 84-byte static lock objects, aligned to four
bytes and exported as correctly sized global C objects. The C fixtures verify
those sizes and FILE/stat field layouts against actual RISC-V target headers.
Existing stdlib-only initialization continues to use its arena-owned main record.

The stdio profile uses `_impure_data` as the main/global record and initializes
the actual archive's `__sf` FILE array through `__sinit()`. Static lock identities
map to normal/recursive SDK mutexes. The three FILE locks use staged SDK handles.
All fallible allocation happens before stdio/global-record mutation; failed
startup restores the exact SDK heap, including native-table allocation failure.
Startup requires an initialized arena and a fresh libc/scheduler state; errors
are `-19`, `-12` or `-16`. Global stream/lock storage lasts until reboot.

Standard-library code uses the `_r` console callbacks directly. Call
`esp_libc_posix_bind()` when C code needs public `read/write/close/lseek/isatty/
fstat/open` or `flockfile/ftrylockfile/funlockfile` names. For explicit FILE locking
alone, `esp_libc_file_locks_bind()` retains only those three aliases. These are
explicit reachability choices within the fixed 128 KiB code profile; formatters,
POSIX probes and timer stress each have their own test image. Oversized programs
reject linking while preserving existing destinations. Cached-flash/radio profiles
remain separate work.

UART0 retains the ROM configuration unless the application explicitly changes
it through the UART adapter. Fds0/1/2 start open: fd0 reads available bytes and
returns `EAGAIN` if empty; fds1/2 write raw bytes. Closing a descriptor persists
until reboot. Invalid descriptors use `EBADF`, bad caller buffers `EFAULT`, and
oversized signed byte counts `EINVAL`. Zero-length calls permit null buffers.
`fstat` returns the pinned 88-byte character-device structure with 128-byte block
size; console seek fails with `ESPIPE`. Filesystem `open` is not provided and
returns target `ENOSYS`. The pinned newlib errno ABI differs from Linux:
`ENOSYS=88`, `ETIMEDOUT=116`; header assertions and real C error paths verify them.

`esp_libc_console_budget(cycles)` accepts1..2147483647 CPU cycles and returns zero,
or `-22` without changing the budget. Default write polling budget is16000000
cycles. It starts after TX serialization is acquired and is snapshotted for the
whole write. Expiration after progress returns the positive partial count;
expiration without progress returns C `-1` and target `ETIMEDOUT`. Waiting for
another task's lock follows the normal scheduler rules. State/allocator/FILE-lock
and console callbacks are task-only and fail-stop from ISR context. `abort()`
also fail-stops; process-exit/signal support is not supplied by this profile.

SDK child records inherit the initialized global stream pointers and cleanup
callback. The reaper closes private standard-stream replacements once, flushes
memory streams, releases their buffers/cookies/locks, and preserves all three
global streams even when a child redirects one stream to another global stream.
Actual C tests verify shared FILE recursion and noninterleaved writes across
cooperative switches and real timer preemption, plus exact heap recovery after
warmup of newlib's reusable global FILE pool.

The matrix checks integer/64-bit/floating-point formatting and exact UART output
at O0/O2/Os with compressed/uncompressed C callers, fragmented binary
`fread/fwrite`, bounded/partial writes, fd/errno behavior, initialization rollback,
ELF object shape, ISR exclusions and preserved-output link rejection. Both chips
execute under their explicitly selected stock QEMU. Physical UART timing remains open.
This profile exercises the explicitly linked toolchain library. ROM callbacks
require the additional explicit initialization below.

## Optional ROM newlib callbacks and common mutexes

Import `esp32c3-libc-rom.flex` or `esp32c6-libc-rom.flex` and link with both
`--newlib-stdio --newlib-rom`. Initialize the SDK heap, call
`esp_libc_stdio_init()`, then `esp_libc_rom_init()` with interrupts masked before
starting the scheduler. This is a one-time boot operation: it rejects an active
scheduler, enabled interrupts, a previous installation, a foreign ROM syscall
table/global record, or changed console descriptors. It checks the ROM chip ID
before writing any ROM-owned state. An uninitialized stdio layer returns `-19`;
ownership/order conflicts return `-16`, and a chip mismatch returns `-95`.

The linker emits the primary ESP-IDF ABI's 39-pointer ILP32 syscall table,
explicit relocation records and exact absolute ROM entry/slot symbols. It
retains the linked toolchain's `_global_impure_ptr` symbol and writes the separate
ROM global-record cell directly. The table routes allocation, task-local reent,
console and lock calls to the same SDK-owned runtime. Unsupported filesystem,
process and clock operations return target `ENOSYS` without changing output
buffers. Unexpected ROM `__sinit`, abort, exit, raise and assert callbacks
fail-stop. The optional ROM float hooks stay null, matching the default IDF
configuration; use linked toolchain formatting for floating-point and 64-bit
formats.

C3 ROM still uses a 60-byte, four-byte-aligned `stat` with 32-bit time and
`st_blksize` at44. Its table callback has a separate adapter; the linked
toolchain keeps its 88-byte/eight-byte-aligned layout. Startup prepares the
global standard FILEs using linked `__swsetup_r`, preserving errno and existing
FILE error flags around read-only stdin setup. This follows IDF's C3 ROM
compatibility workaround. Arbitrary private FILE formatting through ROM is
outside this profile's verified scope; use the linked toolchain for those
streams.

The actual chip ROM common-mutex initializer copies the shared magic value into
its own lock storage. A ROM-specific callback recognizes aligned magic cells
only inside that chip's reserved ROM RAM range, mapping them to the existing
normal/recursive SDK common mutexes. They cannot be closed. Ordinary stdio-only
firmware retains the smaller lock implementation through an optional alias hook.

The C3 suite executes actual ROM `strdup`, overflow-checking `strtol` and integer
`printf` across cooperative switching and real timer preemption. It checks 288
complete output lines, task-local errno, exact task heap recovery, typed syscall
callbacks, adjacent guards around the old `stat`, binary console traffic and
startup ownership. Separate typed callbacks exercise both actual common-mutex
storage cells decoded from the unmodified C3 ROM initializer; ROM `printf` uses
the global FILE lock and is not claimed as common-mutex contention proof.
C6 executes ROM workers, syscall-table, console, ownership and guard cases with
its explicit QEMU option. C6 common-mutex storage addresses still lack the
independent C3-style decoded-cell fixture. Physical boards,
cached-flash radio memory reservations and actual vendor radio startup remain
open.

ROM worker fixtures initialize shared stdout with a zero-output ROM `printf`
before measuring worker reclamation. On C6 the first output otherwise retains
a shared 128-byte buffer (144 bytes including allocator overhead). That buffer
stays constant across task generations. `riscv-rom-worker-controls.py` checks
protected/cold fixtures and deliberately omitted worker frees across both chips
and all three memory profiles: 18 ROM boots, six detected worker leaks and
three cold-C6 stdout controls. This initialization changes the test baseline;
production stdio allocation policy is unchanged.

## ROM-configured UART0 FIFO and interrupts

The matching `esp32c3-uart.flex` or `esp32c6-uart.flex` adds nonblocking
`esp_uart_try_read()` and `esp_uart_try_putc(byte)`. Read returns a byte or `-1`
for empty; write accepts 0..255 and returns `-11` when the 128-byte FIFO is full.
Each check/transfer masks CPU interrupts to prevent a task and callback from
consuming the same FIFO slot. The ROM baud rate, framing and pin routing remain
in use. Explicit two-port initialization, baud/framing and hardware flow-control
configuration are available as described below.

Attach `esp_uart_irq_source()` through the matching IRQ module. Configure
RX-full 1..127 and TX-empty 0..127 with `esp_uart_irq_thresholds(rx,tx)`;
`esp_uart_irq_timeout(bits)` selects 0..1023 bit periods, with zero disabling it.
C3/C6 use different threshold fields, timeout registers and synchronization
mechanisms. Configuration preserves other fields and bounds synchronization
waiting; hardware timeout returns `-110` with the caller's interrupt mask
restored. It can leave the attempted peripheral configuration in place.

`esp_uart_irq_mask(mask)` replaces the UART0 interrupt-enable bitmap;
`esp_uart_irq_pending()` reads enabled status, `esp_uart_irq_raw()` reads raw
status and `esp_uart_irq_ack(mask)` clears selected events. The supported mask
is 0..0x7ffff, following the pinned LL interrupt mask. Callbacks drain receive
bytes and acknowledge their events. Disable TX-empty/TX-done events when the
transmit queue has no more work.

Stock C3 ROM boots verify 16 received binary bytes in four independent host
chunks, exact returned bytes, TX-done delivery, two FIFO thresholds and four
receive-timeout events below the FIFO threshold. Primary-header tests check both
chips' exact writes, full/empty behavior, invalid-argument no-write behavior,
interrupt-mask restoration and a stuck synchronization register. C6 executes
the two FIFO-threshold cases; its real RX-timeout behavior and physical UART
pin/timing acceptance remain open.

## UART0/1 initialization and configuration

The `-uart.flex` entry exposes `esp_uart_bus_*` operations for bus 0 or 1. Existing
UART0 entrypoints retain their behavior until explicit initialization. C3 UART1
is at `0x60010000`; C6 UART1 is at `0x60001000`.

`esp_uart_bus_init(bus,baud,data_bits,parity,stop_code)` selects the 40 MHz XTAL,
initializes a gated-off port and configures baud and framing. Baud accepts
39..5000000, data_bits 5..8, parity 0=none/1=even/2=odd, and stop_code 1=one/
2=one-and-a-half/3=two stop bits. The 12-bit integer/four-bit fractional divider
and 1..256 source predivider follow the pinned LL limits. C3 holds the core reset
around a cold bus-gate/reset sequence; C6 uses its PCR gate/reset registers.
Initialization clears stale events and disables hardware flow control. It leaves
pad routing for an explicit call.

Reconfiguration is task-only and requires a quiescent enabled port: interrupt
enables must be zero, FIFOs empty, RX/TX FSMs idle, resets released and register
synchronization complete. Busy returns `-16` before writes. Invalid buses and
configuration values return `-22` before writes. External peers must remain
quiescent while reconfiguring. A synchronization timeout returns `-110`, restores
the caller's interrupt mask and can leave attempted settings in the peripheral.
`esp_uart_bus_baud(bus)` reports divider-derived integer baud for the selected
40 MHz XTAL profile; other source/fractional-clock configurations return `-95`,
and a gated-off port returns `-19`.

`esp_uart_bus_flow(bus,mode,rx_threshold)` configures mode bit 0=RTS receive
throttling and bit 1=CTS transmit gating. A receive threshold 1..127 is required
with RTS; otherwise 0..127 is accepted. This also requires a quiescent enabled
port. `esp_uart_bus_pins(bus,tx,rx,rts,cts)` selects explicit allowed pads;
`-1` leaves that signal alone. It rejects duplicate/reserved pads before writes,
uses push-pull TX/RTS and pull-up RX/CTS, and retains the existing pad exclusions.
Masked updates preserve unrelated peripheral and GPIO fields. No previous pin routes are automatically reclaimed.

The FIFO/IRQ APIs have matching bus-prefixed forms, such as
`esp_uart_bus_try_read(bus)` and `esp_uart_bus_irq_mask(bus,mask)`.
`esp_uart_bus_flush(bus,cycle_budget)` waits for both FIFO drain and an idle TX
shift register, returning `-110` when its cycle budget expires. Caller interrupt
state remains intact.

The header oracle covers both ports, eight baud rates, all 36 framing combinations,
flow and pad routing, busy/invalid no-write guards and stuck synchronization.
Stock C3 ROM boots verify UART0/1 divider readback, fragmented RX/TX responses and
TX-done/receive-timeout delivery after initialization. QEMU omits the SYSTEM UART
gate and C3 source-clock register readback, and GPIO is a stub. Clock/gate/baud-getter
and pad/RTS/CTS policy therefore use the primary-header oracle; physical baud,
framing and flow-control signals remain unverified. C6 executes four explicit
UART0/1 initialization/divider/fragmented-I/O cases. Its UART1 RX-timeout case
remains blocked by the vendor model limitation described below.

The pinned official C6 QEMU device inherits the C3 UART implementation without
overriding timeout fields. Native C6 UART0/1 timeout firmware returns its bounded
wait error; diagnostic-only C3-layout writes make both ports pass. Those writes
are confined to the investigation firmware. Production uses the primary-header
C6 layout. The two timeout cases remain unverified for native C6 behavior.

The C6 LP-domain model also ignores software calibration store
`LP_AON_STORE1_REG` (`0x600b1004`), although the pinned header defines all 32
bits as read/write. Full typed-OSI fixtures stop at their nonzero readback check.
They remain required by default. For this known model, explicitly pass
`--c6-slowclk-store unavailable` to retain those six C6 cases as packages with
model-gap reasons and no CPU success credit. Radio IRQ/order/refusal cases and
the other execution families still run. Production keeps the correct STORE1
address. Native nonzero slow-clock callback behavior remains T560/T499 work.

The execution tools require these cases by default. When deliberately testing
this known vendor model, pass `--c6-uart-timeout unavailable` alongside
`--qemu-c6 PATH` (and `--execute-c6` for individual UART peers). Only those two
C6 cases retain package checks, with explicit model-gap reasons and no C6 ROM
boot credit. FIFO, divider and other peripheral cases still execute; C3 timeout
cases still execute. Omit the setting when testing a model with C6 timeout
support. Physical C6 timeout acceptance remains open under T558/T499.

## GPIO matrix and pin interrupts

Import the matching `esp32c3-gpio.flex` or `esp32c6-gpio.flex` to add matrix
routing and pin-interrupt APIs. `esp_gpio_route_output(pin,signal)` accepts
signals 0..128; 128 selects the GPIO output latch. `esp_gpio_route_input(pin,signal)`
accepts 0..127 and configures the chip-specific input-select bit. Both APIs retain
the existing flash-pad exclusions and reject invalid inputs before MMIO writes.

`esp_gpio_irq(pin,mode)` configures 0=disabled, 1=rising, 2=falling, 3=any edge,
4=low level or 5=high level. It owns the pin's interrupt-enable field, masks CPU
interrupts during configuration and clears the old pin latch before enabling
the normal CPU route. `esp_gpio_irq_source()` supplies the source for an explicit
`esp_irq_attach` through the matching `-irq.flex` module. Callbacks read raw
per-pin status with `esp_gpio_irq_pending(pin)` and clear individual latches with
`esp_gpio_irq_ack(pin)`. A level input can assert again while its level persists.

Primary-header tests compare exact writes on all allowed pads and matrix
signals, preserve unrelated register bits and check that rejected calls write
nothing. Stock QEMU's GPIO device is a stub. Both chip boots verify emitted API
control flow only; external matrix signals, pad levels and GPIO IRQ delivery
still require physical acceptance.

## Interrupts, timers and preemption

Import `esp32c3-irq.flex` or `esp32c6-irq.flex` under `lib/platform/`.
Startup configures C3's legacy INTC or C6's PLIC with all CPU lines masked,
level triggering, threshold 1 and peripheral routes disconnected. The adapter
uses priority 1 CPU line 1 for shared device callbacks and line 7 for FROM_CPU0
software callbacks. `esp_irq_attach(source,handler)` owns a source route;
callbacks inspect and acknowledge their device. The table holds at most 32
sources. Software callbacks and ordinary attachment of FROM_CPU0 are mutually
exclusive. First software-handler installation clears stale pending state;
replacement preserves it. Detaching an unknown source leaves its route alone.
`esp_irq_enable()` sets mstatus.MIE while retaining the other status bits.

Callbacks run masked, without nesting, on a separate 16 KiB IRQ stack. Entry
saves all 31 nonzero GPRs, original SP, mepc, mstatus, mcause, mtval, mtvec, mie
and the interrupted stack floor. The dispatcher receives the CPU-line bitmap.
Synchronous faults, nested entry and native bump allocation inside an ISR
fail-stop. Blocking SDK operations and direct task switches remain forbidden
inside callbacks.

Import the matching `-timer.flex` for the two 54-bit TIMG counters. Timer IDs 0
and 2 select group 0/group 1 timer 0; IDs 1 and 3 reject. Prescalers accept 2..65535;
select XTAL 40 MHz with `xtal=1`, or APB with zero. C6 uses the PCR clock mux.
Word APIs accept a 32-bit low word and 22-bit high word. Counter snapshots use
the hardware latch, pending reads raw peripheral status, and alarm/ack APIs
support one-shot or autoreload operation. Configure pins/clocks explicitly for
the board; the SRAM profile assumes a 40 MHz crystal.

Import the matching `-sdk-preempt.flex`, initialize the SDK heap/tasks, enable
interrupts and call `esp_sdk_preempt_start(quantum_us)` with 1000..1000000us.
The scheduler leases idle TIMG0 timer0; TIMG1 timer0 remains its monotonic clock.
Existing timer use, pending events or a source owner returns `-16` before the
lease. Stop restores the saved timer configuration, count, route and enable
ownership. ISR callbacks request rescheduling; the compiler epilogue switches
only after they return. Before a switch, it validates space and copies the 208-byte
return frame onto the interrupted task's stack. Each suspended task owns its
saved mepc/mstatus; later interrupts can reuse the dedicated IRQ stack. Allow
space for this return frame and the scheduler call frames in task stacks.

Stock C3/C6 ROM boots verify software interrupts, both timer groups, all GPRs,
masked nesting rejection, stack guards and CPU-bound C preemption with separate
main/task TLS at O0/O2/Os and both static TLS access models. Physical interrupt
timing and board behavior remain unverified.

## Static C TLS

The linker accepts `.tdata` and `.tbss` from explicit ILP32 C objects/archives,
following the [RISC-V TLS conventions](https://riscv-non-isa.github.io/riscv-elf-psabi-doc/#_thread_local_storage).
Local-exec and initial-exec access work with `--no-relax`; initial-exec GOT words
live in the bounded data region. The original initialization template and a
separate main-thread instance share the selected static-data region (64 KiB
default, 32 KiB radio).
Both remain below the native heap; TLS does not enlarge the SRAM profile.

The compiler initializes the main instance and tp **before** trusted platform
initialization or `main()`: initialized bytes are copied and the remaining TLS
bytes are zeroed, including alignment gaps. Without TLS, tp starts at zero.
The template stays separate from the main instance so new tasks receive the
original values after main-thread TLS changes.

SDK task creation adds TLS size and alignment slack to the requested usable
stack allocation, then places TLS above the private stack. The block remains
owned by that TCB and is released by normal task reaping. The `stack_size` TCB
field at byte 576 records the complete allocation, including TLS. Invalid TLS
metadata or allocation failure returns zero without publishing a task or leaking
its TCB/stack. The effective TLS alignment is at least 16 bytes; stronger object
alignment is retained. Available SRAM and SDK arena capacity bound the result.

`flex_tls_descriptor` is a reserved compiler/linker symbol. Its eight u32 words
at `esp32_state()+24` contain magic `0x31534c54`, template address, initialized
size, total size, alignment, main-instance address and two zero reserved words.
All words are zero in an image without TLS. The linker validates the ELF TLS
segment, load mapping, sections and instance bounds before patching the descriptor
and replacing outputs. Startup validates the descriptor before copying bytes;
SDK task creation validates it again. Older compiler ELFs can still link ordinary
non-TLS C; TLS requires the new descriptor capability.

Obtain addresses of C TLS variables through C accessors. Absolute
`esp32_external("tls_variable")` imports reject because TLS symbols hold offsets
from tp. General/local-dynamic TLS loaders and C++ TLS constructor/destructor
registration are not supplied. Vendor-specific thread-local libc/runtime setup
and complete vendor-library startup remain open.

## GPSPI2 master

Import `esp32c3-spi.flex` or `esp32c6-spi.flex` under `lib/platform/`.
Only bus 2 is accepted; flash SPI0/1 and nonexistent GPSPI3 are excluded.
`esp_spi_init(bus,sck,mosi,miso,hz,mode)` configures caller-owned quiescent SPI2
and explicit allowed pads. MOSI or MISO may be `-1`; at least one is required.
Duplicate/reserved pads, frequencies outside 40000..20000000 and modes outside 0..3
reject before writes. Clock dividers round down from 40 MHz XTAL so the resulting
frequency, returned by init, does not exceed the request. CS is software-controlled
by the caller. The driver uses MSB-first bytes, a 64-byte CPU FIFO and explicit
C3 SYSTEM/peripheral or C6 PCR clocks/resets. DMA, slave mode and queued interrupt
transfers remain separate work.

Initialization and deinitialization are task-only. Reinitialization, an active
command, enabled interrupts, active DMA/slave state or a held reset rejects with
`-16`. `esp_spi_deinit(bus)` releases the selected pads and gates only SPI2;
its 96-byte state block is reused by later initialization. The caller owns the
peripheral and pads; an unrelated idle driver cannot be identified through MMIO.

`esp_spi_transfer(bus,tx,rx,size,cycles)` accepts 0..65536 bytes, optional TX/RX
buffers and a transaction-wide cycle budget 1..2147483647. Valid data transfers
require initialization and the corresponding pads. Exact in-place full duplex
is allowed; distinct overlapping or out-of-range buffers reject. RX-only mode
clocks zero dummy bytes. The driver checks register synchronization, TRANS_DONE
and command completion; FIFO errors return `-5`, and budget expiration returns
`-110`. Both recover saved peripheral configuration for a later retry. ISR and
concurrent calls reject while the transaction owns the state.

An incomplete FIFO chunk is never copied to RX. A failed multi-chunk transfer
can leave its completed RX prefix in place. `esp_spi_transferred(bus)` and
`esp_spi_status(bus)` report that completed prefix and the last transaction error.
The caller must release software CS after either result. Zero-length calls do no
bus work and leave prior progress/error metadata intact.

The primary-header oracle checks both register layouts, modes, six clock requests,
FIFO boundaries through 64 KiB, in-place and one-direction buffers, busy/invalid
no-write guards, completion ordering, FIFO faults, retries and a shared deadline.
Stock C3/C6 ROM checks cover bounded timeout recovery and timer-ISR exclusion.
They do not prove a successful SPI wire transfer; external devices and
timing/pads remain acceptance gates.

## HP I2C0 master

Import `esp32c3-i2c.flex` or `esp32c6-i2c.flex` under `lib/platform/`.
`esp_i2c_init(0,sda,scl,hz)` accepts distinct allowed pads and 10000..400000 Hz,
using the 40 MHz XTAL and the pinned HAL's timing calibration. Both profiles expose
HP bus 0 only; C6 LP I2C has separate clocks and pins and is not selected here.
C3 uses local clock fields, while C6 uses PCR. Their peripheral open-drain
control bits also differ; GPIO open-drain is enabled before either latch is
released high. Native pulls aid idle; external pull-ups determine electrical
bus timing. Initialization requires caller ownership and a quiescent controller;
reinitialization, ISR, active command/FIFO/IRQ/reset and concurrent calls reject
with `-16` before writes. `esp_i2c_deinit(0)` releases pads and gates only I2C0;
its 96-byte state is reused by later initialization.

`esp_i2c_transfer(0,address,tx,tx_size,rx,rx_size,cycles)` sends 7-bit addresses,
optional writes and repeated-start reads. Write-only payloads accept 0..31 bytes;
a combined write/read accepts at most 30 write bytes, reserving two address bytes
in the 32-byte TX FIFO. RX accepts 0..32 bytes. The eight-command engine uses
RESTART6/WRITE1/READ3/STOP2/END4 and NACKs the final received byte. `esp_i2c_probe`
sends an address/STOP with no application payload. TX is fully enqueued before
RX is copied, so exact or partial buffer overlap is allowed. Invalid arguments,
uninitialized state and busy pins/controller return `-22`, `-19` and `-16`.

The shared cycle budget includes command/FIFO preparation and completion polling.
Arbitration loss returns `-11`, NACK `-6`, hardware/software timeout `-110` and
FIFO/completion inconsistencies `-5`. Every issued command must complete and RX
FIFO length must match before any caller RX write. Errors restore controller
configuration and release the transaction state without clocking the bus-clear
sequence. `esp_i2c_status(0)` and `esp_i2c_transferred(0)` retain the last acquired
transaction's error and completed application-byte count. Busy/invalid calls
leave that metadata alone.

`esp_i2c_recover(0,cycles)` is an explicit caller-owned bus-clear operation;
never use it to disturb another active master. It permits a stuck controller
but rejects enabled IRQs, ISR context and concurrent ownership. It switches to open-drain GPIO,
releases the lines, emits up to nine clock pulses and then STOP, waiting for
stretched SCL. Its half-period pauses use 8000 CPU cycles, conservatively allowing
at least 50us at the documented 160MHz CPU ceiling for
[C3](https://www.espressif.com/sites/default/files/documentation/esp32-c3_datasheet_en.pdf)
and [C6](https://www.espressif.com/sites/default/files/documentation/esp32-c6_datasheet_en.pdf).
A short remaining budget rejects the next pause instead of overrunning it.
Persistent SDA-low returns `-16`; SCL stretching or deadline expiration returns
`-110`. Both output latches are released and matrix routes/controller setup
restored after acquired recovery, including failures. External drive and physical
STOP completion cannot be guaranteed when a device keeps SCL low.

The independent C oracle compiles unmodified HAL timing, open-drain and command
layout definitions against primary register headers. It checks nine timing rates,
every legal FIFO size pair, overlapping buffers, address edges, fault priorities,
all-command completion, RX length, retry/lifecycle and 17 recovery scenarios.
Its poll watchdog also detects a driver that never reads the cycle counter.
Stock C3/C6 ROM boots verify held-low rejection, bounded recovery timeout and
real timer-ISR exclusion. Successful slave transfers and pull-up/clock timing
remain acceptance gates. Long queued/IRQ transfers, slave/10-bit mode
and C6 LP I2C remain separate adapters under the wider platform work.

## Default SRAM and XIP memory layouts

| Region | C3 | C6 | Capacity |
| --- | --- | --- | --- |
| Code/trap/startup | `0x40380000` | `0x40800000` | 128 KiB |
| Control/globals/TLS template/main | `0x3fca0000` | `0x40830000` | 64 KiB |
| Native bump heap | `0x3fcb0000` | `0x40840000` | 32 KiB |
| SDK arena | `0x3fcb8000..0x3fcc0000` | `0x40848000..0x40850000` | 32 KiB |
| Main stack | `0x3fcc0000..0x3fcc8000` | `0x40850000..0x40858000` | 32 KiB |
| IRQ stack | `0x3fcc8000..0x3fccc000` | `0x40858000..0x4085c000` | 16 KiB |

C3's instruction/data aliases differ by `0x700000`; code ends at the physical
start of static data. C6 uses unified SRAM. Main and IRQ stacks remain below the ROM
loader reservations in the pinned ESP-IDF v5.5.1
[C3 layout](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_system/ld/esp32c3/memory.ld.in)
and [C6 layout](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_system/ld/esp32c6/memory.ld.in).
The separate radio memory profile above provides a larger SDK arena; complete
radio-controller reservation/startup acceptance remains open. Cached execution
uses the explicit XIP or radio targets above.

The first 24 data bytes retain the existing marker convention: heap cursor +0,
status +4, full main result +8, interrupt depth +16 and stack floor +20.
The following 32 bytes hold the static TLS descriptor; user data starts at byte
56. The status is `0x444f4e45` on return or `0x54524150` on a trap. Code/data bounds,
XOR checksum, appended SHA-256 and ELF load segments are independently checked.

## Platform adapters and verification

Import `lib/platform/esp32c3.flex` or `esp32c6.flex`. They supply polled UART,
hexadecimal output, cycle delays and GPIO direction/latch/input/pull/open-drain
operations. C3 GPIO11..17 and C6 GPIO24..30 remain reserved for flash/power.
Use an explicitly chosen board pin; the examples only print over UART.

```sh
build/flexscript-riscv scripts/test-esp32-riscv.flex -o build/test-riscv
build/test-riscv --compiler build/flexscript-riscv \
  --work build/riscv-tests --qemu /path/to/qemu-system-riscv32 \
  --reference /path/to/pinned-idf-reference
```

The lock suite additionally requires the unmodified newlib header closure under
`newlib/`, the pinned IDF `components/newlib/platform_include/sys/lock.h`, and
a generated `sdkconfig.h`. The newlib state suite additionally requires the
explicit pinned `riscv-libc.a`, target headers under `riscv-newlib/` and
`riscv-libc-provenance.json`; stdio additionally uses `riscv-libgcc.a` and its
provenance manifest. ROM tests additionally require the chip headers and ROM
linker maps listed in `rom-libc-provenance.json`. Those inputs are
checksum-verified before testing. Radio/atomic families additionally use
`radio-provenance.json`, its vendor archives, ROM maps and GNU atomic ABI sources.
`reference/libc-provenance.json` in the verification
artifact records their source and checksums. The reference directory contains original ESP-IDF v5.5.1 files under their
`components/soc/...` paths; tests never download or replace a compiler. LLVM's
assembler independently checks production instruction encoders. Independent
Python word cases and the existing 858-vector corpus execute through C3 ROM;
primary-header C oracles check both chips' exact GPIO/UART writes and masks.
LLVM C/assembly also verifies task-context switching, saved registers and gp/tp,
bidirectional ILP32 calls, callbacks, recursion,
register preservation and archive linking at O0/O2/Os with compressed and
uncompressed instructions. Static TLS tests cover two access models, O0/O2/Os,
256/4096-byte alignment, main-memory poisoning, task isolation/reaping and preserved-output rejections.
By default the suite executes C3 and validates C6 packages. Pass a separate
`--qemu-c6 /path/to/c6-qemu-system-riscv32` to execute C6 core runtime, C ABI,
task/context, static TLS, newlib locks/state/stdio, ROM libc, cached-flash, radio
memory-profile, atomic, radio IRQ/order/ownership guards, vendor MAC/WPA preinit, station
preflight/refusal, PMU policy, GPIO/SPI/I2C guards and UART FIFO/configuration
families too. Family reports count
actual C3/C6 ROM boots and remaining package-only checks independently. Other
families still validate C6 packages; this option does not establish their C6
MMIO or vendor-library behavior.

The C6 tool used here is built from [official Espressif QEMU commit
febae182](https://github.com/espressif/qemu/commit/febae182e132e4055529be423a818225ebddaa3a).
`build/esp32-c6-qemu-upstream/provenance.json`, `source-sha256.json` and
`build-report.json` retain archive/tool/dependency hashes, the unchanged original
vendor-source check, binary hash and bundled C6 ROM hash. No emulator source is
patched. The host wrapper only supplies the bundled ROM search path. Build with
one low-priority job; the local Meson/Ninja tools do not replace the compiler.
The build uses `-Ddtc:werror=false` for newer host C headers and enables the
installed libslirp dependency because this vendor revision incorrectly treats
a disabled wrapped dependency as found. Its C3 machine currently exits with an
unknown AES device type, so keep the established C3 release selected separately.

Individual execution-capable Python peers use `--execute-c6 --qemu-c6 PATH` for
the same opt-in behavior. The shared ownership fixture skips the chip's reserved
software interrupt source when filling all 32 peripheral-owner slots.

Remaining T164 gates include physical C3/C6 boot, vendor-specific RISC-V
runtime and vendor-library startup, plus the wider peripheral ports. Physical pad, waveform, radio and storage acceptance remain separate.

C6 PMU startup also needs internal analog-I2C access. The C6 radio wrapper now
provides `esp_radio_c6_regi2c(block, reg, msb, lsb, data, cycles)` as a prerequisite:
`data=-1` reads a field; a nonnegative value writes that field without changing
its other byte bits. It requires CPU0 Wi-Fi ownership, no ADC/PHY activity and
non-ISR context. Only the five pinned internal blocks are accepted. The caller
must already supply the chip's base modem/APB and 160 MHz clock prerequisites;
this access primitive does not initialize those clocks or the PMU.

A completion timeout returns `-110` and retains the internal bus lease, clock
and selector state. Further transfers return `-5`; radio cleanup refuses the
held lease. `esp_radio_c6_regi2c_recover(cycles)` waits for both engines to become
idle before restoring the saved fields. Recovery does not replay a command:
a timed-out write may already have committed, so its caller must read back the
uncertain value. A foreign busy engine is refused before selector or command
publication. All waits use bounded, wrap-safe cycle budgets. Pinned-header/PAC
MMIO models and C3 shared-ownership guard execution support this implementation;
C6 execution of this internal analog-I2C component and real analog transfers
remain unverified. The
production C6 `esp_radio_hardware_init()` gate remains in place until the full
HP/LP power and clock sequence is implemented and verified.

The C6 radio wrapper also supplies the internal PMU state-policy component:
`esp_radio_c6_pmu_address(row)`, `esp_radio_c6_pmu_mask(row)` and
`esp_radio_c6_pmu_value(row, hp_bias, lp_bias)` describe 49 HP/LP state fields.
Masks preserve reserved bits and exclude immediate command registers; applying
this table alone is not a power or clock initialization sequence. The values
follow the pinned IDF state defaults. `esp_radio_c6_pmu_read_bias(low_power)`
reads immutable C6 eFuse fields and selects the HP (`0`) or LP (`1`) bias using
the IDF block-version, default, offset and saturation rules. It never writes
an eFuse or a PMU register. C3 rejects these C6 calibration-register reads.

Primary C structures/defaults and native MMIO models check the policy. A C3
firmware peer executes those C definitions against the native table and bias
functions; that is pure C6 policy execution on C3, not C6 CPU or PMU execution.
The ordered RF/analog/regulator/PLL/modem-clock transaction, recovery and actual
C6 execution remain required under T536. The C6 radio enable gate remains.

C3/C6 cached radio builds can import `lib/platform/esp32c3-wifi.flex` or
`lib/platform/esp32c6-wifi.flex` for the shared station facade. The C ABI uses
the pinned 160-byte init and 184-byte station configurations. RISC-V lifecycle,
control and transmit guards inspect saved mstatus.MIE through the architecture
hook; Xtensa continues to inspect PS.INTLEVEL. Teardown resets the two exported
RISC-V lifecycle locks after quiescence, without assuming the Xtensa-only third
lock exists. Resource preflight refuses foreign IRQ routes and reserves both
Wi-Fi IRQ slots before publishing hardware ownership.

The explicit local vendor builder accepts `--libc`, `--libgcc`, `--libm` and
`--objcopy` overrides. It validates all three library pins; omitted libraries
are queried from the explicitly selected matching GCC tool. A nonstandard nm
path requires an explicit objcopy path. WPA mutex visibility changes only
symbol metadata in a temporary archive. The input archive remains unchanged.
The builder supplies the 24 pinned uint16 FTM coefficients for each chip; this
resolves vendor data dependencies and does not establish working FTM ranging.

The standalone RISC-V link policy leaves the six optional Wi-Fi optimization
section families in flash, as the pinned IDF default scheme specifies with its
IRAM optimizations disabled. Mandatory `.iram1`/`.phyiram` code stays in IRAM;
libphy readonly data stays in DRAM. The existing 64 KiB IRAM/32 KiB static DRAM
bounds remain enforced. `examples/esp32c3-wifi-init.flex` and the C6 counterpart
exercise the full explicit vendor build. C3 stock QEMU enters the real vendor
initializer and waits at the PHY status poll for register 0x6000e050. No MMIO
write is used to bypass that wait. Successful vendor initialization, RF traffic
and hidden controller SRAM acceptance remain unverified. C6 still returns -95
before hardware enable until the complete PMU/clock sequence is implemented;
its full image is checked as a package only.

`riscv-wifi-reference.py` runs six typed-C modes on C3 and, when selected, C6,
lifecycle rollback/retry, masked/ISR admission, packet ownership and the exact
newlib soft-double dependency. Its separate real-vendor observation records the
PHY wait without claiming initialization success. `riscv-wifi-link-reference.py`
checks archive allocated-byte preservation, primary section policy, bounded
IRAM/DRAM rejection and input/output alias protection. With `wifi-primary`
reference inputs present, both families run from `test-esp32-riscv.flex`.

C6 PMU startup has a reversible staging component in
`esp32c6-radio-pmu-stage.flex`. `esp_radio_c6_pmu_stage(cycles)` snapshots all
49 masked HP/LP policy fields, the RF internal-I2C power bits and three
regulator-interface fields, then stages the calibrated state defaults. It
requires an owned idle Wi-Fi domain, no ADC/PHY activity and the analog bus's
base clocks. Its budget applies separately to each bounded bus operation.
It does not issue immediate PMU commands, calibrate oscillators/bandgap, or
satisfy `esp_radio_hardware_init()`'s C6 enable gate.

The 416-byte native snapshot is published only after allocation succeeds.
Exhaustion returns `-12`, preserves the caller's interrupt state and domain
ownership, and leaves the snapshot pointer and PMU lease unchanged. Existing
snapshots can be reused even when the remaining native heap is exhausted.
The primary-register model checks allocation failure, retry, reuse and rollback;
`riscv-pmu-stage-allocation-reference.py` separately exhausts the real C6 native
heap in raw-image, SRAM ELF, cached-flash and radio profiles with IRQs enabled
and masked. These failure-path boots do not initialize the PMU or analog bus.


A prepared transaction keeps a PMU lease. Radio resource release, hardware
lifecycle, PHY access and unrelated internal-I2C callers refuse that lease;
the staging code grants its own internal-bus access while IRQs are masked.
`esp_radio_c6_pmu_abort(cycles)` first waits for any uncertain bus command to
finish, restores the digital fields and then reads back regulator fields
before restoring them. It preserves unrelated bits and retains the lease if
recovery or rollback times out. It never automatically retries an uncertain
command. A complete startup consumer can use `esp_radio_c6_pmu_commit()` to
transfer the staged defaults to platform lifetime after completing calibration
and clock setup. Commit alone does not enable RF, and those remaining startup
steps are still tracked under T547/T536.

The staged PMU can also own the factory bandgap trim transaction through
`esp_radio_c6_ocode_stage(cycles)`. It calls the pinned CPU0 ROM reset-reason
function first. Non-power-on resets retain the analog trim and skip both eFuse
reads and trim writes. On power-on, nonzero eFuse block versions select the
factory OCODE byte. The transaction snapshots `I2C_ULP_EXT_CODE` and
`I2C_ULP_IR_FORCE_CODE`, writes the code before enabling its force bit, and
preserves the other bits in the force register. A successful preparation keeps
its trim lease inside the enclosing PMU lease.

`esp_radio_c6_pmu_abort(cycles)` rolls back any trim transaction before restoring
regulators or RF-I2C power. `esp_radio_c6_ocode_abort(cycles)` can also roll back
just the trim while leaving the PMU prepared. Both retain ownership on timeout,
recover the bus to idle and read back uncertain writes before restoration.
`esp_radio_c6_pmu_commit()` refuses an incomplete trim transaction and commits a
completed one with the PMU state. These component commits still require the
remaining full clock/power startup before hardware enable.

Block version0.0 still returns `-95` from the OCODE stage: those chips require
the explicit legacy software calibration component described below. That
component requires exclusive PLL/clock ownership; it does not complete the
full ordered modem-clock/PHY startup tracked by T561/T547. The primary-header/I2C model checks
all256 trim bytes and reset reasons, all32 encoded fuse versions, interrupted
preparation/rollback, and32,768 vectors from the actual pinned vendor reset and
fuse-policy functions. This is model verification; actual C6 trim application,
software calibration and RF operation remain unverified.

`esp32c6-radio-clock.flex` supplies the CPU-side XTAL handoff needed before
legacy PLL-off calibration. `esp_radio_c6_clock_frequency(which)` returns
nominal active CPU, AHB or APB frequency in Hz for selectors0,1 or2. It validates
the C6 root/divider encodings, including the forced120MHz CPU case whose AHB
still derives from the160MHz root.

After PMU preparation, `esp_radio_c6_clock_begin(cycles)` enters an IRAM closure,
checks DMA/REGDMA and both SPI-memory command/FSM owners, snapshots the source,
low-speed CPU/AHB dividers and ROM delay calibration, then hands CPU/AHB to
40MHz XTAL. It raises CPU before AHB and selects XTAL after the dividers are
ready. A successful begin, or an error after its first mutation, retains the
PMU clock lease **and keeps interrupts masked**. The caller must complete
`esp_radio_c6_clock_restore(cycles)` before normal execution resumes.

Restore checks for foreign clock changes and requires a stable, powered,
ungated PLL before selecting an old PLL source. It restores the old source,
AHB before CPU low-speed dividers, the original ROM ticks-per-microsecond value
and finally the original interrupt state. Errors retain ownership and the
interrupt mask for explicit recovery. PMU abort and commit return `-16` while
the clock lease is held; restore the clocks first. Both public wrappers use
64-bit C-ABI returns so negative native statuses remain signed.

This component preserves PLL power and peripheral clock configuration. MSPI
follows the root clock, so its frequency changes during the handoff and the
DMA/flash-idle preconditions apply.
The complete hardware-startup integration remains under T561/T547. The independent
primary-HAL oracle checks clock decoding and modeled handoff/restoration;
real ELF packages verify IRAM placement, and optional C6 ROM checks verify
signed refusal statuses. Actual clock switching and physical timing remain
unverified.

`esp32c6-radio-pll.flex` adds an explicit owned PLL power cycle beneath the
CPU clock lease. After `esp_radio_c6_pmu_stage` and a successful
`esp_radio_c6_clock_begin`, call `esp_radio_c6_pll_begin(cycles)` to snapshot
power/gate state and the MSPI PLL route, validate an existing canonical
40MHz/480MHz analog configuration, and power down PLL/I2C using direct PMU
write-trigger commands. Already-off PLL states are accepted without calibration.
The PLL lease retains the XTAL source, masked interrupts and the analog-I2C
master root clock. That root clock stays enabled continuously across the
asynchronous PLL calibration and settling interval, including timeout recovery.
Nested bus calls preserve the held clock. Final restore checks and reinstates
the original root-clock bit; a failed readback retains the lease.

`esp_radio_c6_pll_consumer(1)` acquires an explicit shared-consumer reference;
`esp_radio_c6_pll_consumer(0)` releases it. Existing references, functional
UART/RMT/LEDC/timer/watchdog/I2S/ADC/PWM/PVT/SPI2/IOMUX clock selections, USB,
functional modem clocks and the analog USB-PLL bit refuse power-off. The
DMA/REGDMA and flash-idle checks also apply. Platform owners must register
consumers not represented by these observed clock gates. Consumer changes
are refused while a PLL lease is held.

Cleanup order is **PLL restore, CPU clock restore, PMU abort**.
`esp_radio_c6_pll_restore(cycles)` restores missing power bits and the saved
PLL gate for calibration, starts calibration, issues all six pinned vendor coefficient writes,
polls CALDONE, waits at least400 XTAL CPU cycles (10 microseconds), then stops
calibration and restores the saved analog controls, PLL gate and MSPI route. A budget
below400 cycles cannot complete the settling step. Every timeout retains
ownership for explicit recovery, including after a partial power change or
calibration stop. CPU clock restore refuses while the PLL lease is held.
The public IRAM callback wrappers preserve signed64-bit status results.

The analog-I2C driver journals whether it issued the write command. On timeout,
PLL recovery waits for the bus to become idle; an uncertain write is read back
before retry, while a timeout during an RMW read still requires the coefficient
write even when the old value already matches. This prevents both duplicate
and omitted programming writes without trusting busy-register command readback.

The independent C oracle executes the pinned HAL's actual six-write
configuration function and derives MMIO fields from primary headers. The host
model checks consumer gates, both analog masters, retained or lost coefficients,
interrupted power/control writes, every configuration-bus timeout, settling and
cleanup. The model injects the already-held XTAL lease; the separate clock
oracle checks that handoff. SRAM/XIP/radio ELF checks inspect the real callback
locations, and optional existing C6 ROM execution checks signed invalid-budget
returns only. PLL power switching, analog calibration/timing, legacy OCODE
and RF startup remain unverified on physical hardware. This component does not
remove the production `-95` full-startup gate.

`esp32c6-radio-ocode-legacy.flex` supplies software calibration for power-on
parts with eFuse block version0.0. The existing `esp_radio_c6_ocode_stage`
continues to handle retained trims/factory codes and returns `-95` for this
legacy branch. To run the legacy component explicitly, prepare PMU, call
`esp_radio_c6_clock_begin`, then `esp_radio_c6_pll_begin`, and invoke
`esp_radio_c6_ocode_legacy_stage(cycles)`. All three outer leases must remain
held. The stage checks actual XTAL/divider, PLL-off and analog-master-clock
state, rejects shared consumers, and refuses non-power-on resets, newer fuse
versions or a forced external code before pulsing calibration reset.

The stage snapshots RESETB, intentionally writes zero then one even if an old
bit matches, and reads the O_DONE/BG_O_DONE status byte until **both** flags
are set. Polling is bounded by the smaller of the supplied cycle budget and
400000 cycles at40MHz (nominal10ms), with32-bit wrap handling and deadline
checks before and after each transfer. It does not depend on slow-clock
calibration retention stores. Snapshot/reset commands separately use the
supplied per-command budget. The public wrappers preserve signed native
statuses and enter real IRAM closures.

Success leaves RESETB=1 and the newly calibrated internal OCODE, matching
vendor startup; the internal result cannot be restored to its prior value.
The component marks calibration ready and releases its OCODE lease, allowing
PLL restoration, CPU clock restoration and the remaining startup work. A later
PMU abort does not undo a completed internal calibration.

On failure, call `esp_radio_c6_ocode_legacy_abort(cycles)` **before** PLL/CPU
restoration. It retains IRQ masking and ownership on any further failure,
recovers a pending bus command, reads back uncertain reset writes and restores
the saved reset bit without blindly replaying a strobe. Restoring RESETB=1 may
restart calibration, so abort also waits for both done flags before releasing
the PLL-off lease. Subsequent cleanup is PLL restore, CPU clock restore, then
PMU abort. If an abort keeps timing out, the caller must retain those leases;
this component does not permit normal execution to resume with an uncertain
calibration.

The legacy C oracle executes the pinned vendor `calibrate_ocode` function
against all16 status-bit combinations and checks clock/reset ordering. The
host model combines the real PMU, analog bus, PLL and OCODE components with an
injected held XTAL lease. It tests both master routes, root-clock/IRQ states,
reset/fuse policy, every snapshot/reset/status timeout, interrupted aborts,
late completion, nominal10ms and cycle wrap. SRAM/XIP/radio firmware checks
cover callback placement and signed invalid-budget returns. These results
prove the modeled sequence and packaging; actual bandgap voltage, analog
transfers, clock switching and full hardware/RF startup remain unverified.

`esp32c6-radio-calibration.flex` coordinates all three reset-aware paths on an
already prepared PMU. Call `esp_radio_c6_calibration_prepare(cycles)` after
`esp_radio_c6_pmu_stage(cycles)` and before the remaining modem/PHY startup.
It selects retained calibration for non-power-on resets without reading trim
fuses, factory trim for a nonzero eFuse block version, or legacy calibration
for power-on/version0.0. The legacy path acquires the XTAL and PLL-off leases,
runs calibration, restores PLL, then restores CPU/AHB clocks and ROM ticks.
Success leaves PMU prepared and OCODE ready; the caller still owns PMU
commit/abort and the remaining startup work.

An admitted preparation failure retains the coordinator lease and IRQ mask.
Call `esp_radio_c6_calibration_abort(cycles)` until it succeeds before calling
PMU abort or retrying preparation. Abort recovers OCODE, PLL, then CPU clocks;
it never replays preparation. Public PMU/clock/PLL/OCODE operations and direct
PMU analog writes refuse while this recovery owns the lease. Repeated cleanup
failures retain ownership and the IRQ mask. Successful cleanup restores the
caller's original IRQ state and leaves PMU prepared with OCODE not ready.
An inactive coordinator abort is a no-op after admission checks: it does not
undo a successful calibration. Completed internal legacy calibration remains
irreversible, including when subsequent clock restoration fails.

The receipt globals `esp_radio_calibration_mode` identify factory1, retained2
or legacy3. `esp_radio_calibration_phase` is idle0, preparing1 or recovery2;
`esp_radio_calibration_step` identifies policy/trim1, XTAL2, PLL-off3, legacy4,
PLL-restore5 or CPU-restore6. `esp_radio_calibration_error` retains the original
preparation error; `esp_radio_calibration_cleanup_error` reports the most
recent explicit abort. Invalid budgets, reset reasons or initial ownership
reject before taking the coordinator lease. A new admitted preparation resets
both error fields.

The coordinator executes as an ordinary cached caller; its clock-changing
helpers retain their IRAM callbacks. The combined host model executes actual
clock handoff/restoration helpers with PMU/PLL/OCODE, all32,768 pinned vendor
policy vectors, every analog-command timeout and interrupted recovery. Its
21 deliberate defects cover selection, ordering, IRQ retention, leases,
cleanup and error reporting. Three firmware profiles check callback placement
and signed invalid-budget/unprepared-lease returns. This is model and package
evidence: actual cached execution across clock changes, analog timing and
physical RF startup remain unverified. The full C6 initializer retains its
clean `-95` gate until modem clocks and PHY startup are implemented.

The PMU transaction also snapshots the pinned C6 force-default controls for
TOP, HP_AON, CPU, Wi-Fi, LP peripherals and the memory no-isolation field.
After the49 mode-policy rows, preparation clears the six force flags in each
controlled power domain and the four memory no-isolation bits. Each domain
uses one masked write with bounded readback; unrelated fields and the reserved
power domain are preserved. Fixed singleton snapshots keep the checked
`alloc(416)` contract unchanged.

Before mutation, preparation refuses asserted reset/isolation/power-down
forces for the executing TOP/AON/CPU domains and asserted SRAM isolation.
Wi-Fi and LP peripherals may initially be forced off. Failed force writes
retain the PMU lease and record preparation intent before the write. Explicit
PMU abort first restores trim and regulator accesses, then restores force
controls in reverse order before the final RF/I2C power restore. Recovery
reads before writing, so a timed-out but committed write is not blindly
replayed. Commit requires all six force rows to have completed and transfers
their state to platform lifetime. These register operations do not implement
PMU immediate clock updates or enable the full C6 hardware path.

The force oracle executes the pinned `pmu_power_domain_force_default` and its
actual LL functions on primary C structs, including the skipped reserved
domain. It supplies1,536 address/mask/value vectors. The model executes real
PMU staging, analog transfers and force rollback, both IRQ modes, every force
prepare/abort timeout, late readback, reserved-field preservation and partial
commit refusal. Native firmware checks pure address/mask/snapshot helpers and
heap-failure admission; valid power writes and physical transitions remain
unverified.

`esp32c6-radio-modem.flex` stages the remaining modem register policy after
PMU preparation and successful calibration. Call
`esp_radio_c6_modem_stage(source, divider, cycles)` with source0 RC_SLOW,
1 RC_FAST,2 main XTAL,3 RC32K,4 XTAL32K or5 external32K, and divider0..4095.
The caller supplies an available oscillator, as in the vendor clock API;
this function does not start or calibrate that oscillator.

The stage ORs the ten pinned ESP-IDF ICG defaults into the existing maps,
preserving existing mode bits and all unrelated fields. BT and IEEE802154
use ACTIVE-only defaults; Wi-Fi, FE, MODEM_APB and the LP domains also permit
MODEM. It stops the Wi-Fi power clock, disconnects its LP mux, selects the
shared32K source where needed, sets the source/divider, then enables that
clock. Enabled/forced coexistence or BLE timer clocks refuse admission.
A forced Wi-Fi power clock also refuses, because its ordinary enable cannot
stop it. Changing a shared32K source selected by BLE/coexistence refuses even
when those users' clocks are gated; an unchanged selector is allowed.

Success holds the modem lease and the caller's IRQ mask. Every owned write
has bounded readback, with wrapping cycle deadlines and a late-read check.
Failure retains the lease and snapshots. Retry
`esp_radio_c6_modem_abort(cycles)` until it succeeds; it restores the source,
divider and maps while the consumer is stopped, then restores the original
Wi-Fi power-clock enable and IRQ state. Recovery reads before writing and
resumes at the failed step. Public PMU/clock/calibration operations, PMU analog
writes and new PLL references refuse during the modem lease. The receipt
fields `esp_radio_modem_phase` (prepared1/recovery2), `step` (preparation1..8),
`recovery` (cleanup0..6), `error` and `cleanup_error` expose progress and retain
the original preparation error separately from the latest abort result.

After the enclosing startup has issued PMU immediate updates and completed
base-clock activation, while PHY references and hardware-ready are still zero, `esp_radio_c6_modem_commit()` transfers both modem and PMU state to
platform lifetime together. A committed configuration cannot be undone with
this staging abort. Immediate ICG activation/live-state rollback remains
T582; this stage does not issue WT strobes or enable RF. The production C6
hardware initializer retains its `-95` gate.

The model executes the real modem stage/abort/commit and PLL reference guard
against24,576 vectors from pinned C HAL functions, LL bitfields and the ICG
default table, covering every divisor and source in both IRQ states. Prepared
PMU/calibration inputs are injected; their independent suites test the actual
lower stages. Native SRAM/XIP/radio firmware executes rejected/unprepared
calls only. Physical clocks, oscillator availability, analog transfers and
complete modem/PHY startup remain unverified.

The analog-I2C primitive now checks both busy engines before selecting its
160 MHz source. `esp_radio_c6_regi2c_idle()` provides a command-free preflight
using the existing source and restores the register-clock enable bit. Refusing
a foreign transfer never changes its source, selector or command. Primary C
headers/PAC fields, both masters/source states, fault/recovery wire traces and
actual C3 shared-lease guard boots support these changes. They do not prove
C6 CPU execution, PMU operation or real analog transfers.

C6 station fixture execution currently covers typed configuration canaries,
soft-double `floor` vectors, context/IRQ ownership/capacity guards and clean
`-95` hardware refusal. It exits before the synthetic vendor lifecycle, retries,
credentials, event and packet path exercised on C3. The fixture prints that
limited C6 scope explicitly. Full vendor-linked C6 refusal is likewise an
observed gate, not completed initialization. PMU policy execution performs
read-only eFuse access and primary-C comparisons without PMU or analog writes;
factory fuse values and actual power/clock startup remain unverified.
