# Bare-metal ESP32 and ESP32-S3

`--target esp32s3` (LX7) and `--target esp32` (original LX6) compile Flexscript directly into Xtensa instructions and
packages a ROM-loadable firmware image. The backend, startup, image writer,
platform adapter and regression harness are written in Flexscript. Firmware
compilation invokes no assembler, linker, C compiler, Rust compiler or ESP-IDF
build. There is no interpreter or RTOS in the generated firmware.

C3/C6 RISC-V targets now have a separate [implementation and verification guide](esp32-riscv.md). C3 ROM execution is verified in stock QEMU; C6 execution and the remaining platform ports are open.

## Build

From the Flexscript repository, using the installed compiler:

```sh
mkdir -p build
flexscript compiler/main.flex -o build/flexscript-esp32
build/flexscript-esp32 --target esp32s3 examples/esp32s3-blink.flex -o build/esp32s3-blink.bin
```

The example prints on UART0 and toggles GPIO4. Connect an external LED through
a suitable series resistor to GPIO4; it does not drive the onboard RGB LED.
UART0 retains the ROM's baud/clock and GPIO43 TX / GPIO44 RX routing (normally
115200 baud). Use the board's UART bridge or an external UART adapter; this
target does not initialize USB CDC or USB Serial/JTAG as its console.

The image is the ROM's bootloader-stage program and belongs at flash offset
`0x0`, replacing the second-stage bootloader. It needs no partition table or
separate application image. For a chosen test board, the raw-image operation
with espflash 4.x is:

```sh
espflash write-bin --port /dev/ttyUSB0 0x0 build/esp32s3-blink.bin
```

No flashing is performed by the compiler or tests. SPI flash mode is DIO,
40 MHz, with a 4 MiB size field. Secure boot and flash encryption provisioning
are outside this target's current scope.

## Language and runtime

The targets accept Flexscript source with local imports, functions,
recursion, control flow, globals, strings, all 64-bit word operators,
`load8`/`store8`, `load64`/`store64`, and `alloc`. Integer arithmetic retains the
native backend's wrapping, signed comparisons, arithmetic right shift, and
shift-count masking. Division truncates toward zero; division/remainder by zero
and `MIN / -1` or `MIN % -1` fail-stop. Unaligned 64-bit memory access is lowered
to byte operations. Pointers are physical 32-bit addresses carried in 64-bit
words; a nonzero high word traps before a memory access.

Intra-function branches retain compact three-byte jumps when their signed
18-bit displacement fits. Larger functions use absolute jumps only for distant
edges, including forward/backward control flow and short-circuit expressions.
The compiler repeats function layout until every branch fits, preserving call
and callback relocations. Valid FIR functions may end in a jump. Profile code
and memory limits still apply.

Compile `scripts/test-esp32-branches.flex` to run the dedicated regression
suite with `--compiler PATH --qemu PATH --ld PATH [--baseline PATH]
[--report PATH]`. It boots both chips through stock Espressif QEMU, including
S3 SDK RAM and both cached-flash profiles, terminal FIR jumps and cascading
branch expansion. An optional pre-change compiler verifies compact byte parity
and rejects the formerly out-of-range fixtures. This is machine-code execution
evidence; physical board acceptance remains separate.

The internal calling convention uses `callx0`/`ret`, a2:a3 for values, a14 for
the frame and a1 for the stack. Optional ELF targets bridge to the windowed C
ABI for vendor archives; see [vendor integration](esp32-vendor.md). Locals
are initialized to zero. Stack frames reserve words only for locals read by
the function; unread stores are omitted while initializer and assignment
expressions still execute. Source argument positions, including sparse C
callback parameters, retain their original calling convention. The compiler
emits only functions reachable from `main()`, allowing unused platform-specific
helper bodies in imports.

The dedicated local-frame regression runner is
`scripts/test-esp32-locals.flex`. Compile it natively, then run it with
`--compiler PATH --qemu PATH --ld PATH [--gcc PATH] [--baseline PATH]
[--report PATH]`. It covers all nine profiles, discarded-expression effects,
zero initialization on a reused stack, high-numbered source slots, sparse
private/C parameters, exact live-frame limits and output preservation. An
optional pre-change compiler verifies byte parity for all-read functions,
code-size reductions and the formerly rejected sparse frames.

Hardware intrinsics available only under this target:

| Intrinsic | Behavior |
| --- | --- |
| `esp32_load32(address)` | Aligned 32-bit read with memory barriers; zero-extended result. |
| `esp32_store32(address, value)` | Aligned 32-bit write of the low word with barriers; returns zero. |
| `esp32_cycles()` | Zero-extended CPU CCOUNT register. |
| `esp32_halt()` | Mask interrupts and spin forever. |
| `esp32_callback(function)` | Address of a named one-argument Flexscript callback. |
| `esp32_call(address, argument)` | Invoke a callback using the private call0 ABI. |
| `esp32_irq_save()` / `esp32_irq_restore(ps)` | Mask interrupts and restore the saved PS. |
| `esp32_irq_mask(mask)` / `esp32_irq_enabled()` | Write/read CPU INTENABLE. |
| `esp32_irq_pending()` / `esp32_irq_raise(mask)` / `esp32_irq_clear(mask)` | Read pending interrupts; set/clear software interrupts. |
| `esp32_state()` | Active target native control-block address. |
| `esp32_irq_pc()` | EPC1; sample before ISR calls into C. |
| `esp32_wait()` | WAITI 0: atomically unmask and wait for an interrupt. |

`lib/platform/esp32s3.flex` provides polled UART output/input, hexadecimal
printing, GPIO input/output on valid pins 0..48, pulls, open-drain, matrix routing and GPIO interrupt configuration and delay by CPU cycles. Cycle delays do not
assume a particular clock rate. The application controls pin selection/wiring.

Startup installs a private exception-vector table, masks interrupts, selects
the call0 processor mode, establishes the stack, disables boot watchdogs and
calls `main()`. Exceptions and runtime traps enter a fail-stop loop. Returning
from main stores its full result and enters a terminal loop. This version is
single-core. An optional cooperative SDK runtime is described below. Original
ESP32 Wi-Fi passive scanning, Bluetooth HCI startup, passive BLE reception
and externally received BLE advertisements are physically verified through
vendor libraries. See [vendor integration](esp32-vendor.md) for the separate `esp32-btdm-elf` memory
layout, explicit radio build commands and limits. Filesystem, dynamic FFI and
Linux syscall emulation remain unavailable. SetaScript, saved FIR and external
frontends now compile through the same native backend, including checked
state arrays and UART word messages. Explicit native platform inputs provide
startup/hardware adapters; see [frontend compilation](esp32-frontends.md).
This is a cross-compilation target; the compiler
itself still runs on Linux x86-64.

## SRAM layout

| Region | Address | Capacity |
| --- | --- | --- |
| IRAM vectors/startup/functions | `0x40380000` | 128 KiB |
| DRAM globals/strings | `0x3fcb0000` | 64 KiB |
| Zero-initialized bump allocations | `0x3fcc0000` | 32 KiB |
| Descending stack | `0x3fcd0000..0x3fcd8000` | 32 KiB |

`--target esp32s3-sdk-elf` selects a RAM-only layout for larger SDK programs:

| Region | Address | Capacity |
| --- | --- | --- |
| IRAM vectors/startup/Flexscript/vendor code | `0x40380000..0x403b0000` | 192 KiB |
| Control block, globals/strings and vendor data/BSS | `0x3fcc0000..0x3fcc4000` | 16 KiB |
| Native bump heap | `0x3fcc4000..0x3fcc6000` | 8 KiB |
| Explicit SDK allocator and task stacks | `0x3fcc6000..0x3fcd0000` | 40 KiB |
| Main stack | `0x3fcd0000..0x3fcd8000` | 32 KiB |

Link this target with `scripts/esp32-link.flex` without `--xip`; the resulting
ROM image uses S3 flash offset `0x0`. Compiler and linker enforce both code and
data bounds, including linked C/assembly inputs. The existing S3 targets retain
their layout. The SDK profile does not reserve S3 PHY/controller memory or
provide cached-flash or S3 radio initialization.

`--target esp32s3-xip-elf` keeps vectors, startup, IRQ callbacks and the cache
initializer in SRAM, and places ordinary native/GNU C functions in flash:

| Region | Address | Capacity |
| --- | --- | --- |
| IRAM vectors/startup/IRQ and explicit vendor IRAM | `0x40380000..0x40398000` | 96 KiB |
| Control block, globals/strings and vendor data/BSS | `0x3fca8000..0x3fcb0000` | 32 KiB |
| Native bump heap | `0x3fcb0000..0x3fcb2000` | 8 KiB |
| SDK allocator and task stacks | `0x3fcb2000..0x3fcd0000` | 120 KiB |
| Main stack | `0x3fcd0000..0x3fcd8000` | 32 KiB |
| Cached code (IROM) | `0x42000000..0x42300000` | Up to 3 MiB |
| Cached read-only data (DROM) | `0x3c400000..0x3c700000` | Up to 3 MiB |

Import `lib/platform/esp32s3-xip.flex` and link with `--xip`. The ROM image starts
at flash offset `0x0`; cached code starts at offset `0x30000`, followed by data
on a 64 KiB boundary. The combined image must fit 4 MiB of flash, so the code
and data maxima cannot both be used at once. The two buses share an MMU table:
IROM uses entries starting at zero; DROM starts at entry64. Mapping DROM at
`0x3c000000` would overwrite IROM mappings. The initializer checks the layout
before ROM calls, verifies the ROM's MMU split and restores PS on every return.
Startup traps if initialization fails before calling cached code.

The S3 SDK heap accepts requests according to the active arena, including the
full 120 KiB cached profile; `calloc` checks the product before multiplying.
S3 driver buffers require a recognized active profile and must lie between its
control block plus24 bytes and `0x3fcd0000`. This excludes control words and the
physical IRAM alias; a zero-length buffer may point exactly at the upper end.

Stock QEMU passes cached code/data across 64 KiB pages, GNU C windowed calls,
IRQ/FPU preemption, full allocator churn, timers, ADC guards and buffer checks.
Physical S3 flash boot, cache timing, radio initialization and RF remain unverified.

The [pinned silicon memory map](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32s3/include/soc/soc.h)
places the instruction alias 0x6f0000 above data SRAM. This profile's code ends
at the physical start of its control block. Its main stack also ends below
the [ROM loader reservation](https://github.com/espressif/esp-idf/blob/v5.5.1/components/esp_system/ld/esp32s3/memory.ld.in).
`tests/esp32/s3-sdk-reference.py` compiles an independent C oracle against those
pinned headers, checks emitted ELF regions and exercises all six SDK heap
profiles, rejection preservation and exact boundary allocations in stock QEMU.

These regions account for the IRAM/DRAM aliases of physical SRAM. Individual
function frames are limited to 16 KiB of retained local slots, with runtime stack checks on entry and
expression pushes. `alloc` rounds to eight bytes, returns `-12` on exhaustion
and `-22` for zero size, and has no free operation. Calling `alloc` from an
interrupt callback traps, preventing main/ISR allocator races. ISR callbacks
must be bounded, acknowledge their device and avoid allocation. No PSRAM is required.

The first 24 DRAM bytes are reserved: heap cursor at +0, completion status at
+4 (`0x444f4e45` for returned main, `0x54524150` for a trap), main's 64-bit
result at +8, interrupt depth at +16 and active stack floor at +20. These markers allow bounded emulator verification without a
special guest syscall or an emulator-only execution path.

## Verification

Use Espressif's QEMU fork with the `esp32s3` machine and its bundled S3 ROM:

```sh
flexscript scripts/test-esp32.flex -o build/test-esp32
build/test-esp32 --compiler build/flexscript-esp32 \
  --qemu /path/to/qemu-system-xtensa --report build/esp32-report.json
```

The harness independently checks segment bounds/addresses, XOR checksum and
SHA-256 (OpenSSL). It boots the images from emulated flash through the actual
S3 ROM. Tests cover 858 independently computed word-operation references on
both native x86-64 and Xtensa, recursion and eight-argument calls, globals,
unaligned memory, zeroed allocation/exhaustion, cycle counting, UART output,
GPIO register programming, CPU exceptions, pointer/alignment faults, arithmetic
traps, stack exhaustion and compiler diagnostics/output preservation.

The complete core suite requires an SD-capable S3 QEMU build. The pinned
[Espressif release esp-develop-9.2.2-20260417](https://github.com/espressif/qemu/releases/tag/esp-develop-9.2.2-20260417)
passes all 24 ROM boots and 1,166 checks. The earlier 20250817 build cannot
attach the SD backing image; this is a test-tool capability failure, not a passed
SD test. Archive and executable checksums are retained in the verification report.

Initial validation used Espressif QEMU
`esp-develop-9.2.2-20260417` on Linux x86-64. GPIO register writes execute in the
emulator; external pin voltages, LED blinking, UART receive and a physical
ESP32-S3 board have not been verified. QEMU does not implement the physical
IO_MUX behavior. The live example's blink loop is exercised separately; its
cycle delays are not a calibrated wall-clock interval.

Software IRQ handler replacement on both chips preserves an already-pending
event and restores the caller's interrupt mask. First installation clears stale
unowned software state. Each chip passes 64 exact deliveries across masked
levels and rejected registrations; restoring unconditional pending-clear makes
the corresponding test fail. These are ROM/QEMU checks, not physical timing.

Format and register references:

- [Espressif ROM firmware image format](https://docs.espressif.com/projects/esptool/en/latest/esp32s3/advanced-topics/firmware-image-format.html)
- [Pinned ESP32-S3 register definitions, ESP-IDF v5.5.1](https://github.com/espressif/esp-idf/tree/v5.5.1/components/soc/esp32s3/register/soc)
- [Xtensa ISA reference](https://dl.espressif.com/github_assets/espressif/xtensa-isa-doc/releases/download/latest/Xtensa.pdf)
- [Espressif ESP32-S3 emulator](https://github.com/espressif/esp-toolchain-docs/blob/main/qemu/esp32s3/README.md)

## Original ESP32 and RAM-only board tests

The original ESP32 has different peripheral addresses, memory layout, chip ID
and boot offset. Use `lib/platform/esp32.flex`, `esp32-irq.flex`,
`esp32-common.flex` and `esp32-timer.flex`. Its current adapters cover UART0,
GPIO, level-1/software interrupts, the four timer-group counters and the
original-chip `esp32-spi.flex` / `esp32-i2c.flex` bus drivers. The
`esp32s3-*` adapters below are S3-specific and must not be used on this chip.
Original ESP32 has no native USB controller; the connected board's CH340 is a
USB-to-UART bridge. USB OTG/Serial-JTAG support requires an S3 board.

| Original ESP32 region | Address | Capacity |
| --- | --- | --- |
| IRAM code | `0x40080000` | 128 KiB |
| DRAM globals/strings | `0x3ffb0000` | 64 KiB |
| Bump heap | `0x3ffc0000` | 32 KiB |
| Stack | `0x3ffd0000..0x3ffd8000` | 32 KiB |

A persistent original-ESP32 ROM image belongs at `0x1000`; S3 uses `0x0`.
The image header has chip ID 0 for original ESP32 and 9 for S3. Do not cross-flash
these targets. GPIO34..39 on original ESP32 are input-only with no internal
pull resistors; GPIO6..11 are normally reserved for module flash.

To run without replacing existing flash firmware:

```sh
build/flexscript-esp32 --target esp32 examples/esp32-timer.flex -o build/esp32-timer.bin
flexscript scripts/esp32-ram-image.flex -o build/esp32-ram-image
build/esp32-ram-image --input build/esp32-timer.bin --output build/esp32-timer.elf
espflash flash --ram --no-stub --chip esp32 --port /dev/ttyUSB1 \
  --after no-reset --non-interactive --skip-update-check \
  --ignore-app-descriptor --monitor --no-reset build/esp32-timer.elf
```

The converter verifies image bounds, chip ID, SHA-256 and XOR checksum, then
wraps the exact generated bytes in ELF32 sections/program headers. It invokes
no assembler/linker. Rebooting returns to the existing flash firmware.

On 2026-10-14, `tests/esp32/legacy-interrupts.flex` ran on the USB-connected
original ESP32 revision 3.0 / 4 MB board through the RAM loader and printed
`PASS: real Xtensa software and timer interrupts, counter and preserved context`.
That verifies UART TX, native calls, software interrupts, timer alarm interrupt,
WAITI wakeup and context return on physical hardware. No flash was written and
no external GPIO was driven. S3 physical hardware remains unverified.

## Original ESP32 digital GPIO hardware verification

`tests/esp32/gpio-wire-physical.flex` uses the confirmed GPIO21--GPIO25 jumper
in both directions. The same standalone ELF passes 736 digital samples and
160 callbacks on the original board and in the native wire model: strong drive
against all three pull settings, input pull propagation, open-drain sink/release,
and rising/falling/both-edge/low-level/high-level interrupts. The complete
application UART transcripts match. Removing the virtual wire makes the fixture
fail. Saved firmware sources rebuild the ELF byte for byte.

This test uses RAM only, releases both pins, verifies the original full 4MiB
flash unchanged and resets the board. It measures digital levels on these two
pins; voltage calibration, waveform timing and all-pad electrical coverage are
separate work. UART RX was independently exercised by the two earlier private
provisioning/network runs; their restoration proofs and the16RX/15TX-state
register regression are recorded alongside the new GPIO result. Evidence:
`build/esp32-goal-verification/gpio-wire/report.json`.

## Original ESP32 I2S and integrated DMA

`lib/platform/esp32-i2s.flex` and `esp32-dma.flex` add original-chip I2S0/1
stereo16/32-bit Philips PCM with bounded SRAM descriptors, asynchronous
submit/wait/cancel and finite duplex exchange. An active PLL clock is required;
ROM RAM loading alone can leave that source unavailable. The finite exchange
uses a silent priming frame and separate caller workspace to align RX frame0.

The 2026-10-15 RAM-only hardware fixture passed64 exact PCM round trips through
GPIO21-to-GPIO25: both controllers, both sample widths,8/44.1/96/192kHz and
one-frame through maximum aligned payloads. Full4MiB flash checksum remained
unchanged and the board was reset. Independent C-register/target-descriptor
contract checks pass245,856 assertions and20 deliberately broken adapters.
This does not verify an external codec or an I2S machine-code emulator model.
See [API, reproduction and remaining limits](esp32-i2s.md).

## ESP32-S3 peripheral adapters

All drivers are Flexscript and generate direct machine code. Register contracts
come from ESP-IDF v5.5.1; no ESP-IDF runtime is linked. Applications own pin,
clock and DMA-channel selection. Drivers are single-owner and nonreentrant.
Timeout arguments are positive CPU CCOUNT cycles (at most `2147483647`), with
32-bit rollover handling. Device errors return negative errno values. Buffers
must lie in the target's internal DRAM; DMA buffers/descriptors must be aligned.
A timeout/error can leave a partial transfer; it does not promise rollback.

| Module in `lib/platform/` | Implemented scope | Verification |
| --- | --- | --- |
| `esp32s3.flex` | UART0, both GPIO banks, input/pulls/open-drain, matrix routing and interrupt configuration | UART TX and GPIO registers in QEMU; independent host GPIO contract checks |
| `esp32s3-irq.flex` | CPU0 shared level-1 device callbacks and software interrupt, attach/detach, enable | Actual Xtensa exception entry/return in QEMU; original-chip equivalent on board |
| `esp32s3-timer.flex` | Four 54-bit timer counters, prescaler, XTAL/APB, start/stop, alarms/rearm | Actual timer alarm/interrupt in QEMU |
| `esp32s3-spi.flex` | SPI2/3 master, modes 0..3, full duplex, 64-byte FIFO chunks, software CS | Host model: data/chunks, divider, invalid buffers and timeout/rollover |
| `esp32s3-i2c.flex` | I2C0/1 7-bit master, write/read/repeated start, 30-byte TX / 32-byte RX | Host model: command opcodes, address bytes, NACK, arbitration loss and timeout |
| `esp32s3-pwm.flex` | LEDC four shared timers/eight channels, XTAL fractional divider, duty/stop | Host register model; no measured waveform |
| `esp32s3-adc.flex` | Serialized ADC1/2 RTC one-shot raw12-bit readings, attenuation and deinit | Primary-header350829 checks/24 defects; native ownership/ISR/deadline tests; analog operation/calibration unverified |
| `esp32s3-rmt.flex` | TX channels 0..3 / RX 4..7, fixed 48-symbol memory, filter and timeout | TX host model; physical pulses/capture unverified |
| `esp32s3-dma.flex` | Five GDMA RX/TX pairs, descriptors, ownership, bounded completion/error | QEMU: SHA-256 DMA of padded abc block, independently verified digest |
| `esp32s3-i2s.flex` | Stereo 16/32-bit Philips master, simplex per controller, fractional XTAL sample clock, GDMA blocks | Host clock/descriptor contract; actual sample stream unverified |
| `esp32s3-usb-serial.flex` | Fixed USB Serial/JTAG FIFO read/write | Host FIFO/timeout contract; S3 hardware unverified |
| `esp32s3-usb.flex` | DWC2 full-speed PIO device endpoints and host control/bulk packet primitives | Host controller contract; no bus enumeration proof |
| `esp32s3-usb-cdc.flex` | Polled CDC ACM device, EP0 descriptors/requests, deferred address, line coding, bulk echo | Host descriptor/control/buffering tests; firmware compiles, physical USB pending |
| `esp32s3-sd.flex` | Native SD slot 0, one data wire, SD/SDSC initialization and 512-byte block I/O via IDMAC | QEMU card: capacity, reads, persistent write/readback; no physical card |
| `esp32s3-flash.flex` | JEDEC SPI NOR erase/program/read, explicit region beyond first MiB, page splitting | QEMU flash write/readback plus protected first MiB checksum |
| `esp32s3-psram.flex` | Confirmed quad-capable PSRAM in single-wire PIO mode, explicit transfer API | QEMU 8 MB PSRAM identification and burst-boundary read/write |

Start with each module's public function signatures. SPI uses manual GPIO CS
around `esp_spi_transfer`; I2C exposes `esp_i2c_transfer(bus,address,tx,tx_size,
rx,rx_size,cycles)`. Timer IDs are `group*2+timer`; use `esp_timer_source(id)`
when attaching an interrupt. Use `esp32_callback(handler)` with
`fn handler(source)`. Test pending status before acknowledging a shared IRQ.

Before WAITI, mask interrupts and recheck the event. WAITI 0 atomically unmasks
and waits; a separate unmasked check followed by WAITI can lose a wakeup.
`examples/esp32-timer.flex` demonstrates the pattern.

I2S returns the actual quantized sample rate from `esp_i2s_init`; it does not
claim every requested rate is exact. RMT PIO is bounded by on-chip symbol RAM.
The S3 ADC API maps unit1 channels0..9 to GPIO1..10 and unit2 channels0..9 to
GPIO11..20. `esp_adc_pin(unit,channel)` returns that mapping. Call
`esp_adc_init(unit,channel,attenuation)` with attenuation0..3 before
`esp_adc_read(unit,channel,cycles)`; `esp_adc_deinit` releases the channel to a
digital input. The first successful init retains640 bytes of native state;
later channel initialization reuses it. Init configures only the requested pad
and saves its desired attenuation; conversion controls are applied during reads.

A read masks CPU0 interrupts and holds shared analog ownership. It restores
clock/power, reader/inversion/interrupt, attenuation, mux, arbiter and control
fields on success, timeout and invalid data, preserving unrelated bits and the
caller's complete saved PS. One CCOUNT deadline covers both ADC1 idle waiting
and conversion completion, including counter wrap. A valid cycle budget is
1..2147483647. Uninitialized reads return-19; timeouts return-110; ADC2 arbiter
unselected/interrupted sample flags return-11 for retry.

Busy ADC/ISR contexts, existing RTC conversion interrupt users, active ULP
timer/start controls, selected RTC/digital controllers and an asserted SAR
reset return-16 before allocations or device writes. Operations that would
configure or use a held RTC/digital pad also return-16; deinitializing an
unconfigured channel is a no-op. ADC2 also
rejects init/read/deinit while a native radio domain, PHY reference or PHY clock
reference is active. ADC1 remains available with shared fields restored after
each read. GPIO19/20 also serve USB; pad selection remains an application/board
choice. Physical S3 analog values, ADC/radio overlap and calibrated voltage
still need hardware verification.

`tests/esp32/s3-adc-reference.py` verifies all20 channels, all4 attenuation codes,
PS levels0/1/3/7/15 with upper flags retained, timeout/retry, invalid samples,
first-init guards and66600 nested rejections against an independent C oracle
compiled from pinned Espressif headers. Its operation spies use scripted sample
values; they do not add emulator peripheral/timing support. The standalone ADC
API and SDK guard fixtures also execute actual S3 machine code on stock QEMU;
that evidence covers guards, allocation failure and deadlines, without claiming
analog sample correctness. See `build/esp32-backend-s3-adc/report.json`.

ADC values are raw counts, not calibrated millivolts. SD has no filesystem,
MMC/eMMC/high-speed/4-bit mode or card hotplug layer. Flash operations require
RAM-resident code and unencrypted, non-octal SPI NOR. PSRAM is not cache-mapped
and does not enlarge `alloc`; octal PSRAM still requires a board-specific port.

USB Serial/JTAG and OTG share the S3 internal PHY on GPIO19/20. The CDC example
uses OTG; it is separate from UART0 and the fixed Serial/JTAG controller. Host
mode requires a board-provided current-limited 5V VBUS supply and full-speed
hardware. Host packet primitives are not a hub, class-driver or enumeration
stack. The CDC example uses demonstration VID/PID values; choose authorized
identifiers before distributing a product.

Original ESP32 passive Wi-Fi scanning and Bluetooth HCI commands now work on
the connected board using vendor archives, native OS callbacks, PHY calibration
and cached flash. The clean BLE scanner received 221 advertising reports in
five seconds with zero dropped host events. The laptop also received
the clean example's Flexscript advertisement with repeated RSSI updates.
Original ESP32 station association/reconnection, DHCP acquisition/renewal,
DNS, UDP echo and ICMP are now physically verified; see
[native networking](esp32-network.md). TCP/TLS and S3 radio integration remain
open. See
[vendor integration](esp32-vendor.md) for reproducible builds, runtime and memory
contracts, and verification limits. Original ESP32 and S3 require different
vendor binaries and adapters.

## Expanded regression evidence

The harness also verifies main's returned value, the first MiB of flash after
every boot, physical SRAM-alias bounds, code execution beyond 64 KiB, callback
arity errors and allocation traps inside a real ISR. It tests both chips' ROM
boot paths, SD backing-file persistence, SPI NOR page boundaries and quad PSRAM
burst boundaries. The host register model executes unchanged production driver
code against deterministic device responses; it is not hardware emulation.
The QEMU build used here models GDMA/SHA, SD and memory SPI, but lacks the
GPSPI/I2C/USB OTG/analog devices needed for physical equivalence claims.


## Persistent settings core

The allocation-free [settings store](esp32-settings.md) implements bounded
key/value snapshots and atomic two-bank commits, with independent NOR/power-cut
and cached-flash Xtensa verification. The [original-ESP32 flash backend](esp32-flash.md)
passes controller/cache models, two four-boot QEMU paths and physical
cached-flash transfers/settings across four hardware boots. Original firmware
is fully restored and checksum-verified after the temporary probe. The optional [radio NVS provider](esp32-nvs.md) installs the pinned callbacks
and enables Wi-Fi persistence when initialized before the station. Firmware
that does not initialize it retains disabled persistence.

## Original ESP32 SPI and I2C

Import `lib/platform/esp32-spi.flex` or `lib/platform/esp32-i2c.flex` for the
original ESP32. Their init/transfer signatures match the corresponding S3
adapters. SPI2/3 support MSB-first bytes, modes0..3, up to64KiB per call in
64-byte FIFO chunks, explicit GPIO CS and a whole-transfer cycle budget.
Configured rates are40kHz..20MHz and init returns the rounded-down actual rate.
`esp_spi_deinit(bus)` releases the configured pads and clock. Reinit while
active returns-16. Exact in-place transfers work; partial buffer overlap is
rejected. A timeout resets/restores the controller for retry; earlier completed
RX chunks remain visible.

I2C0/1 support10..400kHz, 7-bit addresses, write<=30bytes/read<=32bytes,
repeated START, and address-only probes. NACK returns-6, arbitration loss-11,
timeout-110, and an incomplete STOP or mismatched RX count-5. Failed transfers
leave the caller's RX buffer untouched and reset/restore the controller.
`esp_i2c_deinit(bus)` releases the pads and clock. `esp_i2c_recover(bus,cycles)`
explicitly attempts up to9 open-drain SCL pulses followed by STOP, respecting
clock stretching and always releasing both lines. Call recovery only when the
application owns the bus. Ordinary transfers reject a busy/non-idle bus with-16.
External pull-ups and peripheral wiring still determine electrical operation.

The unchanged production drivers pass10,375 native register/wire checks using
121 values compiled independently from checksummed ESP-IDFv5.5.1 C definitions.
The oracle detects deliberately wrong SPI clock edges, I2C STOP opcodes,
SRAM bounds, TX FIFO alias, unguarded RX reads and RTC pull configuration. It covers both controllers, all SPI modes, FIFO boundaries,
in-place data, combined I2C commands, error/retry paths, rollover, pin routing,
busy ownership, deinit and bus-clear/clock-stretch failures. Reproduce with
local official header files listed in `tests/esp32/bus-oracle/sources.json`:

```sh
python3 tests/esp32/bus-register-reference.py --compiler build/flexscript \
  --reference /path/to/official-header-basenames --work /tmp/esp32-bus-test \
  --report /tmp/esp32-bus-test/result.json
```

The connected original ESP32 passes120 real SPI FIFO transfers through GPIO
pad loopback: both controllers, all4modes, approximately100kHz/1MHz/5MHz and
1/63/64/65/130-byte sizes. Both I2C controllers physically return NACK without
a peer, recover, retry, deinitialize and reinitialize. This probe loads RAM
only; the full4MiB flash checksum remains unchanged and the board is reset.
Successful I2C data exchange with an independent peripheral, electrical timing
and external chip-select behavior remain unverified. QEMU has no equivalent
GPSPI/I2C device model; host oracles are separate evidence.

Original-chip I2C TX FIFO writes use the APB alias (`0x6001301c` / `0x6002701c`).
RX FIFO reads use an interrupt-masked APB preread followed by the DPORT read,
matching the pinned Espressif workaround. CPU1 is inactive in current profiles.
The reference runner also checks the pinned DPORT implementation's instruction
ordering and rejects omitted guards as deliberate defect controls.

Original ESP32 RTC-capable GPIO pads require RTC pull registers even in digital
mode. `esp_gpio_pull` now uses those fields and preserves the adjacent GPIO32/33
pull state under interrupt masking. The independent C oracle covers all12
pull-capable RTC pads. A RAM-only physical probe verifies pull-up, pull-down,
open-drain low and released-high input readings on GPIO25/26/27/32/33, then
releases them. This is pad readback, not an external voltage or waveform
measurement. Firmware source: `tests/esp32/gpio-pulls-physical.flex`.

`tests/esp32/i2c-fifo-physical.flex` verifies real controller TX consumption and
RX FIFO counts/data on both original-chip I2C controllers at1/2/3/16/31/32-byte
sizes. It deliberately disables address ACK checking and samples an open bus,
so this verifies FIFO hardware/access paths without claiming a responsive
peripheral or a successful ordinary `esp_i2c_transfer`. The public driver
continues to require address ACK. `tests/esp32/bus-fifo-pulls-physical.flex`
combines that proof with the RTC-pad pull probe. Both are RAM-only fixtures.
GPIO34..39 have no internal pulls: pull-none performs no register write and
requested pull-up/down returns-22, preserving their ADC/sensor pad controls.

The user-confirmed GPIO21-to-GPIO19 jumper additionally verifies successful
peer transactions: `tests/esp32/i2c-peer-physical.flex` runs174 cases using
each I2C controller as master at10/100/400kHz. It checks payloads in the other
controller's actual RX FIFO and reads its preloaded replies, including full
FIFOs, repeated START, NACK, unchanged RX on timeout and successful retries.
SCL22 feeds the other controller through the GPIO input matrix. Both SDA pads
are open-drain; this is a real shared SDA wire, not software-faked ACK/data.

The same jumper supplies MOSI21-to-MISO19 for
`tests/esp32/spi-peer-physical.flex`:176 verified transfers across both SPI
controllers, all4modes and configured100kHz/1/5/20MHz; plus64KiB in-place
transfers in every mode, GPIO23 software-CS low/high pad readback, and retries
after an expired cycle budget. The64KiB fixture uses `esp32-radio-elf` for its
larger SRAM/stack layout; it does not start a radio. The initial short UART
observer expired after two completed modes and reset the board; identical
firmware completed with a longer observer. Every run checks the full4MiB
flash checksum and resets. These tests do not measure external timing/voltage
or claim interoperability with an unrelated external peripheral device.

Frozen sources, the compiler, independent register references and all3 final
hardware images reproduce exactly under
`build/esp32-goal-verification/bus-io-fixes/report.json`.

Original ESP32 LEDC PWM and RMT now have separate native drivers. API,
clock/ownership limits and physical waveform fixtures are documented in
[Original ESP32 PWM and RMT](esp32-signals.md) and
[original ESP32 raw ADC](esp32-adc.md). S3 analog and peripheral verification
retain their own gates.

An independent [Xtensa machine-code emulator](esp32-emulator.md) is under
development alongside the backend. Its CPU subset runs emitted firmware;
full peripheral parity remains T223.
