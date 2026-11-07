requires x >= 0 && x < 100;
ensures result == old(x) + 1;
fn increment(x) {
    ghost let initial = x;
    x = x + 1;
    assert x == initial + 1;
    return x;
}

requires n >= 0 && n < 10;
ensures result == n;
fn count(n) {
    let i = 0;
    ghost let iterations = 0;
    invariant i >= 0 && i <= n;
    invariant iterations == i;
    decreases n - i;
    while i < n {
        i = i + 1;
        proof { iterations = iterations + 1; }
    }
    assert iterations == n;
    return i;
}

fn main() { return increment(4) - count(5); }
