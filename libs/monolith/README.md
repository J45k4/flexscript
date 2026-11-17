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

Multipart forms
---------------

`monolith/multipart.flex` parses bounded `multipart/form-data` bodies through
`mono_mp_open(content_type, bytes, length, max_parts)` and repeated
`mono_mp_next(state)` calls. A part exposes `mono_mp_name`, `mono_mp_filename`,
`mono_mp_type`, `mono_mp_data`, and `mono_mp_size`. Data points into the caller's
input buffer and is valid only while that buffer is retained; copy or consume it
before freeing or reusing the buffer. The parser does not allocate or copy the
part contents. It rejects malformed or oversized headers, invalid boundaries,
and more than 64 parts, and uses a linear-time delimiter scan. It leaves upload
size limits, authentication, storage and streaming to the application.

The small `monolith/web.flex` loop accepts both URL-encoded and multipart POSTs.
For multipart, `web_multipart` is a validated parser ready for iteration during
`app_request`; the existing 8 KiB request limit still applies. Applications
that need larger transfers should stream or send bounded chunks through their
own authorized transport instead of raising that global in-memory limit.
