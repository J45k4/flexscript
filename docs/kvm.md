# Linux KVM virtual machines

`lib/kvm.flex` implements a Linux x86-64 virtual machine monitor interface in
Flexscript, using `/dev/kvm` directly. Linux KVM executes guest CPU instructions;
Flexscript owns RAM, CPU setup, image loading and userspace device emulation.
The monitor does not launch or link QEMU. No compiler changes or new language
syntax are required.

This is separate from the [Flexscript bytecode VM](vm.md): these guests execute
x86 machine code, including privileged kernel instructions.

## Build and run

From the Flexscript repository root, with a current compiler:

```sh
build/flex-publish tools/flexvirt.flex -o build/flexvirt
build/flexvirt --check
build/flexvirt --demo
```

Substitute your compiler path for `build/flex-publish`. `--check` creates a VM,
64 MiB RAM and one vCPU, configures CPUID, then releases them. It does not execute
guest instructions. `--demo` (also the default with no arguments) builds a small
16-bit x86 guest in memory, prints through emulated COM1, and exits successfully
when the guest executes HLT.

Two explicit software paths are also available:

```sh
# A normal process with our x86 interpreter/JIT; no /dev/kvm required.
build/flexvirt --backend software --demo
build/flexvirt --backend software --kernel workdir/flexos/build/flexos-baremetal.bin
# Test our KVM backend through an emulated API transport.
build/flexvirt --backend kvm-emulated --demo
build/flexvirt --backend kvm-emulated --kernel workdir/flexos/build/flexos-baremetal.bin
```

Both paths share the software CPU, Multiboot loader, RAM/exit-buffer layout and
serial device. `kvm-emulated` additionally exercises the KVM library's creation,
memory registration, CPU setup, mapping and ioctl sequence. It is an in-process
test transport, not an operating-system `/dev/kvm` replacement for arbitrary
applications. See [software x86 architecture and limits](x86.md).

Software guests default to 100 million instruction steps across run calls.
`--fuel N` sets a limit from one to one trillion for either emulated backend;
REP iterations each consume a step. This option is rejected for hardware KVM.
`--check` identifies the selected backend in its output. Both emulated backends
default to native block translation with checked interpreter fallback. Use
`--cpu-engine interpreter` to disable translation, or `--stats` to report native
coverage and translation attempts. See the [CPU benchmark](x86.md#native-execution-and-benchmarking).

Emulated Linux boots accept `--userspace-clock-divisor N` (a power of two from
16 to 4096; default 16). PIT/RTC initially use one tick per 16 instruction or
idle steps. The first userspace execution switches to the requested divisor
without resetting counter history. Larger divisors give the software CPU more
instructions between interrupts and guest timer deadlines; they change guest
time relative to execution. RDTSC is a separate instruction counter. See the
[Omarchy boot status and installed-disk frontend](omarchy-boot.md) for current
runtime evidence and direct boot from FAT32/UKI payloads with the ISO detached.

Emulated backends accept `--net user` to attach a modern virtio-net device at
PCI slot 4, IRQ 5. Flexscript owns its split queues and checked scatter DMA;
the optional standalone `libslirp.so.0` library supplies IPv4 NAT, DHCP and DNS.
No QEMU process or TAP interface is used. The guest subnet is `10.0.2.0/24`,
gateway `10.0.2.2`, DNS `10.0.2.3`, and the first DHCP lease is `10.0.2.15`.
Host loopback access, inbound forwarding and IPv6 are disabled. Checksum/GSO
offloads and merged receive buffers are not advertised. Networking is off
unless requested, and both Omarchy launchers forward `--net user`.
New diagnostic images append bounded GPU and network state sections. The
network section preserves queues, pending RX frames and libslirp's supported
state stream, including DHCP leases. External connections may disconnect;
this is not lossless migration. Whole-VM recovery with these sections remains
unverified, and the older local recovery reader still rejects these devices.

Run the optional network protocol and device tests on hosts with libslirp:

```sh
build/test-kvm --compiler build/flex-publish --with-user-net
```

These tests use restricted networking and verify ARP, DHCP, callback ABI bytes,
queue wraparound, interrupt suppression and DMA rejection without Internet
traffic. The separate Linux diagnostic passed actual driver binding, DHCP,
DNS and an outbound HTTP response; see [Omarchy runtime evidence](omarchy-boot.md).

The default hardware backend needs hardware virtualization, Linux KVM and permission to open
`/dev/kvm` read/write. Containers also need that device exposed. Missing device
access produces an error; there is no automatic software-emulation fallback.

## Boot a Flexscript kernel

```sh
build/flex-publish --target baremetal-x86_64 tests/kvm/serial.flex -o build/kvm-serial.bin
printf Z | build/flexvirt --kernel build/kvm-serial.bin
```

The fixture prints `KVM kernel ready`, reads and echoes `Z`, and halts. It runs
the compiler's protected-mode to long-mode bootstrap, unlike the 16-bit demo.

The existing FlexOS serial image uses this same flat Multiboot format:

```sh
build/flexvirt --kernel workdir/flexos/build/flexos-baremetal.bin
```

The loader validates the header, checksum, supported flags, file offsets, load
range, BSS and entry point. It builds Multiboot memory information and enters
32-bit protected mode with the Multiboot magic in EAX and info address in EBX.
The kernel's bootstrap installs its page tables and enters long mode itself.
No firmware or bootloader executable is used.

COM1 output goes to stdout; stdin supplies COM1 input. Terminal input uses the
host's existing line buffering, so press Enter to send a line. Ctrl+C terminates
the monitor. Guest HLT ends the monitor with status zero. Invalid images, failed
KVM operations and unsupported exits return status one; invalid CLI usage returns
two. The monitor reports the numeric exit reason for unexpected guest exits.

## Library API

| Function | Result |
| --- | --- |
| `kvm_create(bytes)` | VM handle, or zero on failure; RAM must be page aligned, 1 MiB to 3 GiB |
| `kvm_start(vm, entry, bits, a, b)` | Set flat 16/32-bit CPU state, EAX/RAX=a, EBX/RBX=b; one on success |
| `kvm_run(vm)` | KVM exit reason, or -1 on syscall failure/interruption |
| `kvm_io_data(vm)` | Bounds-checked pointer to a port-I/O transfer, or zero |
| `kvm_close(vm)` | Close owned descriptors and unmap RAM and run state |
| `kvm_multiboot(ram, bytes, image, size)` | Load a flat Multiboot image and return its entry, or zero; ram=0 validates only |

Errors set `kvm_message` and `kvm_error`. The first library is Linux x86-64 only;
ioctl values and structure layouts are checked against system headers by the test
suite. Handles are opaque to applications except for the current low-level layout:
RAM pointer at offset 24, RAM size at 32, run pointer at 40, run mapping size at 48.
Applications must handle each exit before calling `kvm_run` again. I/O completion
occurs when reentering KVM. The command-line monitor handles byte COM1 transfers
and HLT; other exit reasons fail visibly.

## Verification and limits

```sh
build/flex-publish scripts/test-kvm.flex -o build/test-kvm
build/test-kvm --compiler build/flex-publish
# Alternatively, place temporary artifacts in a new workspace directory:
build/test-kvm --compiler build/flex-publish --work-dir build/kvm-check-new
# On a KVM-enabled host, prohibit hardware execution skips:
build/test-kvm --compiler build/flex-publish --require-kvm
```

Offline checks require `cc`, GNU `as` and `objcopy`. They cover Linux ABI
layouts/constants, valid boot loading and BSS,
Multiboot memory information, malformed images and I/O transfer bounds. The
hardware checks run the real-mode guest and a compiled long-mode kernel, including
serial input/output and HLT. Missing/inaccessible `/dev/kvm` is explicitly reported
as a hardware skip; other initialization failures fail the suite. Header checks
need a C compiler and Linux development headers, but the monitor itself does not.

The suite always executes both emulated backends, covering the real-mode demo,
protected-mode/long-mode bootstrap, a recursive arithmetic kernel, serial I/O,
halt and instruction exhaustion. It compares 18,496 arithmetic results and status
flags against real host x86 instructions, and checks decoding, page translation,
1,121 native full-width multiply/divide cases, guest page-fault recovery,
Linux boot parameters and handoff, PCI configuration accesses, memory bounds,
invalid instructions and API lifecycle cleanup. These checks run before any
hardware skip.

Local verification passed the offline suite, both emulated backends and the
native x86 comparison suite. The existing FlexOS serial image boots, accepts
shell commands and halts through both `software` and `kvm-emulated`. Hardware
execution remains unverified because `/dev/kvm` is absent in this environment.

This is one vCPU with COM1 serial I/O. The emulated Linux platform connects
serial interrupts to IRQ4; hardware KVM still uses polling. Linux guests have
a minimal PCI host bridge and optional native boot-framebuffer window
(`--window`, emulated backends only), plus read-only regular-file virtio
media (`--iso FILE`) and a separate writable regular-file VM disk (`--disk FILE`).
An experimental 2D virtio GPU (`--virtio-gpu`, emulated backends only) supports
resources, DMA transfers, scanout and cursor queues. The native window switches
to its pixels when the guest selects a scanout. Unit and bare-metal guest probes
pass; a diskless run of Omarchy's official Linux kernel also initializes its
virtio GPU framebuffer and passes DRM topology/render-node checks. Desktop
operation remains unverified. See
[Omarchy boot evidence](omarchy-boot.md).
There is no PC firmware, network, SMP or snapshot support
or general QEMU device compatibility. An experimental Linux bzImage loader
with an optional matching uncompressed ELF is available; see
[software x86 guests](x86.md#experimental-omarchy-kernel-boot). Use the serial
FlexOS target; desktop and Doom targets need additional devices. Multiboot HLT
is treated as termination. Emulated Linux guests have a limited PIT/PIC/RTC
platform and ring-0 interrupt delivery, including HLT wakeup; see the CPU/device
limitations in that document. Hardware KVM interrupt injection remains absent. A hardware guest that
never exits can run indefinitely; use an external timeout when running untrusted
or experimental kernels. This initial monitor has no host resource sandbox.

Reference: [Linux KVM API](https://docs.kernel.org/virt/kvm/api.html).
