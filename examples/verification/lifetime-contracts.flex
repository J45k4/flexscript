// Explicit platform assumption: Linux munmap on a 4 KiB-page target.
// This syscall body is not checked. The release frame permits revocation of
// this page, and the postcondition states the successful-return consequence.
trusted;
terminates;
requires page > 0 && (page & 4095) == 0;
reads nothing;
modifies nothing;
releases bytes(page, 4096);
ensures result != 0 || !readable_bytes(old(page), 4096);
fn external_release_page(page) {
    return syscall(11, page, 4096, 0, 0, 0, 0);
}

requires page > 0 && (page & 4095) == 0;
requires writable_bytes(page, 4096);
reads nothing;
modifies nothing;
releases bytes(page, 4096);
ensures result != 0 || !readable_bytes(page, 4096);
ensures old(writable_bytes(page, 4096));
fn release_page(page) {
    return external_release_page(page);
}

// Allocation is ordinary runtime code here; main requests no allocation proof.
fn main() {
    let page = alloc(4096);
    if page < 0 { return 1; }
    return release_page(page) != 0;
}
