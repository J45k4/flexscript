# Linux native threads

`import "thread";` provides shared-memory kernel threads, joining, sequentially
consistent atomics, and a process-local mutex. The implementation is Flexscript;
the compiler emits a small x86-64 clone/startup sequence and atomic instructions.
It needs neither pthreads nor libc. This is a runtime library, not a proof feature.
The sequential proof checker does not certify these operations.

Initial support is **native Linux x86-64**, with hardware lowerings enabled.
Compile an executable explicitly:

```sh
flexscript examples/thread/counter.flex -o counter
./counter
```

[`counter.flex`](../../examples/thread/counter.flex) demonstrates a contended
mutex around a shared global. [`parallel-fill.flex`](../../examples/thread/parallel-fill.flex)
uses disjoint memory regions and joining, with no mutex.

Both native pipelines (`ir` and `direct`) are supported. VM execution, portable
targets, and `--lowering-mode reference` do not implement this runtime.
`thread_supported()` returns 1 for supported native compilation and 0 otherwise;
it describes the compiled implementation, not whether the OS will permit a
particular allocation or clone. Creation still reports kernel errors.
Native callbacks are rejected in VM/portable programs. Without a callback,
unsupported thread/mutex APIs return `-38` (`ENOSYS`); directly invoking an atomic
operation on an unsupported target traps instead of silently using ordinary
loads/stores.

## Starting and joining

```flex
import "thread";

// native_callback uses the existing six-word System V callback convention.
// The library passes the argument first and zero for the remaining five words.
fn worker(argument, b, c, d, e, f) {
    store64(argument, 42);
    return 123;
}

fn main() {
    let data = alloc(8);
    let result = alloc(8);
    if data < 0 || result < 0 { return 1; }
    let task = thread_start(native_callback(worker), data);
    if task < 0 { return 2; }
    if thread_join(task, result) < 0 { syscall(231, 3, 0, 0, 0, 0, 0); }
    let failed = load64(data) != 42 || load64(result) != 123;
    if thread_destroy(task) < 0 { return 4; }
    syscall(11, data, 8, 0, 0, 0, 0);
    syscall(11, result, 8, 0, 0, 0, 0);
    return failed;
}
```

| Function | Contract |
| --- | --- |
| `thread_start(callback, argument)` | Return a positive opaque handle or negative errno. Default usable stack: 1 MiB. |
| `thread_start_with_stack(callback, argument, bytes)` | As above, requesting 64 KiB through 1 GiB, rounded up to 4096 bytes. |
| `thread_join(handle, result_out)` | Wait for actual kernel thread exit, write its full 64-bit return value if `result_out != 0`, release its stack, and return 0. Errors are negative errno. |
| `thread_destroy(handle)` | Release a successfully joined handle. Return `-16` (`EBUSY`) before a successful join. Discard the handle after success. |

Each stack has a 4096-byte inaccessible guard on both ends. Creation failures
release both the stack and handle. A successful start can return after the worker
has already finished; completion tracking accounts for that race.

One task can join a handle at a time. Another simultaneous join returns `-16`;
joining again after a successful join returns `-22` (`EINVAL`). Self-join returns
`-35` (`EDEADLK`). A join failure preserves the handle for retry. There is no
detach, cancellation, timed join, or general cycle/deadlock detection.

Handles must come from this library and remain valid. Destruction requires no
concurrent operation on the handle; accesses after destruction are invalid.
`result_out` must be zero or writable storage that does not overlap the handle or
worker stack. Arguments and pointed-to storage must remain alive until the worker
finishes. Join all workers before ending the program.

## Atomics and mutexes

All atomic operations are sequentially consistent, for ordinary coherent memory.
Addresses must be valid and naturally aligned (4 bytes for 32-bit operations,
8 bytes for 64-bit operations). This does not model device/MMIO memory. Do not mix
unsynchronized ordinary accesses with atomic accesses to the same storage.

| Function family (32 and 64 variants) | Result |
| --- | --- |
| `atomic_load32(p)`, `atomic_load64(p)` | Current value. |
| `atomic_exchange32(p, value)`, `atomic_exchange64(p, value)` | Replace the value; return the old value. Also serves as a sequentially consistent store when the result is ignored. |
| `atomic_compare_exchange32(p, expected, value)`, `atomic_compare_exchange64(...)` | Replace only when equal to `expected`; always return the observed old value. Strong CAS, no spurious failure. |
| `atomic_fetch_add32(p, value)`, `atomic_fetch_add64(p, value)` | Add with wrapping arithmetic; return the old value. |

32-bit inputs use their low 32 bits and results are zero-extended. Operations use
native MOV, XCHG, LOCK CMPXCHG and LOCK XADD instructions; these atomics have no
hidden mutex fallback. The compiler conservatively treats them as effectful calls.

`mutex_create()` returns a zero-initialized mutex or negative errno.
`mutex_lock(m)` and `mutex_try_lock(m)` return 0 on acquisition; try-lock returns
`-16` when busy. `mutex_unlock(m)` releases it; only the owning task may unlock.
The mutex does not track owner identity, so non-owner unlock is not diagnosed.
`mutex_destroy(m)` releases an unlocked mutex and returns `-16` if locked. As with
handles, destruction requires external assurance that no task uses or waits for
the object. Mutexes are nonrecursive, process-local and nonrobust; there is no
fairness or priority-inheritance guarantee. Owner death does not release a mutex.

Contended locks sleep using FUTEX_WAIT_PRIVATE and unlock wakes a waiter with
FUTEX_WAKE_PRIVATE. Waiters retry after spurious wakeups, interruption, or a
changed expected value. A wake failure from unlock is reported after the state
has been unlocked; it does not mean the caller still owns the mutex.

## Kernel and runtime boundaries

The startup lowering calls the raw x86-64 `clone` syscall with shared address
space, file descriptors, filesystem context, signal handlers, thread group and
SysV semaphore adjustments. The kernel writes and clears the handle's TID using
CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID. Join uses a non-private futex wait
matching the kernel's exit wake. The parent resumes normally; the child switches
to its new stack, invokes the callback, records its result, and calls raw `exit`.
It never returns through the parent's stack frame. The original clone interface
is sufficient here and avoids requiring clone3 support.

**These are freestanding Flexscript workers, not POSIX/glibc threads.** This
runtime does not initialize an independent libc TLS area, register pthread state,
run pthread cleanup/destructor handlers, or provide a thread-local variable API.
Workers must use thread-safe Flexscript code and raw syscalls, not glibc/foreign
library calls that require that setup. Do not mix this runtime with a pthread
runtime or signal handlers that depend on per-thread libc state. Existing
Flexscript libraries with mutable global caches or buffers are not automatically
thread-safe merely because they are written in Flexscript.

Ordinary shared accesses still need appropriate synchronization. Creating a
thread does not make its memory accesses atomic. Returning normally from the
callback supplies the join result; terminating it directly with raw `exit`
bypasses that result assignment. Fatal signals can terminate the whole process.

The `concurrent`, ownership, and synchronization proof annotations discussed for
future verification are not introduced by this library. Verification of sources
with these lowering declarations remains explicitly unproved.

## Validation

```sh
python3 scripts/test-thread.py --compiler build/stage2
```

The suite executes real simultaneous kernel tasks in both native pipelines and
both IR optimization modes. It checks shared process identity, distinct thread
IDs, contended mutex updates, atomic RMW/CAS and data publication, return values,
repeated and nested creation, self-join, competing joins, stack guards and mapping
reclamation, invalid inputs, failed-clone cleanup, unsupported execution
modes, and the sequential verifier's rejection boundary. This is runtime test
evidence, not a formal concurrency proof.

Kernel contracts: [clone](https://man7.org/linux/man-pages/man2/clone.2.html),
[FUTEX_WAIT](https://man7.org/linux/man-pages/man2/FUTEX_WAIT.2const.html), and
[FUTEX_WAKE](https://man7.org/linux/man-pages/man2/FUTEX_WAKE.2const.html).
