# Applications

Language/runtime capabilities belong in Flexscript's `compiler/`, `vm/`, `lib/`
and `libs/` directories. Applications can consume them from a separate checkout.

[Collie](https://github.com/J45k4/collie) now has its own repository. Its agent,
CLI, desktop and Android hosts, tests and packaging are maintained there.
From a sibling Collie checkout:

```sh
cd ../collie
./configure --sdk ../flexscript
./build.sh cli
./build.sh desktop
./build.sh tools
```

Flexscript builds and tests independently of Collie. Existing ignored Collie
build outputs and traces may remain locally under `apps/collie/`; they are not
application source and are not read by the new build.
