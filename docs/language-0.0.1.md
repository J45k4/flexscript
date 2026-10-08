# Flexscript 0.0.1 core

The bootstrap core is a general imperative language targeting Linux x86-64.
Its compiler emits ELF executables containing native instructions directly.
There is no interpreter, intermediate C, assembler, linker, or libc dependency
in generated executables. Source files use `.flex`.

This document describes the released bootstrap core. The 0.0.2
compiler also supports [local imports](imports.md); the published 0.0.1 binary
must first compile that updated compiler to use this extension.

```text
global total = 0;

fn sum(n) {
    let result = 0;
    while n > 0 {
        result = result + n;
        n = n - 1;
    }
    return result;
}

fn main(argc, argv) {
    total = sum(10);
    return total;
}
```

## Values and storage

Every value is one 64-bit word. Arithmetic and comparisons interpret words as
signed two's-complement integers. Addresses are words too. Boolean results are
0 or 1; zero is false and every other value is true. Addition, subtraction,
multiplication, and negation wrap modulo 2^64. Division truncates toward zero;
remainder has the dividend's sign. Division by zero and MIN / -1 trap. Shift
counts use their low six bits; right shift is arithmetic.

Decimal literals range from 0 to 9223372036854775807. Hexadecimal literals
(`0x...`) encode any 64-bit pattern. Negative values use unary `-`. Identifiers
are ASCII letters or underscores followed by letters, underscores, or digits.
`//` comments run to the end of a line. Statements end in `;`.

`let name = expression;` creates a mutable block-scoped local. Parameters are
mutable locals. Inner blocks can shadow names. Duplicate declarations in the
same scope and undefined variables are errors. Top-level mutable `global`
declarations have literal initializers and precede functions. Globals and
functions share a namespace. Builtin names and language keywords are reserved.

Strings are UTF-8 bytes followed by a zero byte; the value is their address.
Escapes: `\n`, `\r`, `\t`, `\0`, `\\`, and `\"`. String contents are writable
in this initial backend. Memory is explicitly managed: `alloc` obtains zeroed
storage for the process lifetime. No collection, implicit ownership, or bounds
checking exists in the bootstrap core. Compiler buffers have explicit limits.

## Expressions and statements

Precedence, highest first:

1. Function calls, parentheses.
2. Unary `-`, `!`, `~`.
3. `*`, `/`, `%`.
4. `+`, `-`.
5. `<<`, `>>`.
6. `<`, `<=`, `>`, `>=`.
7. `==`, `!=`.
8. `&`, then `^`, then `|`.
9. `&&`, then `||`.

Binary operators associate left. `&&` and `||` short-circuit and yield 0 or 1.
Arguments evaluate left to right. Functions can call later-defined functions
and recurse; call argument counts are checked. Functions without an explicit
return yield zero. Functions are named, not first-class values.

Statements: local declaration, assignment to a local or global, expression
statement, `return expression;`, `if expression { ... } else { ... }`, and
`while expression { ... }`. `else if` is supported. Braces introduce scopes.
The entry function is `main()` or `main(argc, argv)`. The kernel supplies argc
and a pointer to an array of string pointers. Its return value becomes the
process exit status (low eight bits).

## Builtins and operating-system interface

| Operation | Behavior |
| --- | --- |
| `load8(address)` | Read one byte, zero-extended. |
| `store8(address, value)` | Write the low byte; return value. |
| `load64(address)` | Read a word; unaligned addresses are allowed. |
| `store64(address, value)` | Write a word; return value. |
| `alloc(bytes)` | Linux anonymous mmap, read/write; returns address or negative errno. |
| `syscall(number, a, b, c, d, e, f)` | Linux x86-64 syscall, with six argument words. |

Raw syscalls return negative errno on failure. Syscall numbers and constants
are Linux x86-64 specific. The compiler uses read/write/open/close, fstat, ftruncate, fchmod,
mmap, and exit. See `compiler/main.flex` for the file and diagnostic helpers.

## Compiler contract and limits

`flexscript source.flex -o executable` compiles one source file. `--help` and
`--version` work without a source file. Invalid source and I/O failures produce
stderr diagnostics and nonzero status. Source diagnostics include the path,
line, and byte column. Output is written only after compilation succeeds.

Version 0.0.1 has a single source unit and a custom internal stack calling
convention. Modules, aggregate types, floating point, FFI, optimizations,
additional targets, and automatic memory management are future work. Executables
use a single read/write/execute ELF segment in this bootstrap backend.

Limits: source below 16 MiB, emitted file at most 64 MiB, 2048 globals,
2048 functions, 4096 active locals / slots per function, 65536 call sites,
and 128 nested expressions, blocks, or conditional chains. Exceeding a limit is
a compiler error. Output symlinks are rejected, and source/output aliases are
rejected before truncation.
