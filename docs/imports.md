# Source imports

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

## HTTP and HTTPS imports

The current compiler can fetch source directly from an HTTP or HTTPS URL:

```flexscript
import "https://example.com/flex/math.flex";
import "http://localhost:8080/flex/helpers.flex";

fn main() {
    return add(20, 22);
}
```

Within a downloaded file, `import "helpers.flex"` resolves against that file's
URL directory, and `import "../shared.flex"` resolves against its parent.
Paths starting with `/` resolve against the same origin, not the host
filesystem. `//host/path` retains the importing URL's scheme. Query strings are supported. After a
redirect, relative imports use the final URL. The downloader accepts up to five
redirects with absolute or origin-relative locations. HTTP-to-HTTPS redirects
are supported; redirects from HTTPS back to HTTP are rejected. A source can
explicitly import either scheme, including a mixed HTTP/HTTPS dependency graph.

URL identity lowercases hostnames, removes the default port and literal dot
segments, and preserves query strings, repeated slashes and percent escapes.
Repeated URLs and diamond dependencies share definitions. Redirects to an
already loaded URL share that module too. URL cycles are rejected. Diagnostics
include the source URL, line and column.

HTTP imports use Flexscript's TCP implementation. HTTPS imports use OpenSSL 3
directly, with certificate and hostname verification and the host's trusted CA
store. No curl or external downloader is invoked. Credentials in URLs, fragments
and IPv6 literal authorities are unsupported. Downloads share a 30-second deadline per
compilation and the same file-count, nesting and combined source-size limits as
local imports. Sources are kept in memory for this compilation; there is no
persistent download cache. The static core cannot fetch URL sources because
the system DNS resolver requires FFI.

Native compilation and VM execution fetch URL sources by default:

```sh
flex run app.flex
# The entry source can also be a URL:
flex run https://example.com/flex/app.flex
flex run http://localhost:8080/app.flex
# Disable downloads when running local source:
flex run --no-url-imports app.flex
```

`--no-url-imports` rejects URL sources before making a network request.
`flex run --restricted` also disables downloads unless `--allow-url-imports`
is provided. In restricted mode, source downloads do not grant network or FFI
access to guest code. Ordinary `flex run` permits native host operations.
Use immutable URLs, such as a Git commit path, when builds
need to reproduce the same source.

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

Build `build/tools` once using the [Flexscript tooling instructions](bootstrapping.md).

```sh
build/tools/test-imports build/flexscript
build/tools/test-url-imports build/flexscript
```

Repeat the full bootstrap chain, core tests, import tests, and a rebuild in an
empty filesystem with no Rust, libc, or other compiler:

```sh
build/tools/bootstrap --compiler build/downloaded/flexscript-0.0.1-linux-x86_64 \
    --out-dir build/imports-bootstrap
```

That final clean-room check also compiles and runs the nested-import example.
