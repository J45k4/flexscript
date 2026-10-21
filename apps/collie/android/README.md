# Collie on Android

A native Android chat app embedding Collie's existing Flexscript compiler,
checked interpreter, native Responses tool protocol and FlexDB. Java owns the
Android lifecycle, chat widgets, document picker and HTTPS/SSE transport. A
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

Open **Menu → Import auth.json** and choose the ChatGPT login file created by
Codex. Collie uses `tokens.access_token` and `tokens.account_id`, not an API key.
It sends HTTPS directly to the same Codex Responses backend as desktop Collie.
Expired credentials require refreshing the file with Codex and importing it
again; OAuth login/token refresh is not yet implemented in this app.

The default model is `gpt-6.1-sol`; Menu can change it. Prose streams as it
arrives. Generated programs appear in expandable Flexscript cards, followed by
real stdout, stderr, state and exit code. **Stop** cancels the current HTTP
request or cooperatively stops compilation/VM execution. **New** creates a
workspace; **Menu → Resume session** reopens one. Context shows tokens, with
`~` for an estimate. **Menu → Compact context** and automatic compaction use the
shared Codex checkpoint protocol and desktop limits (272,000 raw; 258,400 usable;
244,800 automatic compaction threshold for the default model).

Open **Menu → Permissions** to control the agent's access for the current
conversation. Six independent switches grant internet access, workspace file
reads, workspace file writes, database reads, database writes, and archived
message access. Settings save immediately and survive restart/resume. New and
older conversations default to the existing enabled capabilities; changing one
conversation does not affect another. The model receives the current grants in
each request, and the native VM broker enforces them on every capability call.
Denied operations return 0 with `db_error()` set to `Permission denied: NAME`.
Computation/stdout still work when all six are off. The internet switch controls
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

There is no initial database schema. Programs use the existing `db_*` API.
Committed transactions persist; uncommitted transactions roll back after each
execution. The visible archive is queryable with `db_history` and
`db_history_read`, including source and actual observations. Encrypted model
reasoning stays in the provider history and is not exposed through that archive.

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
    if !response {let error=db_error();syscall(1,2,error,db_len(error),0,0,0);return 1;}
    let body=http_body(response);
    syscall(1,1,db_word(body),db_bytes(body),0,0,0);
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
```

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

The phone interface now has a custom dark theme and Collie launcher mark,
aligned chat bubbles, formatted assistant replies, syntax-colored expandable
programs with line numbers/copy controls, compact VM result/error cards, a
keyboard-aware composer, a workspace sheet, and a full Conversations page with readable titles.
The context meter stays separate from execution status. Scrolling to the latest
message preserves composer focus; reading earlier messages pauses automatic
scrolling. The native presentation lives in `CollieUi.java` and
`MessageStyle.java`; the model/VM protocol remains in the shared engine.

Eight UI checks passed on the Galaxy A55: formatted replies and VM results,
source expansion/collapse, keyboard input, workspace/conversation menus, the
welcome screen, live streaming/tool execution, and restoring the original chat.
Screenshots and the exact APK checksum are in `build/android-collie/ui/`.

Conversations is now a dedicated full-screen page, opened from the chat header
or workspace menu. It lists all saved chats newest first, with message previews,
dates, a Current marker, search, and a New conversation button. Rows are recycled
with Android ListView; metadata is loaded off the UI thread. Both the page’s
Back button and Android system Back return to the active chat. Opening a row
resumes that conversation. Search also handles empty results.

Seven navigation checks passed on the Galaxy A55, including search/clear, both
Back controls, opening a saved search result, creating a new chat, and preserving
the original conversation. Evidence is in `build/android-collie/conversations/`.
