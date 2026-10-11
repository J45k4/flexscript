// Opt-in native FIR output device. Buffer only protocol words; flush before
// every input word and on main return, so request/reply programs cannot deadlock.
// Default compilation retains immediate, unbuffered word I/O.
global word_io_buffered=0;
global word_io_exit_call=0;
global word_io_count=0;
global word_io_flush=0;
global word_io_write=0;
fn word_io_call(target) {
    emit(232);emit32(target-output_size-4);return 0;
}
fn word_io_exit() {
    if !word_io_buffered {return 0;}
    emit(80); // preserve main's exit status
    emit(232);word_io_exit_call=output_size;emit32(0);
    test_rax();let success=jump(132);
    emit(72);emit(199);emit(4);emit(36);emit32(1); // failed final flush => exit 1
    patch_jump(success);emit(88);return 0;
}
fn word_io_native() {
    if !word_io_buffered {return 0;}
    word_io_count=4194304+output_size;
    let i=0;while i<65544 {emit(0);i=i+1;}
    word_io_flush=output_size;
    patch32(word_io_exit_call,word_io_flush-word_io_exit_call-4);
    // r8 = count address, r9 = payload cursor, r10 = bytes remaining.
    emit(73);emit(184);emit64(word_io_count);
    emit(73);emit(185);emit64(word_io_count+8);
    emit(77);emit(139);emit(16);
    emit(77);emit(133);emit(210);let latched=jump(136);let empty=jump(132);
    let loop=output_size;
    emit(184);emit32(1);emit(191);emit32(1);
    emit(76);emit(137);emit(206);emit(76);emit(137);emit(210);emit(15);emit(5);
    // Retry EINTR and short writes. A failed device stays failed, preventing
    // subsequent writes from overrunning a full or partially flushed buffer.
    emit(72);emit(131);emit(248);emit(252);let retry=jump(132);patch32(retry,loop-retry-4);
    test_rax();let failed=jump(142);
    emit(73);emit(1);emit(193);emit(73);emit(41);emit(194);
    let more=jump(133);patch32(more,loop-more-4);
    emit(73);emit(199);emit(0);emit32(0);
    patch_jump(empty);immediate(0);emit(195);
    patch_jump(failed);emit(73);emit(199);emit(0);emit32(-1);
    patch_jump(latched);immediate(-1);emit(195);
    word_io_write=output_size;
    emit(80); // preserve write_word's original value
    emit(73);emit(184);emit64(word_io_count);
    emit(73);emit(139);emit(8); // rcx = used bytes
    emit(72);emit(133);emit(201);let bad=jump(136);
    emit(73);emit(185);emit64(word_io_count+8);
    emit(73);emit(137);emit(4);emit(9); // [r9 + rcx] = rax
    emit(72);emit(131);emit(193);emit(8);
    emit(73);emit(137);emit(8);
    emit(72);emit(129);emit(249);emit32(65536);let room=jump(133);
    word_io_call(word_io_flush);test_rax();let error=jump(133);
    patch_jump(room);emit(88);emit(195);
    patch_jump(bad);patch_jump(error);emit(90);immediate(-1);emit(195);
    return 0;
}
