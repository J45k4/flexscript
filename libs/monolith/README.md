# Monolith

Optional native web apps for Flexscript: keyed HTML/SSE UI updates, bundled
browser assets, and separate SQLite/schema modules.

```flex
import "monolith";
// Optional:
import "monolith/model.flex";
```

See [the Monolith guide](../../docs/monolith.md) and the source apps under
[`examples/monolith`](../../examples/monolith/).

`monolith/cache.flex` adds bounded owned resource snapshots, MIME-bound SHA-256
ETags, GET/HEAD revalidation, explicit public/private/no-store policies and
content-versioned immutable URLs. The keyed server uses it for its JavaScript
and stylesheet automatically. See the resource caching section in the guide and
`python3 tests/monolith/cache.py --compiler build/flexscript --browser`.
