requires writable_bytes(buffer, 4);
modifies bytes(buffer, 4);
ensures forall k in 0..4: load8(buffer + k) == 0;
fn clear_four(buffer) {
    let i = 0;
    invariant i >= 0 && i <= 4;
    invariant forall k in 0..4: k >= i || load8(buffer + k) == 0;
    decreases 4 - i;
    while i < 4 {
        store8(buffer + i, 0);
        i = i + 1;
    }
    return 0;
}

requires writable_bytes(buffer, 8);
reads bytes(buffer, 8);
modifies bytes(buffer, 8);
ensures result == old(value);
ensures load64(buffer) == old(value);
fn round_trip(buffer, value) {
    store64(buffer, value);
    return load64(buffer);
}

// This ordinary entry point supplies real storage when the example is run.
// Verification checks the annotated functions independently. Source allocation
// verification is still pending; main itself does not request verification.
fn main() {
    let buffer = alloc(8);
    if buffer < 0 { return 1; }
    if round_trip(buffer, 0x12345678) != 0x12345678 { return 2; }
    clear_four(buffer);
    return load64(buffer) != 0;
}
