# ARM64 Linux backend

`--target linux-arm64` (alias `aarch64`) compiles Flexscript, SetaScript and
validated FIR into a static, little-endian AArch64 Linux executable. The backend
is written in Flexscript and emits machine instructions and ELF headers directly.
Building a program does not invoke an assembler, C compiler, linker or emulator.

Build the compiler using an existing Flexscript compiler, then run a program
with QEMU's Linux user emulator:

```sh
mkdir -p build
flexscript compiler/main.flex -o build/flex-arm64
build/flex-arm64 --target linux-arm64 examples/arm64/hello.flex -o build/hello-arm64
qemu-aarch64-static build/hello-arm64
```

`qemu-aarch64` works as well when supplied by the installed QEMU package. The
example prints `Hello from native ARM64 Flexscript!`. No guest Linux image,
ARM64 libc, root filesystem or cross sysroot is needed for these static programs.

## Supported behavior

- Signed 64-bit words, wrapping arithmetic, bitwise operations, masked shifts,
  comparisons, boolean short-circuiting, branches and loops.
- Functions, recursion, imports, globals, writable string literals, up to 4096
  local/parameter slots, and `main()` or `main(argc, argv)`.
- `load8`, `load64`, `store8`, `store64`, unaligned accesses and zero-initialized
  `alloc` mappings. Loads and stores use real process addresses.
- Raw Linux ARM64 `syscall`, with the six arguments in x0-x5 and number in x8.
- SetaScript/FIR state and bounds-checked arrays; unbuffered eight-byte
  little-endian `read_word`/`write_word`; explicit `--platform` modules.
- External FIR and generated-source frontends, and compile-time transforms.
  Extension code continues to run in the compiler host's restricted VM.

Integer calls follow AAPCS64: x0-x7 carry the first eight arguments, further
arguments occupy the caller's stack in source order, and x0 carries the return
value. SP remains 16-byte aligned. Generated functions preserve x29/x30 through
a frame record and do not use x18 or x19-x28. This is the integer subset of the
ABI; there is no floating-point/vector/aggregate C ABI or external symbol linker.

Division or remainder by zero and MIN/-1 explicitly trap with `BRK`. Array
indexes outside their declared span also trap. ARM64's hardware `SDIV` would
otherwise silently produce a value for those invalid arithmetic operations.
Word I/O retries interrupted calls and handles partial transfers; EOF or error
before a complete word returns -1, matching the existing native FIR behavior.

## Syscalls and libraries

**Syscall numbers are architecture-specific.** `syscall(1, ...)` is not an ARM64
write. The compiler does not translate x86-64 syscall IDs or structure layouts.
Use [the ARM64 Linux adapters](../lib/platform/linux-arm64.flex), which provide
read, write, openat-based open, close, seek, munmap, clock_gettime and exit.

For example:

```flex
import "lib/platform/linux-arm64.flex";
fn main() {
    return arm64_write(1, "hello\n", 6) != 6;
}
```

The existing x86-64 Linux libraries, compiler-host runtime and FlexOS platform
services have not been ported wholesale. Compiling the compiler into a working
ARM64-hosted compiler is a separate runtime-porting milestone. The compiler
containing this backend can still rebuild itself on its existing x86-64 host.

`ffi_open`, `ffi_symbol`, and the `ffi_call` builtins are rejected, as are buffered
word I/O and x86 bare-metal builtins. User-defined functions with FFI names still
resolve as ordinary functions. This Linux target produces static executables.
The separate [`android-arm64` target](android.md) produces position-independent
objects for shared-library linking and Android APK packaging.

## Executable layout

The output is ELF64 `ET_EXEC`, machine `EM_AARCH64`, with a fixed code image at
0x400000 and entry at 0x401000. Static data starts at 0x10000000. Code and data
have separate RX and RW load segments, aligned to 64 KiB; the GNU stack header
requests a non-executable stack. `.text`, `.data` and `.shstrtab` sections permit
inspection with `readelf` and `llvm-objdump`. Allocation uses Linux anonymous
read/write `mmap` mappings rather than an executable heap.

Local branch displacements are checked. Conditional IR branches use an inverted
short condition around an unconditional branch, supporting functions larger
than the conditional instruction's range. Calls and unconditional branches
currently use the signed 26-bit branch displacement; an oversized displacement
is a compile error. No register allocator or optimized instruction scheduler is
implemented yet: locals and expression temporaries reside in stack frames.

## Verification

```sh
python3 scripts/test-arm64.py build/flex-arm64 --report build/arm64-tests.json
```

The suite requires Python 3, `qemu-aarch64` or `qemu-aarch64-static`, `clang`, and
`ld.lld`. LLVM is used only as an independent ABI test oracle. On Debian/Ubuntu
these tools are available in `qemu-user`, `clang`, and `lld` packages.

Tests include existing language fixtures and invalid-source diagnostics, 5154
full-width arithmetic results checked against Python and the x86-64 backend,
register/stack arguments through 4096 parameters, large frames and long branches,
traps, file I/O, state arrays, word I/O, frontend/platform integration, ELF layout
and deterministic emission. A separate LLVM-assembled caller invokes generated
code and checks stack arguments, preserved registers and stack alignment.

These Linux tests are **QEMU user-emulation results**. Android has its own
[object and emulator tests](android.md); physical ARM64 and FlexOS boot
verification remain separate milestones.

References: [AAPCS64](https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst),
[QEMU user emulation](https://www.qemu.org/docs/master/user/main.html).
