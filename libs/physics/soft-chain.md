# Experimental flexible particle chain

This host-side Flexscript primitive wraps the existing rigid-body solver.
Import `libs/physics/soft-chain.flex` to use it. The world ABI and existing
rigid-body callers are unchanged.

Create 3–128 distinct sphere bodies in a rigid world and place their IDs in an
array. Call `sc_chain(world, ids, count, stretch, bend, damping)`. Parameters
are binary32 bit patterns in SI units. The initial distances become rest
lengths. Neighbour springs resist stretching and second-neighbour distance
springs provide limited bending resistance. Static endpoints are supported.

Call `sc_step(chain)` for one chain, or `sc_step_group(array, count)` for up to
128 disjoint chains in the same world. The group sums every chain's forces and
advances the world **once**. Do not step multiple chains in the same world
separately for one timestep. Existing persistent body forces are restored after
the step. The conservative explicit timestep/mass/stiffness bound is checked at
construction and every step; invalid group or unsafe changed settings return
zero without advancing. Each chain must own distinct bodies. Call
`sc_close(chain)` before closing its world; reconstruct after rebuilding the
world or changing particles or rest geometry.

Run the native test from the Flexscript root:

```sh
build/flex libs/physics/tests/soft-chain.flex -o /tmp/flex-soft-chain-test
/tmp/flex-soft-chain-test
```

The tests cover restoring a bent chain, floor contact, two chains stepping
simultaneously, persistent-force preservation, shared-particle rejection,
nonfinite/coincident spring failures, constructor validation, and rejecting an
unsafe changed timestep. Run all of these with:

```sh
python3 -m unittest discover -s flex/experiments/soft-physics -p test_soft_chain.py
``` The stability bound is an experimental guard, not a guarantee under
arbitrary contacts or loads.

This particle-and-spring model is not a continuum, cloth, or full wristband:
it has no strap surface or width, twist stiffness, pad attachment, connected
collision filtering, or measured material calibration. Sphere spacing controls
gaps. The underlying engine has no continuous collision detection. GPU, Wasm,
renderer, suction, and workcell integration remain unimplemented or unvalidated.
