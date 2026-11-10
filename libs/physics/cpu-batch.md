# CPU world batches

`cpu-batch.flex` is an optional **native Linux x86-64** host adapter for
independent worlds. It uses Linux pidfds (kernel 5.3 or newer) and calls the
existing allocation-free `ph_step` solver in isolated worker processes.
The common solver, GPU path, numerical timestep, iterations and geometry are
unchanged. It parallelizes worlds; it does not split a single world across CPUs.

```flexscript
import "libs/physics/cpu-batch.flex";
fn main() {
    let count=3;
    let stride=ph_world_bytes(8,8,128,2);
    let worlds=alloc(count*stride);
    let i=0;
    while i<count {
        let w=worlds+i*stride;
        ph_world_init(w,8,8,128,2);
        ph_box_body(w,0,0,0,0xbf000000,0,0x41200000,0x41200000,0x3f000000);
        ph_box_body(w,1,0,0,0x3f800000,0x3f800000,0x3e800000,0x3e800000,0x3e800000);
        i=i+1;
    }
    let result=ph_cpu_batch_advance(worlds,count,stride,500,2,30000);
    syscall(11,worlds,count*stride,0,0,0,0);
    return result!=1;
}
```

All arenas must be contiguous, have the same layout/size, and use the version-1
layout produced by `ph_world_init`. The adapter validates capacities, offsets,
counts, body references and the iteration range before spawning workers.
The caller must exclusively own the arenas during the synchronous call.
Workers are capped at the number of worlds. Counts up to 1024, requests of
1–64 workers, and up to one million steps per call are supported, within a
2 GiB batch allocation limit. Zero steps is a validated no-op.

The deadline is in milliseconds and covers input copying, worker startup and
work. It is checked between bounded host operations and before publishing
results; final copyback and cleanup can extend the total call duration. This is
not a realtime deadline guarantee. A private shared mapping holds in-flight results. Workers inherit
the caller's numerical environment at `fork`; their floating-point status
flags remain process-local. No GPU, rendering, detector or controller runs in
the workers. Inputs must be valid physics worlds; transient solver scratch
contents are not a portable state representation. Warm-cache records and
persistent options survive copyback and further stepping.

Return values:

| Result | Meaning | Input arenas |
| --- | --- | --- |
| `1` | All requested steps completed | Updated |
| `0` | A world reported a physics fault | Updated; inspect each `world+192` |
| `-1` | Invalid arguments or arena layout | Unchanged |
| `-2` | Allocation, pidfd or fork failure | Unchanged |
| `-3` | A worker failed or could not be reaped normally | Unchanged |
| `-4` | Deadline exceeded | Unchanged |

Every child is reaped before its shared mapping is released. Cancellation uses
pidfds, never a possibly recycled PID. A parent-death signal kills workers if
their caller disappears. A caller must not concurrently reap the adapter's
children or modify its input arenas.

Each call currently copies arenas and starts fresh workers. Use enough work to
amortize that cost; this is not a persistent pool or a single-world latency
optimization. Simulator-specific SIMD kernels and previously measured RoboBand
speedups are not part of this adapter. Measure the actual application, including
control, rendering and inference, before claiming a training-speed improvement.

Run the native parity, timeout, worker-death and parent-death tests with:

```sh
python scripts/test-physics-cpu-batch.py --compiler /tmp/flex-physics-compiler
```

The fixture compares every step of all fifteen existing physics scenes,
including moving welds and compound bodies, checks warm-cache resumption, and
verifies that failed workers and timeouts cannot publish partial results.

An optional diagnostic compares sequential stepping with three workers over
30 independent worlds drawn from those fifteen small fixtures, 2,000 steps
each. It alternates arm order across six pairs, includes batch copying,
startup and cleanup, excludes fixture construction in both arms, and requires
exact persistent physical state after every pair. It does not model a
30-band environment or the full simulator:

```sh
/tmp/flex-physics-compiler libs/physics/tests/bench-cpu-batch.flex -o /tmp/bench-cpu-batch
/tmp/bench-cpu-batch
```
