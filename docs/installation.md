# Installing the Flexscript command

The public compiler command is `flexscript`. Keep `flex` available for the
unrelated lexical-analyzer tool; Flexscript applications should not implicitly
select it as their compiler.

Install a verified build or release binary under the new name:

```sh
mkdir -p "$HOME/.local/bin"
install -m 755 build/stage3 "$HOME/.local/bin/flexscript"
# Add ~/.local/bin to PATH if it is not already there.
flexscript --version
flexscript --help
flexscript examples/hello.flex -o /tmp/hello
/tmp/hello
```

Build and verify stage3 first using [bootstrapping.md](bootstrapping.md), or use
a verified `flexscript-VERSION-linux-x86_64` release asset instead. Internal build
artifact paths such as `build/flex` remain valid; their filenames do not reserve
a command on PATH. The `.flex` source extension and `--language flex` option
are unchanged.

Run source with `flexscript run app.flex`, and check signed release updates
with `flexscript upgrade --check`. Upgrade replaces the invoked executable at
its installed path, so installations named `flexscript` keep that name.

For an older installation named `~/.local/bin/flex`, verify that it belongs to
Flexscript before moving it aside. Do not rename or remove a system lexer.
Setaworld resolves `flexscript` from PATH, with `FLEX` as an explicit executable
override; it does not install or upgrade a compiler automatically.
