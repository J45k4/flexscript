# Bounded JSON

Use `import "json/tree.flex";` for a bounded, nonfatal JSON parser and
writer. The library runs in native Flexscript and the checked VM, and it
allocates through the shared monolith memory helpers, so a failed parse
leaves no partial state behind.

Parse a complete document with `j_parse(text)`. The result is a node: kinds
are 0 null, 1 integer, 2 string, 3 array, 4 object, 5 boolean and 6 raw
number text. Zero means the document was rejected. Strings decode to
zero-terminated UTF-8, so escaped NUL bytes and lone surrogates are rejected
rather than truncated. Objects reject duplicate keys; nesting is bounded at
32 levels; numbers keep their exact source text when they carry a fraction
or an exponent and otherwise parse as 64-bit signed integers.

`j_get(parent,key)` looks up an object member, `j_string` and `j_integer`
read typed members, and array elements are the child chain at offset 16 with
siblings at offset 24. `j_encode(node)` writes the tree back to JSON text:
booleans write as `true` or `false`, and raw nodes write their source text.
Raw byte payloads (kind 7) require an explicit transport encoding and are
rejected by the writer.

From the repository root, build and run the parse regression with the
source libraries selected.

```sh
FLEXSCRIPT_LIB="$PWD/libs" flexscript libs/json/tests/parse.flex -o /tmp/flexscript-json-test
/tmp/flexscript-json-test
```
