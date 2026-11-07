// All word operations keep ordinary Flexscript wrapping semantics.
requires x < 0x7fffffffffffffff;
ensures result == old(x) + 1;
ensures result > old(x);
fn increment(x) {
    return x + 1;
}

ensures (result & mask) == (value & mask);
ensures (result & ~mask) == (word & ~mask);
fn write_field(word, mask, value) {
    return (word & ~mask) | (value & mask);
}

requires limit >= 0;
ensures result >= 0 && result <= limit;
fn clamp(x, limit) {
    if x < 0 { return 0; }
    if x > limit { return limit; }
    return x;
}

fn main() {
    return increment(41) - 42;
}
