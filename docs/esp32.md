# Bare-metal ESP32 and ESP32-S3

`--target esp32s3` (LX7) and `--target esp32` (original LX6) compile Flexscript directly into Xtensa instructions and
packages a ROM-loadable firmware image. The backend, startup, image writer,
platform adapter and regression harness are written in Flexscript. Firmware
compilation invokes no assembler, linker, C compiler, Rust compiler or ESP-IDF
build. There is no interpreter or RTOS in the generated firmware.

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

The internal calling convention uses `callx0`/`ret`, a2:a3 for values, a14 for
the frame and a1 for the stack. Optional ELF targets bridge to the windowed C
ABI for vendor archives; see [vendor integration](esp32-vendor.md). Locals
are initialized to zero. The compiler emits only functions reachable from
`main()`, allowing unused platform-specific helper bodies in imports.

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

These regions account for the IRAM/DRAM aliases of physical SRAM. Individual
function frames are limited to 16 KiB, with runtime stack checks on entry and
expression pushes. `alloc` rounds to eight bytes, returns `-12` on exhaustion
and `-22` for zero size, and has no free operation. Calling `alloc` from an
interrupt callback traps, preventing main/ISR allocator races. ISR callbacks
must be bounded, acknowledge their device and avoid allocation. No PSRAM is required.

The first 16 DRAM bytes are reserved: heap cursor at +0, completion status at
+4 (`0x444f4e45` for returned main, `0x54524150` for a trap), and main's 64-bit
result at +8. These markers allow bounded emulator verification without a
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

Initial validation used Espressif QEMU
`esp-develop-9.2.2-20260417` on Linux x86-64. GPIO register writes execute in the
emulator; external pin voltages, LED blinking, UART receive and a physical
ESP32-S3 board have not been verified. QEMU does not implement the physical
IO_MUX behavior. The live example's blink loop is exercised separately; its
cycle delays are not a calibrated wall-clock interval.

Format and register references:

- [Espressif ROM firmware image format](https://docs.espressif.com/projects/esptool/en/latest/esp32s3/advanced-topics/firmware-image-format.html)
- [Pinned ESP32-S3 register definitions, ESP-IDF v5.5.1](https://github.com/espressif/esp-idf/tree/v5.5.1/components/soc/esp32s3/register/soc)
- [Xtensa ISA reference](https://dl.espressif.com/github_assets/espressif/xtensa-isa-doc/releases/download/latest/Xtensa.pdf)
- [Espressif ESP32-S3 emulator](https://github.com/espressif/esp-toolchain-docs/blob/main/qemu/esp32s3/README.md)

## Original ESP32 and RAM-only board tests

The original ESP32 has different peripheral addresses, memory layout, chip ID
and boot offset. Use `lib/platform/esp32.flex`, `esp32-irq.flex`,
`esp32-common.flex` and `esp32-timer.flex`. Its current adapters cover UART0,
GPIO, level-1/software interrupts and the four timer-group counters. The
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
| `esp32s3-adc.flex` | ADC1/2 RTC one-shot raw 12-bit readings and attenuation | Host model of conversion/timeout; analog operation and calibration unverified |
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
