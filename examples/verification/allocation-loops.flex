// Each recursive call promises a fresh one-byte buffer on success.
requires depth >= 0 && depth <= 3;
reads nothing;
modifies nothing;
decreases depth;
ensures result < 0 || (fresh_bytes(result, 1) && writable_bytes(result, 1));
fn buffer(depth) {
    if depth == 0 {
        return alloc(1);
    }
    return buffer(depth - 1);
}

// Freshness makes this buffer internal to main even though it comes through
// a recursive summary. The invariant describes the loop's evolving byte.
reads nothing;
modifies nothing;
ensures result == 0;
fn main() {
    let p = buffer(2);
    if p < 0 {
        return 0;
    }
    store8(p, 0);
    let i = 0;
    invariant i >= 0 && i <= 3;
    invariant fresh_bytes(p, 1) && writable_bytes(p, 1);
    invariant load8(p) == i;
    decreases 3 - i;
    while i < 3 {
        store8(p, i + 1);
        i = i + 1;
    }
    return load8(p) - 3;
}
