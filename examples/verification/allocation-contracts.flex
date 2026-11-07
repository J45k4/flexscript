// Fresh storage is internal to this invocation. Allocation can fail; the
// failure branch returns normally without dereferencing the error value.
reads nothing;
modifies nothing;
releases nothing;
ensures result == 0;
fn main() {
    let p = alloc(8);
    if p < 0 {
        return 0;
    }
    assert writable_bytes(p, 8);
    assert load64(p) == 0;
    store64(p, 42);
    return load64(p) - 42;
}
