global count = 0;

spec fn twice(x) { return x + x; }

ensures twice(x) == x * 2;
lemma fn doubling(x) {
    assert twice(x) == x * 2;
}

ensures result == twice(x);
fn double(x) {
    proof { doubling(x); }
    return x * 2;
}

reads count;
spec fn current_count() { return count; }

requires count >= 0 && count < 100;
ensures count == old(current_count()) + 1;
ensures result == count;
fn increment_count() {
    count = count + 1;
    return count;
}

requires n >= 0;
ensures result == old(n);
decreases n;
spec fn counted(n) {
    if n == 0 { return 0; }
    n = n - 1;
    return counted(n) + 1;
}

requires n >= 0;
ensures result == counted(n);
fn identity(n) { return n; }

fn main() { return double(3) - identity(6) + increment_count() - 1; }
