requires n >= 0;
ensures result == old(n);
fn count_to(n) {
    let i = 0;
    invariant i >= 0 && i <= n;
    decreases n - i;
    while i < n {
        i = i + 1;
    }
    return i;
}

requires x >= 0 && x < 4;
requires y >= 0 && y < 4;
ensures result == 0;
fn countdown_pair(x, y) {
    invariant x >= 0 && x < 4;
    invariant y >= 0 && y < 4;
    decreases x, y;
    while x || y {
        if y {
            y = y - 1;
        } else {
            x = x - 1;
            y = 3;
        }
    }
    return x + y;
}

fn main() {
    return count_to(10) - 10;
}
