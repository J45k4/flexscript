# FlexScript
See [function lowering hooks](docs/lowering.md) for explicit symbol bindings,
native SSE2 float arithmetic, portable fallbacks and reference mode.

The optional [optimizing CPU kernel backend](docs/cpu-kernels.md) emits C++17
from validated word IR, then uses Clang for native register allocation.
