# C FFI

Flexscript can load shared libraries, look up symbols and call fixed-arity C
functions on Linux x86-64 using the System V AMD64 ABI. The compiler emits the
ELF, ABI adapters and dynamic-linking metadata directly. Compilation does not
invoke a C compiler or linker.

```flex
fn main() {
    let libc = ffi_open("libc.so.6");
    if !libc { return 1; }
    let strlen = ffi_symbol(libc, "strlen");
    if !strlen { return 2; }
    return ffi_call(strlen, "hello", 0, 0, 0, 0, 0);
}
```

This program exits with status 5. Library names may be sonames or paths. Loading
uses `dlopen` with `RTLD_NOW`; missing libraries and missing symbols return zero.
Never call a zero symbol pointer. Library loading uses the system loader's search
rules, including its environment configuration.

| Operation | Result |
| --- | --- |
| `ffi_open(name)` | Library handle or zero. |
| `ffi_symbol(handle, name)` | Symbol address or zero. |
| `ffi_call(pointer, a, b, c, d, e, f)` | Raw word/pointer result. |
| `ffi_call_i32(pointer, a, b, c, d, e, f)` | Signed C `int`, extended to a word. |
| `ffi_call_u32(pointer, a, b, c, d, e, f)` | Unsigned C `int`, extended to a word. |

Supply all six argument slots and set unused slots to zero. Supported arguments
are integer words and pointers; narrower C integers use the low bits. Match the
function's actual C signature and choose the appropriate return operation. Void
functions can use `ffi_call` with the result ignored. Structures can be allocated
as byte buffers and passed by pointer using their C ABI layout.

This initial FFI supports up to six integer/pointer arguments. Floating-point
arguments/results, structures passed or returned by value, variadic functions,
general callbacks, and automatic header binding generation are not supported. OpenSSL
macros are handled by calling their underlying exported functions, such as
`SSL_ctrl` and `SSL_CTX_ctrl`.

The adapters preserve the internal Flexscript calling convention and align the
stack for C calls. Named Flexscript functions take precedence over these FFI
intrinsics; the frozen bootstrap uses ordinary shim definitions to build its
static core. Normal applications should use the intrinsic names directly.

Programs using `ffi_open` or `ffi_symbol` require the glibc dynamic loader at
`/lib64/ld-linux-x86-64.so.2` and `libc.so.6`. Programs without those operations
retain the standalone ELF format. Calling a function pointer alone does not add
a loader dependency.

The direct native x86-64 pipeline also supports `native_callback(function)` for
a named function taking exactly six words and returning one word. Compile with
`--native-pipeline direct`. It returns a System V AMD64 trampoline suitable for
passing to C; the target must have all six parameters, including unused ones.
The callback and its globals belong to the originating executable and must not
outlive it. Call synchronously on the originating thread; this does not provide
thread safety, foreign-thread attachment or exception unwinding. Restricted VM,
portable IR and other architecture targets reject this intrinsic. The native
IR pipeline currently rejects it too; use the direct pipeline explicitly.
`scripts/test-native-callback.py` verifies repeated C-to-Flexscript calls with
six arguments and signed results. Collie's desktop broker uses this adapter to
reuse the shared checked engine.

`lib/ffi.flex` provides `ffi_close(handle)` for `dlclose`. A symbol pointer must
not outlive its library handle.

Build `build/tools` once using the [Flexscript tooling instructions](bootstrapping.md).

```sh
./build/flex examples/ffi.flex -o build/ffi-example
./build/ffi-example
build/tools/test-ffi build/flex
```

The integration tests use a tiny C fixture library to independently check the
ABI, argument order, stack alignment, pointer identity, signed/unsigned returns,
stateful calls and symbol errors. The C compiler is a test dependency only.
