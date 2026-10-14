# Monolith

Optional native web apps for Flexscript: keyed HTML/SSE UI updates, bundled
browser assets, and separate SQLite/schema modules.

```flex
import "monolith";
extend "monolith/syntax.flex";
// Optional:
import "monolith/model.flex";
```

See [the Monolith guide](../../docs/monolith.md) and the source apps under
[`examples/monolith`](../../examples/monolith/).

Nested `view` declarations compile to ordinary render functions and specialized
patch programs. Static nodes and attributes have no runtime property comparisons;
dynamic bindings and keyed collection/conditional changes produce DOM patches.
