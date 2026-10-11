# Native windows

`libs/gui.flex` provides native windows, input, a 2D canvas, RGBA framebuffer
presentation, window-backed OpenGL contexts, cached dispatch and GLSL compilation.
Its implementation lives in `libs/gui/`; `lib/gui.flex` and `lib/gui/*` remain
compatibility imports. The library is written in
Flexscript and uses the existing integer/pointer FFI; it does not change the
compiler or require a Rust runtime, browser, C compiler or linker to build apps.
SDL2 2.26 or newer is a runtime dependency (`libSDL2-2.0.so.0`).

The initial target is Linux x86-64, matching the native compiler and FFI.
SDL supplies X11/Xwayland and Wayland platform integration. The backend is
selected by SDL, or explicitly with `SDL_VIDEODRIVER=x11` or `wayland`.
X11/Xwayland and an actual OpenGL GPU have been exercised locally. Native
Wayland selection is supported by SDL but has not been independently verified
by this library's acceptance suite. Windows/macOS binaries are not supported.

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
| `gui_relative_mouse(window,enabled)` | Grab/hide the pointer for relative motion; requires keyboard focus to enable. |
| `gui_key(window,scancode)` | Held physical key, after processing events. |
| `gui_mouse_buttons(window)` | Held buttons as a bit mask: left 1, middle 2, right 4. |
| `gui_focused(window)` | Keyboard focus state. |
| `gui_text_input(enabled)` | Start or stop SDL's UTF-8 text input. |
| `gui_ticks()`, `gui_delay(ms)` | Milliseconds since SDL initialization, and a delay. |

Flags can combine `GUI_RESIZABLE`, `GUI_HIDDEN` and `GUI_HIGH_DPI`; 0 creates a
normal visible window. Sizes must be 1–16384. Up to 32 windows can coexist.
Handles include a generation: closing and reusing a slot cannot let an old
handle operate on the new window. Closing an invalid/already closed handle
returns 0. The bounded record storage is retained for reuse for process lifetime.

Use one application-wide event loop. `gui_event()` allocates a 128-byte buffer
once; reuse it. `gui_poll(event)` returns 1 for a supported event and 0 when the
queue is empty. It updates held input state for the event's window. Unknown
events are consumed safely; empty polls clear the output buffer. There are no
per-frame library allocations after initialization, apart from SDL's own storage
and streaming-texture creation when dimensions change.

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
| `GUI_WHEEL` | `gui_event_dx/dy`: signed integer horizontal/vertical steps, with flipped direction normalized. |

Physical key constants include `GUI_KEY_ESCAPE`, `GUI_KEY_LEFT`,
`GUI_KEY_RIGHT`, `GUI_KEY_UP_ARROW` and `GUI_KEY_DOWN_ARROW`; other keys use
[SDL scancodes](https://wiki.libsdl.org/SDL2/SDL_Scancode). Text entry is separate
from physical keys. Keyboard layout conversion and UTF-8 font rendering belong
to the app. IME composition UI, clipboard, gamepads and drag/drop are not exposed
yet. Unsupported events with owning payloads are freed while being ignored.

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
