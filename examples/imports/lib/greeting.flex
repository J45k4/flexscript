import "strings.flex";

fn greet() {
    let message = "Hello from imported Flexscript!\n";
    syscall(1, 1, message, text_size(message), 0, 0, 0);
    return 0;
}
