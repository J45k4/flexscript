requires n >= 0 && n <= 4;
ensures forall i in 0..n: i >= 0 && i < n;
fn range(n) { return n; }

ensures (exists i in -2..3: i == x) == (x >= -2 && x < 3);
ensures (forall i in -2..3: i != x) == !(x >= -2 && x < 3);
fn membership(x) { return x; }

ensures forall i in 0..3: exists j in i..3: i == j;
fn nested() { return 0; }

fn main() { return range(3) - membership(3) + nested(); }
