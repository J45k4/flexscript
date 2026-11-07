global samples = 0;

// This contract models external behavior. The verifier does not check its body
// or establish the normal-return assumption. Every dependent proof says so.
trusted;
terminates;
reads samples;
modifies samples;
ensures samples == old(samples) + 1;
ensures result >= 0 && result <= 1;
fn external_bit() {
    samples = samples + 1;
    return syscall(39, 0, 0, 0, 0, 0, 0) & 1;
}

requires samples == 0;
ensures samples == 2;
ensures result >= 0 && result <= 2;
fn sample_pair() {
    return external_bit() + external_bit();
}

fn main() {
    sample_pair();
    return 0;
}
