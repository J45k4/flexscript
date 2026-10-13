# Buffered native word output

Native FIR programs can opt into a 64 KiB output buffer:

```sh
flexscript --word-io buffered program.seta -o program
```

Without this option, `write_word` retains the original immediate eight-byte
Linux write. `--word-io unbuffered` explicitly selects that default. Wasm, IR
output, bare-metal and ordinary Flexscript compilation do not accept buffering.

The buffered device flushes when full, before every `read_word`, and when `main`
returns. Thus an interactive program can write a response and wait for its next
request without leaving the response buffered. Programs that require immediate
output while continuing computation should use the default device.

Both devices retry interrupted and short writes. A failed buffered flush latches
the device failure: later writes and input return -1, and a failed final flush
exits with status 1. Successful `write_word` calls return their original value;
for buffering this means accepted into the buffer, rather than already delivered.
The wire format remains eight little-endian bytes per word.

`compiler/word-io.flex` emits the device routines. The native FIR lowering calls
them; the compiler's entry stub preserves `main`'s status while flushing at exit.
This changes neither VM execution nor Wasm device semantics.

Run independent Linux device checks from the repository root:

```sh
python3 tests/word-io/check.py /absolute/path/to/flex
# Optional old compiler checks unchanged default native and Wasm bytes:
python3 tests/word-io/check.py /path/to/flex --baseline /path/to/previous-flex
```

The test traces only its own child processes to force EINTR and actual partial
kernel reads/writes. It also checks request/reply flushing, buffer boundaries,
signed word values, final flushes, device errors and unsupported target rejection.
The fault-injection portion requires permission to trace owned child processes.
