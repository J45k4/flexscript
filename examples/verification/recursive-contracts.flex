// Function measures compare entry values across recursive call edges.
requires n >= 0;
ensures result == old(n);
decreases n;
fn count(n) {
    if n == 0 { return 0; }
    n = n - 1;
    return count(n) + 1;
}

requires n >= 0;
ensures result == 0;
decreases n;
fn left(n) {
    if n == 0 { return 0; }
    return right(n - 1);
}

requires n >= 0;
ensures result == 0;
decreases n;
fn right(n) {
    if n == 0 { return 0; }
    return left(n - 1);
}

requires x >= 0 && x < 3;
requires y >= 0 && y < 3;
ensures result == 0;
decreases x, y;
fn pair(x, y) {
    if y { return pair(x, y - 1); }
    if x { return pair(x - 1, 2); }
    return 0;
}

fn main() { return count(5) - 5 + left(8) + pair(2, 2); }
