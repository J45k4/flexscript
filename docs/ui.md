# Portable declarative views

Flexscript's `view` syntax has one AST frontend and update-code generator shared
by Monolith's HTML views and portable views. Portable views render to native
Android widgets, DOM elements, or a native SDL desktop canvas. The desktop
adapter implements layout, painting and editing in Flexscript on `libs/gui`.
FlexOS adapters remain future work.

```flex
import "ui";
extend "ui/syntax.flex";
global count=0;
view app_view(){
    column("app",padding:20,gap:12){
        text("count",text:m_int(count),size:24);
        button("increase",text:"Increase",action:"increase");
    }
}
```

The syntax frontend parses components, properties, local bindings, `if`/`else`,
`each`, and `use` into an explicit UI AST with source locations. It validates
keys, widgets, properties and structure, then lowers the AST to ordinary
Flexscript functions. Expressions continue through the normal Flexscript compiler.
No Java or JavaScript is generated for individual screens.

Native applications that treat static view properties as immutable can select
`extend "ui/syntax.flex" with "desktop";`. This profile packs constant attributes
into name/value tables and emits update functions only for reachable components
and views referenced by ordinary Flexscript functions. Ordinary generation keeps
its existing mutable-property behavior.

`desktop:my_desktop_guard` additionally declares that the pure, zero-argument
boolean function `my_desktop_guard()` is true for this build. The frontend selects
matching view branches before following component uses. It still validates the
structure and property types of excluded branches. The shared UI library has no
application-specific guard names. Use `desktop-source:my_desktop_guard` when an
embedder also needs the validated transformed modules exported as source.

Calling `app_view()` builds a keyed tree. Retain the previous root and
`ui_index`; `ui_compiled_diff(old,new,old_index,new_index)` returns an array of
operations. `ui_compiled_diff(0,new,0,new_index)` creates a complete snapshot.
Literal properties need no runtime comparisons; generated functions compare
dynamic bindings and keyed structural candidates. Each refresh still rebuilds
the tree: fine-grained dependency tracking and cached static trees are not
implemented. The shared generic builder differ remains available as `ui_diff`.

## Widgets and properties

| Widget | Meaning |
| --- | --- |
| `column`, `row`, `stack` | Vertical, horizontal, or overlapping layout |
| `scroll`, `hscroll` | Vertical/horizontal scrolling viewport with one unconditional content view |
| `text`, `button` | Text and an action button |
| `input` | Editable text; `text` is its placeholder |
| `check` | Boolean control: Android Switch, browser checkbox |
| `image` | Image loaded by the platform from `source`; `zoom:1` enables Android pinch/pan or desktop wheel/drag |
| `progress` | Native progress indicator, value 0..1000 |

Every node starts with a stable nonempty string key. Keys must be unique across
the mounted tree. Nodes and component descendants inside `each` need dynamic
keys, for example `m_cat("worker-",m_int(id))`. A conditional can reuse a key in
mutually exclusive branches; changing its template replaces that subtree.
The tree limit is 2,048 nodes; lists are currently ordinary keyed children rather
than virtualized native list widgets.

Common properties:

- Strings: `text`, `action`, `description`, `color`, `background`, `border_color`,
  `font`, `align`. Use hex colors; `font:"medium"` selects medium text weight.
  Alignment is `start`, `center`, or `end` within the widget's layout axis.
- Integers: `padding`, `padding_x`, `padding_y`, `gap`, `radius`, `border_width`,
  `size`, `weight`, `width`, `height`, `min_height`. Layout lengths use Android dp
  and browser/desktop logical px; text size uses Android sp or browser/desktop px. Positive weight
  shares available parent-axis space. Width/height `-1` fill the parent and `-2`
  wrap content. Platform font metrics and control appearance can differ.
- Booleans expressed as Flexscript words: `hidden`, `enabled`, `checked`.
  `checked` belongs to `check`; `action_id` is an integer accompanying `action`.
- `value` is an explicit string value for `input`. Updates that do not change
  this property preserve drafts, focus, selection and composing text. Changing
  it explicitly replaces the draft. `source` belongs to `image`; native source
  resolution is currently a local Android URI and browser source resolution a
  browser URL. Android also resolves `preview:ID` to an immutable private
  snapshot and `resource:TYPE/NAME` to an APK resource. Browser embedders can
  provide `imageSource` through the renderer platform adapter.
  The portable browser host permits images from its own origin, data URLs and
  blob URLs; it does not fetch arbitrary remote image sources.
- `autocapitalize` belongs to `input`: `"none"` (the default), `"sentences"`,
  `"words"`, or `"characters"`. Android and DOM adapters pass this hint to the
  platform editor; they do not rewrite the value in Flexscript. Search and
  identifiers should use `"none"`; chat can request `"sentences"`. Desktop
  committed text remains unchanged.

Unknown widgets and properties fail compilation. Portable views use explicit
style properties; HTML tags and CSS classes remain in the Monolith HTML frontend.
A platform adapter is required for any additional native widget.

## Platform bridge

Batches have `{version:1,ops:[...]}`. Operations are keyed `insert`, `remove`,
`move`, `text`, `placeholder`, `label`, `checked`, `hidden`, and `attribute`.
An insertion carries a `node` record containing kind, key, text, action, action ID,
checked/hidden state, properties and children. It contains no HTML. Property
patches use the `attribute` operation with a name and string value, or null to
remove a property; boolean state has dedicated operations. Action names and IDs
are encoded as the `action` and `action_id` attributes.

Adapters maintain key-to-widget maps and apply the batch on the platform UI
thread. Input events return `{key,type,action,action_id,value}`. User typing uses
`change` with a string; check changes carry a boolean; button clicks use `click`.
Programmatic patches do not produce user events. Reconnect snapshots reconcile
existing keys and preserve local drafts when their explicit value is unchanged.
The embedding application owns model state, revision/order tracking and routing
of events; the renderer owns widgets. Arbitrary guest programs have not gained
access to the app UI bridge.

The Android adapter is `apps/collie/android/UiRenderer.java`; the DOM adapter is
`libs/ui/web.js`. All Collie screens and interaction policy are under
`apps/collie/ui/`. `libs/ui/richtext.flex` converts Markdown/code to generic rich
text runs; Android only constructs the corresponding native spans.

The UI reducer consumes `{state,action,data,event}` and returns
`{version,state,ops,command}`. Native service effects (file picking, camera,
clipboard, worker actions, persistence and navigation exits) are selected by
Flexscript. The Android host executes them and publishes facts/acknowledgements.
Old/new models cross calls; no tree pointers survive. Navigation snapshots omit
conversation content and credentials. Persistence failure restores the actual
policy using a shared state update.

Android compiles this UI into an independent `libcollie_ui.so`, with a separate
JNI lock and bounded arena from the agent/compiler/VM image. Long agent execution
therefore cannot block native UI evaluation. `ui-host.c` provides allocation,
failure handling and JNI only; it denies UI-side filesystem/network/process calls.
The ARM64 `ui-native-test` executable uses the same UI image without Android.

Additional properties used by Collie include numeric `single_line`, `min_lines`,
`max_lines`, `selectable`, `timestamp`, `follow`, `line_height`, `alpha`, `zoom`,
and `progress`; string `ime`, `hint_color`, `position`, and `runs`. A `runs` value
is JSON rich text: text fragments, style bits, optional colors and HTTP(S) links.
Timestamps use platform-local formatting. `follow:1` on a scrolling viewport
follows content only while already near its tail. `ime:"send"` emits a `submit`
event from the editor. Property updates preserve unchanged native composing text.

On desktop, vertical wheel input scrolls the vertical ancestor even when the
pointer is over a horizontal code viewport. Horizontal wheel input or
Shift+wheel pans horizontal content. A standalone horizontal viewport also
accepts ordinary wheel input. Nested panes pass input to an ancestor when they
reach the relevant edge; offsets are clamped per event so direction reversals
respond before the next frame.
Vertical scrollbars expand within 16 logical pixels of the viewport edge.
Desktop scroll views can set `scrollbar_width` (3–9 logical pixels, default 3)
and `scrollbar_track:1` for a persistent track while the content overflows.
Their thumbs support captured pointer dragging; track clicks page the content.
Dragging preserves text focus/selection and is canceled on release, focus loss,
modal changes, or removal/disablement of the viewport.
Manual scrolling away from the bottom pauses tail following through background
updates; scrolling or dragging back to the bottom resumes following new content.

## Browser host and examples

`import "ui/web.flex"` combines portable views with Monolith's existing native
loopback HTTP/SSE transport. It keeps the same `app_init`, `app_tick`,
`app_action`, and `mono_run` hooks. In `app_action`, `mono_field("ui_key")`,
`mono_field("ui_type")`, and `mono_field("ui_value")` carry native UI event data.
The first SSE snapshot mounts the view; portable pages are not server-rendered
HTML and require JavaScript. This browser host is currently Linux x86-64.

```sh
build/flexscript examples/ui/counter.flex -o build/ui-counter
build/ui-counter 8092
# From the checkout: the identical view used by the Android app.
build/flexscript examples/ui/collie-permissions.flex -o build/ui-permissions-web
build/ui-permissions-web 8092
```

Existing `import "monolith"; extend "monolith/syntax.flex";` applications keep
their HTML/SSE wire format and stylesheet support. They now use the same AST
parser and runtime tree/update machinery through compatibility imports.

## Verification

```sh
build/flexscript scripts/build-tools.flex -o build/build-tools
build/build-tools --compiler build/flexscript
build/tools/ui-assets --check
build/tools/test-ui --compiler build/flexscript
build/tools/test-collie-ui --compiler build/flexscript
xvfb-run -a build/tools/test-ui-desktop --compiler build/flexscript --x11
# After building Collie's debug APK, also compare actual ARM64 output and widgets:
build/tools/test-ui --compiler build/flexscript \
  --out build/android-collie-ui --serial emulator-5580
build/tools/test-collie-ui --compiler build/flexscript \
  --out build/android-collie-ui
build/tools/test-collie-ui-android --out build/android-collie-ui \
  --serial emulator-5580
build/flexscript examples/ui/collie-permissions.flex -o build/ui-permissions-web
build/flexscript tests/ui/browser.flex -o build/test-ui-browser
build/test-ui-browser build/ui-permissions-web /usr/bin/chromium
```

The native/interpreter/JIT fixtures, real Chromium tests and Android widget tests
consume the same compiler-generated batches. Checks cover structure changes,
keyed identity, event bindings, input drafts/focus/selection, controlled values,
minimal screen patches, cross-client actions, and Linux/Android output parity.
The browser test replays every Collie screen and saves
`build/ui-permissions-browser.png` and `build/collie-ui-browser.png`. Rebuild the
embedded browser asset after editing either browser source:
`build/tools/ui-assets`.

Android's existing build flattens and adapts engine sources to its bounded host
ABI. It first compiles a small UI entry using the shared extension's `source`
export mode, then embeds those validated transformed modules. Export uses length-prefixed
UTF-8 module frames to avoid spending the bounded extension VM budget on source
escaping. The UI and agent images are linked independently. This avoids
running the view extension over the entire embedded Flexscript compiler.

## Native desktop adapter

`import "ui/desktop.flex"` consumes the identical ABI1 batches using SDL2 windows
and the existing GUI canvas. It creates custom drawn desktop controls; it does
not use a webview or generate platform-specific screen code. All eleven widget
kinds, row/column weights, stacking, clipping, scroll viewports, rounded surfaces,
progress, rich text and local images are supported. Text uses SDL2_ttf with
Fontconfig fallback; local PNG/JPEG/etc decoding uses GdkPixbuf. These libraries
load lazily. The underlying GUI window/input/renderer ABI remains in `libs/gui`.

On Debian/Ubuntu install `libsdl2-2.0-0 libsdl2-ttf-2.0-0 libfontconfig1
libgdk-pixbuf-2.0-0 fonts-dejavu-core`; Noto fonts provide additional Unicode
coverage. Building the C test oracle also needs SDL2 headers and a C compiler.
The production implementation is entirely Flexscript with integer FFI calls.

```sh
build/flexscript examples/ui/desktop-counter.flex -o build/ui-desktop-counter
build/ui-desktop-counter
# From the checkout, the actual Collie permissions view and reducer:
build/flexscript examples/ui/desktop-permissions.flex -o build/ui-desktop-permissions
build/ui-desktop-permissions
```

The browser and desktop counters import `counter-view.flex`, including the same
view and counter actions. Both desktop examples accept an optional frame count
for bounded smoke checks. The permissions example keeps grants in memory and
Back closes its window; it is not a complete desktop Collie agent host.
The complete [Collie desktop host](../apps/collie/desktop/README.md) wires the
shared chat, conversations, permissions and worker views to the checked engine,
native event loop, persistence and Linux platform services.

An embedding application owns its event loop and platform effects:

- `ui_desktop_open(title,width,height,flags)` returns the GUI window handle.
- `ui_desktop_apply(packet)` applies `{version:1,ops:[...]}`. It copies incoming
  JSON into a private arena, so the caller may release its request storage.
- `ui_desktop_event(gui_event)` returns the same portable input record as Android
  and the browser, or 0 when no application action occurred. Pass each normalized
  event from `gui_poll`; the application handles quit/close itself.
- `ui_desktop_needs_draw()` handles invalidation and the editor's blinking caret;
  `ui_desktop_draw()` reflows/paints, and `ui_desktop_present()` presents.
  `ui_desktop_repaint()` paints cached geometry for visual-only changes such as
  a container background. Use `draw()` after content, layout or window changes.
- `ui_desktop_image(source,path)` binds virtual sources such as `preview:ID` or
  `resource:TYPE/NAME` to host-approved local files. Plain paths and `file://` work
  directly. Remote image URLs are not fetched by the renderer.
- `ui_desktop_focus(key)`, `ui_desktop_bounds(key,out)`,
  `ui_desktop_identity(key)` and `ui_desktop_value(key)` expose retained controls.
- `ui_desktop_focus_scope(key)` restricts focus and Tab navigation to a modal
  subtree. Pass an empty key to restore navigation across the window. Removing
  the subtree clears the scope. A row child with `height:-1` stretches to the
  row's full height, allowing a sidebar and content pane to fill a window.
- Desktop focus styling accepts `focus_border_color`, `focus_border_width`,
  and `focus_background`. Set `focus_within:1` on a container to apply these
  styles when a descendant has focus, such as an editor inside a composer row.
  Focus styling does not change layout dimensions. Clicking or editing an input
  restarts its caret blink with the caret visible immediately.
- Empty operation batches preserve the existing model and draw invalidation;
  they do not rebuild retained descriptors or request another frame.
  Returned text pointers remain valid only until the next model mutation.
- `ui_desktop_close()` releases textures, font handles and the private model.
  The caller retains ownership of other GUI windows and application allocations.

Stable keys preserve editor drafts/caret/selection and scroll offsets through
moves and reconnect snapshots. Explicit `value` changes replace the draft.
Editing supports committed UTF-8 text input, selection, arrows, Home/End,
Backspace/Delete, Tab, clipboard shortcuts, and `ime:"send"` submit events.
Set `selection_scope:1` on a desktop document container to let a press in its
blank space begin a drag into nearby selectable text. The press stays pending
until the drag threshold is crossed; an ordinary blank click clears focus.
Blank-space fallback skips controls, images, disabled regions, hidden/clipped
text, and scrollbars. Release, focus loss, and node removal
cancel a pending drag.

Pointer selection reuses one retained text layout and lazily cached UTF-8 caret
positions; warm drag events do not rebuild layout or measure fonts. Text/style,
wrap width, display density and node removal invalidate the cache. Repeated
motions within the same character do not request another redraw.
Following the transcript never moves keyboard focus. Model arenas compact after
each batch; removed nodes release native textures. One renderer with up to
2,048 retained nodes is currently supported per process, with up to 128 cached
font size/style/fallback combinations. Fonts and cached text layers follow the
window's framebuffer density (up to 4x); layouts and caret positions stay in
window units. Moving between display densities invalidates font bitmaps while
preserving drafts and selection. Text-only layers retain straight glyph alpha,
so antialiased edges blend against the final background once.

Desktop applications can use `rt_markdown_tables(text)` from
`libs/ui/markdown-tables.flex` for pipe tables. It emits cell metadata on the
usual rich text runs, with a tab/newline copy order. The desktop renderer keeps
a whole message in one selectable widget, aligns columns, wraps cell content,
and draws table backgrounds separately from antialiased glyphs. This avoids
allocating one native widget per cell. The extension supports up to 16 columns
and 256 rows per table; plain `rt_markdown` retains its existing inline output.

The initial desktop backend does not yet expose an OS accessibility tree or
preedit composition display. It consumes completed SDL text input. Markdown
text selection uses rendered UTF-8 content, so copying a
selection excludes formatting delimiters. Desktop link runs are underlined and
emit a `type:"link"` event with the destination in `value` on click; dragging
selects text instead. The application validates the destination against its
rendered runs and owns browser/file opening. Text layers are bounded to 8,192
by 16,384 pixels; very long text still
needs tiled rendering/virtualization. The host supplies authentication, storage,
networking, file dialogs and agent execution for a full application.

`scripts/test-ui-desktop.flex` applies the actual generic and Collie compiler
batches, verifies decoded text/image pixels, and saves native screenshots under
`build/ui-desktop-*.png`. Its text raster regression compares cached glyphs with
direct font rendering on dark/light backgrounds and at reduced opacity, using
simulated 1x and 2x framebuffers, and checks density-aware caret hit testing.
The selection regression also compares cached hit testing with independent font
measurements, checks cache invalidation/cleanup, and reports processing times in
`build/ui-selection-performance.json`. These timings exclude physical display
latency. The SDL dummy driver supports headless pixel tests;
`--x11` additionally requires mapped windows and real XTest keyboard/pointer input
on an isolated display. CI uses Xvfb so tests never touch the user's desktop.
