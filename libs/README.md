# Flexscript libraries

New multi-module libraries live in their own subdirectory here. Existing
low-level adapters in `lib/` remain available and can be imported directly.

- [`ml`](ml/README.md): tensors, reverse-mode autodiff, neural-network layers,
  optimizers and optional CUDA kernels, implemented in ordinary Flexscript.
- [`db`](db/README.md): FlexDB, an experimental single-file relational database
  with typed rows, transactions and programmatic queries.
- [`monolith`](monolith/README.md): native web apps with keyed HTML/SSE updates,
  bundled browser assets, and optional SQLite persistence and schema tooling.

Named imports such as `import "monolith";` resolve through the compiler's source
library installation or `FLEXSCRIPT_LIB`. See [installation and named imports](../docs/monolith.md#install-source-libraries).
