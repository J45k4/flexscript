# Query-free submission experiment - 2026-10-27

Status: **rejected**. Correctness passes, but the native A/B control shows
selection and typing latency regressions. The exact tested pre-experiment
renderer has been restored. No SDL release qualification is claimed.

The complete GPU diagnostic includes query drains and a post-present `glFlush`.
Its scroll latency difference was smaller/inconclusive, unlike the earlier
uninstrumented failure. That does not establish a cause. This experiment tests
one submission change with query instrumentation disabled on both variants.

## Single renderer change and correctness

The experimental `gr_present` calls cached `glFlush` after a successful EGL
swap and Wayland flush. It does not wait for completion, add a delay, change
frame pacing or issue queries. Hidden/no-present and failed-present paths do not
call it. The GL dispatch table appends the function without moving any existing
entry. The exact before/after renderer delta is checked mechanically against
`build/migration/explicit-flush-before/gl.flex`.

The frozen pre-change executable is
`build/migration/gpu-present-benchmark/ui-benchmark`; the candidate is
`explicit-flush-benchmark/ui-benchmark`. Full generated sources and executable
hashes are retained. The application package is `explicit-flush-candidate/`.

Correctness passes in:

- `explicit-flush-window-r1/`: private Weston 1x IR / 2x direct, all lifecycle,
  opacity, remap, resource and framebuffer checks.
- `explicit-flush-correctness-r1/`: full Collie/Pinyin, IR/direct independent
  renderer state/pixels, matched four-scene correctness, both presentation
  implementations/commit association, and actual EGL failure cleanup.
- Its selection equivalence report compares all 6,400,000 bytes with the frozen
  native baseline. Both SHA-256 values are
  `bda803bdf283abaff0ec916c141f898866e5f5b3f94f8ce79a5e3552ee89c835`.

## Controlled native comparison

`scripts/compare-native-submission.py` runs seven alternating before/after pairs
of 160 updates for scroll, selection and Unicode typing. Both are native, using
the same private compositor/GPU, effective resolution, fonts/content, inline PNG,
CPU affinity and fixed 23 ms replay arrivals. Both explicitly disable all GPU
query instrumentation. Every scheduled arrival and presentation is retained;
the script rejects dropped/retimed updates, discard outcomes, mismatched viewport/
GPU/clock, incorrect edit/selection state, missing CPU phases and invalid captures.
The first selection pair must also match byte for byte.

The script records executable/generated-source/font/harness hashes, raw per-frame
records, CPU-clock intervals and run-boundary host context. It resamples whole
paired runs, preserving correlated frames, to estimate the after-minus-before
p95 difference. All outliers remain; boundary snapshots are not per-frame
interruption attribution. The experiment is serial and no other builds/tests
run during measured workloads.

This is **not an SDL qualification run**. Its CPU gate is unavailable by design.
A repeatable controlled scroll-latency improvement, without a confident
regression in the other interactive cases, would justify proceeding to the full
four-workload SDL CPU comparison and query-free three-case SDL latency comparison.
If the control does not establish a benefit, retain the evidence and remove the
extra submission call rather than treating diagnostic scheduling changes as a
proven fix. Numerical release gates in `SLD_migration.md` remain unchanged.

```sh
env SDL_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0 nice -n19 python3 scripts/test-wayland-ime-session.py \
  --binary build/migration/explicit-flush-ime \
  --paired-benchmark build/migration/explicit-flush-benchmark/ui-benchmark \
  --native-submit-control build/migration/gpu-present-benchmark/ui-benchmark \
  --package-root build/migration/ime-lab/root --scale 1250 \
  --out build/migration/explicit-flush-control-r1
```

## Completed control and decision

`build/migration/explicit-flush-control-r1/native-submission-control/report.json`
completed all **6,720** query-free updates, with no discarded outcomes. Every
selection/typing update and CPU-clock phase was checked. The first selection
pair's 6,400,000 RGBA bytes agree exactly, SHA-256
`ddc86757f667660f8f71ddfb31a815eeb8dee89fa996e6a67a36d6d5fc87ca7d`.
This differs from the short-smoke hash because the final selection position
depends on the sample count; the before/after pair uses the same count.

Fixed-arrival input-to-presentation p95 in milliseconds:

| Workload | Frozen native | Extra-flush native | Mean paired after-minus-before p95 (95% interval) |
| --- | ---: | ---: | ---: |
| scroll | 6.252 | 6.201 | -0.132 ms (-0.344 to +0.023) |
| selection | 5.593 | 6.217 | +0.759 ms (+0.559 to +1.004) |
| typing | 8.579 | 9.206 | +0.555 ms (+0.344 to +0.826) |

Scroll is inconclusive. Selection and typing regress in all seven pairs, beyond
the paired uncertainty. Selection CPU p95 also increases in the pooled samples;
raw host/CPU records remain included without removing spikes. Consequently the
candidate does not meet the predeclared criterion for proceeding to SDL
qualification. No full SDL qualification time was spent on this rejected change.

The extra `glFlush` call and dispatch-table entry were removed by restoring the
exact original renderer snapshot, after checking that no unrelated edit would
be overwritten. Its SHA-256 equals the frozen pre-experiment identity. The
experimental renderer source, generated source, binaries, correctness evidence
and control results remain intact. The A/B tool remains available for later
submission experiments; it does not alter application behavior. This result
rules out retaining this particular extra-flush placement as a fix, not every
possible driver/queueing cause of the scrolling gap.

SDL remains default. Work is local and uncommitted on `codex/sdl-migration`.
Current source, accepted/experimental build and raw-evidence hashes are in
`build/migration/explicit-flush-final-evidence.json`. The scoped cleanup audit
is `explicit-flush-host-cleanup.json`; no matching process, mount or private
runtime remains. The experimental package is retained only as rejected evidence.
