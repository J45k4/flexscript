# Local imports

Flexscript 0.0.2 supports importing local `.flex` source files:

```flexscript
import "../lib/net.flex";
import "../lib/strings.flex";

fn main() {
    // Call functions defined in imported files.
    return 0;
}
```

Import declarations end with a semicolon and must appear at the beginning of
a file, before globals and functions. Imported files can import other files.
Relative paths are resolved against the importing file's directory, regardless
of the compiler's working directory. Absolute paths are also accepted. Paths
use the normal string escapes, except a decoded zero byte is rejected. Source
files must be regular files; directories and pipes are rejected.

All imported definitions share one namespace. A function or global is available
by its ordinary name, without an alias or module prefix. Duplicate declarations
are errors, and `import` is now a reserved declaration name. Each file still
requires its globals before its functions. The compiler collects all globals
before compiling functions, so functions can reference globals from any file
in the import graph. Function calls can refer to definitions in later files,
including mutual recursion between functions.

A source file is loaded once per compilation, using its device and inode for
identity. Repeated imports, diamond-shaped dependency graphs, and alternate
paths or symlinks to the same file do not duplicate its declarations. Relative
imports within a file use the path by which that file was first loaded.
Circular imports are rejected. Every loaded definition is compiled into the
same native ELF executable; imports do not perform runtime loading or introduce
a library dependency. There is no package registry, module aliasing, namespace
qualification, or selective import in this first version.

Diagnostics from an imported file retain that file's path, line, and column,
including function errors discovered during final symbol resolution. Failed
compilations preserve an existing output file. The output cannot overwrite any
loaded source file, even through a hardlink.

Limits: 256 distinct files including the entry file, 64 files in an active
import chain including the entry, less than 16 MiB of combined source, and
4095 bytes per resolved import path. Existing global, function, local, call,
and output limits apply across the entire program.

## Build from the bootstrap point

The released 0.0.1 compiler does not itself recognize imports. Its unchanged
core syntax can compile the updated self-hosted compiler:

```sh
mkdir -p build
build/downloaded/flexscript-0.0.1-linux-x86_64 compiler/main.flex -o build/flexscript
build/flexscript examples/imports/main.flex -o build/imported-hello
./build/imported-hello
# Hello from imported Flexscript!
```

The example imports `lib/greeting.flex`, which in turn imports
`lib/strings.flex`. The updated compiler also rebuilds itself without Rust:

```sh
build/flexscript compiler/main.flex -o build/flexscript-rebuilt
cmp build/flexscript build/flexscript-rebuilt
```

This extension ships in 0.0.2. The published 0.0.1 artifact, tag, and Rust seed
remain the original bootstrap point.

## Verification

Run import graph, diagnostic, path, limit, and source-protection tests:

```sh
python3 scripts/test-imports.py build/flexscript
```

Repeat the full bootstrap chain, core tests, import tests, and a rebuild in an
empty filesystem with no Rust, libc, or other compiler:

```sh
python3 scripts/bootstrap.py --compiler build/downloaded/flexscript-0.0.1-linux-x86_64 \
    --out-dir build/imports-bootstrap
```

That final clean-room check also compiles and runs the nested-import example.
