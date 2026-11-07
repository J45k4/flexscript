global count = 0;

requires count >= 0 && count < 100;
reads count;
modifies count;
ensures count == old(count) + 1;
ensures result == count;
fn increment_count() {
    count = count + 1;
    return count;
}

requires count >= 0 && count < 99;
reads count;
modifies count;
ensures count == old(count) + 2;
ensures result == count;
fn increment_twice() {
    increment_count();
    return increment_count();
}

fn main() {
    return increment_twice() - 2;
}
