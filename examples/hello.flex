fn main() {
    let message = "Hello from native Flexscript!\n";
    syscall(1, 1, message, 30, 0, 0, 0);
    return 0;
}
