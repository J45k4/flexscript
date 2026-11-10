# Optional native CPU physics

This Linux x86-64 AVX2 backend advances one shared version-1 world with three or
six physics processes. It packages the qualified contact SIMD kernel, collision and
parameter queues, and fused dependency scheduler. The scalar/Wasm/GPU solver
remains available through the normal physics module. This optional backend has
C/C++ numerical libraries and requires the qualified Clang 23 `znver3` output.
Source, assembly and binary hashes reject unsupported compiler/source drift.

Build from the Flexscript repository root:

```sh
python libs/physics/native/build.py --workers 6
```

The JSON result names an immutable bundle under `target/physics-native/`. Import
its `physics.flex` from a native-only program, create a shared arena with
`ph_native_world`, and call `ph_native_start(world)` before `ph_step`/`ph_advance`.
Use `ph_native_close(world)` to stop/reap helpers before releasing the arena.
Only one world may have active helpers in a process; the caller exclusively owns
it during stepping. Start from a single-threaded native host. This is separate
from `cpu-batch.flex`, which advances independent worlds in isolated processes.

The construction API, world layout and settings are the existing physics API.
This backend includes predictive separated support corners and circular cap/face
contact refinements from the qualified dense-contact solver. It is therefore an
explicit backend choice, not a claim of byte-identical trajectories to every
legacy scalar contact model. Six versus serial execution within this backend
preserves active-state results, contact/body ordering and strict FP operations.
It retains bounded dispatch, parent polling, helper-death detection, parent-death
signals and a two-second phase deadline. Workers inherit the caller's FP control
settings at startup; their FP status flags remain process-local and are not
merged into the parent. More processes require more CPU.

`build.py` is also an importable build API. `build(output_root, clang, workers=3)` returns a
verified numerical/source bundle. `solver_source(library_dir, collision, color,
poll, clock)` binds a host's polling and monotonic-millisecond clock functions
by symbol. The default build uses three workers; choose six explicitly. Custom hosts must retain polling failures and the original deadline
semantics. No renderer, detector, robot, controller or application import occurs
in this package. RoboBand supplies its existing serial-service polling and clock
at this boundary. Both its default three-worker native runtime and explicit
six-worker runtime consume these library sources directly.

The numerical libraries are content-identical to the matching qualified three-
and six-worker RoboBand engines. Its 30-band headless measurement showed 1.290x throughput versus
that application's three-worker default, with more CPU processes. This is not a
general Flexscript benchmark or a training-speed guarantee. The full Student
command/path gate failed despite higher simulated-time throughput; reliable
full-pipeline realtime and autonomous pickup were not demonstrated. An earlier
uncaptured numerical failure remains unresolved. These limits are preserved
rather than converted into backend guarantees.

Run the package tests with the standard library unittest runner:

```sh
python -m unittest discover -s scripts -p 'test_physics_native.py' -v
python scripts/test-physics-native.py --compiler /path/to/flexscript --workers 3
python scripts/test-physics-native.py --compiler /path/to/flexscript --workers 6
```
