# SetaScript and frontend input on ESP32

The Xtensa backend accepts the bundled SetaScript frontend, validated portable
FIR1..FIR6 artifacts and external frontend extensions on all seven ESP32 output
profiles. Each route emits native Xtensa instructions. There is no interpreter
or frontend extension running on the device.

The existing SetaScript subset is unchanged: `i32` and `bool` functions,
conditionals, literal-bounded loops, initialized scalar/array state and word
messages. Its integer values retain the existing signed64-bit word semantics,
despite the `i32` spelling. Checked array indexing retains all64 index bits;
negative, out-of-range and high-word aliases fail-stop before accessing memory.
The frontend's existing recursion, type, loop and syntax checks still apply.
Hardware intrinsics and Linux/FFI restrictions keep their normal target rules.
Low-level hardware calls belong in Flexscript adapters or source frontends;
this change does not add host-call syntax to SetaScript.

## Compile a program

Use a compiler built with this support, selected explicitly through `FLEX`:

```sh
FLEX=build/esp32-goal-verification/frontends/flexscript
"$FLEX" --target esp32 examples/esp32-word-echo.seta -o build/echo.bin
"$FLEX" --target esp32s3 examples/esp32-word-echo.seta -o build/echo-s3.bin
```

`.seta` selects the bundled frontend automatically. `--language seta` selects it
for another filename. Saved IR is explicit:

```sh
"$FLEX" --target ir examples/esp32-word-echo.seta -o build/echo.fir
"$FLEX" --language ir --target esp32-elf build/echo.fir -o build/echo.elf
```

The output profiles and normal memory/startup contracts remain:

| Target | Output and startup |
| --- | --- |
| `esp32`, `esp32s3` | Direct ROM image for the corresponding chip |
| `esp32-elf`, `esp32s3-elf` | ELF for RAM loading or the explicit linker driver |
| `esp32-radio-elf` | Original-ESP32 ELF with reserved SDK/radio SRAM |
| `esp32-xip-elf` | Original-ESP32 cached code; requires the native cache initializer |
| `esp32-btdm-elf` | Cached code and Bluetooth-safe original-ESP32 memory layout |

For ELF output, compile `scripts/esp32-link.flex` and supply the normal explicit
GNU `--ld` and ROM-script inputs. Supply `--image` to produce a ROM image;
cached profiles also require `--xip`. See [vendor linking](esp32-vendor.md).
State shares the normal target static image:64KiB maximum, or32KiB in the
reserved-radio layouts, including control words and native adapter data.
Large portable IR profiles do not expand physical MCU memory. The existing
128KiB IRAM/16KiB function-frame bounds also remain in force.

## Explicit native platform adapters

`--esp32-platform adapter.flex` adds a trusted Flexscript module and its normal
imports after frontend lowering. It is available only for frontend ESP32
compilation. Native functions and globals share the same linked program and
static image with FIR functions/state. Duplicate function/global names and
output aliases into app/platform/frontend inputs are rejected.

Use the existing cache initializer for cached SetaScript or FIR applications:

```sh
"$FLEX" --target esp32-xip-elf \
  --esp32-platform lib/platform/esp32-xip.flex \
  examples/esp32-word-echo.seta -o build/echo-xip.elf
```

An adapter may export `fn esp_platform_init()` to configure hardware and call
application functions before `main`. The compiler calls it after cache setup,
where applicable. It must take no parameters and return the64-bit word zero;
a nonzero result fail-stops before `main`. Without this function no extra
initialization hook runs. The option does not enable radios or peripherals
automatically.

Native code can call typed application functions using the ordinary private
word ABI and register native interrupt handlers that call them. Adapters are
responsible for the application's type and synchronization contracts; shared
64-bit state is not implicitly atomic across interrupts. ISR allocation remains
forbidden. The physical fixture pairs
[`frontend-physical.seta`](../tests/esp32/frontend-physical.seta) with
[`frontend-physical-platform.flex`](../tests/esp32/frontend-physical-platform.flex):
the adapter configures a hardware timer, acknowledges interrupts and calls the
SetaScript `on_timer` function while main exchanges UART messages.

External frontends continue to run in the existing bounded host VM, without
file/network/FFI grants. Target flags are cleared inside that VM. Portable FIR
passes through the shared validator; FSX1 source results reuse the ordinary
target parser and intrinsics. The explicitly selected native platform input is
a compiler input, not an extra VM capability granted to the frontend.

## Word messages

`read_word()` receives exactly eight little-endian bytes from the ROM-configured
UART0 console and blocks until they arrive. `write_word(value)` sends eight
bytes and returns that word. The firmware has no stdin EOF indication. It
retains the configured baud/pins, has no SDK task yield inside its polling loops
and does not add buffered word I/O. One application owns the UART stream.

The classic ESP32 uses8-bit FIFO counts and a separate receiver-state field in
adjacent bits; S3 uses its own wider count fields. The classic read path saves
PS, masks interrupts across the status/FIFO access and restores the exact PS
on both available/empty paths. Waiting therefore permits already-enabled
interrupts to progress. This follows the existing original-ESP32 UART adapter
and its APB erratum protection. Register fields are defined by
[Espressif's pinned UART register header](https://github.com/espressif/esp-idf/blob/v5.5.1/components/soc/esp32/register/soc/uart_reg.h).

ROM boot text shares UART0 before the application starts. Binary host tooling
must distinguish startup text from its own protocol. The regression fixtures
use an explicit `FLEXIO01` ready word; the physical fixture additionally emits
`FLEXPASS` only after its state, full-width values, write return and timer
callback checks succeed.

## Verification

`scripts/test-esp32-frontends.flex` requires explicit `--compiler`, `--ld`,
`--rom` and `--qemu` inputs. `--objdump` optionally selects the GNU Xtensa
disassembler; by default it is derived from the supplied linker prefix.
`--report` and `--uart-model-report` preserve independent JSON evidence.
The verified run passes2044 checks across87 emulator boots.
It is registered in `scripts/build-tools.flex`; run it from the repository root.
The suite covers ROM boot in all seven output profiles, bundled/saved/external
frontends, native Flexscript behavior parity, FIR1..6, native/FIR calls and
initial state, rejected aliases/names, startup failures, checked array traps
and exact64-bit messages split across3/5/3/5-byte writes. It does not flash a
physical board.

The separate UART model executes actual emitted instructions decoded by GNU
objdump against independent register/PS behavior. Its101 cases include all16
classic RX states,15 TX states, three saved PS values, empty/full polling,
exact eight-byte words and two broken-instruction controls. This catches the
classic receiver-state bug that the QEMU UART model did not expose.

The original-ESP32 RAM-only probe receives/sends the independently expected
binary words, updates checked SetaScript state and runs the timer-to-SetaScript
callback during the UART exchange. Full4MiB ROM checksums before/after match the saved
original firmware, and the board is reset afterward. No flash write is used.
S3 execution is emulator-verified; its physical board verification remains a
separate open task.

The final compiler cohort also passes core84, imports46, frontend/IR529,
shaders498, Wasm907, existing ESP32 target1099 and vendor-link/runtime1091
checks. Three self-hosted compiler stages are byte-identical. The final build
reproduces both the exact RAM-tested timer/UART ELF and the earlier physically
verified NVS/Wi-Fi flash image. Source snapshots, binaries, reports, UART data
and full-flash checksum/reset evidence are preserved in
`build/esp32-goal-verification/frontends-verification.json`.
