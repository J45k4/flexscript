# Terminal Tetris

`examples/tetris.flex` is a complete playable Tetris game written in Flexscript
0.0.1. The published native compiler builds it directly into an executable.
Linux x86-64 and an ANSI terminal at least 58 columns by 24 rows are required.

From the project root, using the downloaded 0.0.1 compiler:

```sh
mkdir -p build
build/downloaded/flexscript-0.0.1-linux-x86_64 examples/tetris.flex -o build/tetris
./build/tetris
```

If your compiler is elsewhere, substitute its path in the compilation command.
The generated game binary needs no compiler, Rust, Python, or libc to run.

| Key | Action |
| --- | --- |
| Left / Right or A / D | Move |
| Up or W | Rotate clockwise |
| Z | Rotate counterclockwise |
| Down or S | Soft drop |
| Space | Hard drop |
| P | Pause / resume |
| R | Restart, including after game over |
| Q or Ctrl-C | Quit |

Features: seven tetrominoes, shuffled seven-piece bags, next-piece preview,
landing ghost, rotation with basic wall/floor kicks, line clearing, scoring,
increasing gravity, pause, and restart. The playfield is 10 by 20 cells.

Line scores are 100 / 300 / 500 / 800 times the current level for one / two /
three / four lines. Soft drop earns one point per cell; hard drop earns two.
Every ten lines increases the level. Rotation uses simple kicks, not the full
official SRS rules. There is no hold piece or lock delay in this version.

The game uses an alternate screen and restores terminal settings and cursor
visibility on normal quit, Ctrl-C, and handled termination signals. A terminal
that becomes too small pauses gameplay until enlarged again.

## Verification

Run the game's deterministic rules tests without a terminal:

```sh
./build/tetris --self-test
```

Compile and run both the game rules and pseudo-terminal integration tests:

Build `build/tools` once using the [Flexscript tooling instructions](bootstrapping.md).

```sh
build/tools/test-tetris --compiler /path/to/flexscript
```

The integration tests exercise keyboard polling, split arrow sequences,
pause/resume, drops, restart, resize, and exact terminal restoration on quit and
signals. Terminal I/O follows the Linux kernel termios/ioctl ABI and the
[Linux termios](https://man7.org/linux/man-pages/man3/termios.3.html) and
[signalfd](https://man7.org/linux/man-pages/man2/signalfd.2.html) interfaces.
