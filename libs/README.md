# Flexscript libraries

New multi-module libraries live in their own subdirectory here. Existing
low-level adapters in `lib/` remain available and can be imported directly.

- [`autotune`](autotune/README.md): native Flexscript kernel generators, compute
  sweeps, correctness checks and GPU benchmark reports.
- [`ml`](ml/README.md): tensors, reverse-mode autodiff, neural-network layers,
  optimizers and optional CUDA kernels, implemented in ordinary Flexscript.
- [`compress`](compress/README.md): native Zstd-compatible streaming decoding
  and fast encoding, with standard-format interoperability.
- [`http`](http/README.md): native HTTP/HTTPS requests, incremental streaming,
  deadlines and cancellation, with verified OpenSSL TLS and no libcurl.
- [`db`](db/README.md): FlexDB, an experimental single-file relational database
  with typed rows, transactions and programmatic queries.
- [`physics`](physics/README.md): a portable rigid-body engine with shared native,
  WebAssembly, HIP and direct AMD RDNA solver source.
- [`render`](render/README.md): native meshes, cameras, custom shader materials,
  depth passes, textures and shared SetaScript water/atmosphere shaders.
- [`monolith`](monolith/README.md): native web apps with keyed HTML/SSE updates,
  bundled browser assets, and optional SQLite persistence and schema tooling.

Named imports such as `import "monolith";` resolve through the compiler's source
library installation or `FLEXSCRIPT_LIB`. See [installation and named imports](../docs/monolith.md#install-source-libraries).
