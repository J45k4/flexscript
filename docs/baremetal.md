# Bare-metal x86-64 target

```sh
flex --target baremetal-x86_64 kernel.flex -o kernel.bin
qemu-system-x86_64 -accel tcg -m 64M -smp 1 -display none \
  -monitor none -serial stdio -nic none -no-reboot -no-shutdown -kernel kernel.bin
```

This target emits a flat Multiboot 1 image loaded at 4 MiB. The compiler emits
the boot header and CPU startup code itself: page tables identity-map the first
four GiB using 2-MiB supervisor pages, the CPU enters long mode, a stack is installed
at 3 MiB, and `main()` is called. Returning from `main()` disables interrupts and
halts. The image is limited to 1 MiB. Use at least 64 MiB of guest RAM.

All compiler and kernel source can be Flexscript. There is no assembler, linker,
C runtime or guest Linux dependency. QEMU supplies its normal firmware and
Multiboot loader. Its host implementation is external tooling.

The kernel entry must be `fn main()` with no arguments. The saved Multiboot magic
is a zero-extended word at `0x400020`; the boot-information pointer is at
`0x400028`. The stack and page tables at `0x100000..0x106000` are reserved.
Manage heap allocation in the kernel using the boot memory information.

Functions, globals, integer arithmetic, imports, strings, `load8`, `load64`,
`store8` and `store64` work as with native Linux compilation. The bare-metal
target adds privileged hardware builtins:

| Builtin | Operation |
| --- | --- |
| `port_in8(port)` | Read an unsigned byte from an x86 I/O port. |
| `port_out8(port, value)` | Write the low byte to an x86 I/O port; return zero. |
| `port_in16(port)` / `port_out16(port, value)` | Read/write a 16-bit I/O value. |
| `port_in32(port)` / `port_out32(port, value)` | Read/write a 32-bit I/O value. |
| `cpu_halt()` | Disable interrupts and halt forever. |

Linux `alloc`, `syscall` and FFI calls are rejected during compilation. Hardware
builtins are rejected on the Linux and VM targets. Interrupts stay disabled;
drivers must poll until interrupt handling is implemented. This initial backend
does not install an IDT or offer scheduling, protection between native tasks,
automatic heap allocation, or a freestanding Flexscript VM.

Build the compiler containing this backend using an existing Flexscript compiler:

```sh
/path/to/released-flex compiler/main.flex -o build/flex
build/flex --target baremetal-x86_64 tests/baremetal/serial.flex -o build/serial.bin
build/flex scripts/test-baremetal.flex -o build/test-baremetal
build/test-baremetal --compiler build/flex --qemu qemu-system-x86_64
```

Released 0.0.5 can build the updated compiler; that frozen release does not itself
implement this target. Normal compilation still emits Linux ELF executables.

The QEMU regression fixture verifies 64-bit global/memory operations, recursive
calls, signed division, UART output and real UART input. It also finds standard
VGA using 32-bit PCI configuration I/O, checks 16-bit VBE port reads/writes and
accesses the high PCI framebuffer through the identity mapping. Compiler CI runs it
after the three-stage self-hosting and language/VM suites.

References: [Multiboot header and loading rules](https://www.gnu.org/software/grub/manual/multiboot/multiboot.html),
[QEMU system emulator](https://www.qemu.org/docs/master/system/qemu-manpage.html).
