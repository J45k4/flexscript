# Native windows

`libs/gui.flex` provides native windows, input, a 2D canvas, RGBA framebuffer
presentation, window-backed OpenGL contexts, cached dispatch and GLSL compilation.
Its implementation lives in `libs/gui/`; `lib/gui.flex` and `lib/gui/*` remain
compatibility imports. The library is written in Flexscript and uses the native
compiler's FFI/callback support; building applications requires no Rust runtime,
browser, C compiler or linker. The default compatibility backend requires SDL2
2.26 or newer (`libSDL2-2.0.so.0`). The native
`FLEX_GUI_BACKEND=wayland` path uses Wayland/EGL/OpenGL and direct font libraries
without loading SDL. Collie selects it automatically in Wayland sessions; see
[correctness acceptance](sdl-migration-correctness-2026-10-27.md).

The initial target is Linux x86-64, matching the native compiler and FFI.

The optional `libs/gui/draw.flex` image API uses the
[image library](../libs/image/README.md). `gui_image_load(window,path,dimensions)`
returns a texture handle for the active backend and writes width/height to the
caller's 16-byte output.
It accepts regular PNG/JPEG/WebP files up to 64 MiB, at most 8192 pixels per side
and 24 megapixels for texture upload. Release textures with `gui_texture_close`.
Call `gui_image_decoder_close()` after the final image load to release the shared
codec context; existing textures retain their uploaded pixels. The retained UI
adapter does this automatically on close. SVG needs rasterization before loading.
SDL supplies X11/Xwayland and Wayland integration on the compatibility backend.
Its display driver is selected automatically, or explicitly with
`SDL_VIDEODRIVER=x11` or `wayland`.
X11/Xwayland and an actual OpenGL GPU have been exercised locally. Native
Wayland is exercised by the accelerated private-compositor baseline; complete
real desktop acceptance remains outstanding. Windows/macOS binaries are not
supported.

## Run the examples

From the project root, using a full compiler with imports and FFI:

```sh
build/flex examples/gui/window.flex -o build/gui-window
build/gui-window

build/flex examples/gui/opengl.flex -o build/gui-opengl
build/gui-opengl
```

The canvas example draws a rectangle that moves with the arrow keys and changes
color on mouse clicks. Both examples respond to Escape and the window manager's
close button. An optional numeric frame count makes either example exit after
a bounded run, e.g. `build/gui-window 120`.

## Minimal application

Import paths are relative to the source file. This example assumes a file in
`examples/`:

```flex
import "../libs/gui.flex";
fn main() {
    let window=gui_open("Hello from Flexscript",800,500,GUI_RESIZABLE);
    if !window {gui_quit();return 1;}
    let event=gui_event();
    let running=1;
    while running {
        while gui_poll(event) {
            let kind=gui_event_kind(event);
            if kind==GUI_QUIT || kind==GUI_CLOSE {running=0;}
        }
        if !gui_clear(window,0x102c2a) ||
           !gui_fill(window,80,80,120,80,0xe9bd7c) ||
           !gui_present(window) {gui_quit();return 1;}
        gui_delay(16);
    }
    gui_close(window);
    gui_quit();
    return 0;
}
```

Operations return 1 on success and 0 on failure, unless they return a handle,
dimension, state or pointer. `gui_error` is a NUL-terminated error string after
a failure; it may be replaced by later operations. Copy it if needed long-term.
`gui_quit()` returns 0 and closes all windows and this library's SDL video
subsystem reference. It does not shut down separately initialized SDL subsystems.
All GUI calls must run on the application's main thread.

## Windows and input

| API | Behavior |
| --- | --- |
| `gui_init()` | Optional explicit initialization; opening a window also initializes. |
| `gui_open(title,w,h,flags)` | Create a window; return a positive opaque handle or 0. |
| `gui_close(window)` | Release its renderer, texture, context and native window. |
| `gui_quit()` | Close every remaining window and release the video subsystem. |
| `gui_width(window)`, `gui_height(window)` | Current client size in window coordinates. |
| `gui_pixel_width(window)`, `gui_pixel_height(window)` | Current drawable size in physical pixels. |
| `gui_resize(window,w,h)` | Request a client size; the compositor may constrain it. |
| `gui_title(window,title)` | Change the window title. |
| `gui_show(window,visible)` | Show or hide the window. |
| `gui_fullscreen(window,enabled)` | Enable or disable desktop fullscreen. |
| `gui_maximize(window,enabled)` | Request maximized or unmaximized state. |
| `gui_minimize(window)` | Ask the compositor to minimize the window. |
| `gui_restore(window)` | Show the window in its windowed, unmaximized state. |
| `gui_relative_mouse(window,enabled)` | Grab/hide the pointer for relative motion; requires keyboard focus to enable. |
| `gui_key(window,scancode)` | Held physical key, after processing events. |
| `gui_mouse_buttons(window)` | Held buttons as a bit mask: left 1, middle 2, right 4. |
| `gui_focused(window)` | Keyboard focus state; native input-only seats use text-input focus while no keyboard exists. |
| `gui_text_input(enabled)` | Start or stop the backend's UTF-8 input. |
| `gui_text_focus(window,identity)` | Select an editor session by stable identity; 0 disables it. |
| `gui_text_epoch(window)` | Current focus epoch for rejecting delayed composition. |
| `gui_text_surrounding(window,text,cursor,anchor,cause)` | Supply committed UTF-8, byte offsets and change cause (0 IME, 1 other). |
| `gui_text_area(x,y,w,h)` | Candidate popup anchor in logical window units; update after editor scrolling/layout. |
| `gui_ticks()`, `gui_delay(ms)` | Monotonic milliseconds (backend-specific epoch), and a delay. |
| `gui_wait(ms)` | Wait up to `ms` for an event without consuming it; returns 1 when an event is queued, or 0 on timeout/error. Call on the GUI thread, then use `gui_poll`. |
| `gui_wait_sources(ms,sources,count)` | Wait for GUI input or borrowed FD readiness; inspect results, then drain GUI events and service ready descriptors. |
| `gui_frame_ready(window)` | Native/instrumented SDL: shown/configured and no pending application frame callback. Ordinary SDL: 1 for a valid window. |

Flags can combine `GUI_RESIZABLE`, `GUI_HIDDEN` and `GUI_HIGH_DPI`; 0 creates a
normal visible window. Sizes must be 1–16384. SDL supports up to 32 windows;
the experimental native backend currently owns one window.
The native canvas advertises a full opaque region after a complete opaque
window clear. Its bounds use logical coordinates and follow resize/remap.
Transparent or partial frames remove the hint; alpha in a separate layer does
not change the window's known opacity. Each new backbuffer must establish its own
opacity. Transparent toplevels have no public GUI flag.
Handles include a generation: closing and reusing a slot cannot let an old
handle operate on the new window. Closing an invalid/already closed handle
returns 0. The bounded record storage is retained for reuse for process lifetime.

Use one application-wide event loop. `gui_event()` allocates a 128-byte buffer
once; reuse it. `gui_poll(event)` returns 1 for a supported event and 0 when the
queue is empty. It updates held input state for the event's window. Unknown
events are consumed safely; empty polls clear the output buffer. There are no
per-poll payload allocations for ordinary keys/pointer motion. IME transactions
and clipboard transfers allocate bounded owned storage; renderer/cache changes
and SDL may allocate separately.

`gui_wait_sources` accepts 0–16 caller-owned 24-byte records containing three
64-bit words: descriptor, interests and result. Interests combine
`GUI_WAIT_READ` and `GUI_WAIT_WRITE`; results can additionally contain
`GUI_WAIT_HUP`, `GUI_WAIT_ERROR` and `GUI_WAIT_INVALID`. Clear/inspect readiness
on every call. The wait never consumes bytes or closes descriptors. It returns
1 for GUI or source readiness, and 0 for timeout/error; internal protocol work
can return early without an application event. Timeouts are 0–2147483647 ms.
Use this only on the GUI thread, without nested waits. The native backend joins
application descriptors with the display and bounded clipboard transfers in one
kernel poll, retaining keyboard-repeat, cursor and transfer deadlines. SDL's
compatibility implementation caps each wait at 16 ms. Callers must recheck their
conditions after every return and watch writable pipes only while bytes remain.

Native `gui_present` requests at most one outstanding application frame callback.
Use `gui_frame_ready` to coalesce dirty updates before drawing. While it is false,
continue processing input/service events and wait on their descriptors; keep the
UI dirty rather than redrawing repeatedly. Callback completion can return from a
wait without enqueueing an input event, so recheck readiness after every return.
Hidden/unconfigured windows are not ready. Unmapping cancels the pending callback;
an EGL swap failure releases a newly requested callback and reports `gui_error`.
Explicit `gui_present` calls still submit immediately when mapped: applications
that ignore readiness retain control over their submission rate. Ordinary SDL compatibility
pacing is unchanged. Enabling its observer also enables callback readiness
for controlled comparisons. A frame callback permits another redraw; it is not a
presentation timestamp. See the [Wayland surface protocol](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface).

`gui_event_window(event)` identifies the window, except application-wide
`GUI_QUIT` and `GUI_RENDER_RESET`, whose window is 0. A close event is a request;
the application still owns the window until it calls `gui_close`.

| Kind | Event accessors |
| --- | --- |
| `GUI_QUIT`, `GUI_CLOSE`, `GUI_EXPOSE`, `GUI_RENDER_RESET` | Kind and window. |
| `GUI_RESIZE` | `gui_event_x/y`: current width/height in window coordinates. |
| `GUI_FOCUS` | `gui_event_code`: 1 gained, 0 lost. |
| `GUI_KEY_DOWN`, `GUI_KEY_UP` | `gui_event_code`: SDL scancode; `gui_event_repeat`, `gui_event_modifiers`. |
| `GUI_TEXT` | `gui_event_text`: NUL-terminated UTF-8, valid until the next poll. |
| `GUI_MOUSE_MOVE` | `gui_event_x/y`: absolute position; `gui_event_dx/dy`: signed relative movement. |
| `GUI_MOUSE_DOWN`, `GUI_MOUSE_UP` | `gui_event_button`: 1 left, 2 middle, 3 right; `gui_event_x/y`. |
| `GUI_WHEEL` | `gui_event_dx/dy`: signed integer horizontal/vertical steps, with flipped direction normalized. `gui_event_modifiers` reports the current modifier keys. |
| `GUI_CLIPBOARD` | `gui_event_code`: request token; `gui_event_x`: 1 success, 0 failure. Take the owned result with `gui_clipboard_take(token)`. |
| `GUI_IME` | `gui_event_code`: transaction token. `gui_ime_data(token)` returns borrowed composition data until the next poll/release. |

Physical key constants include `GUI_KEY_ESCAPE`, `GUI_KEY_LEFT`,
`GUI_KEY_RIGHT`, `GUI_KEY_UP_ARROW` and `GUI_KEY_DOWN_ARROW`; other keys use
[SDL scancodes](https://wiki.libsdl.org/SDL2/SDL_Scancode). Text entry is separate
from physical keys. Backends convert keyboard layouts into committed UTF-8;
font drawing is available through the text helpers below. IME composition uses
the transaction API described below. Gamepads and drag/drop are not exposed yet.
Unsupported events with owning payloads are freed while being ignored.

Focus loss and close/quit requests clear held input. Relative mouse mode has one
owner and is released on focus loss or destruction. Drain events every frame
before reading held keys, so input cannot remain latched across focus changes.

## Canvas and pixel presentation

`gui_canvas_open(window,software)` explicitly creates an SDL renderer: 0 lets
SDL choose, 1 requests software. Canvas operations create one lazily if absent.
Initialize it before treating a visible window as ready; SDL may replace the
underlying native window when setting up a GPU renderer.

`gui_clear(window,0xRRGGBB)`, `gui_fill(window,x,y,w,h,0xRRGGBB)` and
`gui_present(window)` draw opaque pixels and present the frame. Coordinates are
drawable pixels. Mouse positions use window coordinates; scale by drawable size
divided by window size when high DPI makes them different.

`gui_clear` clears the entire current render target, regardless of the logical
canvas size or clip rectangle. `gui_texture_clear` does the same with transparent
pixels. Both preserve the clip for subsequent drawing, on SDL and native Wayland.

`gui_pixels(window,pixels,w,h,pitch,bytes)` uploads a CPU framebuffer and draws it
scaled to the full drawable. Pixels are **R, G, B, A bytes**, top-to-bottom;
`pitch` is bytes per row and may include padding. `bytes` must cover at least
`(h-1)*pitch+w*4`. The caller owns the buffer and must provide truthful allocation
sizes. Upload completes before return; the library retains only the SDL texture.
Call `gui_present` afterwards. The texture is reused until dimensions change or
SDL reports a renderer reset.

`gui_read_pixels(window,pixels,pitch,bytes)` captures the current drawable as
RGBA bytes. Query drawable dimensions and allocate enough storage first. Read
**before** present: SDL does not promise to retain a presented backbuffer.

## OpenGL windows

`gui_gl_open(title,w,h,flags,major,minor,es)` creates a context and window together.
Use `es=0` for desktop core OpenGL or `es=1` for OpenGL ES. Failure returns 0
with an error and releases the partially created window. It never silently
falls back to a different requested API/version.

`gui_gl_current(window)` switches the current context.
`gui_gl_proc(window,name)` makes it current and returns a function pointer.
Match the actual function's signature when using `ffi_call`; the existing FFI
accepts at most six integer/pointer arguments and does not pass floats in SSE
registers. `gui_gl_cached_proc(window,name)` resolves and caches a pointer per
live context, switching context when needed. It copies symbol names (1–63 bytes),
stores at most 128 functions per window, and resets the cache when a closed slot
is reused. `gui_gl_call(window,name,a,b,c,d,e,f)` resolves through this cache and
returns the raw FFI result; zero may be a valid result, so resolve the pointer
first when lookup failure must be distinguished. Pointer-taking OpenGL functions
can use buffers for floating-point data. If external code changes SDL's current
context, call `gui_gl_current(window)` before resuming cached dispatch. All calls
remain on the main thread.

`gui_gl_shader(window,kind,source)` compiles one NUL-terminated GLSL stage.
`gui_gl_program(window,vertex,fragment)` compiles and links vertex/fragment source.
They return a GL object or 0, with driver diagnostics in `gui_error` on failure.
Failed objects and temporary stages are deleted. Successful shader/program objects
belong to the caller/context; delete them through OpenGL when finished. Scratch
and dispatch storage are bounded and retained per window slot for reuse.

`gui_gl_swap(window)` presents the default framebuffer.
`gui_gl_swap_interval(window,interval)` requests -1 adaptive, 0 immediate or
1 synchronized presentation. Drivers may reject interval changes; applications
can treat that specific failure as optional. Canvas operations reject GL windows
and GL operations reject ordinary windows. A renderer may combine this window
library with its own GL function dispatch and the existing `lib/graphics.flex`
shader helpers; `gfx_open` itself creates a separate headless EGL context.

The library owns device operations. Application scene protocols, geometry,
materials, shaders and HUD behavior remain in the application.

## Standalone application snapshots

Setaworld vendors a byte-identical snapshot under `src/platform/` so it can build
outside the Flexscript checkout. Update it from this library, from the Flexscript
root, and verify the source files and SHA256 provenance together:

```sh
build/flex scripts/sync-gui.flex -o build/sync-gui
build/sync-gui workdir/setaworld/src/platform
build/sync-gui workdir/setaworld/src/platform --check
```

The destination must already exist. This Flexscript maintenance tool uses the
host's `sha256sum`; neither hashing nor synchronization runs in the game loop.

## Verification

```sh
build/flex scripts/test-gui.flex -o build/test-gui
build/test-gui build/flex --report build/gui-headless-report.json
# Explicitly opens temporary windows and exercises real desktop input:
build/test-gui build/flex --gui --report build/gui-report.json
```

The default suite uses SDL's dummy video driver: no browser, GPU or display.
It checks compatibility imports, window lifecycle, multiple windows, stale handles, bounded capacity,
canvas pixels, RGBA channel order/padded strides, texture reuse/reset, events,
UTF-8, signed mouse movement, focus cleanup and unavailable-display errors.
A small **test-only** C fixture uses SDL headers to independently construct native
`SDL_Event` structures for the decoder. It bypasses event injection limitations
in SDL2 compatibility layers. Building tests needs `cc`, SDL2 and X11 headers;
applications need none of those headers or tools.

`--gui` additionally verifies independent OpenGL contexts, cached symbol ownership,
shader compile/link failures and recovery, context reuse, mapped/viewable X11 windows,
keyboard movement, mouse clicks, real visible pixels and WM close. It requires
X11/Xwayland, OpenGL 3.3, XTest and libpng. Keyboard/mouse tests briefly focus their
own example window and restore previous focus/pointer position. Captures contain
only the examples: `build/gui-window.png`, `build/gui-input.png` and
`build/gui-opengl.png`. Use Xvfb with Mesa software GL for isolated CI acceptance.

SDL ABI references: [window creation](https://wiki.libsdl.org/SDL2/SDL_CreateWindow),
[events](https://wiki.libsdl.org/SDL2/SDL_Event),
[OpenGL dispatch](https://wiki.libsdl.org/SDL2/SDL_GL_GetProcAddress).
## Portable desktop views

`libs/ui/desktop.flex` builds the portable declarative widget renderer on this
library's windows, events and canvas. The same view syntax and update batches run
on Android, Chromium and desktop. See [Portable views](ui.md#native-desktop-adapter)
and [the native counter example](../examples/ui/desktop-counter.flex).

The optional `libs/gui/draw.flex` module adds font/text layers, texture drawing,
clipping, translucent fills and local image decoding through `libs/image`.
The SDL compatibility path loads SDL2_ttf and Fontconfig lazily. The experimental
`FLEX_GUI_BACKEND=wayland` path uses direct FreeType/HarfBuzz and EGL/OpenGL;
its remaining restrictions are recorded in [migration progress](sdl-migration-progress.md).
Fonts and textures have explicit close functions.
Font handles are opaque on both backends. SDL handles now own scaling metadata
as well as the underlying TTF font; do not pass them directly to SDL_ttf APIs.
Bitmap fonts select the nearest available strike, while width/height/ascent and
drawing respect the requested pixel size. Scalable SDL fonts keep their existing
metrics; native font sizing is unchanged. See the
[bitmap-size checks](sdl-migration-bitmap-2026-10-27.md).

The native canvas owns its GL context and keeps its program, VAO, vertex buffer
and texture unit bound. Repeated unchanged logical size or physical clip state
does not split a draw batch. Texture uploads and render-target switches still
bind their affected texture/framebuffer explicitly. Switching between an EGL
window surface and its hidden pbuffer preserves the context and these bindings;
the native canvas does not expose a context for external GL mutation.

`gui_text_carets_available()` reports whether the backend exposes shaped caret
geometry. On the native backend,
`gui_text_carets(font,text,offsets,count,positions)` fills caller-owned 64-bit
visual x positions in **26.6 physical pixels** from the same cached HarfBuzz run
used for drawing. Offsets are ascending UTF-8 byte boundaries, including 0 and
the text length; callers normally use grapheme boundaries. RTL positions decrease
in logical order. The adapter uses font GDEF ligature carets when available,
adjusted for the shaped advance, and otherwise distributes a cluster's advance
over its graphemes. The output survives later cache lookups. SDL returns 0 from
the capability query and retains its compatibility prefix measurements.

This is geometry for one shaped run. Paragraph bidi ordering, visual navigation
affinity and full Unicode line-breaking remain separate layout responsibilities.
For a resolved run, `gui_text_width_direction(font,text,direction)`,
`gui_text_layer_draw_direction(window,font,text,color,x,y,direction)` and
`gui_text_carets_direction(font,text,offsets,count,positions,direction)` use the
same shape/cache key. Direction is 0 (guess), 4 (LTR) or 5 (RTL). Explicit
directions require the native backend; SDL rejects them. The retained native UI
uses [`libs/unicode`](../libs/unicode/README.md) for paragraph ordering and line
resets, then passes that direction through all three paths.
`gui_text_script(codepoint)` queries the existing HarfBuzz Unicode adapter for
script itemization; Common/Inherited/Unknown return 0 to inherit context.

The native backend separates logical sizes (`gui_width/height`) from physical
buffer sizes (`gui_pixel_width/height`). `gui_scale(window)` reports density in
thousandths, independently of pixel rounding at odd logical sizes. Preferred
fractional scales use a viewport; otherwise output/integer scale is used.
The experimental implementation supports 1x through 4x and rejects framebuffer
sizes beyond its limits rather than silently reducing resolution. Cursor shapes
are supplied by the compositor when supported, with `libwayland-cursor` theme
fallback. Current public cursors are default and horizontal resize. The fallback
honors `XCURSOR_THEME`/`XCURSOR_SIZE`, caches up to four integer densities, and
animates immutable theme images with per-frame hotspots and one outstanding
cursor-surface frame callback. Animation uses elapsed monotonic time and clamps
the next event wait to a frame deadline. It stops on pointer leave/device loss
and does not redraw the application. Losing a keyboard capability preserves the
seat and pointer; losing the seat releases its input, clipboard and IME devices.
Pointer leave/device loss cancels held mouse buttons with releases at (-1,-1),
without an input serial that could authorize clipboard ownership.

Native hidden windows have an offscreen EGL pbuffer: drawing/readback is allowed,
but presentation does not map a window, swap buffers or increment present counts.
xdg-shell negotiates up to version 6, capped by the server's advertised version,
so tiled-edge state notifications are available when supported.
Hiding a mapped window unmaps it and destroys its xdg role. Showing recreates the
role after an asynchronous sync barrier and waits for a fresh configure before
attaching content. The owned title, app ID, constraints and requested states are
reapplied. EGL surfaces can change while the GL context, layers and glyph atlas
remain owned by the same renderer. The EGL configuration must support both window
and pbuffer surfaces; this is verified on the current NVIDIA test target.

`gui_resize` chooses the native floating client size and changes fixed-size hints
when needed. Fullscreen/maximized/tiled bounds remain compositor-owned; a resize
requested there becomes the preferred windowed restore size. Fixed floating
clients retain their requested size when given an ordinary configure suggestion.
Fullscreen/maximize/minimize requests remain subject to compositor policy.
xdg-shell does not report a minimized state or offer an unset-minimize request.
Restoring after our minimize request therefore unmaps/remaps the role; focus is
still decided by the compositor. `GUI_EXPOSE` requests a redraw when a fresh
configure or show makes content ready. Close/disconnect emits one `GUI_CLOSE`,
releases held input and cancels native cursor/clipboard/IME activity.

Clipboard helpers are available with the window API. `gui_clipboard_copy(text)`
copies bounded UTF-8 text. For paste, call `gui_clipboard_request(window)` and
keep its nonzero request token. Continue processing events; when `GUI_CLIPBOARD`
arrives with that token, call `gui_clipboard_take(token)`. The returned string is
caller-owned and must be released with `gui_clipboard_release(text)`. Failed
requests return no string; an empty successful selection returns an empty string.
`gui_clipboard_cancel(token)` closes pending transfers and releases unread data.
A new request supersedes the previous one; stale completion events carry no
owning pointer. The payload limit is 1 MiB.

`gui_clipboard_read()` remains a synchronous compatibility helper for SDL and
our own native selection. External Wayland selections use the asynchronous API.
The native transport shares the display's poll wait, enforces transfer deadlines,
and retains source bytes until outstanding writes finish or are canceled.

## IME composition

The retained desktop UI manages this automatically. Custom editors should call
`gui_text_focus` on editor changes, supply surrounding committed text, and update
the caret rectangle after layout. Identities must change when an editor is
replaced; delayed composition from an earlier session must be discarded. The
native adapter uses text-input-v3 version 1 when available. Without that optional
protocol, XKB text and compose/dead keys continue to work. SDL editing events use
the same normalized composition payload; SDL commits retain `GUI_TEXT`.

For `GUI_IME`, call `gui_ime_data(gui_event_code(event))` before polling again.
The data belongs to the GUI; copy strings if retaining them. `gui_ime_release`
can release early. Pending tokens are bounded to 128, each string to 4000 bytes.
The queue releases unhandled payloads as polling advances and all storage on
window/GUI close. No owning pointer is embedded in a queued event.

| Data byte offset | Meaning |
| --- | --- |
| 0 / 8 | Window / editor focus epoch (`gui_text_epoch(window)`). |
| 16 / 24 | Protocol serial / whether it matches the last client commit. |
| 32 / 40 | Bytes to delete before/after the selection. |
| 48 / 56 | Preedit cursor/selection byte offsets; both -1 hide the cursor. |
| 64 / 72 | Commit/preedit UTF-8 byte lengths. |
| 80 | Cancellation notification. |
| 96 / 104 | Borrowed commit/preedit NUL-terminated string pointers. |

Apply each transaction in order: remove the old preedit, delete surrounding
text, replace the selection with committed text, then display the new preedit
and its cursor. Preedit is separate from the saved draft. All indices/deletions
must respect UTF-8 boundaries. A same-session serial mismatch still applies
edits, while outgoing protocol state waits for a matching serial; the Wayland
adapter handles this. It ignores replies predating the current enable/session.
Surrounding text is cropped to a UTF-8-safe 4000-byte window containing the whole
selection; larger selections temporarily omit surrounding support.

The real Fcitx Pinyin suite runs only on a private headless Sway/D-Bus session;
it verifies native preedit, Chinese commit, candidate placement and full Collie.
See [reproduction and remaining gates](sdl-migration-progress.md).

## Wayland presentation feedback

`gui_presentation_enable(window,1)` enables optional `wp_presentation` v1
measurements if the compositor advertises a locally queryable clock.
`gui_presentation_track(window,nonzero_tag)` arms the next actual submission;
call it before dispatching an input/update to measure that work too. Only one tag
may be armed at once; pending capacity exhaustion returns 0. GUI/window lifecycle
and frame pacing work without this optional protocol. SDL's Wayland canvas backend can attach a comparison observer with the same
API. It borrows SDL's display/surface through `SDL_GetWindowWMInfo`, while owning
its registry, proxies and private event queue. SDL's listeners and queues remain
untouched. Only one SDL window may own the observer at a time; a second enable
returns 0. X11, dummy drivers and SDL OpenGL windows do not support this observer.

`gui_presentation_track_at(window,tag,arrival_ns)` instead records a caller-known
arrival in the clock advertised by `gui_presentation_clock`. It includes time
already spent waiting for dispatch; the library does no clock conversion.
Negative/future timestamps return 0 without allocating a tag. Sampling dispatch
time remains the default with `gui_presentation_track`. The benchmark uses this
explicit timestamp for replay arrivals scheduled independently of frame callbacks;
neither form establishes physical input timing by itself.

Drain `gui_presentation_poll(window,out)` into a caller-owned **128-byte** buffer.
It returns 1 per result, otherwise 0. Fields are 64-bit words:

| Byte offset | Meaning |
| --- | --- |
| 0 / 8 | Caller tag / status: 1 presented, 2 discarded, 3 observation cancelled, 4 invalid or unrepresentable timestamp. |
| 16 | Signed POSIX compositor clock ID. |
| 24 / 32 | Origin sampled when armed (or explicit arrival passed to `track_at`) / immediately before requesting feedback for submission. |
| 40 / 48 | Presentation nanoseconds / compositor refresh prediction in nanoseconds. |
| 56 / 64 | Output sequence bits / protocol presentation flags. |
| 72 | Synchronized output's registry name, or 0 if unknown/unbound. |
| 80 | Receipt time sampled in the same compositor clock. |
| 88–127 | Reserved, zero. |

A cancelled observation does not prove that the update was invisible. Hiding,
turning telemetry off, optional-global removal, and a failed swap cancel affected
records. Discarded is a distinct compositor outcome; retain it when counting
completed visible updates. Do not interpret zero refresh/sequence values as a
known display interval or missing-refresh count. Flags retain the compositor's
hardware/vsync/zero-copy claims; a headless result with zero flags is not physical
scanout proof. High/low seconds and sequence words are decoded without truncation;
unrepresentable signed nanoseconds return status 4.

`gui_presentation_clock(window,out16)` writes clock ID/current nanoseconds to two
64-bit words. Use that clock for latency boundaries; GUI ticks, frame callback
milliseconds and swap-return time may have different domains and meanings.
`gui_presentation_stats(window,out48)` writes six totals: active, unread, lost,
cancelled, presented events, discarded events. An invalid-timestamp presented event
still counts in the event total. These functions return 0 on unsupported backends
or invalid arguments. `enable(window,0)` cancels active measurements; unread
results remain available.

The SDL observer retains one registry per video lifetime rather than allocating
another on each window reopen. Window close releases its 40-KiB telemetry store;
`gui_quit` destroys only observer-owned objects and its queue, before SDL tears
down its own display. It never disconnects the borrowed connection. Observation
uses the same prepare/read/cancel pairing on a private queue, then lets SDL pump
its events. An instrumented wait also returns within 16 ms for SDL events pushed
by other threads/devices without Wayland socket readiness. Real compositor keys
and SDL-pushed keys are verified before/after observer teardown. Disabled
instrumentation leaves ordinary SDL rendering/waits unchanged.

The public SysWM layout (72 bytes; subsystem/display/surface at offsets 4/8/16)
is independently checked against SDL headers, and a test-only C oracle compares
actual pointers. The application implementation is Flexscript; it loads no C
observer shim. Sources: [SDL's SysWM API](https://wiki.libsdl.org/SDL2/SDL_GetWindowWMInfo)
and [Wayland queue ownership](https://wayland.freedesktop.org/docs/html/apb.html).

Each presentation context has a 256-byte header and lazily allocates 40 KiB for at most
64 pending and 256 completed records. A full completion queue drops the new result
and increments `lost`; every completed/cancelled slot is reclaimed. Check that
counter before treating a sample set as complete. Closing the window releases all
storage and protocol proxies. Telemetry is disabled in ordinary Collie use.
Pinned, licensed presentation XML and the Flexscript-generated metadata are
checked against the independent `wayland-scanner` test oracle. Real private-session
records are compared with raw protocol events by
`scripts/test-wayland-presentation.py`; reproduction is in
[the migration journal](sdl-migration-progress.md).

Collie selects native Wayland by default when `WAYLAND_DISPLAY` is set, respecting
explicit backend or SDL video-driver overrides. Generic GUI consumers retain
the SDL default. See [migration correctness acceptance](sdl-migration-correctness-2026-10-27.md)
for supported scope and remaining platform coverage.
