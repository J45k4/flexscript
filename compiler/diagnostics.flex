// Source location and fatal compiler diagnostics.
global source = 0;
global source_size = 0;
global source_path = 0;
global token_start = 0;

fn length(text) {
    let n = 0;
    while load8(text + n) != 0 { n = n + 1; }
    return n;
}

fn write_all(fd, bytes, size) {
    while size > 0 {
        let n = syscall(1, fd, bytes, size, 0, 0, 0);
        if n == -4 { n = 0; }
        else { if n <= 0 { return 0; } }
        bytes = bytes + n;
        size = size - n;
    }
    return 1;
}

fn print(fd, text) { return write_all(fd, text, length(text)); }

fn print_number(n) {
    let buf = alloc(32);
    let i = 31;
    store8(buf + i, 0);
    while n >= 10 {
        i = i - 1;
        store8(buf + i, 48 + n % 10);
        n = n / 10;
    }
    i = i - 1;
    store8(buf + i, 48 + n);
    print(2, buf + i);
    return 0;
}

fn fail(message) {
    print(2, source_path);
    print(2, ":");
    let i = 0;
    let line = 1;
    let column = 1;
    while i < token_start && i < source_size {
        if load8(source + i) == 10 { line = line + 1; column = 1; }
        else { column = column + 1; }
        i = i + 1;
    }
    print_number(line);
    print(2, ":");
    print_number(column);
    print(2, ": error: ");
    print(2, message);
    print(2, "\n");
    syscall(60, 1, 0, 0, 0, 0, 0);
    return 0;
}
