# Monolith

Monolith is an optional Flexscript library for native web apps. The app builds a
keyed UI tree in Flexscript. Monolith renders the initial HTML and sends small
DOM patches over SSE; the bundled JavaScript adapter applies them and preserves
local input drafts, focus, and selection. SQLite is a separate optional module.

The library is in `libs/monolith/`, with the public entry point
`libs/monolith.flex`. Applications import it by name:

```flex
import "monolith";
```

## Build and run

From a Flexscript checkout, build a current compiler in `build/`. Its named
imports find the checkout's `libs/` relative to the compiler executable:

```sh
flexscript compiler/main.flex -o build/flexscript
build/flexscript run examples/monolith/todo.flex
# A second app with arbitrary actions and fields, without SQLite:
build/flexscript run examples/monolith/counter.flex
```

Todo serves <http://127.0.0.1:8080/> and persists to `todo.db` in the working
directory. Counter serves <http://127.0.0.1:8081/> and keeps its state in memory.
Open either app in two tabs to see shared updates. Stop the server with Ctrl-C.
Both accept optional port and state-path arguments after the source filename.
An app can also be compiled with `-o` and run directly.

Source launching transparently compiles and executes a native app, removing its
temporary executable before execution. This keeps the server independent of VM
fuel and time limits. Restart after changing source; file watching is not provided.

Requires Linux x86-64 and glibc. Only the SQLite modules require
`libsqlite3.so.0`; browser apps require a browser with EventSource.

## Install source libraries

The installer copies the compiler to `PREFIX/bin/flexscript` and library sources
to `PREFIX/share/flexscript/{libs,lib}`. It also installs the Monolith examples.
Run it from the checkout or an extracted release library bundle:

```sh
build/flexscript scripts/install.flex -o build/install
build/install --compiler build/flexscript --prefix "$HOME/.local"
```

After installation, a source file anywhere can `import "monolith"` and run with
`flexscript run /path/to/app.flex`. Imports within libraries resolve relative
to their source file as usual. Native app binaries already contain their browser
assets and do not need the library sources at runtime.

Existing exact local import paths take precedence. A missing named import
searches `FLEXSCRIPT_LIB` if set, otherwise the compiler executable's
`../share/flexscript/libs`, `../libs`, then `libs` directories. `.flex` is optional
for library names. Explicit `./`, `../`, and absolute paths keep their local
meaning. URL imports keep their URL semantics. `FLEXSCRIPT_LIB` is one directory,
and takes precedence over the default roots; use it for custom build locations:

```sh
FLEXSCRIPT_LIB=/path/to/flexscript/libs /path/to/compiler run app.flex
```

Releases include `flexscript-libraries-VERSION.tar.gz` in the signed checksum
manifest. Extract it and compile `scripts/install.flex` with the corresponding
compiler binary to install both. `flexscript upgrade` currently updates the
compiler executable only; reinstall the matching source library bundle when
upgrading an installation that uses named library imports.

## App hooks

Define these four functions and call `mono_run`:

```flex
import "monolith";
global count=0;
fn app_init(state_path) {return 0;}
fn app_tick() {return 0;}
fn app_view() {
    ui_begin();let root=ui_node("main","app",0);
    ui_add(root,ui_node("p","count",m_int(count)));
    ui_add(root,ui_action(ui_node("button","increase","Increase"),"increase",0));
    return root;
}
fn app_action(action,id) {
    if m_eq(action,"increase") {count=count+1;return 200;}return 422;
}
fn main(argc,argv) {return mono_run(argc,argv,"My app",8080,"");}
```

`app_init` initializes persistent app state and returns zero on success.
`app_view` builds a fresh tree with stable, unique keys. `app_action` receives
an app-defined action name and optional positive numeric ID, and returns an HTTP
status; `200` refreshes the view and publishes its patches. The app owns mutations,
validation, and transaction boundaries. `app_tick` runs once per second and
returns nonzero when externally changed state needs a refresh.

`mono_run(argc,argv,title,default_port,default_state_path)` configures the page
title, listener, and app state path. Set `mono_style` in `app_init` to replace the
default stylesheet. All browser clients share the same app view and state.

## UI and actions

`ui_node(tag,key,text)` creates a node; `ui_add(parent,child)` appends a child.
Use `ui_text`, `ui_class`, and `ui_attribute` to set text, classes, and ordinary
HTML attributes. Attribute values are escaped. Pass `0` to omit an attribute,
or `""` for a present boolean attribute. Class and Monolith key/action attributes
have dedicated helpers. Dynamic text belongs in leaf nodes.

`ui_action(node,name,id)` attaches an action. Buttons send it on click;
checkboxes and selects send it on change. `check` is a checkbox
helper node, with `ui_value(check,checked)` for server-owned checked state.
`empty` is a paragraph helper, with `ui_value(node,hidden)` for visibility.

Forms carry their action on the form node. Give fields their own names and mark
submit buttons explicitly; normal form submission also works without JavaScript:

```flex
let form=ui_add(root,ui_action(ui_node("form","rename",0),"rename",42));
let input=ui_add(form,ui_node("input","name","New name"));
ui_attribute(input,"name","display_name");
ui_add(form,ui_attribute(ui_node("button","save","Save"),"type","submit"));
```

Inside `app_action`, `mono_field("display_name")` reads the decoded field value.
Fields live until the request finishes; copy values into app-owned storage if
they must survive. Duplicate field names are rejected. `token`, `action`, and
`id` are reserved form fields managed by the transport.

Draft input values are preserved across remote patches and reconnect snapshots.
Use `data-mono-clear` on a field to clear an unchanged submitted draft after a
successful form action. Optional `data-mono-status` and `data-mono-error`
elements display connection state and action errors; their UI keys are app-owned.
The adapter handles insertion, removal, movement, text, checked state, classes,
and generic attribute changes without replacing the whole page.

## Optional SQLite and schema support

Import `monolith/sqlite.flex` for SQLite statements, parameter binding,
transactions, schema metadata, and external-write polling. Import
`monolith/model.flex` to also use the existing single-model schema parser:

```flex
import "monolith";
import "monolith/model.flex";
fn app_init(path) {
    return mono_model(path,"model Todo { id Int primary auto; title Text(240); completed Bool default false; }");
}
fn app_tick() {return db_poll();}
```

`model_select_sql`, `model_insert_sql`, `model_update_sql`, `model_delete_sql`, and
`model_find_sql` return parameterized queries. Values use `db_text` and `db_int`;
always finalize statements with `db_finish`. The full Todo example demonstrates
transactional handlers: start `BEGIN IMMEDIATE`, then `db_transaction(status)`
commits a `200` result or rolls back a rejected action. External writes are
detected by `db_poll` using `PRAGMA data_version`.

The schema parser currently supports one model, an automatic integer primary
key, `Text(N)`, and `Bool`. Schema metadata refuses implicit migrations and
adoption of existing tables. The optional external-schema builder remains:

```sh
build/monolith-builder build examples/monolith/external-schema.flex \
  --schema examples/monolith/todo.mono --compiler build/flexscript -o build/todo
```

Apps owning their HTTP routes can instead import `monolith/web.flex` for the
HTTP/form/SSE loop with `app_init`, `app_request`, and `app_tick` hooks. This is
a separate entry point; it does not import the keyed UI server.

## Verification

```sh
build/flexscript scripts/build-monolith.flex -o build/build-monolith
build/build-monolith --compiler build/flexscript
build/test-monolith-integration build/flexscript
build/test-monolith-integration build/flexscript --source
build/test-monolith-browser build/flexscript /usr/bin/chromium --source
build/test-monolith-browser build/monolith-todo /usr/bin/chromium
build/flexscript scripts/test-libraries.flex -o build/test-libraries
build/test-libraries build/flexscript
```

The integration suite checks SQLite persistence, escaping, rejected requests,
two live clients, external writes, reconnects, and source/native execution.
Source checks include native handoff, temporary-file cleanup, execution beyond
the VM deadline, source edits, and unrelated directories and paths with spaces.
Browser tests cover both Todo and Counter, draft/focus/selection preservation,
arbitrary action and field names, changing attributes, rejected controls, and
mobile Todo layout. Screenshots are saved to `build/monolith-*.png`.
The library suite checks named imports in native/interpreter/JIT execution,
local precedence, explicit relative paths, and installed and symlinked compilers.

Refresh the committed asset bundle after editing the browser adapter or CSS:

```sh
build/flexscript scripts/monolith-assets.flex -o build/monolith-assets
build/monolith-assets
```

## Portable views

The HTML `view` frontend now shares its AST parser, keyed records, and compiled
update machinery with [portable views](ui.md). Existing Monolith HTML views
retain their DOM wire format. Portable views use `extend "ui/syntax.flex"` and
explicit widget/style properties, with native Android and DOM adapters.

## Current scope

The listener binds to loopback. There are no accounts, per-client views,
automatic migrations, HTTPS termination, or offline writes. Actions use a random
process token and reject foreign Host/Origin headers. HTML/JSON values are
escaped and SQLite values are bound parameters. The keyed server currently
allows 2,048 UI nodes, 64 connections, 32 SSE subscribers, 8-KiB headers, 4-KiB
form bodies, and 64 fields with unique names. View dependency tracking is coarse:
each successful action recomputes the shared tree, then diffs minimize patches.

## Resource caching

`monolith/cache.flex` provides immutable, process-owned binary resource
snapshots. Both HTTP transports use the same implementation. The keyed
`mono_run` server automatically snapshots its bundled JavaScript and configured
stylesheet after `app_init`, emits content-versioned URLs in HTML, and serves
those URLs with `public, max-age=31536000, immutable`. Unversioned `/client.js`
and `/style.css` aliases use `public, no-cache` and ETag revalidation. Unknown
versions return 404; they never receive newer bytes under an old immutable URL.
HTML containing action tokens, SSE and ordinary replies remain `no-store`.

For applications using `monolith/web.flex`, register server-owned files or byte
buffers at startup and explicitly choose resource routes:

```flexscript
// In app_init, before the request loop:
logo=mono_resource_file("assets/logo.png","image/png");
m_assert(logo,mono_resource_error);
// Or capture an exact byte range, including embedded NUL bytes:
resource=mono_resource_bytes(data,size,"application/octet-stream");
// When generating HTML:
let url=mono_resource_url("/logo.png",logo);
// In a GET/HEAD route, after any required authorization:
web_resource(fd,logo,"immutable",31536000);
```

Only select `immutable` after matching the requested version to
`mono_resource_version(resource)`. `web.flex` puts the query in `web_get("v")`;
applications should return 404 for a mismatching version and use `revalidate`
for a bare alias. `mono_resource_match(request_path,route,resource)` is available
for transports retaining a complete request target: 0 means no match, 1 the bare
alias, and 2 the exact versioned URL.

`mono_resource_reply(fd,method,if_none_match,resource,mode,seconds)` is the
transport-independent writer. `web_resource` supplies its current method and
parsed `If-None-Match` value. Policies are:

| Mode | Cache-Control | Conditional behavior |
| --- | --- | --- |
| `revalidate` | `public, no-cache` | Matching GET/HEAD returns 304 |
| `immutable` | `public, max-age=N, immutable` | Matching GET/HEAD returns 304 |
| `private` | `private, no-cache` | Matching GET/HEAD returns 304 after caller authorization |
| `no-store` | `no-store` | Always sends a fresh 200 representation |

Immutable ages must be 1-31536000 seconds. Responses have a strong SHA-256 ETag,
a locale-independent HTTP Date, explicit MIME type and `nosniff`. Validators are
`SHA256(MIME || NUL || SHA256(body))`, so changes in bytes or MIME type change the
version. Weak `If-None-Match` comparisons, lists (including commas inside opaque
tags), wildcard and duplicate header fields are handled. Invalid conditions do
not produce a false match. HEAD preserves the representation length; 304 has no
body or Content-Length. The helper accepts only GET/HEAD; other methods receive
405. It does not implement ranges, compression, Last-Modified/If-Modified-Since
or write preconditions.

Defaults are 128 snapshots, 16 MiB of retained mapped pages and 4 MiB per
resource. `mono_resource_limits(total_bytes,entries,file_bytes)` configures an
empty cache (bounded to 64 MiB, 1024 entries and 8 MiB per resource). Failed
admission returns 0 with `mono_resource_error`, preserving existing resources.
The file loader accepts regular Linux files, limits growth while reading, and
copies captured bytes into owned storage. It never maps a request URL to a host
path. Register files through an application-owned allowlist.

Snapshots survive request-arena resets and file changes/deletion. They do not
poll or reread files per request. Restart or explicitly replace a snapshot to
adopt new bytes. Accessors are `mono_resource_data`, `mono_resource_size`,
`mono_resource_etag`, `mono_resource_version`, `mono_resource_count` and
`mono_resource_retained_bytes`. `mono_resource_release` and
`mono_resources_clear` free owned pages; callers must not retain freed handles.
Registration/replacement must be serialized with request handling. Deployments
that need old version URLs to stay available should retain those snapshots or
serve previous immutable artifacts separately.

The native helper uses Linux syscalls, OpenSSL 3 SHA-256 and libc's `gmtime_r`.
Private resource authorization belongs before lookup/conditional handling, on
every request. A validator is not an access token.

Run the disposable protocol and optional headless browser checks:

```sh
python3 tests/monolith/cache.py --compiler build/flexscript
python3 tests/monolith/cache.py --compiler build/flexscript --browser
```

The suite checks binary/empty data, memory ownership/bounds, conditional
GET/HEAD, malformed and duplicate validators, authorization ordering, changes
across restart, both transports and actual browser cache reuse/invalidation.
