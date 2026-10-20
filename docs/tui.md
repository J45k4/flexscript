# Native terminal UI library

Import `libs/tui/tui.flex` to build Linux terminal applications in Flexscript.
The library has no ML or GPU dependency. `llm.flex` and
[`apps/collie`](../apps/collie/README.md) are chat applications using it;
`examples/tui/editor.flex` is a standalone editor example.

```sh
build/flex-llm examples/tui/editor.flex -o build/tui-editor
build/tui-editor
```

The library uses Linux terminal ioctls, poll and signalfd. libc supplies display
widths; GLib supplies Unicode combining-mark classification. It supports UTF-8
editing, combining marks, emoji modifiers, ZWJ sequences and regional flags.
This is a small native library, with one active terminal and editor per process,
rather than a complete Unicode text-layout engine.

## Modules

| File | Responsibility |
| --- | --- |
| `terminal.flex` | Raw mode, alternate screen, signal cleanup, size, ANSI output, Unicode and render scratch |
| `events.flex` | Incremental keys, modifiers, mouse, UTF-8 and bracketed-paste parsing |
| `editor.flex` | Cursor, selection, insertion, deletion, word movement and prompt history |
| `screen.flex` | Wrapped byte ranges, drawing and mouse-to-byte mapping |
| `widgets.flex` | Scrollable text view and multiline editor widgets |
| `clipboard.flex` | Wayland `wl-copy` / `wl-paste`, or X11 `xclip` |
| `tui.flex` | Public aggregate import |

## Event loop

Call `h_environment(argc,argv)`, `te_init()` and `ti_init()`, then `tu_open()`.
`tu_open()` returns false for redirected stdin. Call `tu_close()` on every
normal exit; it restores terminal attributes, mouse/paste modes, cursor and
alternate screen. `ti_wait(milliseconds)` returns 0 for timeout, 1 when input
has been queued, or 2 for SIGINT/SIGTERM/SIGHUP or a terminal disconnect.
The application should exit its loop and call `tu_close()` for result 2.
Uncatchable signals such as SIGKILL cannot restore a terminal.

Consume queued input with `while ti_next(wait_result==0) { ... }`. A timeout
flushes a lone Escape; split CSI and UTF-8 sequences wait for more input.
Applications may instead call `ti_feed(bytes,length)` to supply input from
another transport. Bracketed paste is delivered as a single event and never
turned into Enter key events. Input is bounded to 128 KiB; `ti_overflow` reports
an oversized paste.

| `ti_kind` | Event data |
| --- | --- |
| 1 | UTF-8 text in `ti_text` |
| 2 | `ti_key`, with `ti_mod` bits 1 Shift, 2 Alt, 4 Ctrl |
| 3 | SGR mouse: `ti_x`, `ti_y` (one-based), `ti_button`, `ti_release` |
| 4 | Bracketed paste in `ti_text`, preserving newlines |

Keys use ASCII control values where applicable. Special values are 1001 Up,
1002 Down, 1003 Right, 1004 Left, 1005 Home, 1006 End, 1007 Delete, 1008 PageUp
and 1009 PageDown. The parser recognizes Alt+Enter and CSI-u Shift+Enter;
Ctrl+J is a portable newline binding when a terminal does not distinguish
Shift+Enter. Mouse button values retain xterm's drag and wheel bits.

## Editor and rendering

`te_set(text)`, `te_replace(text)`, `te_backspace()` and `te_delete()` manipulate
the editor. `te_left(select)`, `te_right(select)`, `te_word(left,select)` and
`te_move(byte_offset,select)` move the cursor. Use valid cluster boundaries
for explicit byte offsets. `te_low()` / `te_high()` delimit a selection.
`te_line_edge(end,select)` moves within the current logical line;
`te_vertical(down,select,columns)` moves between wrapped rows, recalling prompt
history at the first or last row when selection is off.
`te_submit()` returns the draft, records it in history and clears the editor;
`te_recall(down)` browses history and restores the unsent draft at the end.

Build each frame in an `h_buffer()`. `tu_line(out,row,text,color)` writes a
clipped line; colors are SGR parameters such as `"1;36"` or zero for default.
`tw_text(out,text,row,height,scroll,lo,hi,color)` draws wrapped text, where
scroll zero follows the end and `lo`/`hi` select byte offsets (-1 disables
selection). `tw_editor(out,row,height)` draws the composer and positions its
cursor. `tw_panel(out,title,text,bottom,max_height,scroll)` anchors a panel at
the given bottom row and grows upward, clipping and scrolling long content.
It returns the panel's top row (or zero when there is insufficient room).
`tw_progress(out,row,completed,total,tick_ms)` draws a fraction and percentage
when `total` is positive, or an animated activity bar when the total is unknown.
`ts_wrap(text,columns)` and `ts_offset(text,rows,row,column)` let an
application map mouse coordinates back to byte offsets, including wide text
and wrapping. The application owns focus, dragging and scroll policy.

Use `tu_mark()` / `tu_reset(mark)` around temporary frame allocations. Keep
application state outside that scope. In particular, initialize persistent
buffers before rendering: `h_data()` can allocate backing storage lazily.
Call `h_print(1,h_data(out))` before resetting frame scratch.
`tu_clean(text)` removes terminal control bytes from untrusted display text.

`tc_copy(text)` returns success, and `tc_paste()` returns text or zero.
`tc_error` describes a failure. Clipboard commands use argv vectors without
shell interpolation. The application chooses copy shortcuts and whether a
mouse selection copies automatically. Clipboard adapters are synchronous;
applications requiring uninterrupted redraw during clipboard operations can
run them in a worker. Copy waits only for the helper's launcher to exit, not
for output pipes inherited by its background clipboard owner. It keeps that
owner alive for later paste requests. Copy failures are recoverable; a stalled
launcher times out after two seconds.

## Checks

```sh
build/flex-llm scripts/test-tui.flex -o build/test-tui
build/test-tui
python scripts/test-llm-tui.py
```

The native suite covers Unicode editing, selection, incremental events, paste,
wrapped mouse offsets, large transcripts and rendering allocation lifetimes.
The PTY suite checks the chat application's streaming, clipboard adapters,
mouse copying/pasting, cancellation, persistence, resize and terminal restoration.
Clipboard integration tests use isolated command fixtures; desktop clipboard
availability depends on the user's session. The background-owner regression
checks streaming, selection clearing, paste, large Unicode transfers and
helper failures with `python scripts/test-llm-tui.py --clipboard-only`.
