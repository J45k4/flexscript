# Collie native Wayland correctness acceptance — 2026-10-27

The Linux x86-64 / Wayland Collie implementation is delivered on the isolated
`codex/sdl-migration` worktree. Native Wayland is selected automatically in a
Wayland session. SDL remains available for explicit compatibility selection,
X11, and other GUI/OpenGL consumers. This is a local implementation and build;
no commit, push, merge or remote CI run is implied.

The user accepted speed and asked to finish correctness. That decision replaces
the original numerical performance completion gates. Historical latency misses
remain misses; the reports are preserved in the migration journal. No further
performance claim is inferred from these correctness runs.

## Final change

An empty IME acknowledgement could cancel a pending asynchronous paste, discard
editor layout and restart the caret even without a text/composition change. The
reproducer failed before the fix. The editor now leaves such a transaction alone
when there is no active preedit. Protocol `done` serial/hold processing remains
unchanged. Active preedit clearing, actual commit/delete, explicit cancellation,
invalid-range handling and UTF-8 insertion remain tested.

Collie's backend policy is now explicit: `FLEX_GUI_BACKEND` wins; an explicit SDL
video-driver variable selects SDL; otherwise `WAYLAND_DISPLAY` selects native
Wayland, with SDL selected when it is absent. A native initialization failure is
reported, without silently switching backends. Generic GUI consumers keep their
existing selection policy.

## Functional evidence

All artifact paths below are relative to this worktree. GPU sessions were
private headless Sway/Weston compositors using this host's NVIDIA GPU. They did
not open desktop windows or change installed packages/system configuration.

| Area | Final result | Artifacts |
| --- | --- | --- |
| Shared Collie pages and reducer | 20 UI groups: pages, settings/accounts, projects, permissions, attachments/preview, streaming, thinking, history and stale chat-load handling | `build/migration/correctness-shared-ui.log`, `build/collie-ui-report.json` |
| Desktop widgets on native | 93 checks in IR at 1× and 93 in direct at 2×: all 11 pages, images, permission round-trip, focus feedback, links, selection from gutters, copy/paste and resize | `build/migration/correctness-release-ui-final/` |
| Tables and scrolling on native | Wrapping/alignment, 47 rows, table selection/copy/link activation, streamed table replacement; nested wheel routing, Shift+wheel, overscroll reversal, thumb/track dragging and capture cleanup at both scales | Same directory, `tables.*.log` and `scrolling.*.log` |
| Editor regression | Six final IR/direct checks for empty IME/paste lifetime, composition, commit/delete, focus/selection/typing races and cancellation | `build/migration/correctness-release-editor/` |
| Real input method | Fcitx Pinyin preedit, Chinese commit, candidate popup and composer caret geometry, both fixture and full rebuilt Collie at 125% | `build/migration/correctness-release-full/` |
| Full application | Unicode draft, settings/account navigation, return to chat, sidebar shortcut and capture; native maps contain no SDL | Same directory, `ui-smoke/` |
| Backend policy | Auto native, explicit native/SDL, SDL-driver choice, native override of that choice, invalid override rejection | Same directory, `ui-smoke/backend-selection.json` |
| Event loop and failures | Independent application-FD/Wayland-input wakeups, service loss, error stream, shutdown and rendered error state | Same directory, `wait/` |
| Fractional sizing | Fixed-window composed pixels under independent resize, client resize, fullscreen/remap, tiled constraints, preferred-size restore and retained textures/text at 125% | Same directory, `window-size/` |
| Rendering scenes | SDL/native scroll, selection, stream and navigation; matching viewport/pixel sizes, inline images and 24 presentation outcomes per backend/scene; additional native captures | Same directory, `paired-smoke/` and `ui-smoke/` |
| Window lifecycle | 26 checkpoints each in 1× IR and 2× direct: hidden/readback, resize, fullscreen/maximize/minimize/restore, opacity, close/disconnect and 20 rapid remaps; temporary region ownership checked independently | `build/migration/correctness-release-lifecycle/` |
| Input/cursor/clipboard | Animated cursor frames/hotspots, keyboard/pointer capability loss/recovery and seat removal; actual preferred-scale transitions 1×→1.25×→1.5×→2×→1×; independent wl-copy/wl-paste peers at 100,000 bytes and 1 MiB | `build/migration/correctness-release-input/` |
| Resource lifetime | 40 native create/draw/close/quit cycles per pipeline: no stale owned handles or GL errors; no FD growth after warm-up, final count 4 | `build/migration/correctness-release-ui-final/*/native-lifetime.stdout.log` |
| Text shaping/raster | 20 comparisons with independent C FreeType/HarfBuzz oracle: hinted small text, CJK, RTL runs, combining marks and fixed-strike color emoji | `build/migration/text-tests/` |
| Bidi and wrapping | 1,020 retained bidi layouts and 789 Unicode wrap layouts per pipeline, including rich runs and long words | `build/migration/ui-bidi-tests/`, `build/migration/ui-linebreak-tests/` |
| SDL compatibility | Shared desktop UI, tables, scrollbars, text raster and selection-cache regressions pass after native test extraction | `build/migration/correctness-release-sdl.log` |

Widget event replay tests verify rendering and interaction semantics. Separate
compositor producers and input-method/clipboard peers verify real protocol
transport. Neither is a physical input-device or hardware scanout measurement.
Saved 1×/2× widget captures and the 125% full-app capture were also inspected.
The same final package was copied byte-for-byte into `build/collie-desktop` and
rechecked there: real Pinyin, backend policy, rendering and full-app navigation
passed again in `build/migration/correctness-release-package/`.
The new empty-IME regression is wired into CI in both compiler pipelines;
remote CI and GPU CI have not run.

## Scope and remaining qualification

Supported here: Linux x86-64, one Collie Wayland window, OpenGL 3.3, EGL window and
pbuffer surfaces, direct Fontconfig/FreeType/HarfBuzz and xkbcommon adapters.
The shipped migration/build code is Flexscript; Python/C in these suites are
independent test orchestration/oracles. Existing service broker and codec/TLS
libraries have not been removed by this GUI migration.

Physical mixed-monitor movement, additional GPU drivers/input methods, full
Script_Extensions tailoring, long-duration resource soak and GPU CI remain
follow-up coverage. The tests establish bounded repeated teardown, not an
unlimited leak-free claim. Native relative pointer mode, multiple native windows
and an externally owned GL context are outside this Collie canvas scope; retain
SDL for consumers requiring them. No claim of cross-platform SDL removal is made.

## Build and run

From this worktree:

```sh
build/build-desktop --compiler build/compiler-next --out build/collie-desktop
./build/collie-desktop/collie
FLEX_GUI_BACKEND=sdl2 ./build/collie-desktop/collie
```

`build/collie-desktop` contains a byte-verified copy of the final package. From the main checkout
it is `./build/sdl-migration/build/collie-desktop/collie`.

To repeat the broad native widget and lifecycle checks with already extracted
private test dependencies:

```sh
python3 scripts/test-wayland-window-session.py --compiler build/compiler-next --weston-root build/weston-root --ui-workflows --out build/migration/recheck-ui
python3 scripts/test-wayland-window-session.py --compiler build/compiler-next --weston-root build/weston-root --out build/migration/recheck-lifecycle
```

The final evidence manifest records source, package and report hashes. The host
cleanup report checks for surviving processes/runtimes from these final tests.
