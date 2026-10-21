# Collie

A conversational agent harness written in Flexscript. Ordinary text streams to
the user. The model has one native tool, `flexscript`, which accepts raw source
and executes it in the restricted VM. Collie returns program output and errors
with the matching tool call ID; the model can answer in prose or call it again.

Each session also has a persistent FlexDB workspace. It starts with **no tables**:
the agent chooses its own schemas, queries and workflow by writing Flexscript.
The harness supplies language/runtime APIs and access limits, not an agent-memory
schema. Committed data survives subsequent programs, model-context compaction,
and session resume.

The CLI, authentication, HTTPS/SSE transport, tool handling, agent loop, Linux
execution adapter, and tests are all `.flex` sources. HTTPS uses Flexscript's
existing OpenSSL FFI. Linux isolation uses Bubblewrap and prlimit. Android
now has a [native app](android/README.md) that embeds the same compiler, checked
VM, provider protocol and FlexDB behind Android lifecycle, UI and HTTPS adapters.

## Build and run

From `apps/collie`, launch directly from source:

```sh
flexscript run main.flex
```

`flexscript main.flex` also works. Both forms build `apps/collie/build/collie`
and replace the script VM with the native host, so workers and long-running
interactive sessions work normally. Options after `main.flex` are forwarded to
Collie. The launcher uses the invoking compiler for the native build and guest
execution by default; `--compiler PATH` or `COLLIE_COMPILER` selects another.

Collie lives at `apps/collie` in the Flexscript repository and imports the
Flexscript SDK from `../../scripts/lib` and `../../lib`. It needs a native Linux
Flexscript compiler with VM support, OpenSSL 3 with trusted system certificates,
Bubblewrap, prlimit, and ldd. VM execution needs working user namespaces.

Build from the repository root:

```sh
build/flex-android scripts/build-collie.flex -o build/build-collie
build/build-collie --compiler build/flex-android
./build/collie --model YOUR_CODEX_MODEL 'Hello'
```

The build driver is also included as `build/tools/build-collie` by
`scripts/build-tools.flex`. Select the compiler you are developing with
`--compiler`; the root `build/collie` output is shared across the application
and runtime work.

Commands below use the repository root unless noted. An application-local build
is also supported:

```sh
cd apps/collie
mkdir -p build
../../build/flex-android main.flex -o build/collie
./build/collie --model YOUR_CODEX_MODEL 'Hello'
cd ../..
```

User-facing text always streams on stdout. A prose-only reply finishes the turn
without a VM run. Add `--stream` to also watch tool input arrive on stderr:

```sh
./build/collie --model YOUR_CODEX_MODEL 'Calculate the first 20 Fibonacci numbers' --stream
```

## Interactive terminal

Run Collie without arguments to open the full-screen chat UI using your existing
Codex ChatGPT `auth.json` and the default model, `gpt-6.1-sol`. No network request
is made until you send a task. Use `--model` to override the default; model
availability is checked by the backend when a request is sent. When choosing the
default model, missing or invalid login tokens are rejected before the terminal
enters raw mode.

The UI uses the same `libs/tui` widgets as `llm.flex`. Omit the task to open it,
or use `--tui` to start with an initial task:

```sh
./build/collie
./build/collie --model YOUR_CODEX_MODEL
./build/collie --model YOUR_CODEX_MODEL --tui 'Calculate 6*7' --stream
./build/collie --model YOUR_CODEX_MODEL --resume latest
```

The UI supports streamed prose, a multiline Unicode editor, prompt history,
selection, clipboard copy/paste, mouse scrolling, resizing, and cancelling a
running turn with Escape. Enter sends; Ctrl+J or Alt+Enter adds a newline.
Bracketed paste preserves newlines without sending. Ctrl+C copies a selection
or exits; Ctrl+D exits. Terminal modes are restored on exit and termination signals.

Generated code appears under a collapsible Flexscript heading. Click it or use
Ctrl+T to toggle the latest block, including the actual VM stdout. `--stream`
expands code while it arrives; `/code` (or `/code on`) shows all generated
programs and their VM stdout, including future programs. `/code off` collapses them.
Compiler and VM errors remain visible in yellow even with code collapsed.
The editor stays usable during model requests and VM execution.

The default model, `gpt-6.1-sol`, uses Codex's bundled 272,000-token context
window, with 258,400 usable tokens (95%) and automatic compaction at 244,800
tokens (90%). A larger window in another client's model cache does not change
this default. Other models use their cached metadata when available. The count uses the latest
reported token total, including reasoning, without accumulating past requests.
Pending messages and compacted contexts use Codex's text/encrypted-content
estimates and are marked `~` and `(est)`. `?` means no count yet. Missing or invalid
model metadata uses Codex's 272,000-token fallback. The footer tracks the current
conversation's byte size, message count, and number of successful compactions.
Usage and encrypted checkpoints survive resume and reset with `/new` or a model
change. `/history` shows the usable and auto-compaction thresholds.

Automatic compaction follows Codex's foreground V2 flow. Before a model request,
Collie compares active context usage with the model's `auto_compact_token_limit`,
defaulting to 90% of the context window and capped at that threshold. Reaching
the usable context window also triggers compaction, as in Codex. Use `/compact`
to compact immediately, or `--context-window N` and `--auto-compact N` to override
the defaults within the model's advertised maximum and 90% cap. For example,
`--context-window 500000` explicitly selects 475,000 usable tokens and a
450,000-token compaction trigger for the default model.

In the TUI, `/context` shows the current limits. Use `/context 500000` to
change the window, `/compact 300000` to change the compaction threshold,
or `/context default` to restore both model defaults. `/compact default`
resets just the threshold. Changes preserve the conversation, apply to the next
request, and are saved with the session. The panel shows the effective limits
after applying the model's caps. `/compact` still compacts immediately.

Compaction sends a `compaction_trigger` to the same Codex Responses backend and
requires a completed response containing exactly one encrypted compaction item.
It keeps up to 64,000 estimated tokens of the newest user requests, followed by
that checkpoint; prior assistant replies and VM observations remain in the
visible transcript and are represented by the checkpoint in model context.
The next request carries the opaque item back to the model. Compaction never
executes code or emits its output as user prose. Cancellation, invalid responses,
or failures leave the last committed model context intact. A backend
`context_length_exceeded` error also triggers one compaction/retry attempt.

The implementation follows `openai/codex` revision `89461ea`: model-window math,
the foreground trigger, retained-user history, checkpoint validation and token
estimates. Collie pins the default model to that revision's bundled window and
reads the existing Codex model cache for other models; it does not refresh that
catalog or run Codex's speculative background compaction and hook system.

`/help` lists shortcuts. `/new` resets the conversation, `/clear` clears only the
display, `/model MODEL` starts a new chat with another model, and `/logs` shows
host diagnostics. Follow-up prompts include previous replies and VM observations.
Cancelled or failed turns are marked explicitly in model history.

Sessions are saved atomically with mode 0600 under
`$XDG_STATE_HOME/collie/sessions` (default `~/.local/state/collie/sessions`).
Use `--history-dir PATH` to select a directory, `/sessions` to list saved chats,
and `/resume latest` or `/resume ID` to restore one. Sessions include the model,
conversation context, code, and observations; they do not contain login tokens.
Model context has an 8 MiB transport guard; sessions are bounded to 16 MiB.
These local transport bounds do not introduce additional compaction triggers.
The local visible transcript is bounded separately (about 7 MiB or 4,000 items);
start another conversation with `/new` if that archive fills. Model compaction
does not silently erase transcript entries.

Passing a quoted task without `--tui` retains the plain streaming CLI for pipes
and scripts. Authentication and restricted guest execution are shared by both modes.

Rejection reasons and compiler/VM diagnostics are always displayed on stderr.
Reply-format failures say `reply rejected`, source-policy failures say
`program rejected`, and execution failures include the exit status and error text.
The same observations still go back to the model for correction. User prose on
stdout is unaffected; no tracing or streaming flag is needed to see errors.

The default guest compiler is discovered alongside the executable in the
repository build directory (`flex-android`, `flex`, `flexscript`, then `stage2`).
Both repository-root and application-local builds work independently of the
current directory. Override it with `--compiler /path/to/flex` or
`COLLIE_COMPILER`.
`--max-steps` limits model replies, defaults to 8, and is bounded at 32.

## Authentication

Collie reads the ChatGPT login cached by `codex login` in
`$CODEX_HOME/auth.json`, defaulting to `~/.codex/auth.json`. Select another file
with `--auth-file /path/to/auth.json`. It authenticates to the Codex Responses
backend using `tokens.access_token` and `tokens.account_id`. No OpenAI API key is
used. Keyring-only logins are not supported.

The cache is reread on every request and never modified. Codex remains responsible
for refreshing it. Credentials stay in the native provider worker and never enter
model messages, transcripts, or guest mounts.

Requests advertise one `custom` tool named `flexscript`, use `tool_choice: "auto"`,
disable parallel calls, and set `store: false`. Encrypted reasoning items are
preserved alongside tool calls for stateless continuation. TLS verifies
the certificate and hostname; redirects are rejected. The transport follows the
Codex CLI's backend protocol, which can change.

## Tool calls

The bootstrap prompt is in [providers/instructions.flex](providers/instructions.flex).
Collie uses the Responses API's [native custom tools](https://developers.openai.com/api/docs/guides/function-calling#custom-tools):
one tool named `flexscript` accepts raw code, without tags, JSON wrapping or Markdown
fences. Assistant messages are separate prose and never execute.

For example, the model can say "I'll check the VM" and call `flexscript` with:

```flexscript
fn main() {
    let s = "VM is working.\n";
    syscall(1, 1, s, 15, 0, 0, 0);
    return 0;
}
```

Collie executes the completed `custom_tool_call` and sends a
`custom_tool_call_output` with its matching `call_id`. Its output is a JSON
string containing `state`, `stdout`, `stderr`, `exit_code` and truncation
information. Compiler errors, VM traps and source-policy rejections return
through this same result channel so the model can repair the program. Diagnostics
remain visible in the terminal. Program output is not automatically the final
user answer: the model can explain it in its next message.

Both `return 0` and `return 42` produce a result. A completed response without a
tool call finishes the turn. Exhausting the reply or conversation limit exits
unsuccessfully.

Source deltas stream into the code viewer, independently of prose. Execution
waits for `response.completed`, a completed tool item, and a matching source and
item ID. Interrupted streams, unknown tools, malformed IDs, oversized input and
multiple calls never execute. Literal `<FLEXSCRIPT>` in prose is just text.
Saved conversations from the earlier tagged protocol remain readable.

Try the loop without a model or credentials:

```sh
./build/collie --replay apps/collie/tests/fixtures/greeting.json 'Hello'
./build/collie --replay apps/collie/tests/fixtures/repair.json 'Print 42' --stream
```

Replay files contain an array. A string is ordinary assistant prose. An object
has an `output` array of Responses items, for example:

```json
[
  {"output": [{
    "type": "custom_tool_call",
    "name": "flexscript",
    "call_id": "fixture-call",
    "status": "completed",
    "input": "fn main(){return 42;}"
  }]},
  "The program returned 42."
]
```

Replay call IDs are regenerated for each invocation so repeated turns do not
reuse IDs. Replay never requires credentials.

## Traces

Add `--trace` to save replies to `collie-trace.json` in the current directory,
with mode 0600. Select another filename with `--trace trace.json` or
`--trace=trace.json`. Collie reports the saved path.

Each record contains the full model reply (`text`), user prose (`message`),
tool input (`source`), the native `tool_call` when present, and an `observation`
for each program result. Encrypted reasoning remains in model history, not the
visible transcript or guest history.

```sh
./build/collie --model YOUR_CODEX_MODEL 'Calculate 6*7' --trace
jq -r '.[] | select(.source != "") | .source' collie-trace.json
```

## VM boundary

Programs are self-contained. Imports and compiler extensions are unavailable.
Each round gets fresh memory. Programs can calculate, write stdout/stderr, and
use the provided `db_*` functions to query and mutate their session workspace.
On Linux, host files, user stdin, network, processes, and raw FFI remain unavailable.
The Android app additionally grants its private workspace filesystem and bounded
HTTPS GET through `http_get(url)`; see the [Android API](android/README.md).

The [guest API](guest/README.md) includes table/column discovery, typed values,
transactions, row creation/update/deletion, paged scans, and adding, renaming or
dropping columns. Filters and joins are ordinary Flexscript code. Uncommitted
work is rolled back at program exit or failure; previously committed work remains.
No workspace schema is created by Collie.

`db_history()` and `db_history_read()` expose the archived user/assistant messages,
generated programs and VM observations for read-only inspection. This archive
survives model-context compaction and occupies a separate sidecar file, rather
than imposing tables on the agent's database. Credentials and hidden model
reasoning are not included.

TUI workspace files live under `HISTORY_DIR/workspaces/SESSION_ID.flexdb` with
mode 0600. `/history` shows the path. `/new` selects a new workspace and `/resume`
restores the selected session's database. Plain CLI invocations choose a new
workspace under `$XDG_STATE_HOME/collie/workspaces` by default. Use a fixed path
to share state across CLI invocations (or explicitly share TUI sessions):

```sh
./build/collie --workspace ./build/my-agent.flexdb 'Organize this task however you find useful'
./build/collie --workspace ./build/my-agent.flexdb 'Inspect what you saved and continue'
```

Limits: 64 KiB code and 64 KiB user prose per reply, 4 MiB guest memory, 1,000,000
fuel, a 1-second VM deadline, and 1 MiB combined output. Observations retain
32 KiB per output stream and report truncation. Binary NUL displays as `\0`;
invalid UTF-8 displays as replacement characters. The serialized conversation
has a separate 8 MiB host transport guard and is compacted automatically.

Compilation runs before VM permissions apply. Collie therefore isolates compiler
and VM together in Bubblewrap with private filesystem and network namespaces.
Only the compiler, its runtime libraries, and the current source file are mounted
from the host, together with the trusted guest SDK. The database stays in the
native adapter: a bounded value protocol on stderr/stdin connects guest API calls
to the actual FlexDB engine. The VM never receives database file descriptors,
host pointers, credentials, or unrestricted file access. Request/response frames
are capped at 64 KiB, values at 32 KiB, pages at 128 rows, and calls at 1024 per
program, with a 1 MiB response budget. Oversized pages return an error so the
agent can request fewer rows. Workspace history is bounded to 16 MiB/4095 entries.
A 5-second outer watchdog, 1-GiB address-space limit, and bounded
output also cover compilation. Isolation failures stop the session. This bootstrap
is not a hardened multi-user execution service.

## Check

When changing `guest/runtime.flex`, regenerate its embedded source with
`build/flex-android scripts/embed-collie-guest.flex` before a direct build.
The repository build/test driver regenerates it automatically, and the native
suite checks that the embedded source matches the SDK file.

From the repository root:

```sh
build/flex-android scripts/test-collie.flex -o build/test-collie-driver
build/test-collie-driver --compiler build/flex-android --vm
python3 apps/collie/tests/tui.py --compiler build/flex-android --vm
```

After building the standard tools, use
`build/tools/test-collie --compiler build/stage2 --vm`. CI runs this same suite
against the freshly bootstrapped compiler, without model credentials or network.

The underlying application-local suite remains available from `apps/collie`:

```sh
cd apps/collie
../../build/flex-android tests/test.flex -o build/test-collie
./build/test-collie ../../build/flex-android build/collie
./build/test-collie ../../build/flex-android build/collie --vm
```

The first run checks auth, HTTP/SSE parsing, native tool identities and call/result pairs, message
streaming, and chat without execution. The second also exercises the real VM,
compiler and protocol repair, resource traps, traces, and isolation failures.
Delayed fixtures verify that prose and optional code previews appear before
response completion without duplication.
The offline PTY suite also checks editing, paste, multi-turn context, private
session files and resume, model switching, resize, cancellation, mouse code
expansion, inline VM diagnostics, and terminal restoration on signals. The
application remains entirely Flexscript; Python supplies only the PTY test host.
