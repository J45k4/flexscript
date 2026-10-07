// Native terminal Tetris. Compile with the released Flexscript 0.0.1 binary.
global board = 0;
global shapes = 0;
global bag = 0;
global bag_index = 7;
global random_state = 1;
global piece = 0;
global preview = 0;
global piece_x = 3;
global piece_y = 0;
global rotation = 0;
global score = 0;
global lines = 0;
global level = 1;
global game_over = 0;
global paused = 0;
global running = 1;
global dirty = 1;
global next_fall = 0;
global small_terminal = 0;
global escape_state = 0;
global frame = 0;
global frame_size = 0;
global clock_buffer = 0;
global number_buffer = 0;
global input_buffer = 0;
global old_term = 0;
global raw_term = 0;
global window_size = 0;
global signal_mask = 0;
global old_mask = 0;
global signal_fd = -1;
global poll_buffer = 0;
global terminal_active = 0;
global checks = 0;
global failures = 0;

fn length(text) {
    let n = 0;
    while load8(text + n) { n = n + 1; }
    return n;
}

fn equal(a, b) {
    let i = 0;
    while load8(a + i) && load8(a + i) == load8(b + i) { i = i + 1; }
    return load8(a + i) == load8(b + i);
}

fn byte(c) {
    if frame_size < 16384 {
        store8(frame + frame_size, c);
        frame_size = frame_size + 1;
    } else { running = 0; }
    return 0;
}

fn text(s) {
    let i = 0;
    while load8(s + i) { byte(load8(s + i)); i = i + 1; }
    return 0;
}

fn ansi(s) { byte(27); text(s); return 0; }

fn number(n) {
    let i = 31;
    store8(number_buffer + i, 0);
    if n < 0 { byte(45); n = -n; }
    while n >= 10 {
        i = i - 1;
        store8(number_buffer + i, 48 + n % 10);
        n = n / 10;
    }
    i = i - 1;
    store8(number_buffer + i, 48 + n);
    text(number_buffer + i);
    return 0;
}

fn flush() {
    let sent = 0;
    while sent < frame_size {
        let n = syscall(1, 1, frame + sent, frame_size - sent, 0, 0, 0);
        if n == -4 { n = 0; }
        else if n <= 0 { running = 0; frame_size = 0; return 0; }
        sent = sent + n;
    }
    frame_size = 0;
    return 1;
}

fn cursor(row, column) {
    ansi("["); number(row); text(";"); number(column); text("H");
    return 0;
}

fn now_ms() {
    if syscall(228, 1, clock_buffer, 0, 0, 0, 0) < 0 { running = 0; return 0; }
    return load64(clock_buffer) * 1000 + load64(clock_buffer + 8) / 1000000;
}

fn delay() {
    let ms = 800 - (level - 1) * 65;
    if ms < 80 { return 80; }
    return ms;
}

fn random(limit) {
    random_state = (random_state ^ (random_state << 13)) & 0xffffffff;
    random_state = (random_state ^ (random_state >> 17)) & 0xffffffff;
    random_state = (random_state ^ (random_state << 5)) & 0xffffffff;
    return random_state % limit;
}

fn next_piece() {
    if bag_index == 7 {
        let i = 0;
        while i < 7 { store8(bag + i, i); i = i + 1; }
        i = 6;
        while i > 0 {
            let j = random(i + 1);
            let value = load8(bag + i);
            store8(bag + i, load8(bag + j)); store8(bag + j, value);
            i = i - 1;
        }
        bag_index = 0;
    }
    let result = load8(bag + bag_index);
    bag_index = bag_index + 1;
    return result;
}

fn shape(which, direction) { return load64(shapes + (which * 4 + (direction & 3)) * 8); }

fn initialize_shapes() {
    store64(shapes, 0x00f0); // I
    store64(shapes + 32, 0x0066); // O
    store64(shapes + 64, 0x0072); // T
    store64(shapes + 96, 0x0036); // S
    store64(shapes + 128, 0x0063); // Z
    store64(shapes + 160, 0x0071); // J
    store64(shapes + 192, 0x0074); // L
    let which = 0;
    while which < 7 {
        let direction = 1;
        while direction < 4 {
            let previous = shape(which, direction - 1);
            let rotated = 0;
            let i = 0;
            while i < 16 {
                if previous & (1 << i) {
                    let x = i % 4;
                    let y = i / 4;
                    let nx = 2 - y;
                    if which == 0 { nx = 3 - y; }
                    rotated = rotated | (1 << (x * 4 + nx));
                }
                i = i + 1;
            }
            if which == 1 { rotated = previous; }
            store64(shapes + (which * 4 + direction) * 8, rotated);
            direction = direction + 1;
        }
        which = which + 1;
    }
    return 0;
}

fn cell(x, y) { return load8(board + y * 10 + x); }
fn set_cell(x, y, value) { store8(board + y * 10 + x, value); return 0; }

fn clear_board() {
    let i = 0;
    while i < 200 { store8(board + i, 0); i = i + 1; }
    return 0;
}

fn fits(x, y, direction) {
    let mask = shape(piece, direction);
    let i = 0;
    while i < 16 {
        if mask & (1 << i) {
            let cx = x + i % 4;
            let cy = y + i / 4;
            if cx < 0 || cx >= 10 || cy >= 20 { return 0; }
            if cy >= 0 && cell(cx, cy) { return 0; }
        }
        i = i + 1;
    }
    return 1;
}

fn ghost_y() {
    let y = piece_y;
    while fits(piece_x, y + 1, rotation) { y = y + 1; }
    return y;
}

fn spawn() {
    piece = preview; preview = next_piece();
    piece_x = 3; piece_y = 0; rotation = 0;
    if !fits(piece_x, piece_y, rotation) { game_over = 1; }
    next_fall = now_ms() + delay(); dirty = 1;
    return 0;
}

fn restart() {
    clear_board(); score = 0; lines = 0; level = 1;
    game_over = 0; paused = 0; bag_index = 7;
    preview = next_piece(); spawn();
    return 0;
}

fn clear_lines() {
    let removed = 0;
    let y = 19;
    while y >= 0 {
        let full = 1;
        let x = 0;
        while x < 10 { if !cell(x, y) { full = 0; } x = x + 1; }
        if full {
            removed = removed + 1;
            let row = y;
            while row > 0 {
                x = 0;
                while x < 10 { set_cell(x, row, cell(x, row - 1)); x = x + 1; }
                row = row - 1;
            }
            x = 0;
            while x < 10 { set_cell(x, 0, 0); x = x + 1; }
        } else { y = y - 1; }
    }
    let points = 0;
    if removed == 1 { points = 100; }
    else if removed == 2 { points = 300; }
    else if removed == 3 { points = 500; }
    else if removed == 4 { points = 800; }
    score = score + points * level;
    lines = lines + removed; level = lines / 10 + 1;
    return removed;
}

fn lock_piece() {
    let mask = shape(piece, rotation);
    let i = 0;
    while i < 16 {
        if mask & (1 << i) {
            let y = piece_y + i / 4;
            if y < 0 { game_over = 1; dirty = 1; return 0; }
        }
        i = i + 1;
    }
    i = 0;
    while i < 16 {
        if mask & (1 << i) { set_cell(piece_x + i % 4, piece_y + i / 4, piece + 1); }
        i = i + 1;
    }
    clear_lines(); spawn();
    return 0;
}

fn move(dx) {
    if fits(piece_x + dx, piece_y, rotation) { piece_x = piece_x + dx; dirty = 1; return 1; }
    return 0;
}

fn rotate(direction) {
    let candidate = (rotation + direction) & 3;
    let attempt = 0;
    while attempt < 6 {
        let dx = 0;
        let dy = 0;
        if attempt == 1 { dx = -1; }
        else if attempt == 2 { dx = 1; }
        else if attempt == 3 { dx = -2; }
        else if attempt == 4 { dx = 2; }
        else if attempt == 5 { dy = -1; }
        if fits(piece_x + dx, piece_y + dy, candidate) {
            rotation = candidate; piece_x = piece_x + dx; piece_y = piece_y + dy;
            dirty = 1; return 1;
        }
        attempt = attempt + 1;
    }
    return 0;
}

fn soft_drop() {
    if fits(piece_x, piece_y + 1, rotation) { piece_y = piece_y + 1; score = score + 1; }
    else { lock_piece(); }
    dirty = 1;
    return 0;
}

fn hard_drop() {
    let destination = ghost_y();
    score = score + (destination - piece_y) * 2;
    piece_y = destination; lock_piece(); dirty = 1;
    return 0;
}

fn tick(now) {
    if !paused && !game_over && !small_terminal && now >= next_fall {
        if fits(piece_x, piece_y + 1, rotation) { piece_y = piece_y + 1; }
        else { lock_piece(); }
        next_fall = now + delay(); dirty = 1;
    }
    return 0;
}

fn key(c) {
    if c == 113 || c == 81 || c == 3 || c == 4 { running = 0; return 0; }
    if c == 114 || c == 82 { restart(); return 0; }
    if c == 112 || c == 80 {
        paused = !paused; next_fall = now_ms() + delay(); dirty = 1; return 0;
    }
    if paused || game_over || small_terminal { return 0; }
    if c == 97 || c == 65 { move(-1); }
    else if c == 100 || c == 68 { move(1); }
    else if c == 119 || c == 87 { rotate(1); }
    else if c == 122 || c == 90 { rotate(-1); }
    else if c == 115 || c == 83 { soft_drop(); }
    else if c == 32 { hard_drop(); }
    return 0;
}

fn input(c) {
    if escape_state == 1 {
        if c == 91 || c == 79 { escape_state = 2; return 0; }
        escape_state = 0;
    } else if escape_state == 2 {
        escape_state = 0;
        if c == 65 { key(119); }
        else if c == 66 { key(115); }
        else if c == 67 { key(100); }
        else if c == 68 { key(97); }
        return 0;
    }
    if c == 27 { escape_state = 1; } else { key(c); }
    return 0;
}

fn paint(value, ghost) {
    if ghost { ansi("[90m"); text("::"); ansi("[0m"); return 0; }
    if !value { text("  "); return 0; }
    if value == 1 { ansi("[46m"); }
    else if value == 2 { ansi("[43m"); }
    else if value == 3 { ansi("[45m"); }
    else if value == 4 { ansi("[42m"); }
    else if value == 5 { ansi("[41m"); }
    else if value == 6 { ansi("[44m"); }
    else { ansi("[48;5;208m"); }
    text("  "); ansi("[0m");
    return 0;
}

fn covers(x, y, px, py, mask) {
    let dx = x - px;
    let dy = y - py;
    if dx < 0 || dx >= 4 || dy < 0 || dy >= 4 { return 0; }
    return (mask & (1 << (dy * 4 + dx))) != 0;
}

fn render() {
    if syscall(16, 1, 0x5413, window_size, 0, 0, 0) < 0 { running = 0; return 0; }
    let rows = load8(window_size) + (load8(window_size + 1) << 8);
    let columns = load8(window_size + 2) + (load8(window_size + 3) << 8);
    let was_small = small_terminal;
    small_terminal = rows < 24 || columns < 58;
    ansi("[2J"); cursor(1, 1);
    if small_terminal {
        text("TETRIS: enlarge to 58 x 24. Q quits."); flush(); return 0;
    }
    if was_small { next_fall = now_ms() + delay(); }
    ansi("[1;36m"); text("FLEXSCRIPT TETRIS"); ansi("[0m");
    cursor(2, 1); text("+--------------------+");
    let shadow = ghost_y();
    let mask = shape(piece, rotation);
    let y = 0;
    while y < 20 {
        cursor(y + 3, 1); text("|");
        let x = 0;
        while x < 10 {
            let value = cell(x, y);
            let ghost = 0;
            if !game_over && covers(x, y, piece_x, piece_y, mask) { value = piece + 1; }
            else if !value && !game_over && covers(x, y, piece_x, shadow, mask) { ghost = 1; }
            paint(value, ghost); x = x + 1;
        }
        text("|"); y = y + 1;
    }
    cursor(23, 1); text("+--------------------+");
    cursor(24, 1); text("Good luck!");
    cursor(2, 27); text("SCORE  "); number(score);
    cursor(3, 27); text("LINES  "); number(lines);
    cursor(4, 27); text("LEVEL  "); number(level);
    cursor(6, 27); text("NEXT");
    y = 0;
    while y < 4 {
        cursor(y + 7, 27);
        let x = 0;
        while x < 4 {
            let value = 0;
            if shape(preview, 0) & (1 << (y * 4 + x)) { value = preview + 1; }
            paint(value, 0); x = x + 1;
        }
        y = y + 1;
    }
    cursor(12, 27); text("Arrows/A,D Move");
    cursor(13, 27); text("W / Up     Rotate clockwise");
    cursor(14, 27); text("Z          Rotate back");
    cursor(15, 27); text("S / Down   Soft drop");
    cursor(16, 27); text("Space      Hard drop");
    cursor(17, 27); text("P          Pause");
    cursor(18, 27); text("R          Restart");
    cursor(19, 27); text("Q / Ctrl-C Quit");
    cursor(21, 27);
    if game_over { ansi("[1;31m"); text("GAME OVER - R to restart"); }
    else if paused { ansi("[1;33m"); text("PAUSED - P to resume"); }
    else { ansi("[90m"); text(":: marks the landing spot"); }
    ansi("[0m"); dirty = 0; flush();
    return 0;
}

fn setup_terminal() {
    if syscall(16, 0, 0x5401, old_term, 0, 0, 0) < 0 { return 0; }
    if syscall(16, 1, 0x5413, window_size, 0, 0, 0) < 0 { return 0; }
    let i = 0;
    while i < 36 { store8(raw_term + i, load8(old_term + i)); i = i + 1; }
    store64(raw_term, load64(raw_term) & ~1378);
    store64(raw_term + 12, load64(raw_term + 12) & ~32843);
    store8(raw_term + 22, 0); store8(raw_term + 23, 0); // VTIME, VMIN
    // Read termination signals through poll, so cleanup runs before exit.
    store64(signal_mask, 0x5007); // HUP, INT, QUIT, PIPE, TERM
    if syscall(14, 0, signal_mask, old_mask, 8, 0, 0) < 0 { return 0; }
    signal_fd = syscall(289, -1, signal_mask, 8, 0x80800, 0, 0);
    if signal_fd < 0 {
        syscall(14, 2, old_mask, 0, 8, 0, 0); return 0;
    }
    if syscall(16, 0, 0x5402, raw_term, 0, 0, 0) < 0 {
        syscall(3, signal_fd, 0, 0, 0, 0, 0);
        syscall(14, 2, old_mask, 0, 8, 0, 0); return 0;
    }
    terminal_active = 1;
    ansi("[?1049h"); ansi("[?25l"); flush();
    store64(poll_buffer, 1 << 32);
    store64(poll_buffer + 8, signal_fd | (1 << 32));
    return 1;
}

fn cleanup() {
    if terminal_active {
        syscall(16, 0, 0x5402, old_term, 0, 0, 0);
        ansi("[0m"); ansi("[?25h"); ansi("[?1049l"); flush();
        // Consume pending signals before restoring their default disposition.
        let pending = syscall(0, signal_fd, input_buffer, 256, 0, 0, 0);
        while pending > 0 { pending = syscall(0, signal_fd, input_buffer, 256, 0, 0, 0); }
        syscall(3, signal_fd, 0, 0, 0, 0, 0);
        syscall(14, 2, old_mask, 0, 8, 0, 0); terminal_active = 0;
    }
    return 0;
}

fn initialize() {
    board = alloc(200); shapes = alloc(224); bag = alloc(7);
    frame = alloc(16384); clock_buffer = alloc(16); number_buffer = alloc(32);
    input_buffer = alloc(256); old_term = alloc(36); raw_term = alloc(36);
    window_size = alloc(8); signal_mask = alloc(8); old_mask = alloc(8);
    poll_buffer = alloc(16);
    if board < 0 || shapes < 0 || bag < 0 || frame < 0 || clock_buffer < 0
        || number_buffer < 0 || input_buffer < 0 || old_term < 0 || raw_term < 0
        || window_size < 0 || signal_mask < 0 || old_mask < 0 || poll_buffer < 0 { return 0; }
    initialize_shapes();
    random_state = now_ms() & 0xffffffff;
    if syscall(318, input_buffer, 4, 0, 0, 0, 0) == 4 {
        random_state = load64(input_buffer) & 0xffffffff;
    }
    if !random_state { random_state = 1; }
    return 1;
}

fn check(condition, message) {
    checks = checks + 1;
    if !condition {
        failures = failures + 1; text("FAIL: "); text(message); text("\n"); flush();
    }
    return 0;
}

fn fill_row(y) {
    let x = 0;
    while x < 10 { set_cell(x, y, 1); x = x + 1; }
    return 0;
}

fn self_test() {
    random_state = 1234567;
    let which = 0;
    while which < 7 {
        let r = 0;
        while r < 4 {
            let mask = shape(which, r);
            let count = 0;
            let i = 0;
            while i < 16 { if mask & (1 << i) { count = count + 1; } i = i + 1; }
            check(count == 4, "every rotation has four cells"); r = r + 1;
        }
        which = which + 1;
    }
    let round = 0;
    while round < 20 {
        bag_index = 7;
        let seen = 0;
        let i = 0;
        while i < 7 { seen = seen | (1 << next_piece()); i = i + 1; }
        check(seen == 127, "seven-bag contains every piece"); round = round + 1;
    }
    restart(); clear_board(); piece = 0; rotation = 0; piece_x = 3; piece_y = 0;
    check(fits(0, 0, 0), "I fits left edge");
    check(!fits(-1, 0, 0), "left wall collision");
    check(!fits(7, 0, 0), "right wall collision");
    check(!fits(3, 19, 0), "floor collision");
    set_cell(3, 1, 2); check(!fits(3, 0, 0), "locked block collision");
    clear_board(); check(ghost_y() == 18 && piece_y == 0, "ghost projection is read-only");
    piece_y = 3; let before = score;
    soft_drop(); check(piece_y == 4 && score == before + 1, "soft drop scoring");
    clear_board(); piece = 0; piece_x = 3; piece_y = 0; rotation = 0; score = 0;
    hard_drop();
    check(score == 36, "hard drop scores distance");
    check(cell(3, 19) == 1 && cell(6, 19) == 1, "hard drop locks piece");
    check(piece_y == 0, "lock spawns next piece");
    let n = 1;
    while n <= 4 {
        clear_board(); score = 0; lines = 0; level = 1;
        let i = 0;
        while i < n { fill_row(19 - i); i = i + 1; }
        set_cell(2, 19 - n, 7);
        check(clear_lines() == n, "consecutive line clear count");
        check(cell(2, 19) == 7, "line compaction preserves block");
        let points = 100;
        if n == 2 { points = 300; } else if n == 3 { points = 500; }
        else if n == 4 { points = 800; }
        check(score == points && lines == n, "line clear score"); n = n + 1;
    }
    clear_board(); score = 0; lines = 9; level = 1;
    fill_row(19); check(clear_lines() == 1 && level == 2 && lines == 10, "level progression");
    check(delay() == 735, "level increases gravity speed");
    level = 50; check(delay() == 80, "gravity minimum interval");
    clear_board(); fill_row(19); fill_row(17); set_cell(1, 18, 4);
    check(clear_lines() == 2 && cell(1, 19) == 4, "nonconsecutive line compaction");
    restart(); piece = 0; rotation = 1; piece_x = -2; piece_y = 5;
    check(fits(piece_x, piece_y, rotation), "vertical I at left wall");
    check(rotate(1) && fits(piece_x, piece_y, rotation) && piece_x == 0, "rotation wall kick");
    restart(); let x = piece_x; let y = piece_y;
    key(112); key(97); key(32); tick(next_fall + 10000);
    check(paused && piece_x == x && piece_y == y && score == 0, "pause freezes controls and gravity");
    key(112); tick(next_fall);
    check(!paused && piece_y == y + 1, "resume gravity");
    small_terminal = 1; y = piece_y; tick(next_fall + 10000); key(32);
    check(piece_y == y, "small terminal freezes game"); small_terminal = 0;
    escape_state = 0; x = piece_x; input(27); input(91); input(68);
    check(piece_x == x - 1, "split arrow-key sequence");
    input(27); input(79); input(67);
    check(piece_x == x, "application arrow-key sequence");
    clear_board(); fill_row(0); fill_row(1); preview = 2; game_over = 0; spawn();
    check(game_over, "blocked spawn is game over");
    key(114); check(!game_over && score == 0 && lines == 0 && level == 1, "restart resets game");
    clear_board(); piece = 1; piece_x = 3; piece_y = -1; rotation = 0; game_over = 0;
    lock_piece(); check(game_over && cell(4, 0) == 0, "top-out does not partially write piece");
    running = 1; key(3); check(!running, "Ctrl-C quits");
    text("Tetris self-test: "); number(checks); text(" checks, "); number(failures); text(" failures\n"); flush();
    return failures != 0;
}

fn main(argc, argv) {
    if !initialize() { return 1; }
    if argc == 2 {
        let arg = load64(argv + 8);
        if equal(arg, "--self-test") { return self_test(); }
        if equal(arg, "--help") {
            text("Flexscript Tetris - native Linux x86-64 terminal game\n");
            text("Run in a terminal (58 columns x 24 rows or larger).\n");
            text("A/D or Left/Right: move; W/Up: rotate; Z: rotate back\n");
            text("S/Down: soft drop; Space: hard drop; P: pause; R: restart; Q/Ctrl-C: quit\n");
            text("--self-test runs deterministic game tests without a terminal.\n"); flush(); return 0;
        }
    }
    if argc != 1 { text("Usage: tetris [--help | --self-test]\n"); flush(); return 1; }
    if !setup_terminal() {
        text("Tetris needs an interactive terminal. Run ./build/tetris in your terminal.\n");
        flush(); return 1;
    }
    restart(); let last_frame = 0;
    while running {
        let now = now_ms(); tick(now);
        if dirty || now - last_frame >= 100 { render(); last_frame = now; }
        let ready = syscall(7, poll_buffer, 2, 30, 0, 0, 0);
        if ready < 0 && ready != -4 { running = 0; }
        if load8(poll_buffer + 14) & 1 { running = 0; }
        if load8(poll_buffer + 6) & 1 {
            let n = syscall(0, 0, input_buffer, 256, 0, 0, 0);
            if n < 0 && n != -4 { running = 0; }
            let i = 0;
            while i < n && running { input(load8(input_buffer + i)); i = i + 1; }
        }
        if load8(poll_buffer + 6) & 56 { running = 0; }
    }
    cleanup(); return 0;
}
