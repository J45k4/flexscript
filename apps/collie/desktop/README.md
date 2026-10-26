# Collie on Linux desktop

The native SDL window runs a desktop layout with shared message views, pages, event reducer, provider
protocol, conversation machine, worker scheduler, permission gates, checked VM,
FlexDB and resumable VM checkpoints as the Android application. It starts from
`83e8b37` on `codex/collie-hardware-adapters`; the older `codex/collie-android`
branch is also included in this history.

Build in this worktree using a full Flexscript compiler:

```sh
flexscript compiler/main.flex -o build/flex-collie-desktop
build/flex-collie-desktop apps/collie/desktop/build.flex -o build/build-collie-desktop
build/build-collie-desktop --compiler build/flex-collie-desktop
build/collie-desktop/collie
```

The first command builds this branch's compiler because the desktop engine uses
its native six-word C callback adapter. The engine currently uses the direct
native pipeline; the GUI uses the normal native IR pipeline. No QEMU, Android
SDK, JVM, browser, Python code generator for UI syntax, or installed-compiler
replacement is involved. The Flexscript build driver links the same shared
Android engine and bounded broker; its native syscall ABI, native callbacks, platform services
and application bootstrap change. Android sources are not modified by building.

The desktop application and its build driver are Flexscript. Python and Pillow
are not needed to build or run Collie. Runtime dependencies are SDL2 2.26+,
SDL2_ttf, GDK Pixbuf, OpenSSL 3 libssl/libcrypto, and system sans/monospace
fonts. A C compiler builds the existing small native broker.
Install `zenity` or `kdialog` for file selection. `ffmpeg` enables one-shot Linux
V4L2 camera attachments; camera access remains subject to actual OS/device
permissions. Missing dialogs, cameras and platform adapters return actionable
errors. Camera capture happens only after selecting Camera; opening Collie does
not open a camera or make a model request.

By default the app reads the existing `$CODEX_HOME/auth.json` (or
`~/.codex/auth.json`) and stores its own conversations under
`$XDG_DATA_HOME/collie` (or `~/.local/share/collie`). Connect ChatGPT can import a
Codex `auth.json` through a file chooser, keeping an app-private copy. Model
credentials are never passed to guest HTTPS or hardware operations. Model TLS
uses the shared provider's exact endpoint and headers, rejects redirects, and
feeds all stream events back through the shared provider validator.

```sh
build/collie-desktop/collie --data /path/to/private/collie --auth /path/to/auth.json
```

The sidebar has **Projects** and **Timeline** modes. Projects groups chats under
collapsible project headings, with a chat count and a **+** to start a chat in
that project. Timeline shows every project's chats and personal chats in saved
activity order, with project labels and dates. Search covers all conversations
and project names in either mode and reveals matching collapsed groups. The
mode and collapsed groups survive chat switches and restart.

The top speech-bubble icon starts a **New chat** in the current project. The adjacent
**New project** icon, or the **+** beside the Projects heading, opens a host
folder chooser. The folder name becomes the project name. Use the project groups
or Timeline to open a conversation, and each group's **+** to start a chat there.
When the sidebar is hidden, the header's project button opens a project picker.
Choosing an existing project there opens its latest conversation. Adding a project starts a
separate conversation and leaves existing conversation files in place. Personal
chats keep their own private files.

The gear opens a dedicated **Settings** page with **Model & context**,
**Permissions**, and **Account** navigation. Wide windows use a navigation
column; narrow windows use tabs. Workspace permissions apply to the current
conversation and its workers. Model selection returns to Settings when opened
there, and login import leaves the Account section open. Back or Escape returns
to the conversation with its draft intact. The sidebar footer contains Workers
and the settings gear.

Account lists saved OpenAI logins by name, email and plan when available. Choose
**Add OpenAI account…** to start browser sign-in through the installed Codex CLI.
**Sign in with device code** is available when a browser callback is inconvenient;
Collie shows the one-time code and opens the verification page. You can reopen or
copy the sign-in link, switch methods, or cancel. The login runs asynchronously
and adding keeps the current selection. **Use account** selects a saved login for subsequent messages,
image generation, feedback and workers across conversations. The choice survives
restart. Stop active replies and workers before adding or switching accounts.
**Import an existing login file…** remains a secondary option. Signing in or
importing the same account updates its login instead of creating a duplicate.

Each login attempt uses its own private Codex home under `account-logins/`, with
file-backed credentials, and the structured `account/login/start`,
`account/login/completed` and `account/login/cancel` protocol. It never signs out
the user's normal Codex CLI. Cancel and app shutdown stop the login process and
remove unfinished credentials. A completed login keeps its private home as the
saved account's credential source. An occupied browser callback port is left
alone; use device code or finish that other login first.

This adapter was checked against the installed Codex CLI 0.164.0 source,
commit `6aaac694803004a63c6f393d153c96d22521a6b9`:
[CLI login methods](https://github.com/openai/codex/blob/6aaac694803004a63c6f393d153c96d22521a6b9/codex-rs/cli/src/main.rs),
[managed login protocol](https://github.com/openai/codex/blob/6aaac694803004a63c6f393d153c96d22521a6b9/codex-rs/app-server/src/request_processors/account_processor.rs),
and [official authentication documentation](https://learn.chatgpt.com/docs/auth).
The CLI also supports API keys and enterprise access tokens; Collie's current
Codex transport uses the browser and device-code ChatGPT login methods.

The existing login migrates automatically into private storage, without changing
its original file. Credentials are saved with mode 0600 under `accounts/` in
Collie's data folder; `accounts.json` stores the registry and selection. A matching
refresh in the original Codex file updates that account's private copy. Signing
into a different account in Codex does not silently change Collie's selection.
There is no automatic fallback to another account if the selected login is
missing or rejected. An explicit `--auth` selects that supplied login.

Opening Account refreshes display details. Credentials stay in the host, and
account metadata stays out of saved conversation history and guest inputs.
Fixture runs do not read the host's identity unless an auth file is explicitly
supplied.

Project chats share the chosen host folder through `fs_*`, file previews, links
and attachments. The model receives the real folder path for explaining where
files were created. File grants still apply per conversation, and workers use
the same project folder. Chat history, drafts, images, credentials and each
conversation's `agent.flexdb` remain in Collie's data directory; `projects.json`
stores the folder registry and `session.json` stores the project ID. A missing
project folder does not redirect file operations into a private workspace.

The launcher preserves explicit display/backend settings. When both DISPLAY and
WAYLAND_DISPLAY are missing, it can discover one owned Wayland socket in the
user's runtime directory. It does not guess between multiple sessions, change
desktop configuration, or attach headless runs to the desktop. To inspect video
initialization without creating a window, run
`build/collie-desktop/collie --video-diagnostics`. Startup failures print the
relevant display settings and SDL backend list.

The desktop UI supports streaming replies and public thinking summaries,
collapsible source/results, text selection and clipboard, multiline Unicode
editing, searchable/paged conversations, new/open/resume, model selection,
manual/automatic compaction, per-conversation Ask/Allow/Deny, progress and model
feedback, durable workers and journals, named VM state, cross-chat recall, file
and image attachments, image previews with zoom/pan, and text previews. Enter
sends, Shift+Enter inserts a newline, Tab moves focus, and Escape goes back.
Stop cancels the current turn and its active workers. Source, local variables,
heap and instruction position survive approved suspension in the same shared
checkpoint format as Android. An interrupted non-checkpointed program is never
automatically replayed. Closing the window cancels tasks and saves state; opening
a conversation does not automatically resume a model request.

The Thinking panel appears as soon as a main request starts. Before summary
content arrives it shows a waiting status; public summaries replace that preview
and can be expanded. Replies with no public summaries retain their ordinary
answer without adding synthetic thinking cards. Summary requests use
`reasoning.summary: "auto"`, as described in the
[official OpenAI documentation](https://developers.openai.com/api/docs/guides/reasoning#reasoning-summaries).

The default window is 1280 × 860. Wide windows have a persistent, searchable
conversation sidebar with recent previews and direct access to workers and
workspace permissions. Conversations are ordered by saved message activity;
opening or reading one, editing a draft, and saving settings keep its position.
Vertical scrollbars widen when the pointer approaches the edge. Drag the thumb
to scroll directly, or click the track to page up/down.
The sidebar chat list has its own visible scrollbar at the panel's right edge;
dragging it scrolls only the list while search, mode controls and tools stay fixed.
Drag the divider at the sidebar's right edge to resize it. Its width is saved
across conversations and restarts. The sidebar stays between 220 and 520 pixels,
and shrinks temporarily on smaller windows to leave at least 520 pixels for the
main pane; the preferred width returns when the window is widened.
When the divider has keyboard focus, Left/Right adjusts the width in 16-pixel steps.
Clicking a sidebar conversation paints its selected highlight before processing
message Markdown or loading engine state. The title and a loading pane follow;
the selected conversation's messages and draft appear when ready. Rapid clicks
keep the latest selection, and completed older loads cannot replace it.
Chat and composer width are capped at 820 pixels for
comfortable reading. Below 960 pixels, navigation becomes compact. Ctrl+B
toggles the sidebar on wider windows; its state survives reopening the
conversation. Resizing preserves the draft. The composer gets a green outline
and active background when focused; clicking immediately shows its caret.
Replies render Markdown headings, bold/italic text, lists, inline/fenced code,
strikethrough, pipe tables and links. Table columns honor left/center/right
alignment and wrap long cells. Selection spans the full message, and copied
tables use tabs between cells. Drag to select text, then use Ctrl+C; Ctrl+A selects the
focused message. You can start a text-selection drag in the transcript gutter
or blank space above/below a message. Drag selection caches layout and character positions; the event
loop wakes on input instead of imposing a fixed sleep after each frame.
Clicking a web link opens the browser. Relative file links such
as `[tetris.html](tetris.html)` open the file inside the chosen project folder,
or the current personal conversation's `files` folder, stored under
`$XDG_DATA_HOME/collie/sessions/SESSION/files` (default
`~/.local/share/collie/sessions/SESSION/files`). Merely displaying a message never
opens a link. Raw HTML is displayed as text. Pipe tables are bounded to 16 columns and 256
rows per table.
The model button opens a searchable picker for GPT-6.1 Sol (`gpt-6.1-sol`) and
GPT-6 Astra (`gpt-6-astra`). Search by name or ID, then click a result or press
Enter. The choice is saved for new replies. Settings dialogs provide automatic
field focus and Tab navigation restricted to the dialog.

| Shortcut | Action |
| --- | --- |
| Ctrl+N | New conversation |
| Ctrl+K | Search conversations |
| Ctrl+B | Toggle sidebar or open compact conversation navigation |
| Ctrl+O | Attach a file |
| Ctrl+, | Choose a model |
| Ctrl+L | Focus the composer |
| Ctrl+Q | Quit and save |
| Escape | Close the current panel or return to the composer |

The Permissions page lists the eleven implemented desktop grant categories;
unsupported phone capabilities are omitted. Compact rows place Ask/Allow/Deny
next to their descriptions. The worker scheduler sleeps when no workers are
active, and empty UI updates do not invalidate or rebuild the retained renderer.
Build outputs are replaced atomically, allowing a running window to finish with
its current executable. Close and reopen Collie to load a rebuilt desktop UI.

The native Flexscript UI owns presentation; a separate compiled Flexscript
service owns OS lifecycle, TLS, file choosers and platform adapters. HTTPS uses
the native [Flexscript HTTP library](../../../libs/http/README.md) with verified
OpenSSL TLS, incremental streaming, bounded responses, deadlines and cancellation.
There is no curl executable or libcurl dependency. GDK Pixbuf
normalizes image snapshots directly, without Pillow. Shared Flexscript owns
application policy. The
UI and engine have separate memory, so networking and VM work do not block the
native event loop. Engine calls serialize like Android's ENGINE lock because
FlexDB takes an exclusive lease per operation. Model network waits do not hold
that engine lease. Only one desktop process can open a given data folder.

## Image generation

The desktop guest SDK provides `imagen(prompt, path)` using the existing Codex
ChatGPT login. For example:

```flexscript
fn main() {
    let image = imagen("A friendly collie in a watercolor illustration", "assets/collie.png");
    if !image {
        let error = db_error();
        db_io(0, 2, error, db_len(error));
        return 1;
    }
    return 0;
}
```

The original PNG is saved in the selected project folder, or the personal chat's
`files` folder. Parent directories are created as needed. The chat and model
receive a persisted image preview automatically. The function returns a `db_text`
containing the relative path, or `0` with `db_error()` on failure. It requires
**Model tools and workers** (`workers`) and **Write workspace files**
(`files_write`); Ask prompts happen before dispatch. Close any database
transaction first. The native VM suspends while the provider runs and resumes
its existing stack and heap. Stop cancels the request. Credentials and image
bytes stay in the host; base64 is not printed into tool output.

Prompts are limited to 16 KiB, paths to 1024 bytes, and each program to four
images. Output paths must be relative `.png` paths within the project, without
symlink traversal. PNGs are limited to 12 MiB and 40 megapixels. A private
request journal recovers completed results and prevents automatically repeating
requests whose outcome is uncertain after interruption. An uncertain request
returns an error; a new `imagen` call explicitly requests another image.

The initial provider is `codex`, using
`https://chatgpt.com/backend-api/codex/images/generations`, verified against the
installed Codex client and a live request. This is a Codex backend endpoint,
whose contract can change independently of the public OpenAI API. It uses the
Codex server's default image model; it does not use the selected chat model.
Private `settings.json` can set `image_provider` (default `codex`),
`image_size` (default `1024x1024`), `image_quality` (default `auto`),
`image_background` (default `auto`) and optionally `image_model`.

`imagegen.py` isolates provider transport from VM and file handling. Future
adapters register through `ImageGenerators.register(name, provider)` and implement
`generate(prompt, options, task, transport, request_id)`, returning PNG bytes.
Only the Codex adapter receives Codex credentials; another provider must supply
its own authentication. The shared function and checkpoint protocol are portable,
but the image provider host adapter is currently implemented for desktop only.

## Hardware support

App feature parity does not make Android OS services portable. The desktop
permission screen and model instructions identify Linux adapters explicitly.
The currently implemented guest adapters are bounded default-route TCP/UDP and
HTTPS, DNS/interface inventory, power-supply and thermal facts, IIO sensor
metadata, and USB metadata. Opaque socket handles are conversation-owned and are
closed on revocation, session change and shutdown. No device or network state is
invented. See [hardware-api.txt](hardware-api.txt) for actual contracts.

Linux Bluetooth/BLE, NFC/HCE, UWB, Wi-Fi Direct/Aware, cellular, secure element,
Keystore/biometrics, USB transfers/serial, sensor streaming, guest camera/audio/
MIDI, screen capture, accessibility and VPN adapters still require platform
implementations. Calls return explicit unsupported errors. UI camera
attachments are separate from a guest camera API. Per-transport model routing
currently uses the system default network. The shared Android implementations
remain available on the Android branch; no Android hardware feature is presented
as Linux support merely because its permission is allowed.

## Headless checks

```sh
python3 scripts/test-native-callback.py --compiler build/flex-collie-desktop
python3 scripts/test-collie-desktop-launch.py --out build/collie-desktop
python3 scripts/test-collie-desktop-layout.py --out build/collie-desktop
python3 scripts/test-collie-core.py --desktop --out build/collie-desktop
python3 scripts/test-collie-signals.py --desktop --out build/collie-desktop
python3 scripts/test-collie-workers.py --desktop --out build/collie-desktop
python3 scripts/test-collie-lazy-permissions.py --desktop --out build/collie-desktop
python3 scripts/test-collie-recall.py --desktop --out build/collie-desktop
python3 scripts/test-collie-thinking.py --desktop --out build/collie-desktop
python3 scripts/test-collie-native.py --out build/collie-desktop
python3 scripts/test-collie-native-platform.py --out build/collie-desktop
python3 scripts/test-collie-no-python.py --out build/collie-desktop
```

The desktop suite uses fixture model responses and real native VM/database/
checkpoint processes. It unsets DISPLAY/WAYLAND_DISPLAY, uses SDL's dummy video
driver, disables camera/dialog access, and captures actual rendered chat and
permissions PNGs under `build/collie-desktop/`. It needs private local socket IPC
and local fixture servers. Python is used only by the test harnesses; the app
processes are compiled Flexscript. The previous Python host lives exclusively
in `tests/collie/reference_host/` as a behavior reference. The native binary accepts `--hidden --frames N --width W
--height H --capture FILE.rgba --dump-state FILE.json` for bounded headless
checks. `--events FILE.json` supplies timed shared UI requests for deterministic
end-to-end tests. Ordinary startup does not print the conversation to stdout.

These checks do not constitute a live model request or physical-camera/device
verification.

The GUI build uses the portable UI compiler's `desktop-source:cu_desktop` profile: desktop
view branches are selected at build time, only reachable/public view templates
get update functions, and immutable static properties are emitted as compact
name/value tables. Views referenced by ordinary Flexscript functions remain
update roots. Generic/Android UI generation keeps its existing behavior.
The presentation binary opts into `--native-literals shared`; GUI literals are
immutable metadata, while engine/guest and ordinary compiler builds retain
writable literal storage.

`FLEX_COMPILER=build/flex python3 scripts/test-ui-desktop-profile.py` compares
portable and specialized patch traces, property order/types, escaping and
native/interpreter/JIT output.
