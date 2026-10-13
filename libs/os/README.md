# OS components

Runtime components for executing Flexscript programs with resident workers,
explicit work descriptions and shared command/result memory.

[`gpu/`](gpu/README.md) contains the first implementation: a cooperative AMD GPU
worker team that drives Qwen decoding. A future `cpu/` sibling can provide CPU
workers behind similar request interfaces.
