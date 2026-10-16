# Emulator source layout

The implementation lives under `emulator/`. CPU engines, emulated machines,
guest boot support and host execution backends have separate directories.

| Directory | Contents |
| --- | --- |
| `emulator/common/` | Shared binary and memory helpers. |
| `emulator/x86/` | x86 interpreter, FPU and native block JIT. |
| `emulator/xtensa/` | Xtensa instructions, register windows, USER/FPU state, memory pages, CPU cycles and comparators. |
| `emulator/pc/` | PC interrupt controllers, clocks, PCI, UART, PS/2, virtio devices, guest display, FAT disk reading and Multiboot loading. |
| `emulator/esp32/` | ESP32 board integration, ROM loading and chip-specific peripheral models. |
| `emulator/linux/` | Linux boot protocol, bzImage payload extraction, UKI loading and guest framebuffer support. |
| `emulator/backends/` | Software VM execution, Linux KVM, the emulated KVM test transport and optional libslirp networking. |

The x86 and Xtensa CPU models execute machine instructions. PC and ESP32 models
supply the devices around those CPUs. Linux helpers load a guest kernel onto
that virtual machine; they do not implement a separate CPU engine.

## Entry points

`tools/flexvirt.flex` is the PC monitor. Its explicit execution choices remain
`--backend software`, `--backend kvm` and `--backend kvm-emulated`. The real KVM
backend opens `/dev/kvm`; the emulated KVM transport is an in-process test API.
There is no automatic fallback between these execution choices.

`tests/xtensa/board-run.flex` loads ESP32 firmware ELF files and captures guest
UART output. It uses `emulator/esp32/board.flex` and `emulator/xtensa/cpu.flex`.
Chip coverage and timing limits remain documented in [ESP32 emulation](esp32-emulator.md).

Build the monitor with an installed compiler:

```sh
flexscript tools/flexvirt.flex -o build/flexvirt
```

## Verification

Tests remain in `tests/kvm/`, `tests/xtensa/` and `tests/esp32/`. Their command-line
runners remain under `scripts/`. For the x86/PC/Linux/KVM suite:

```sh
flexscript scripts/test-kvm.flex -o build/test-kvm
build/test-kvm --compiler "$(command -v flexscript)"
```

The suite reports an explicit skip when real KVM is unavailable. Software and
emulated-KVM results do not establish hardware KVM execution.

Xtensa and ESP32 mutation tests use `tests/xtensa/emulator_sources.py` to load the
canonical implementation. Their temporary flat copies retain established
fixture labels such as `xtensa.flex`; these labels are not production import
paths. The helper changes imports for those copies and keeps implementation
bodies intact, allowing existing defect controls to exercise the moved code.

Further details: [x86 execution](x86.md), [KVM monitor](kvm.md),
[Linux guest launchers](omarchy-boot.md), [ESP32 model](esp32-emulator.md).
