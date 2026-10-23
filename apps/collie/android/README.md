# Collie on Android

A native Android chat app embedding Collie's existing Flexscript compiler,
checked interpreter, native Responses tool protocol and FlexDB. Flexscript owns
every screen and UI interaction. Java supplies the generic widget renderer,
Android lifecycle, document/photo/camera APIs and HTTPS/SSE transport. A
freestanding C host translates the trusted runtime's Linux ABI, bounds native
allocations and captures observations. The APK needs no terminal, shell,
external compiler executable, Python runtime, Gradle dependency or NDK sysroot.

## Build and install

Requirements: a current native Flexscript compiler, Clang/LLD, JDK 17, Android
SDK platform 36 and Build Tools 36.1.0. The compiler must include ARM64 indirect
integer calls from this change; rebuild it from `compiler/main.flex` first.

From the repository root:

```sh
build/stage2 compiler/main.flex -o build/flex-collie-android
python3 scripts/build-collie-android.py --compiler build/flex-collie-android \
  --java-home /path/to/jdk-17 --sdk /opt/android-sdk --out build/android-collie
adb -s DEVICE_SERIAL install --no-incremental -r build/android-collie/collie.apk
adb -s DEVICE_SERIAL shell am start -n org.flexscript.collie/.MainActivity
```

The application is named **Collie**, package `org.flexscript.collie`, ABI
`arm64-v8a`, minimum Android 8/API 26, target API 36. This initial build uses a
local development signing key; it is not a store release. Native ELF segments
and the uncompressed APK library are aligned for 16-KiB pages. FlexDB read-only
snapshot mappings use anonymous copies so database offsets need not match the
Android kernel page size. Physical 16-KiB-page devices still need validation.

Open **Menu → Connect ChatGPT** (or **Update ChatGPT login**) and choose the login file created by
Codex. Collie uses `tokens.access_token` and `tokens.account_id`, not an API key.
It sends HTTPS directly to the same Codex Responses backend as desktop Collie.
Expired credentials require refreshing the file with Codex and importing it
again; OAuth login/token refresh is not yet implemented in this app.

The default model is `gpt-6.1-sol`; Menu can change it. Prose streams as it
arrives. Generated programs appear in expandable Flexscript cards, followed by
real stdout, stderr, state and exit code. Program source includes shared code
highlighting, line numbers and a clipboard action. Source and VM result bodies
are independently collapsed by default. **Show result** reveals the full captured
stdout/stderr, including long single-line JSON. **Stop** cancels the current HTTP
request or cooperatively stops compilation/VM execution. **New** creates a
workspace; **Conversations** reopens one. Context shows tokens, with
`~` for an estimate. **Menu → Compact context** and automatic compaction use the
shared Codex checkpoint protocol and desktop limits (272,000 raw; 258,400 usable;
244,800 automatic compaction threshold for the default model).

Open **Menu → Permissions** to control the agent's access for the current
conversation. Seven independent switches grant internet access, workspace file
reads, workspace file writes, database reads, database writes, and archived
message access, and workers/model feedback. Settings save immediately and survive restart/resume. New and
older conversations default to the existing enabled capabilities; changing one
conversation does not affect another. The model receives the current grants in
each request, and the native VM broker enforces them on every capability call.
Denied operations return 0 with `db_error()` set to `Permission denied: NAME`.
Computation/stdout/progress still work when all seven are off. The internet switch controls
guest HTTPS requests; it does not disable Collie's model connection. Revoking
access does not remove data already present in model context or chat history.

## Storage and execution

Every session has private Android storage:

```
files/credentials/auth.json              credentials; unavailable to programs
files/workspaces/SESSION/session.json    conversation and visible archive
files/workspaces/SESSION/agent.flexdb    real persistent FlexDB
files/workspaces/SESSION/files/          agent's private filesystem root /
```

Application tables start empty. The runtime reserves read-only `collie_` tables
for workers, messages, and private named state. Programs use the existing `db_*` API.
Committed transactions persist; uncommitted transactions roll back after each
execution. The visible archive is queryable with `db_history` and
`db_history_read`, including source and actual observations. Encrypted model
reasoning stays in the provider history and is not exposed through that archive.

### Remembering across conversations

Collie can search saved conversations from Flexscript when you ask about earlier
discussions or preferences. The model instructions tell it to search before
guessing, try relevant keywords, and read the original context. Recall uses the
durable visible archive, so it also works after restart or model-context
compaction. It is keyword retrieval; the model interprets the retrieved facts.

- `memory_search(query, session_after, message_after, limit)` returns
  `[matches, next_session, next_message]`. Start with `""`, `0` and a limit of
  1–20. Each match is `[session_id, message_id, role, field, excerpt]`; excerpts
  are at most 512 UTF-8 bytes and include the matching text. Queries are 1–256
  bytes, ASCII case-insensitive substrings; other UTF-8 bytes match exactly.
- Continue with the returned cursors until `next_session` is empty. An empty
  match list can still have a continuation. Each call scans at most eight
  sessions or 1024 messages and stops after reading at least 8 MiB of archives.
  Results follow session/message ID order, rather than relevance or date.
- `memory_history(session_id, after_id, limit)` reads surrounding messages in
  the same row format and limits as `db_history`.
- `memory_read(session_id, message_id, field, offset, limit)` reads a full field
  in chunks, like `db_history_read`. Fields are `role`, `content`, `source`, and
  `observation`; reads return blob values.

For example, `memory_search("keyboard", "", 0, 10)` can locate an earlier
preference. Inspect the matches, then use `memory_read` or `memory_history` to
check what was actually said before answering.

The existing **Read past messages** permission controls recall. Disabling it in
the current conversation blocks searching and reading; disabling it in another
conversation excludes that conversation as a source. Older conversations without
a saved policy retain the existing default grants. Only `session.json` archives
under Collie's workspaces are accessible. Files, other databases, credentials,
hidden reasoning and worker-private histories are not exposed by these APIs.
Recall is read-only, and does not grant general access to other workspaces.
Saved archives larger than the app's 8 MiB session limit cannot be loaded.

Search/paging/policy code lives in `core/recall.flex`; the native storage adapter
only enumerates sibling session IDs and reads their archives without following
symlinks. No Android Java agent policy is added. Verification:

```sh
python3 scripts/test-collie-recall.py --out build/android-agent-signals
python3 scripts/test-collie-recall-android.py --out build/android-agent-signals \
  --serial emulator-5580
```

The preloaded Android filesystem API is:

- `fs_list(path)` → list of name text values, at most 128 entries.
- `fs_mkdir(path)` → 1 on success, 0 on failure.
- `fs_read(path, offset, limit)` → blob; limit 1–32,768 bytes.
- `fs_write(path, db_text(text))` or `fs_write(path, db_blob(p,n))` → atomically
  replace a file of at most 32 KiB. Changes persist independently of transactions.

Use `db_error()` for failures. Paths are relative to the session's `files/`
root, whether or not they begin with `/`. Parent traversal, symlinks, devices and
other app/host files are denied. Credentials and raw database/session files
are outside that capability. This version has no shared-storage folder picker,
USB capability or Android UI API for programs.

Programs have bounded internet access using the preloaded `http_get(url)`:

```flexscript
fn main(){
    let response=http_get("https://example.com/");
    if !response {let error=db_error();db_io(0,2,error,db_len(error));return 1;}
    let body=http_body(response);
    db_io(0,1,db_word(body),db_bytes(body));
    return 0;
}
```

The response is a typed list `[status, body text, final URL text, truncated]`;
`http_status`, `http_body`, `http_url` and `http_truncated` read those fields.
Transport failures return 0 with `db_error()`; HTTP error statuses retain their
body. Only HTTPS GET is supported, with normal Android certificate validation,
three redirects, eight seconds per request and four requests per program.
Bodies are decoded as UTF-8 and bounded to 32 KiB, with NUL/invalid bytes replaced.
Check truncation before treating a document as complete. Network waiting is
separate from the VM CPU deadline. Stop also cancels guest network requests.
The transport never attaches Collie's model credentials or login cookies.
Web content is data, not instructions. No additional model tools are exposed.

### Viewing files and images

The only model tool remains `flexscript`. Its preloaded viewing functions use
the same **Read workspace files** permission and path confinement as `fs_read`:

```flexscript
fn main(){
    if !view_file("/notes.txt") {db_io(0,2,db_error(),db_len(db_error()));return 1;}
    if !view_image("/images/photo.png") {db_io(0,2,db_error(),db_len(db_error()));return 1;}
    return 0;
}
```

`view_file(path)` queues the first 16 KiB of a text file in the actual VM result.
`view_file_range(path, byte_offset, limit)` reads another slice, with a limit of
1–16,384 bytes. The observation's `views` field includes text, byte offset,
byte count and a truncation flag. These are UTF-8 text previews; binary files
require `fs_read` or a supported image decoder. Successful calls return 1;
failures return 0 with `db_error()`. At most four views are queued per program.

`view_image(path)` reads a regular PNG, JPEG or WebP file, up to 2 MiB and
24 megapixels. Android decodes the pixels, applies EXIF orientation, composites
transparency on white, and normalizes a JPEG snapshot to at most 1536 pixels per
edge and 512 KiB. Animated WebP is viewed as a single decoded frame. The harness attaches the actual pixels as an
[`input_image`](https://developers.openai.com/api/docs/guides/images-vision)
part of the tool result sent to the model. It does not ask the model to interpret
base64 text. Snapshots strip source metadata and live outside the guest root in
`files/workspaces/SESSION/previews/`, keyed by their SHA-256. The canonical
conversation stores only snapshot IDs, not base64. Old results keep their exact
snapshot when the source file changes. There are at most 128 distinct snapshots
per conversation. Requests include at most 4 MiB of normalized images, preferring
newest snapshots and including repeated images only once; omitted images are
explicitly identified to the model. Approximate context accounting adds a
conservative 4096 tokens per newly viewed image until real usage is available.

Expand **Show result** to see text/image preview cards. **Open file** displays
selectable text with its byte range. **Open image** opens a full-screen image
with pinch zoom and dragging. Files and images are treated as data, not HTML or
instructions; no external viewer or remote URL is launched.

Use the **+ button beside the message box** and choose **Gallery**, **Camera**
or **Files**. Gallery opens Android's photo picker (or the image document picker
on older Android); Camera opens the phone's camera to take a photo directly.
These use [Android photo selection](https://developer.android.com/training/data-storage/shared/photo-picker)
and [camera intents](https://developer.android.com/media/camera/camera-intents);
Collie requests no broad photo-library or camera permission. Only the chosen
image is imported. Photos up to 32 MiB / 100 megapixels are sampled, oriented,
and converted to a metadata-free JPEG of at most 1536 pixels per edge and
512 KiB before entering the workspace. Camera output uses a temporary private
content URI, is never added to the shared gallery by Collie, and is deleted
after import or cancellation. Files opens Android's document picker. Collie
copies only that selected file into the current private workspace (up to 2 MiB), chooses an unused filename, and shows a draft
attachment with an image thumbnail when supported. Attach up to four files,
remove unwanted attachments with **×**, then press **Send** with or without text.
Draft attachments survive app restarts and stay with their conversation. Removing
one deletes only its imported workspace copy. The agent receives the attached
paths when you send; selecting a file alone sends no message. Sent messages keep
their attachment cards. Contents reach the model when a program reads/views them.
The picker does not grant the VM access to the containing phone folder. Other
apps, credentials and shared storage remain outside the VM's filesystem grant.

Each source is compiled **on the phone** into checked VM bytecode. Guest memory
is bounded to 4 MiB, execution to four million instructions/one second excluding
network waits, source to
64 KiB, stdout/stderr retained to 32 KiB each. Host memory and database traffic
are also bounded. Compiler errors return diagnostic observations rather than
terminating the app. Only validated completed native `flexscript` tool calls
execute; mismatched streamed code, unknown tools and multiple calls are rejected.
Guest raw FFI, processes and ungranted syscalls remain denied.

This first app uses the **interpreter** for guest execution. Its compiler,
provider and database are native ARM64 code. The existing Android arithmetic
leaf JIT is a separate demo and has not been connected to this app's dispatcher.
The VM is the language/capability boundary; it is in the app process, not an
additional Android isolated process. Native compiler/runtime bugs therefore
remain in the app's trust boundary. App-private storage has no total disk quota
beyond available device storage in this first version.

## Headless verification

Start an existing ARM64-capable emulator without a window, then build with
`--debug` to enable private `run-as` test fixtures. Normal builds disable those
intent hooks.

```sh
/opt/android-sdk/emulator/emulator -avd Pixel_9_API_36 -read-only \
  -no-window -no-snapshot -no-boot-anim -no-audio -gpu swiftshader -port 5580
python3 scripts/build-collie-android.py --compiler build/flex-collie-android \
  --java-home /path/to/jdk-17 --out build/android-collie --debug
python3 scripts/test-collie-android.py --out build/android-collie \
  --serial emulator-5580
# Optional real Codex request; streams credentials directly to private storage:
python3 scripts/test-collie-android.py --out build/android-collie \
  --serial emulator-5580 --auth "$HOME/.codex/auth.json"
# Installed debug app, existing conversation, actual public HTTPS endpoints:
python3 scripts/test-collie-android-internet.py --out build/android-collie \
  --serial DEVICE_SERIAL --live
# Exercise real UI switches, native denials, persistence and read-only access:
python3 scripts/test-collie-android-permissions.py --out build/android-collie \
  --serial DEVICE_SERIAL
# File/image previews, permission denials, document picker and live model vision:
python3 scripts/test-collie-android-views.py --out build/android-collie \
  --serial DEVICE_SERIAL --picker --media --live
```

The viewing checks preserve the existing conversation and grants, and remove
their temporary workspace and download fixtures. Omit `--live` for checks that
do not need a signed-in model connection; `--picker` exercises Android's real
document picker. `--media` also exercises Gallery and Camera: on an emulator
it selects the synthetic fixture and captures an emulated photo; on a phone it
opens and cancels both screens without selecting personal photos or taking one.

The test suite also runs the exact native engine under `qemu-aarch64[-static]`,
using an independent freestanding driver. It covers genuine compilation,
functions/loops, diagnostics/recovery, memory/fuel/capability errors, real DB
persistence/rollback, confined files, native tool validation, limits and
compaction. Device tests verify process restart persistence, the complete native
tool loop, UI hierarchy and a screenshot. A live run must show model-generated
program output from the Android VM. Artifacts are `test-report.json`,
`android-ui.xml` and `android.png` in the build output directory.

An x86-64 Android emulator with `libndk_translation` can run the ARM64 APK. Such
a result verifies Android integration, not physical ARM64 phone performance or
the existing JIT's instruction-cache behavior. Test a physical ARM64 phone
before claiming either.

Verified on 2026-10-21: 94 ARM64 compiler/ABI checks and 26 shared-engine/Android
app checks passed. The headless API 36 x86-64 emulator loaded the `arm64-v8a`
library through its native bridge. A real ChatGPT `gpt-6.1-sol` request generated
a Flexscript program on the device, whose VM printed `1205608544140` for
`5125124 * 235235`, then supplied that observation for the assistant's answer.
Database/private-file persistence across app restarts, compiler-error recovery,
cancellation, native tool correlation and expanded-source UI were exercised.
The test report records the exact APK and native-engine checksums.

The same APK was subsequently deployed to a physical Samsung Galaxy A55
(SM-A556B, Android 16/API 36, ARM64, 4-KiB pages). On-phone compilation, FlexDB
commit/reopen, private-file persistence across app restarts and a live ChatGPT
model → native tool → phone VM → assistant reply all passed. The VM printed
`1205608544140`; the app was relaunched with the verified conversation and login
ready to use. Deployment evidence is in `build/android-collie/phone/` for that
local build. This validates physical-device integration, not JIT performance.

The earlier native UI introduced a custom dark theme and Collie launcher mark,
aligned chat bubbles, formatted assistant replies, syntax-colored expandable
programs with copy controls, compact VM result/error cards, a
keyboard-aware composer, a workspace sheet, and a full Conversations page with readable titles.
The context meter stays separate from execution status. Scrolling to the latest
message preserves composer focus; reading earlier messages pauses automatic
scrolling. The current presentation is entirely declared in `apps/collie/ui/`;
`UiRenderer.java` maps the resulting records to Android widgets.

Eight UI checks passed on the Galaxy A55: formatted replies and VM results,
source expansion/collapse, keyboard input, workspace/conversation menus, the
welcome screen, live streaming/tool execution, and restoring the original chat.
Screenshots and the exact APK checksum are in `build/android-collie/ui/`.

Conversations is now a dedicated full-screen page, opened from the chat header
or workspace menu. It lists all saved chats newest first, with message previews,
dates, a Current marker, search, and a New conversation button. The shared view pages rows in batches of 50; metadata is loaded off the UI thread. Both the page’s
Back button and Android system Back return to the active chat. Opening a row
resumes that conversation. Search also handles empty results.

Seven navigation checks passed on the Galaxy A55, including search/clear, both
Back controls, opening a saved search result, creating a new chat, and preserving
the original conversation. Evidence is in `build/android-collie/conversations/`.

## Coordinator, workers and resumable VM programs

Each workspace has a main conversation. It can delegate independent work to
workers through the same single `flexscript` model tool. No additional model
tools or markup protocol are involved:

```flexscript
fn main() {
    let team = db_list();
    db_add(team, db_int(worker_start("Reader", "Inspect the shared project files")));
    db_add(team, db_int(worker_start("Checker", "Check the calculations")));
    if !state_set("team", team) { return 1; }
    let reader = worker_await(db_word(db_at(team, 0)));
    let status = worker_status(reader);
    let answer = worker_result(reader);
    db_io(0, 1, status, db_len(status));
    db_io(0, 1, db_word(answer), db_bytes(answer));
    return 0;
}
```

Check all returned IDs/handles and `db_error()` in production programs, and check
terminal status before treating a worker's result as successful.

- `worker_start(title,task)` returns a durable integer ID, or zero on failure.
- `worker_list()` returns summary rows `[id,values]`. Columns: title, task,
  status, result, error, revision, request_key, updated (monotonic milliseconds).
  Summary text is truncated to 128 bytes, except titles (160). Use
  `worker_get(id)` for complete fields. `worker_status(row)` returns a C string;
  `worker_result(row)` returns a typed text value.
- `worker_messages(id,after_message_id,limit)` returns up to 64 message rows.
  Columns: worker ID, role, content, kind, deduplication key, revision.
  Kinds include `message`, `source`, and `result`. Large public messages are
  split into ordered rows; use the last returned row ID for the next page.
- `worker_send(id,text)` queues a follow-up, including during a running turn.
  `worker_cancel(id)` cancels it. Late completion cannot overwrite cancellation.
- `worker_await(id)` returns a terminal worker row. While pending, the main VM
  suspends at an explicit instruction boundary. The host releases its engine
  lock while waiting, allowing worker model requests and VM programs to run.
- `state_set(name,value)` saves a typed value, including nested lists and IDs;
  `state_get(name)` returns it, or a typed null when missing. Values are private
  to each agent, limited to 32 KiB encoded, with 512 named values per workspace.
  Raw pointers and ordinary globals do not carry over to a *different* program.

Workers have independent model histories and context compaction. They share the
workspace files and FlexDB and inherit its current permission grants. Only the
main coordinator can start, send to, cancel, or await running workers. There are
at most three simultaneous worker model requests, eight active workers, and 64
worker identities per workspace. Native compiler/VM/DB calls are serialized;
model requests can overlap. Each worker turn allows up to 16 programs.

The runtime owns `collie_workers`, `collie_messages`, and `collie_state`. The first
two are queryable through ordinary `db_scan`/`db_get`; runtime tables cannot be
modified or have their schemas changed by generated code. `collie_state` is
accessible only through the owner-aware state functions. Other application
schemas are still chosen by the agent. Worker APIs require **Manage workers**;
message reads also require **Read past messages**. Named state uses the existing
DB read/write grants. Older partial policies leave new grants off until enabled.

Tap **Workers** below the chat status to see active, paused and finished workers,
then tap one to inspect its messages, generated programs and VM results. Source
and results start collapsed. The worker page remains available while the main
conversation is busy. Running workers can be stopped; interrupted workers offer
**Resume worker**.

A VM continuation stores the checked bytecode, guest heap, locals, operand stack,
call frames, program counter, fuel and output budgets. Guest offsets survive
relocation. A versioned checksum and invocation/code checks reject corrupt,
wrong-invocation or outdated-code snapshots. JIT code and host resources are not
serialized. DB transactions must finish before awaiting. Checkpoints are private,
atomically replaced, and capped at 16 MiB. Fuel, remaining execution time, and DB/network/output budgets are retained; external waiting does
not consume the execution deadline.

After process/activity interruption, in-flight workers become paused. The main
conversation offers **Resume saved program** when it has a pending execution.
A saved continuation resumes the same program and accumulates stdout/stderr
across yields. An interrupted program without a safe checkpoint is reported,
rather than replaying potentially completed side effects. Ordinary worker context
and public journal writes are separate durable records; a crash between them can
omit the last public display entry, but does not authorize replay of an uncertain
program. This is not an Android foreground service: the OS can stop the process,
and jobs resume when the app is reopened. Automatic long-term memory-tree
summarization is separate from these execution checkpoints.

Verification:

```sh
python3 scripts/test-collie-workers.py --out build/android-collie-workers
python3 scripts/test-collie-workers-android.py \
  --out build/android-collie-workers --serial emulator-5580
```

The first suite resumes snapshots in separate QEMU ARM64 processes. The second
uses the actual Android scheduler and private prerecorded model fixtures to test
concurrent delegation, shared files/messages, live worker inspection, process
restart and continuation recovery. It does not require model credentials.

The optional live-model check uses ChatGPT `auth.json` in a debug emulator:

```sh
python3 scripts/test-collie-workers-live.py --out build/android-collie-workers \
  --serial emulator-5580 --auth "$HOME/.codex/auth.json"
```

## Shared application core

The Android adapter no longer implements worker scheduling or separate main and
worker conversation loops. These policies run in ordinary shared Flexscript:

| Shared module | Responsibility |
| --- | --- |
| `apps/collie/core/session.flex` | Main/worker state transitions, history and tool-result correlation, compaction, output/view accumulation, persistence and safe restart policy |
| `apps/collie/core/scheduler.flex` | Job selection, concurrency cap, cancellation, permission revocation and recovery |
| `apps/collie/core/permissions.flex` | Grant schema, conservative policy loading and permission UI metadata |
| `apps/collie/core/checkpoint.flex` | VM checkpoint format, validation, budgets and continuation |
| `apps/collie/providers/stream.flex` | Streamed provider events and source/prose validation |
| `apps/collie/providers/images.flex` | Image selection, deduplication, request budget, base64 wire format and token estimation |
| `apps/collie/providers/codex.flex` | Authentication validation, endpoint/headers, model requests and provider errors |

`PlatformTask.java` executes effects emitted by the core: HTTPS model exchange,
native VM invocation, timer wait and UI notification. `WorkerManager.java` binds
scheduler decisions to Android executors and activity shutdown. Neither chooses
which worker to run nor mutates its conversation history. Java still owns native
widgets, image decoding, storage/document/camera APIs, TLS, thread cancellation,
and lifecycle. The small Flexscript Android adapter supplies storage, image-byte,
capability-budget and native-execution hooks; credentials never enter the guest
VM or model context.

The core uses explicit JSON state/effects, so it can run on a different platform
without an Android activity or a Java implementation of the agent loop. The
standalone Linux test host imports the exact same source modules directly:

```sh
build/flex-collie-workers apps/collie/tests/shared-core.flex -o build/test-collie-shared-core
python3 scripts/test-collie-core.py --out build/android-collie-core \
  --core-driver build/test-collie-shared-core
```

The Android native entry points also exercise these transitions under QEMU. This
core preserves existing workspace DBs, worker IDs, history JSON and named state.
Checkpoints require the same SDK and checkpoint version that created them.
Native engine globals remain temporary per call. Durable machine state
lives in conversation/worker JSON and FlexDB, and suspended guest execution lives
in its private VM checkpoint.


### Shared declarative UI

Every Collie screen is now compiled Flexscript, under `apps/collie/ui/`:

| Module | Responsibility |
| --- | --- |
| `app.flex` | Root view, navigation, event validation, UI state and platform effects |
| `chat.flex` | Welcome, suggestions, header/status/context, streaming, history and composer |
| `components.flex` | Messages, source/result folding, error/output views, attachment tiles and previews |
| `pages.flex` | Conversations/search/paging, workers/details/actions, model form, workspace and attachment menus, full-screen previews |
| `permissions.flex` | Permission rows, summaries and grant actions |
| `model.flex` | Filtering, display text, stable identity, history paging and derived state |
| `libs/ui/richtext.flex` | Platform-independent Markdown and code-highlighting runs |

Monolith and these screens share the AST compiler, keyed tree and generated
update primitives. Android has no screen-specific view builders: the former
`ConversationsPage`, `WorkersPage`, `PermissionsPage`, `AttachmentViews` and
`MessageStyle` Java classes are removed. `CollieUi.java` only batches facts/events,
retains the explicit UI model and applies returned operations. Android's window
insets, IME, native spans, bitmap decoding/zoom, clipboard, lifecycle and
file/gallery/camera APIs remain native services.

`libcollie_ui.so` is a small, independently compiled UI image with its own globals,
128-MiB bounded arena and JNI lock. It cannot read files, use the network or start
processes. It evaluates the shared UI reducer while the separate `libcollie.so`
agent/compiler/VM image is busy. UI memory is released after every call; models
and operations are serialized JSON rather than live pointers. `ui-host.c` contains
only the allocator, failure boundary and JNI plumbing. The native test executable
`ui-native-test` exercises the exact same UI code; the agent's `native-test`
remains independent.

Navigation, drafts, selected workers and folds live in the shared UI model.
Android saves its small navigation snapshot in the lifecycle bundle; the shared
reducer requests fresh conversation/worker data after restoration. Source and VM results default
to collapsed. Chat history is paged in batches of 40, conversation rows in batches
of 50, so old content remains accessible without exceeding the keyed-tree limit.
Permission/model changes emit persistence effects for the platform to acknowledge;
failed permission saves restore the actual stored policy through shared state.

This is trusted application UI. Model-generated guest programs have not gained
UI privileges. The portable DOM adapter renders the same records; a browser test
applies complete application traces, and the permissions example runs the actual
shared permissions view through Monolith's HTTP/SSE host.

```sh
python3 scripts/test-collie-ui.py --compiler build/flex-collie-workers \
  --out build/android-collie
python3 scripts/test-ui.py --compiler build/flex-collie-workers \
  --out build/android-collie --serial emulator-5580
python3 scripts/test-collie-ui-android.py --out build/android-collie \
  --serial emulator-5580
python3 scripts/test-collie-workers-android.py --out build/android-collie \
  --serial emulator-5580
python3 scripts/test-collie-android-views.py --out build/android-collie \
  --serial emulator-5580 --picker --media
```

The widget fixture (debug APKs only) verifies native identity, input focus,
selection, drafts, action bindings, snapshots and an independent UI call while
the agent engine lock is held. Full application state/effect tests compare Linux
and the production ARM64 UI image. See [`docs/ui.md`](../../../docs/ui.md) for the
DSL, wire ABI, platform differences and browser checks. Emulator evidence is not
physical-phone deployment evidence.

## Thinking summaries and tool activity

Model requests enable `reasoning.summary: "auto"`. The shared provider processes
`response.reasoning_summary_text.delta` and completed summary/part events, and
keeps public summary text separate from assistant prose and encrypted reasoning.
These are the [Responses API summary events](https://developers.openai.com/api/reference/resources/responses/streaming-events).
Completed summaries are saved with the conversation and in worker journals.
Encrypted continuation data stays in provider history and never enters UI state.

The portable Flexscript view groups summaries, Flexscript calls/results, progress,
and model-feedback records into one **Thinking** panel per user turn. Panels
start collapsed and show the latest API summary as their preview. Expanding the
panel shows the history, with existing controls for viewing code and results.
Assistant messages stream and remain outside the panel. The same grouping is
used in worker conversations. Older conversations with tool activity but no API
summary get a generic activity preview.

Android Java continues to own HTTPS and frame delivery. Summary parsing, display
field selection, persistent cards, grouping and expansion are shared Flexscript.
The debug fixture can feed actual API-shaped events through the same processing
path with a delay between events; it does not fabricate summary text in the UI.
The native and headless Android checks use synthetic provider replies:

```sh
python3 scripts/test-collie-thinking.py --out build/android-agent-signals
python3 scripts/test-collie-ui.py --compiler build/flex-collie-signals \
  --out build/android-agent-signals
python3 scripts/test-collie-thinking-android.py --out build/android-agent-signals \
  --serial emulator-5580
```

## Progress and model feedback inside a program

The preloaded `progress(text)` function publishes a visible conversation card
before the program finishes, then continues the same program. It returns 1 on
success or 0 with `db_error()`. `agent_ask(prompt)` suspends the VM for a separate
model request and returns its plain-text answer as a `db_text` value, or 0 with
an error. Both are ordinary functions inside the existing `flexscript` tool:

```flex
fn main(){
    progress("Loaded the data; deciding what to do next");
    let answer=agent_ask("The measured values were 12, 19 and 23. Which should I inspect first?");
    if !answer {db_io(0,2,db_error(),db_len(db_error()));return 1;}
    fs_write("decision.txt",answer);
    progress("Saved the decision");
    return 0;
}
```

Each signal is an explicit safe point. The native VM saves its heap, local
variables, frames, instruction position, fuel, remaining CPU deadline and
capability budgets before returning control to the harness. Resumption restores
that state; completed code is not replayed. The original model tool call remains
pending until the program finishes, when one correlated result collects stdout,
stderr, file/image views and the progress/feedback records.

Feedback branches from completed conversation items and supplied program/output
facts. It never submits the pending parent tool call without a result. The branch
has no tools and cannot execute nested generated code; its answer is data for the
caller. Failed/oversized/tool-bearing feedback returns an error to the paused
program. Cancellation completes the original call with an explicit observation.
Worker permission is required for feedback and is checked again after suspension.
Progress, like stdout, remains available without worker permission.

Commit or roll back DB transactions before either function. There are at most 32
combined signals per program, including across restarts: progress is 1–4096 bytes,
questions 1–16384 bytes, and answers at most 32768 bytes. Suspension does not reset
the ordinary VM limits. Upgrading the embedded SDK invalidates older checkpoints;
Collie reports that mismatch instead of replaying their code.

Verification uses synthetic model replies and fresh native processes, plus a
headless Android emulator for visible progress, restart, worker and Stop checks:

```sh
python3 scripts/test-collie-signals.py --out build/android-agent-signals
python3 scripts/test-collie-signals-android.py --out build/android-agent-signals \
  --serial emulator-5580
```
