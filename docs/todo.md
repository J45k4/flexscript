# Native Todo

`examples/todo.flex` is a desktop todo app written entirely in Flexscript 0.0.1.
The existing released compiler emits its Linux x86-64 executable directly.
The app draws its own controls, rounded cards, icons, and original 5-by-7 bitmap
font, using X11 rectangles and an offscreen pixmap. There is no UI toolkit,
HTML, Rust runtime, libc, or font asset to install. A local X11 or Xwayland
server with a 24-bit or 32-bit TrueColor screen is required.

From the project root:

```sh
mkdir -p build
build/downloaded/flexscript-0.0.1-linux-x86_64 examples/todo.flex -o build/todo
./build/todo
```

If your native Flexscript compiler is elsewhere, substitute its path. The
resulting executable runs independently of the compiler.

The app supports adding, editing, completing, and deleting tasks; All, Active,
and Completed filters; a completion counter and progress bar; scrolling;
and clearing completed tasks. Click a task card to toggle completion, the
pencil to edit, or the X to delete. Click Add or press Enter to commit input.
An empty list gets its own drawn empty state. The layout follows the window
size, with a minimum usable size of 760 by 560.

| Key | Action |
| --- | --- |
| Enter | Add or save input; toggle selected task when the list has focus |
| Tab / Shift+Tab | Switch input and task list focus |
| Left / Right, Home / End | Move the input caret |
| Backspace / Delete | Edit input; Delete removes a selected list task |
| Up / Down | Select a task; from input, switch to the list |
| Page Up / Page Down | Move list selection one visible page |
| F2 or E, with list focused | Edit the selected task |
| Ctrl+A | Select all input text |
| Escape | Cancel editing and clear input |
| Ctrl+S | Retry saving |
| Ctrl+Q | Close |
| Mouse wheel | Scroll the task list |

Text currently supports printable ASCII, with up to 120 characters per task
and 256 tasks. Long task labels are shortened visually; their full text stays
in storage and can be edited. This is an application built using the existing
language features; it does not change the compiler or language.

## Local data

By default, tasks live in `flexscript-todos.db` in the working directory.
Choose another location or local display with:

```sh
./build/todo --data /path/to/tasks.db
./build/todo --display :0
```

The parent directory must already exist. Each committed task change is saved
immediately. The app writes a private temporary file, syncs it, and atomically
renames it over the data file. Failed saves leave the previous data intact;
the window shows an unsaved status and Ctrl+S retries. Closing retries pending
saves and reports a failure on stderr if saving still fails. Uncommitted input
is not stored.

A sibling `.lock` file prevents two app instances from overwriting the same
list. That small lock file remains after closing; the lock itself is released.
Malformed, nonregular, or symlink data files are rejected before opening the
window. The default list and its sibling files are ignored by Git. The format
is `FLEXTODO1` followed by newline, then one line per task: `0` or `1`, a tab,
and the task text. `1` means completed. Do not edit the file while the app is
running.

The client connects to the local `/tmp/.X11-unix/XN` socket using `DISPLAY`,
with an optional `--display` override. It reads an existing X11 cookie from
`XAUTHORITY` or `~/.Xauthority` when present. It implements the
[X11 core protocol](https://xorg.freedesktop.org/archive/X11R7.7/doc/xproto/x11protocol.html)
in Flexscript, including window events, keyboard mapping, properties, and
rectangle drawing. This version uses screen zero, the first keyboard group,
and conventional TrueColor RGB pixels; it does not support remote X11, native
Wayland, clipboard paste, or Unicode text entry.

## Verification

Run deterministic model and persistence checks without opening a window:

```sh
python3 scripts/test-todo.py
```

Use `--compiler /path/to/flexscript` to select another compiler. To also exercise
the actual native window on the current display:

```sh
python3 scripts/test-todo.py --gui
```

The GUI test opens its own temporary task list, sends input only to the newly
created app window, and verifies saved data after adding, editing, completing,
filtering, deleting, clearing, and scrolling. It also checks save failure and
retry, restart, concurrent-instance locking, normal window close, and SIGTERM
cleanup. A screenshot containing only the synthetic test window is saved to
`build/todo.png`; no desktop screenshot is taken. Python, Xlib, and Pillow are
used by the test driver only.

For a direct model check:

```sh
./build/todo --self-test
```

`--self-test --data PATH` additionally checks persistence and requires a new
path. It leaves the generated test data at that path for inspection.
