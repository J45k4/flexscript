// Rust stage-0 compiler for the Flexscript 0.0.1 core.
// The frontend and native backend are a mechanical Rust port of compiler/main.flex.
// Cargo builds this standalone source; no generator or Flexscript binary is needed.
#![allow(
    unused_mut,
    unused_variables,
    dead_code,
    unreachable_code,
    unused_parens,
    unused_assignments,
    non_upper_case_globals
)]
use std::ffi::CString;
unsafe extern "C" {
    #[link_name = "syscall"]
    fn libc_syscall(number: i64, ...) -> i64;
    fn __errno_location() -> *mut i32;
}
fn word(b: bool) -> i64 {
    if b {
        1
    } else {
        0
    }
}
fn truth(v: i64) -> bool {
    v != 0
}
fn divide(a: i64, b: i64) -> i64 {
    a.checked_div(b).expect("integer division trap")
}
fn remainder(a: i64, b: i64) -> i64 {
    a.checked_rem(b).expect("integer remainder trap")
}
unsafe fn raw_syscall(n: i64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64) -> i64 {
    let result = libc_syscall(n, a, b, c, d, e, f);
    if result == -1 {
        -(*__errno_location() as i64)
    } else {
        result
    }
}
unsafe fn alloc(size: i64) -> i64 {
    raw_syscall(9, 0, size, 3, 34, -1, 0)
}
unsafe fn load8(address: i64) -> i64 {
    *(address as *const u8) as i64
}
unsafe fn load64(address: i64) -> i64 {
    (address as *const i64).read_unaligned()
}
unsafe fn store8(address: i64, value: i64) -> i64 {
    *(address as *mut u8) = value as u8;
    value
}
unsafe fn store64(address: i64, value: i64) -> i64 {
    (address as *mut i64).write_unaligned(value);
    value
}
fn main() {
    let strings: Vec<CString> = std::env::args_os()
        .map(|s| {
            use std::os::unix::ffi::OsStrExt;
            CString::new(s.as_os_str().as_bytes()).expect("NUL in argument")
        })
        .collect();
    let mut argv: Vec<i64> = strings.iter().map(|s| s.as_ptr() as i64).collect();
    argv.push(0);
    let status = unsafe { fs_main(strings.len() as i64, argv.as_ptr() as i64) };
    std::process::exit(status as i32);
}

static mut g_source: i64 = (0u64 as i64);

static mut g_source_size: i64 = (0u64 as i64);

static mut g_source_path: i64 = (0u64 as i64);

static mut g_pos: i64 = (0u64 as i64);

static mut g_token: i64 = (0u64 as i64);

static mut g_token_start: i64 = (0u64 as i64);

static mut g_token_size: i64 = (0u64 as i64);

static mut g_token_value: i64 = (0u64 as i64);

static mut g_output: i64 = (0u64 as i64);

static mut g_output_size: i64 = (0u64 as i64);

static mut g_globals: i64 = (0u64 as i64);

static mut g_global_count: i64 = (0u64 as i64);

static mut g_functions: i64 = (0u64 as i64);

static mut g_function_count: i64 = (0u64 as i64);

static mut g_locals: i64 = (0u64 as i64);

static mut g_local_count: i64 = (0u64 as i64);

static mut g_slots: i64 = (0u64 as i64);

static mut g_depth: i64 = (0u64 as i64);

static mut g_nesting: i64 = (0u64 as i64);

static mut g_conditional_depth: i64 = (0u64 as i64);

static mut g_calls: i64 = (0u64 as i64);

static mut g_call_count: i64 = (0u64 as i64);

unsafe fn fs_length(mut v_text: i64) -> i64 {
    let mut v_n: i64 = (0u64 as i64);
    while ((load8((v_text).wrapping_add(v_n))) != (0u64 as i64)) {
        v_n = (v_n).wrapping_add((1u64 as i64));
    }
    return v_n;

    0
}

unsafe fn fs_write_all(mut v_fd: i64, mut v_bytes: i64, mut v_size: i64) -> i64 {
    while ((v_size) > (0u64 as i64)) {
        let mut v_n: i64 = raw_syscall(
            (1u64 as i64),
            v_fd,
            v_bytes,
            v_size,
            (0u64 as i64),
            (0u64 as i64),
            (0u64 as i64),
        );
        if ((v_n) == ((4u64 as i64).wrapping_neg())) {
            v_n = (0u64 as i64);
        } else {
            if ((v_n) <= (0u64 as i64)) {
                return (0u64 as i64);
            }
        }
        v_bytes = (v_bytes).wrapping_add(v_n);
        v_size = (v_size).wrapping_sub(v_n);
    }
    return (1u64 as i64);

    0
}

unsafe fn fs_print(mut v_fd: i64, mut v_text: i64) -> i64 {
    return fs_write_all(v_fd, v_text, fs_length(v_text));

    0
}

unsafe fn fs_print_number(mut v_n: i64) -> i64 {
    let mut v_buf: i64 = alloc((32u64 as i64));
    let mut v_i: i64 = (31u64 as i64);
    store8((v_buf).wrapping_add(v_i), (0u64 as i64));
    while ((v_n) >= (10u64 as i64)) {
        v_i = (v_i).wrapping_sub((1u64 as i64));
        store8(
            (v_buf).wrapping_add(v_i),
            (48u64 as i64).wrapping_add(remainder(v_n, (10u64 as i64))),
        );
        v_n = divide(v_n, (10u64 as i64));
    }
    v_i = (v_i).wrapping_sub((1u64 as i64));
    store8((v_buf).wrapping_add(v_i), (48u64 as i64).wrapping_add(v_n));
    fs_print((2u64 as i64), (v_buf).wrapping_add(v_i));
    return (0u64 as i64);

    0
}

unsafe fn fs_fail(mut v_message: i64) -> i64 {
    fs_print((2u64 as i64), g_source_path);
    fs_print((2u64 as i64), (b":\0".as_ptr() as i64));
    let mut v_i: i64 = (0u64 as i64);
    let mut v_line: i64 = (1u64 as i64);
    let mut v_column: i64 = (1u64 as i64);
    while (((v_i) < (g_token_start)) && ((v_i) < (g_source_size))) {
        if ((load8((g_source).wrapping_add(v_i))) == (10u64 as i64)) {
            v_line = (v_line).wrapping_add((1u64 as i64));
            v_column = (1u64 as i64);
        } else {
            v_column = (v_column).wrapping_add((1u64 as i64));
        }
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    fs_print_number(v_line);
    fs_print((2u64 as i64), (b":\0".as_ptr() as i64));
    fs_print_number(v_column);
    fs_print((2u64 as i64), (b": error: \0".as_ptr() as i64));
    fs_print((2u64 as i64), v_message);
    fs_print((2u64 as i64), (b"\n\0".as_ptr() as i64));
    raw_syscall(
        (60u64 as i64),
        (1u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    );
    return (0u64 as i64);

    0
}

unsafe fn fs_equal(mut v_a: i64, mut v_an: i64, mut v_b: i64, mut v_bn: i64) -> i64 {
    if ((v_an) != (v_bn)) {
        return (0u64 as i64);
    }
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (v_an)) {
        if ((load8((v_a).wrapping_add(v_i))) != (load8((v_b).wrapping_add(v_i)))) {
            return (0u64 as i64);
        }
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    return (1u64 as i64);

    0
}

unsafe fn fs_is(mut v_text: i64) -> i64 {
    return fs_equal(
        (g_source).wrapping_add(g_token_start),
        g_token_size,
        v_text,
        fs_length(v_text),
    );

    0
}

unsafe fn fs_letter(mut v_c: i64) -> i64 {
    return word(
        (((((v_c) >= (65u64 as i64)) && ((v_c) <= (90u64 as i64)))
            || (((v_c) >= (97u64 as i64)) && ((v_c) <= (122u64 as i64))))
            || ((v_c) == (95u64 as i64))),
    );

    0
}

unsafe fn fs_digit(mut v_c: i64) -> i64 {
    return word((((v_c) >= (48u64 as i64)) && ((v_c) <= (57u64 as i64))));

    0
}

unsafe fn fs_reserved(mut v_name: i64, mut v_size: i64) -> i64 {
    return word(
        (((((((((((((fs_equal(
            v_name,
            v_size,
            (b"fn\0".as_ptr() as i64),
            (2u64 as i64),
        ) != 0)
            || (fs_equal(v_name, v_size, (b"global\0".as_ptr() as i64), (6u64 as i64))
                != 0))
            || (fs_equal(v_name, v_size, (b"let\0".as_ptr() as i64), (3u64 as i64))
                != 0))
            || (fs_equal(v_name, v_size, (b"if\0".as_ptr() as i64), (2u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"else\0".as_ptr() as i64), (4u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"while\0".as_ptr() as i64), (5u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"return\0".as_ptr() as i64), (6u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"load8\0".as_ptr() as i64), (5u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"load64\0".as_ptr() as i64), (6u64 as i64)) != 0))
            || (fs_equal(v_name, v_size, (b"store8\0".as_ptr() as i64), (6u64 as i64)) != 0))
            || (fs_equal(
                v_name,
                v_size,
                (b"store64\0".as_ptr() as i64),
                (7u64 as i64),
            ) != 0))
            || (fs_equal(v_name, v_size, (b"alloc\0".as_ptr() as i64), (5u64 as i64)) != 0))
            || (fs_equal(
                v_name,
                v_size,
                (b"syscall\0".as_ptr() as i64),
                (7u64 as i64),
            ) != 0)),
    );

    0
}

unsafe fn fs_next() -> i64 {
    let mut v_scanning: i64 = (1u64 as i64);
    while (v_scanning != 0) {
        while (((g_pos) < (g_source_size))
            && (((((load8((g_source).wrapping_add(g_pos))) == (32u64 as i64))
                || ((load8((g_source).wrapping_add(g_pos))) == (9u64 as i64)))
                || ((load8((g_source).wrapping_add(g_pos))) == (10u64 as i64)))
                || ((load8((g_source).wrapping_add(g_pos))) == (13u64 as i64))))
        {
            g_pos = (g_pos).wrapping_add((1u64 as i64));
        }
        if (((((g_pos).wrapping_add((1u64 as i64))) < (g_source_size))
            && ((load8((g_source).wrapping_add(g_pos))) == (47u64 as i64)))
            && ((load8(((g_source).wrapping_add(g_pos)).wrapping_add((1u64 as i64))))
                == (47u64 as i64)))
        {
            while (((g_pos) < (g_source_size))
                && ((load8((g_source).wrapping_add(g_pos))) != (10u64 as i64)))
            {
                g_pos = (g_pos).wrapping_add((1u64 as i64));
            }
        } else {
            v_scanning = (0u64 as i64);
        }
    }
    g_token_start = g_pos;
    g_token_size = (0u64 as i64);
    g_token_value = (0u64 as i64);
    if ((g_pos) == (g_source_size)) {
        g_token = (0u64 as i64);
        return (0u64 as i64);
    }
    let mut v_c: i64 = load8((g_source).wrapping_add(g_pos));
    g_pos = (g_pos).wrapping_add((1u64 as i64));
    if (fs_letter(v_c) != 0) {
        while (((g_pos) < (g_source_size))
            && ((fs_letter(load8((g_source).wrapping_add(g_pos))) != 0)
                || (fs_digit(load8((g_source).wrapping_add(g_pos))) != 0)))
        {
            g_pos = (g_pos).wrapping_add((1u64 as i64));
        }
        g_token = (256u64 as i64);
    } else if (fs_digit(v_c) != 0) {
        g_token = (257u64 as i64);
        let mut v_base: i64 = (10u64 as i64);
        g_token_value = (v_c).wrapping_sub((48u64 as i64));
        if ((((v_c) == (48u64 as i64)) && ((g_pos) < (g_source_size)))
            && ((load8((g_source).wrapping_add(g_pos))) == (120u64 as i64)))
        {
            v_base = (16u64 as i64);
            g_pos = (g_pos).wrapping_add((1u64 as i64));
            if ((g_pos) == (g_source_size)) {
                fs_fail((b"expected hexadecimal digits\0".as_ptr() as i64));
            }
            g_token_value = (0u64 as i64);
        }
        let mut v_count: i64 = (0u64 as i64);
        let mut v_done: i64 = (0u64 as i64);
        while (((g_pos) < (g_source_size)) && !(v_done != 0)) {
            let mut v_d: i64 = load8((g_source).wrapping_add(g_pos));
            let mut v_value: i64 = (1u64 as i64).wrapping_neg();
            if (fs_digit(v_d) != 0) {
                v_value = (v_d).wrapping_sub((48u64 as i64));
            } else if (((v_d) >= (97u64 as i64)) && ((v_d) <= (102u64 as i64))) {
                v_value = (v_d).wrapping_sub((87u64 as i64));
            } else if (((v_d) >= (65u64 as i64)) && ((v_d) <= (70u64 as i64))) {
                v_value = (v_d).wrapping_sub((55u64 as i64));
            }
            if (((v_value) < (0u64 as i64)) || ((v_value) >= (v_base))) {
                v_done = (1u64 as i64);
            } else {
                if (((v_base) == (10u64 as i64))
                    && ((g_token_value)
                        > (divide(
                            (9223372036854775807u64 as i64).wrapping_sub(v_value),
                            (10u64 as i64),
                        ))))
                {
                    fs_fail((b"decimal integer out of range\0".as_ptr() as i64));
                }
                if (((v_base) == (16u64 as i64))
                    && (((g_token_value) < (0u64 as i64))
                        || ((g_token_value) > (1152921504606846975u64 as i64))))
                {
                    fs_fail((b"hexadecimal integer out of range\0".as_ptr() as i64));
                }
                g_token_value = ((g_token_value).wrapping_mul(v_base)).wrapping_add(v_value);
                v_count = (v_count).wrapping_add((1u64 as i64));
                g_pos = (g_pos).wrapping_add((1u64 as i64));
            }
        }
        if (((v_base) == (16u64 as i64)) && ((v_count) == (0u64 as i64))) {
            fs_fail((b"expected hexadecimal digits\0".as_ptr() as i64));
        }
        if (((g_pos) < (g_source_size)) && (fs_letter(load8((g_source).wrapping_add(g_pos))) != 0))
        {
            fs_fail((b"invalid integer literal\0".as_ptr() as i64));
        }
    } else if ((v_c) == (34u64 as i64)) {
        g_token = (258u64 as i64);
        let mut v_done: i64 = (0u64 as i64);
        while (((g_pos) < (g_source_size)) && !(v_done != 0)) {
            let mut v_d: i64 = load8((g_source).wrapping_add(g_pos));
            g_pos = (g_pos).wrapping_add((1u64 as i64));
            if ((v_d) == (34u64 as i64)) {
                v_done = (1u64 as i64);
            } else if ((v_d) == (92u64 as i64)) {
                if ((g_pos) == (g_source_size)) {
                    fs_fail((b"unterminated string\0".as_ptr() as i64));
                }
                let mut v_escaped: i64 = load8((g_source).wrapping_add(g_pos));
                if (((((((v_escaped) != (110u64 as i64)) && ((v_escaped) != (114u64 as i64)))
                    && ((v_escaped) != (116u64 as i64)))
                    && ((v_escaped) != (48u64 as i64)))
                    && ((v_escaped) != (92u64 as i64)))
                    && ((v_escaped) != (34u64 as i64)))
                {
                    fs_fail((b"invalid string escape\0".as_ptr() as i64));
                }
                g_pos = (g_pos).wrapping_add((1u64 as i64));
            } else if ((((v_d) == (10u64 as i64)) || ((v_d) == (13u64 as i64)))
                || ((v_d) == (0u64 as i64)))
            {
                fs_fail((b"invalid byte in string\0".as_ptr() as i64));
            }
        }
        if !(v_done != 0) {
            fs_fail((b"unterminated string\0".as_ptr() as i64));
        }
    } else {
        g_token = v_c;
        if ((g_pos) < (g_source_size)) {
            let mut v_d: i64 = load8((g_source).wrapping_add(g_pos));
            if (((v_c) == (61u64 as i64)) && ((v_d) == (61u64 as i64))) {
                g_token = (259u64 as i64);
            } else if (((v_c) == (33u64 as i64)) && ((v_d) == (61u64 as i64))) {
                g_token = (260u64 as i64);
            } else if (((v_c) == (60u64 as i64)) && ((v_d) == (61u64 as i64))) {
                g_token = (261u64 as i64);
            } else if (((v_c) == (62u64 as i64)) && ((v_d) == (61u64 as i64))) {
                g_token = (262u64 as i64);
            } else if (((v_c) == (38u64 as i64)) && ((v_d) == (38u64 as i64))) {
                g_token = (263u64 as i64);
            } else if (((v_c) == (124u64 as i64)) && ((v_d) == (124u64 as i64))) {
                g_token = (264u64 as i64);
            } else if (((v_c) == (60u64 as i64)) && ((v_d) == (60u64 as i64))) {
                g_token = (265u64 as i64);
            } else if (((v_c) == (62u64 as i64)) && ((v_d) == (62u64 as i64))) {
                g_token = (266u64 as i64);
            }
            if ((g_token) > (258u64 as i64)) {
                g_pos = (g_pos).wrapping_add((1u64 as i64));
            }
        }
        if (((((((((((((((((((((g_token) <= (258u64 as i64))
            && ((v_c) != (123u64 as i64)))
            && ((v_c) != (125u64 as i64)))
            && ((v_c) != (40u64 as i64)))
            && ((v_c) != (41u64 as i64)))
            && ((v_c) != (59u64 as i64)))
            && ((v_c) != (44u64 as i64)))
            && ((v_c) != (61u64 as i64)))
            && ((v_c) != (43u64 as i64)))
            && ((v_c) != (45u64 as i64)))
            && ((v_c) != (42u64 as i64)))
            && ((v_c) != (47u64 as i64)))
            && ((v_c) != (37u64 as i64)))
            && ((v_c) != (60u64 as i64)))
            && ((v_c) != (62u64 as i64)))
            && ((v_c) != (33u64 as i64)))
            && ((v_c) != (126u64 as i64)))
            && ((v_c) != (38u64 as i64)))
            && ((v_c) != (124u64 as i64)))
            && ((v_c) != (94u64 as i64)))
        {
            fs_fail((b"unexpected source byte\0".as_ptr() as i64));
        }
    }
    g_token_size = (g_pos).wrapping_sub(g_token_start);
    return (0u64 as i64);

    0
}

unsafe fn fs_expect(mut v_t: i64) -> i64 {
    if ((g_token) != (v_t)) {
        fs_fail((b"unexpected token\0".as_ptr() as i64));
    }
    fs_next();
    return (0u64 as i64);

    0
}

unsafe fn fs_emit(mut v_b: i64) -> i64 {
    if ((g_output_size) >= (67108864u64 as i64)) {
        fs_fail((b"output exceeds 64 MiB\0".as_ptr() as i64));
    }
    store8((g_output).wrapping_add(g_output_size), v_b);
    g_output_size = (g_output_size).wrapping_add((1u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_emit32(mut v_value: i64) -> i64 {
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (4u64 as i64)) {
        fs_emit((v_value).wrapping_shr(((v_i).wrapping_mul((8u64 as i64))) as u32));
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_emit64(mut v_value: i64) -> i64 {
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (8u64 as i64)) {
        fs_emit((v_value).wrapping_shr(((v_i).wrapping_mul((8u64 as i64))) as u32));
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_patch32(mut v_at: i64, mut v_value: i64) -> i64 {
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (4u64 as i64)) {
        store8(
            ((g_output).wrapping_add(v_at)).wrapping_add(v_i),
            (v_value).wrapping_shr(((v_i).wrapping_mul((8u64 as i64))) as u32),
        );
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_jump(mut v_opcode: i64) -> i64 {
    if ((v_opcode) != (233u64 as i64)) {
        fs_emit((15u64 as i64));
    }
    fs_emit(v_opcode);
    let mut v_at: i64 = g_output_size;
    fs_emit32((0u64 as i64));
    return v_at;

    0
}

unsafe fn fs_patch_jump(mut v_at: i64) -> i64 {
    fs_patch32(
        v_at,
        ((g_output_size).wrapping_sub(v_at)).wrapping_sub((4u64 as i64)),
    );
    return (0u64 as i64);

    0
}

unsafe fn fs_test_rax() -> i64 {
    fs_emit((72u64 as i64));
    fs_emit((133u64 as i64));
    fs_emit((192u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_immediate(mut v_n: i64) -> i64 {
    fs_emit((72u64 as i64));
    fs_emit((184u64 as i64));
    fs_emit64(v_n);
    return (0u64 as i64);

    0
}

unsafe fn fs_epilogue() -> i64 {
    fs_emit((201u64 as i64));
    fs_emit((195u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_find(mut v_table: i64, mut v_count: i64, mut v_name: i64, mut v_size: i64) -> i64 {
    let mut v_i: i64 = (v_count).wrapping_sub((1u64 as i64));
    while ((v_i) >= (0u64 as i64)) {
        let mut v_entry: i64 = (v_table).wrapping_add((v_i).wrapping_mul((32u64 as i64)));
        if (fs_equal(
            load64(v_entry),
            load64((v_entry).wrapping_add((8u64 as i64))),
            v_name,
            v_size,
        ) != 0)
        {
            return v_i;
        }
        v_i = (v_i).wrapping_sub((1u64 as i64));
    }
    return (1u64 as i64).wrapping_neg();

    0
}

unsafe fn fs_declare_local(mut v_name: i64, mut v_size: i64) -> i64 {
    if (((g_local_count) >= (4096u64 as i64)) || ((g_slots) >= (4096u64 as i64))) {
        fs_fail((b"too many locals\0".as_ptr() as i64));
    }
    if (fs_reserved(v_name, v_size) != 0) {
        fs_fail((b"reserved declaration name\0".as_ptr() as i64));
    }
    let mut v_prior: i64 = fs_find(g_locals, g_local_count, v_name, v_size);
    if (((v_prior) >= (0u64 as i64))
        && ((load64(
            ((g_locals).wrapping_add((v_prior).wrapping_mul((32u64 as i64))))
                .wrapping_add((24u64 as i64)),
        )) == (g_depth)))
    {
        fs_fail((b"duplicate local\0".as_ptr() as i64));
    }
    let mut v_entry: i64 = (g_locals).wrapping_add((g_local_count).wrapping_mul((32u64 as i64)));
    store64(v_entry, v_name);
    store64((v_entry).wrapping_add((8u64 as i64)), v_size);
    store64((v_entry).wrapping_add((16u64 as i64)), g_slots);
    store64((v_entry).wrapping_add((24u64 as i64)), g_depth);
    g_local_count = (g_local_count).wrapping_add((1u64 as i64));
    g_slots = (g_slots).wrapping_add((1u64 as i64));
    return (g_slots).wrapping_sub((1u64 as i64));

    0
}

unsafe fn fs_variable(mut v_name: i64, mut v_size: i64, mut v_storing: i64) -> i64 {
    let mut v_index: i64 = fs_find(g_locals, g_local_count, v_name, v_size);
    if ((v_index) >= (0u64 as i64)) {
        fs_emit((72u64 as i64));
        if (v_storing != 0) {
            fs_emit((137u64 as i64));
        } else {
            fs_emit((139u64 as i64));
        }
        fs_emit((133u64 as i64));
        fs_emit32(
            ((8u64 as i64).wrapping_neg()).wrapping_mul(
                (load64(
                    ((g_locals).wrapping_add((v_index).wrapping_mul((32u64 as i64))))
                        .wrapping_add((16u64 as i64)),
                ))
                .wrapping_add((1u64 as i64)),
            ),
        );
    } else {
        v_index = fs_find(g_globals, g_global_count, v_name, v_size);
        if ((v_index) < (0u64 as i64)) {
            fs_fail((b"undefined variable\0".as_ptr() as i64));
        }
        fs_emit((72u64 as i64));
        if (v_storing != 0) {
            fs_emit((137u64 as i64));
        } else {
            fs_emit((139u64 as i64));
        }
        fs_emit((5u64 as i64));
        let mut v_target: i64 = load64(
            ((g_globals).wrapping_add((v_index).wrapping_mul((32u64 as i64))))
                .wrapping_add((16u64 as i64)),
        );
        fs_emit32(((v_target).wrapping_sub(g_output_size)).wrapping_sub((4u64 as i64)));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_precedence(mut v_t: i64) -> i64 {
    if ((v_t) == (264u64 as i64)) {
        return (1u64 as i64);
    }
    if ((v_t) == (263u64 as i64)) {
        return (2u64 as i64);
    }
    if ((v_t) == (124u64 as i64)) {
        return (3u64 as i64);
    }
    if ((v_t) == (94u64 as i64)) {
        return (4u64 as i64);
    }
    if ((v_t) == (38u64 as i64)) {
        return (5u64 as i64);
    }
    if (((v_t) == (259u64 as i64)) || ((v_t) == (260u64 as i64))) {
        return (6u64 as i64);
    }
    if (((((v_t) == (60u64 as i64)) || ((v_t) == (62u64 as i64))) || ((v_t) == (261u64 as i64)))
        || ((v_t) == (262u64 as i64)))
    {
        return (7u64 as i64);
    }
    if (((v_t) == (265u64 as i64)) || ((v_t) == (266u64 as i64))) {
        return (8u64 as i64);
    }
    if (((v_t) == (43u64 as i64)) || ((v_t) == (45u64 as i64))) {
        return (9u64 as i64);
    }
    if ((((v_t) == (42u64 as i64)) || ((v_t) == (47u64 as i64))) || ((v_t) == (37u64 as i64))) {
        return (10u64 as i64);
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_normalize() -> i64 {
    fs_test_rax();
    fs_emit((15u64 as i64));
    fs_emit((149u64 as i64));
    fs_emit((192u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((15u64 as i64));
    fs_emit((182u64 as i64));
    fs_emit((192u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_binary(mut v_op: i64) -> i64 {
    fs_emit((89u64 as i64));
    if ((v_op) == (43u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((1u64 as i64));
        fs_emit((200u64 as i64));
    } else if ((v_op) == (45u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((41u64 as i64));
        fs_emit((193u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((137u64 as i64));
        fs_emit((200u64 as i64));
    } else if ((v_op) == (42u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((15u64 as i64));
        fs_emit((175u64 as i64));
        fs_emit((193u64 as i64));
    } else if (((v_op) == (47u64 as i64)) || ((v_op) == (37u64 as i64))) {
        fs_emit((72u64 as i64));
        fs_emit((137u64 as i64));
        fs_emit((199u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((137u64 as i64));
        fs_emit((200u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((153u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((247u64 as i64));
        fs_emit((255u64 as i64));
        if ((v_op) == (37u64 as i64)) {
            fs_emit((72u64 as i64));
            fs_emit((137u64 as i64));
            fs_emit((208u64 as i64));
        }
    } else if ((v_op) == (38u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((33u64 as i64));
        fs_emit((200u64 as i64));
    } else if ((v_op) == (124u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((9u64 as i64));
        fs_emit((200u64 as i64));
    } else if ((v_op) == (94u64 as i64)) {
        fs_emit((72u64 as i64));
        fs_emit((49u64 as i64));
        fs_emit((200u64 as i64));
    } else if (((v_op) == (265u64 as i64)) || ((v_op) == (266u64 as i64))) {
        fs_emit((72u64 as i64));
        fs_emit((135u64 as i64));
        fs_emit((200u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((211u64 as i64));
        if ((v_op) == (265u64 as i64)) {
            fs_emit((224u64 as i64));
        } else {
            fs_emit((248u64 as i64));
        }
    } else {
        fs_emit((72u64 as i64));
        fs_emit((57u64 as i64));
        fs_emit((193u64 as i64));
        fs_emit((15u64 as i64));
        if ((v_op) == (259u64 as i64)) {
            fs_emit((148u64 as i64));
        } else if ((v_op) == (260u64 as i64)) {
            fs_emit((149u64 as i64));
        } else if ((v_op) == (60u64 as i64)) {
            fs_emit((156u64 as i64));
        } else if ((v_op) == (62u64 as i64)) {
            fs_emit((159u64 as i64));
        } else if ((v_op) == (261u64 as i64)) {
            fs_emit((158u64 as i64));
        } else {
            fs_emit((157u64 as i64));
        }
        fs_emit((192u64 as i64));
        fs_emit((72u64 as i64));
        fs_emit((15u64 as i64));
        fs_emit((182u64 as i64));
        fs_emit((192u64 as i64));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_call(mut v_name: i64, mut v_size: i64) -> i64 {
    fs_expect((40u64 as i64));
    let mut v_count: i64 = (0u64 as i64);
    if ((g_token) != (41u64 as i64)) {
        let mut v_more: i64 = (1u64 as i64);
        while (v_more != 0) {
            fs_expression((1u64 as i64));
            fs_emit((80u64 as i64));
            v_count = (v_count).wrapping_add((1u64 as i64));
            if ((g_token) == (44u64 as i64)) {
                fs_next();
            } else {
                v_more = (0u64 as i64);
            }
        }
    }
    fs_expect((41u64 as i64));
    let mut v_builtin: i64 = (0u64 as i64);
    let mut v_arity: i64 = (0u64 as i64);
    if (fs_equal(v_name, v_size, (b"load8\0".as_ptr() as i64), (5u64 as i64)) != 0) {
        v_builtin = (1u64 as i64);
        v_arity = (1u64 as i64);
    } else if (fs_equal(v_name, v_size, (b"load64\0".as_ptr() as i64), (6u64 as i64)) != 0) {
        v_builtin = (2u64 as i64);
        v_arity = (1u64 as i64);
    } else if (fs_equal(v_name, v_size, (b"store8\0".as_ptr() as i64), (6u64 as i64)) != 0) {
        v_builtin = (3u64 as i64);
        v_arity = (2u64 as i64);
    } else if (fs_equal(
        v_name,
        v_size,
        (b"store64\0".as_ptr() as i64),
        (7u64 as i64),
    ) != 0)
    {
        v_builtin = (4u64 as i64);
        v_arity = (2u64 as i64);
    } else if (fs_equal(v_name, v_size, (b"alloc\0".as_ptr() as i64), (5u64 as i64)) != 0) {
        v_builtin = (5u64 as i64);
        v_arity = (1u64 as i64);
    } else if (fs_equal(
        v_name,
        v_size,
        (b"syscall\0".as_ptr() as i64),
        (7u64 as i64),
    ) != 0)
    {
        v_builtin = (6u64 as i64);
        v_arity = (7u64 as i64);
    }
    if (v_builtin != 0) {
        if ((v_count) != (v_arity)) {
            fs_fail((b"wrong builtin argument count\0".as_ptr() as i64));
        }
        if (((v_builtin) == (1u64 as i64)) || ((v_builtin) == (2u64 as i64))) {
            fs_emit((95u64 as i64));
            fs_emit((72u64 as i64));
            if ((v_builtin) == (1u64 as i64)) {
                fs_emit((15u64 as i64));
                fs_emit((182u64 as i64));
            } else {
                fs_emit((139u64 as i64));
            }
            fs_emit((7u64 as i64));
        } else if (((v_builtin) == (3u64 as i64)) || ((v_builtin) == (4u64 as i64))) {
            fs_emit((88u64 as i64));
            fs_emit((95u64 as i64));
            if ((v_builtin) == (3u64 as i64)) {
                fs_emit((136u64 as i64));
            } else {
                fs_emit((72u64 as i64));
                fs_emit((137u64 as i64));
            }
            fs_emit((7u64 as i64));
        } else if ((v_builtin) == (5u64 as i64)) {
            fs_emit((94u64 as i64));
            fs_emit((49u64 as i64));
            fs_emit((255u64 as i64));
            fs_emit((186u64 as i64));
            fs_emit32((3u64 as i64));
            fs_emit((65u64 as i64));
            fs_emit((186u64 as i64));
            fs_emit32((34u64 as i64));
            fs_emit((73u64 as i64));
            fs_emit((184u64 as i64));
            fs_emit64((1u64 as i64).wrapping_neg());
            fs_emit((69u64 as i64));
            fs_emit((49u64 as i64));
            fs_emit((201u64 as i64));
            fs_emit((184u64 as i64));
            fs_emit32((9u64 as i64));
            fs_emit((15u64 as i64));
            fs_emit((5u64 as i64));
        } else {
            fs_emit((65u64 as i64));
            fs_emit((89u64 as i64));
            fs_emit((65u64 as i64));
            fs_emit((88u64 as i64));
            fs_emit((65u64 as i64));
            fs_emit((90u64 as i64));
            fs_emit((90u64 as i64));
            fs_emit((94u64 as i64));
            fs_emit((95u64 as i64));
            fs_emit((88u64 as i64));
            fs_emit((15u64 as i64));
            fs_emit((5u64 as i64));
        }
    } else {
        if ((g_call_count) >= (65536u64 as i64)) {
            fs_fail((b"too many calls\0".as_ptr() as i64));
        }
        fs_emit((232u64 as i64));
        let mut v_entry: i64 = (g_calls).wrapping_add((g_call_count).wrapping_mul((32u64 as i64)));
        store64(v_entry, v_name);
        store64((v_entry).wrapping_add((8u64 as i64)), v_size);
        store64((v_entry).wrapping_add((16u64 as i64)), g_output_size);
        store64((v_entry).wrapping_add((24u64 as i64)), v_count);
        g_call_count = (g_call_count).wrapping_add((1u64 as i64));
        fs_emit32((0u64 as i64));
        if ((v_count) > (0u64 as i64)) {
            fs_emit((72u64 as i64));
            fs_emit((129u64 as i64));
            fs_emit((196u64 as i64));
            fs_emit32((v_count).wrapping_mul((8u64 as i64)));
        }
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_prefix() -> i64 {
    if ((g_token) == (257u64 as i64)) {
        fs_immediate(g_token_value);
        fs_next();
    } else if ((g_token) == (258u64 as i64)) {
        let mut v_start: i64 = (g_token_start).wrapping_add((1u64 as i64));
        let mut v_end: i64 =
            ((g_token_start).wrapping_add(g_token_size)).wrapping_sub((1u64 as i64));
        let mut v_skip: i64 = fs_jump((233u64 as i64));
        let mut v_address: i64 = g_output_size;
        while ((v_start) < (v_end)) {
            let mut v_c: i64 = load8((g_source).wrapping_add(v_start));
            v_start = (v_start).wrapping_add((1u64 as i64));
            if ((v_c) == (92u64 as i64)) {
                v_c = load8((g_source).wrapping_add(v_start));
                v_start = (v_start).wrapping_add((1u64 as i64));
                if ((v_c) == (110u64 as i64)) {
                    v_c = (10u64 as i64);
                } else if ((v_c) == (114u64 as i64)) {
                    v_c = (13u64 as i64);
                } else if ((v_c) == (116u64 as i64)) {
                    v_c = (9u64 as i64);
                } else if ((v_c) == (48u64 as i64)) {
                    v_c = (0u64 as i64);
                }
            }
            fs_emit(v_c);
        }
        fs_emit((0u64 as i64));
        fs_patch_jump(v_skip);
        fs_emit((72u64 as i64));
        fs_emit((141u64 as i64));
        fs_emit((5u64 as i64));
        fs_emit32(((v_address).wrapping_sub(g_output_size)).wrapping_sub((4u64 as i64)));
        fs_next();
    } else if ((g_token) == (256u64 as i64)) {
        let mut v_name: i64 = (g_source).wrapping_add(g_token_start);
        let mut v_size: i64 = g_token_size;
        fs_next();
        if ((g_token) == (40u64 as i64)) {
            fs_call(v_name, v_size);
        } else {
            fs_variable(v_name, v_size, (0u64 as i64));
        }
    } else if ((g_token) == (40u64 as i64)) {
        fs_next();
        fs_expression((1u64 as i64));
        fs_expect((41u64 as i64));
    } else if ((((g_token) == (45u64 as i64)) || ((g_token) == (33u64 as i64)))
        || ((g_token) == (126u64 as i64)))
    {
        let mut v_op: i64 = g_token;
        fs_next();
        fs_expression((11u64 as i64));
        if ((v_op) == (45u64 as i64)) {
            fs_emit((72u64 as i64));
            fs_emit((247u64 as i64));
            fs_emit((216u64 as i64));
        } else if ((v_op) == (126u64 as i64)) {
            fs_emit((72u64 as i64));
            fs_emit((247u64 as i64));
            fs_emit((208u64 as i64));
        } else {
            fs_test_rax();
            fs_emit((15u64 as i64));
            fs_emit((148u64 as i64));
            fs_emit((192u64 as i64));
            fs_emit((72u64 as i64));
            fs_emit((15u64 as i64));
            fs_emit((182u64 as i64));
            fs_emit((192u64 as i64));
        }
    } else {
        fs_fail((b"expected expression\0".as_ptr() as i64));
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_expression(mut v_minimum: i64) -> i64 {
    g_nesting = (g_nesting).wrapping_add((1u64 as i64));
    if ((g_nesting) > (128u64 as i64)) {
        fs_fail((b"expression nesting limit exceeded\0".as_ptr() as i64));
    }
    fs_prefix();
    while ((fs_precedence(g_token)) >= (v_minimum)) {
        let mut v_op: i64 = g_token;
        let mut v_priority: i64 = fs_precedence(v_op);
        fs_next();
        if (((v_op) == (263u64 as i64)) || ((v_op) == (264u64 as i64))) {
            fs_normalize();
            fs_test_rax();
            let mut v_skip: i64 = (0u64 as i64);
            if ((v_op) == (263u64 as i64)) {
                v_skip = fs_jump((132u64 as i64));
            } else {
                v_skip = fs_jump((133u64 as i64));
            }
            fs_expression((v_priority).wrapping_add((1u64 as i64)));
            fs_normalize();
            fs_patch_jump(v_skip);
        } else {
            fs_emit((80u64 as i64));
            fs_expression((v_priority).wrapping_add((1u64 as i64)));
            fs_binary(v_op);
        }
    }
    g_nesting = (g_nesting).wrapping_sub((1u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_conditional() -> i64 {
    g_conditional_depth = (g_conditional_depth).wrapping_add((1u64 as i64));
    if ((g_conditional_depth) > (128u64 as i64)) {
        fs_fail((b"conditional nesting limit exceeded\0".as_ptr() as i64));
    }
    fs_next();
    fs_expression((1u64 as i64));
    fs_test_rax();
    let mut v_otherwise: i64 = fs_jump((132u64 as i64));
    fs_block();
    if (fs_is((b"else\0".as_ptr() as i64)) != 0) {
        fs_next();
        let mut v_end: i64 = fs_jump((233u64 as i64));
        fs_patch_jump(v_otherwise);
        if (fs_is((b"if\0".as_ptr() as i64)) != 0) {
            fs_conditional();
        } else {
            fs_block();
        }
        fs_patch_jump(v_end);
    } else {
        fs_patch_jump(v_otherwise);
    }
    g_conditional_depth = (g_conditional_depth).wrapping_sub((1u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_statement() -> i64 {
    if (fs_is((b"let\0".as_ptr() as i64)) != 0) {
        fs_next();
        if ((g_token) != (256u64 as i64)) {
            fs_fail((b"expected local name\0".as_ptr() as i64));
        }
        let mut v_name: i64 = (g_source).wrapping_add(g_token_start);
        let mut v_size: i64 = g_token_size;
        fs_next();
        fs_expect((61u64 as i64));
        fs_expression((1u64 as i64));
        fs_expect((59u64 as i64));
        fs_declare_local(v_name, v_size);
        fs_variable(v_name, v_size, (1u64 as i64));
    } else if (fs_is((b"return\0".as_ptr() as i64)) != 0) {
        fs_next();
        fs_expression((1u64 as i64));
        fs_expect((59u64 as i64));
        fs_epilogue();
    } else if (fs_is((b"if\0".as_ptr() as i64)) != 0) {
        fs_conditional();
    } else if (fs_is((b"while\0".as_ptr() as i64)) != 0) {
        fs_next();
        let mut v_start: i64 = g_output_size;
        fs_expression((1u64 as i64));
        fs_test_rax();
        let mut v_end: i64 = fs_jump((132u64 as i64));
        fs_block();
        let mut v_back: i64 = fs_jump((233u64 as i64));
        fs_patch32(
            v_back,
            ((v_start).wrapping_sub(v_back)).wrapping_sub((4u64 as i64)),
        );
        fs_patch_jump(v_end);
    } else if ((g_token) == (123u64 as i64)) {
        fs_block();
    } else {
        let mut v_beginning: i64 = g_token_start;
        let mut v_assignment: i64 = (0u64 as i64);
        if ((g_token) == (256u64 as i64)) {
            let mut v_name: i64 = (g_source).wrapping_add(g_token_start);
            let mut v_size: i64 = g_token_size;
            fs_next();
            if ((g_token) == (61u64 as i64)) {
                fs_next();
                fs_expression((1u64 as i64));
                fs_expect((59u64 as i64));
                fs_variable(v_name, v_size, (1u64 as i64));
                v_assignment = (1u64 as i64);
            }
        }
        if !(v_assignment != 0) {
            g_pos = v_beginning;
            fs_next();
            fs_expression((1u64 as i64));
            fs_expect((59u64 as i64));
        }
    }
    return (0u64 as i64);

    0
}

unsafe fn fs_block() -> i64 {
    g_depth = (g_depth).wrapping_add((1u64 as i64));
    if ((g_depth) > (128u64 as i64)) {
        fs_fail((b"block nesting limit exceeded\0".as_ptr() as i64));
    }
    let mut v_before: i64 = g_local_count;
    fs_expect((123u64 as i64));
    while ((g_token) != (125u64 as i64)) {
        if ((g_token) == (0u64 as i64)) {
            fs_fail((b"unterminated block\0".as_ptr() as i64));
        }
        fs_statement();
    }
    fs_expect((125u64 as i64));
    g_local_count = v_before;
    g_depth = (g_depth).wrapping_sub((1u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_global_definition() -> i64 {
    if ((g_function_count) > (0u64 as i64)) {
        fs_fail((b"globals must precede functions\0".as_ptr() as i64));
    }
    if ((g_global_count) >= (2048u64 as i64)) {
        fs_fail((b"too many globals\0".as_ptr() as i64));
    }
    fs_next();
    if ((g_token) != (256u64 as i64)) {
        fs_fail((b"expected global name\0".as_ptr() as i64));
    }
    let mut v_name: i64 = (g_source).wrapping_add(g_token_start);
    let mut v_size: i64 = g_token_size;
    if (fs_reserved(v_name, v_size) != 0) {
        fs_fail((b"reserved declaration name\0".as_ptr() as i64));
    }
    if ((fs_find(g_globals, g_global_count, v_name, v_size)) >= (0u64 as i64)) {
        fs_fail((b"duplicate global\0".as_ptr() as i64));
    }
    fs_next();
    fs_expect((61u64 as i64));
    let mut v_negative: i64 = (0u64 as i64);
    if ((g_token) == (45u64 as i64)) {
        v_negative = (1u64 as i64);
        fs_next();
    }
    if ((g_token) != (257u64 as i64)) {
        fs_fail((b"global initializer must be an integer literal\0".as_ptr() as i64));
    }
    let mut v_value: i64 = g_token_value;
    if (v_negative != 0) {
        v_value = (v_value).wrapping_neg();
    }
    fs_next();
    fs_expect((59u64 as i64));
    let mut v_entry: i64 = (g_globals).wrapping_add((g_global_count).wrapping_mul((32u64 as i64)));
    store64(v_entry, v_name);
    store64((v_entry).wrapping_add((8u64 as i64)), v_size);
    store64((v_entry).wrapping_add((16u64 as i64)), g_output_size);
    g_global_count = (g_global_count).wrapping_add((1u64 as i64));
    fs_emit64(v_value);
    return (0u64 as i64);

    0
}

unsafe fn fs_function_definition() -> i64 {
    if ((g_function_count) >= (2048u64 as i64)) {
        fs_fail((b"too many functions\0".as_ptr() as i64));
    }
    fs_next();
    if ((g_token) != (256u64 as i64)) {
        fs_fail((b"expected function name\0".as_ptr() as i64));
    }
    let mut v_name: i64 = (g_source).wrapping_add(g_token_start);
    let mut v_size: i64 = g_token_size;
    if (fs_reserved(v_name, v_size) != 0) {
        fs_fail((b"reserved declaration name\0".as_ptr() as i64));
    }
    if (((fs_find(g_globals, g_global_count, v_name, v_size)) >= (0u64 as i64))
        || ((fs_find(g_functions, g_function_count, v_name, v_size)) >= (0u64 as i64)))
    {
        fs_fail((b"duplicate function\0".as_ptr() as i64));
    }
    let mut v_entry: i64 =
        (g_functions).wrapping_add((g_function_count).wrapping_mul((32u64 as i64)));
    store64(v_entry, v_name);
    store64((v_entry).wrapping_add((8u64 as i64)), v_size);
    store64((v_entry).wrapping_add((16u64 as i64)), g_output_size);
    g_function_count = (g_function_count).wrapping_add((1u64 as i64));
    g_local_count = (0u64 as i64);
    g_slots = (0u64 as i64);
    g_depth = (1u64 as i64);
    fs_next();
    fs_expect((40u64 as i64));
    if ((g_token) != (41u64 as i64)) {
        let mut v_more: i64 = (1u64 as i64);
        while (v_more != 0) {
            if ((g_token) != (256u64 as i64)) {
                fs_fail((b"expected parameter name\0".as_ptr() as i64));
            }
            fs_declare_local((g_source).wrapping_add(g_token_start), g_token_size);
            fs_next();
            if ((g_token) == (44u64 as i64)) {
                fs_next();
            } else {
                v_more = (0u64 as i64);
            }
        }
    }
    fs_expect((41u64 as i64));
    let mut v_count: i64 = g_local_count;
    store64((v_entry).wrapping_add((24u64 as i64)), v_count);
    fs_emit((85u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((137u64 as i64));
    fs_emit((229u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((129u64 as i64));
    fs_emit((236u64 as i64));
    let mut v_frame: i64 = g_output_size;
    fs_emit32((0u64 as i64));
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (v_count)) {
        fs_emit((72u64 as i64));
        fs_emit((139u64 as i64));
        fs_emit((133u64 as i64));
        fs_emit32((16u64 as i64).wrapping_add(
            (((v_count).wrapping_sub(v_i)).wrapping_sub((1u64 as i64))).wrapping_mul((8u64 as i64)),
        ));
        fs_emit((72u64 as i64));
        fs_emit((137u64 as i64));
        fs_emit((133u64 as i64));
        fs_emit32(((8u64 as i64).wrapping_neg()).wrapping_mul((v_i).wrapping_add((1u64 as i64))));
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    g_depth = (0u64 as i64);
    fs_block();
    fs_immediate((0u64 as i64));
    fs_epilogue();
    fs_patch32(
        v_frame,
        (divide(
            ((g_slots).wrapping_mul((8u64 as i64))).wrapping_add((15u64 as i64)),
            (16u64 as i64),
        ))
        .wrapping_mul((16u64 as i64)),
    );
    return (0u64 as i64);

    0
}

unsafe fn fs_initialize_output() -> i64 {
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (120u64 as i64)) {
        fs_emit((0u64 as i64));
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    store8(g_output, (127u64 as i64));
    store8((g_output).wrapping_add((1u64 as i64)), (69u64 as i64));
    store8((g_output).wrapping_add((2u64 as i64)), (76u64 as i64));
    store8((g_output).wrapping_add((3u64 as i64)), (70u64 as i64));
    store8((g_output).wrapping_add((4u64 as i64)), (2u64 as i64));
    store8((g_output).wrapping_add((5u64 as i64)), (1u64 as i64));
    store8((g_output).wrapping_add((6u64 as i64)), (1u64 as i64));
    store8((g_output).wrapping_add((16u64 as i64)), (2u64 as i64));
    store8((g_output).wrapping_add((18u64 as i64)), (62u64 as i64));
    fs_patch32((20u64 as i64), (1u64 as i64));
    store64((g_output).wrapping_add((24u64 as i64)), (4194424u64 as i64));
    store64((g_output).wrapping_add((32u64 as i64)), (64u64 as i64));
    store8((g_output).wrapping_add((52u64 as i64)), (64u64 as i64));
    store8((g_output).wrapping_add((54u64 as i64)), (56u64 as i64));
    store8((g_output).wrapping_add((56u64 as i64)), (1u64 as i64));
    fs_patch32((64u64 as i64), (1u64 as i64));
    fs_patch32((68u64 as i64), (7u64 as i64));
    store64((g_output).wrapping_add((80u64 as i64)), (4194304u64 as i64));
    store64((g_output).wrapping_add((88u64 as i64)), (4194304u64 as i64));
    store64((g_output).wrapping_add((112u64 as i64)), (4096u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((139u64 as i64));
    fs_emit((4u64 as i64));
    fs_emit((36u64 as i64));
    fs_emit((80u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((141u64 as i64));
    fs_emit((68u64 as i64));
    fs_emit((36u64 as i64));
    fs_emit((16u64 as i64));
    fs_emit((80u64 as i64));
    fs_emit((232u64 as i64));
    fs_emit32((0u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((131u64 as i64));
    fs_emit((196u64 as i64));
    fs_emit((16u64 as i64));
    fs_emit((72u64 as i64));
    fs_emit((137u64 as i64));
    fs_emit((199u64 as i64));
    fs_emit((184u64 as i64));
    fs_emit32((60u64 as i64));
    fs_emit((15u64 as i64));
    fs_emit((5u64 as i64));
    return (0u64 as i64);

    0
}

unsafe fn fs_resolve() -> i64 {
    let mut v_main_index: i64 = fs_find(
        g_functions,
        g_function_count,
        (b"main\0".as_ptr() as i64),
        (4u64 as i64),
    );
    if ((v_main_index) < (0u64 as i64)) {
        fs_fail((b"missing main function\0".as_ptr() as i64));
    }
    let mut v_entry: i64 = (g_functions).wrapping_add((v_main_index).wrapping_mul((32u64 as i64)));
    let mut v_count: i64 = load64((v_entry).wrapping_add((24u64 as i64)));
    if (((v_count) != (0u64 as i64)) && ((v_count) != (2u64 as i64))) {
        fs_fail((b"main must take zero or two parameters\0".as_ptr() as i64));
    }
    fs_patch32(
        (132u64 as i64),
        (load64((v_entry).wrapping_add((16u64 as i64)))).wrapping_sub((136u64 as i64)),
    );
    let mut v_i: i64 = (0u64 as i64);
    while ((v_i) < (g_call_count)) {
        let mut v_site: i64 = (g_calls).wrapping_add((v_i).wrapping_mul((32u64 as i64)));
        let mut v_index: i64 = fs_find(
            g_functions,
            g_function_count,
            load64(v_site),
            load64((v_site).wrapping_add((8u64 as i64))),
        );
        if ((v_index) < (0u64 as i64)) {
            g_token_start = (load64(v_site)).wrapping_sub(g_source);
            fs_fail((b"undefined function\0".as_ptr() as i64));
        }
        let mut v_function: i64 =
            (g_functions).wrapping_add((v_index).wrapping_mul((32u64 as i64)));
        if ((load64((v_function).wrapping_add((24u64 as i64))))
            != (load64((v_site).wrapping_add((24u64 as i64)))))
        {
            g_token_start = (load64(v_site)).wrapping_sub(g_source);
            fs_fail((b"wrong function argument count\0".as_ptr() as i64));
        }
        let mut v_at: i64 = load64((v_site).wrapping_add((16u64 as i64)));
        fs_patch32(
            v_at,
            ((load64((v_function).wrapping_add((16u64 as i64)))).wrapping_sub(v_at))
                .wrapping_sub((4u64 as i64)),
        );
        v_i = (v_i).wrapping_add((1u64 as i64));
    }
    store64((g_output).wrapping_add((96u64 as i64)), g_output_size);
    store64((g_output).wrapping_add((104u64 as i64)), g_output_size);
    return (0u64 as i64);

    0
}

unsafe fn fs_main(mut v_argc: i64, mut v_argv: i64) -> i64 {
    g_source_path = (b"flexscript\0".as_ptr() as i64);
    if ((v_argc) == (2u64 as i64)) {
        let mut v_arg: i64 = load64((v_argv).wrapping_add((8u64 as i64)));
        if (fs_equal(
            v_arg,
            fs_length(v_arg),
            (b"--version\0".as_ptr() as i64),
            (9u64 as i64),
        ) != 0)
        {
            fs_print((1u64 as i64), (b"flexscript 0.0.1\n\0".as_ptr() as i64));
            return (0u64 as i64);
        }
        if (fs_equal(
            v_arg,
            fs_length(v_arg),
            (b"--help\0".as_ptr() as i64),
            (6u64 as i64),
        ) != 0)
        {
            fs_print(
                (1u64 as i64),
                (b"Usage: flexscript <source.flex> -o <binary>\n\0".as_ptr() as i64),
            );
            return (0u64 as i64);
        }
    }
    if ((v_argc) != (4u64 as i64)) {
        fs_print(
            (2u64 as i64),
            (b"Usage: flexscript <source.flex> -o <binary>\n\0".as_ptr() as i64),
        );
        return (1u64 as i64);
    }
    let mut v_option: i64 = load64((v_argv).wrapping_add((16u64 as i64)));
    if !(fs_equal(
        v_option,
        fs_length(v_option),
        (b"-o\0".as_ptr() as i64),
        (2u64 as i64),
    ) != 0)
    {
        fs_print((2u64 as i64), (b"expected -o <binary>\n\0".as_ptr() as i64));
        return (1u64 as i64);
    }
    g_source_path = load64((v_argv).wrapping_add((8u64 as i64)));
    let mut v_destination: i64 = load64((v_argv).wrapping_add((24u64 as i64)));
    if (fs_equal(
        g_source_path,
        fs_length(g_source_path),
        v_destination,
        fs_length(v_destination),
    ) != 0)
    {
        fs_fail((b"source and output paths must differ\0".as_ptr() as i64));
    }
    g_source = alloc((16777216u64 as i64));
    g_output = alloc((67108864u64 as i64));
    g_globals = alloc((2048u64 as i64).wrapping_mul((32u64 as i64)));
    g_functions = alloc((2048u64 as i64).wrapping_mul((32u64 as i64)));
    g_locals = alloc((4096u64 as i64).wrapping_mul((32u64 as i64)));
    g_calls = alloc((65536u64 as i64).wrapping_mul((32u64 as i64)));
    if (((((((g_source) < (0u64 as i64)) || ((g_output) < (0u64 as i64)))
        || ((g_globals) < (0u64 as i64)))
        || ((g_functions) < (0u64 as i64)))
        || ((g_locals) < (0u64 as i64)))
        || ((g_calls) < (0u64 as i64)))
    {
        fs_fail((b"memory allocation failed\0".as_ptr() as i64));
    }
    let mut v_fd: i64 = raw_syscall(
        (2u64 as i64),
        g_source_path,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    );
    if ((v_fd) < (0u64 as i64)) {
        fs_fail((b"cannot open source\0".as_ptr() as i64));
    }
    let mut v_stat: i64 = alloc((144u64 as i64));
    if ((v_stat) < (0u64 as i64)) {
        fs_fail((b"memory allocation failed\0".as_ptr() as i64));
    }
    if ((raw_syscall(
        (5u64 as i64),
        v_fd,
        v_stat,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    )) < (0u64 as i64))
    {
        fs_fail((b"cannot stat source\0".as_ptr() as i64));
    }
    let mut v_source_device: i64 = load64(v_stat);
    let mut v_source_inode: i64 = load64((v_stat).wrapping_add((8u64 as i64)));
    let mut v_done: i64 = (0u64 as i64);
    while !(v_done != 0) {
        if ((g_source_size) >= (16777216u64 as i64)) {
            fs_fail((b"source must be smaller than 16 MiB\0".as_ptr() as i64));
        }
        let mut v_n: i64 = raw_syscall(
            (0u64 as i64),
            v_fd,
            (g_source).wrapping_add(g_source_size),
            (16777216u64 as i64).wrapping_sub(g_source_size),
            (0u64 as i64),
            (0u64 as i64),
            (0u64 as i64),
        );
        if ((v_n) == ((4u64 as i64).wrapping_neg())) {
            v_n = (0u64 as i64);
        } else if ((v_n) < (0u64 as i64)) {
            fs_fail((b"cannot read source\0".as_ptr() as i64));
        } else if ((v_n) == (0u64 as i64)) {
            v_done = (1u64 as i64);
        }
        g_source_size = (g_source_size).wrapping_add(v_n);
    }
    raw_syscall(
        (3u64 as i64),
        v_fd,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    );
    fs_initialize_output();
    fs_next();
    while ((g_token) != (0u64 as i64)) {
        if (fs_is((b"global\0".as_ptr() as i64)) != 0) {
            fs_global_definition();
        } else if (fs_is((b"fn\0".as_ptr() as i64)) != 0) {
            fs_function_definition();
        } else {
            fs_fail((b"expected global or function definition\0".as_ptr() as i64));
        }
    }
    fs_resolve();
    v_fd = raw_syscall(
        (2u64 as i64),
        v_destination,
        (131137u64 as i64),
        (493u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    );
    if ((v_fd) < (0u64 as i64)) {
        fs_fail((b"cannot open output\0".as_ptr() as i64));
    }
    if ((raw_syscall(
        (5u64 as i64),
        v_fd,
        v_stat,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    )) < (0u64 as i64))
    {
        fs_fail((b"cannot stat output\0".as_ptr() as i64));
    }
    if (((load64(v_stat)) == (v_source_device))
        && ((load64((v_stat).wrapping_add((8u64 as i64)))) == (v_source_inode)))
    {
        fs_fail((b"source and output refer to the same file\0".as_ptr() as i64));
    }
    if ((raw_syscall(
        (77u64 as i64),
        v_fd,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    )) < (0u64 as i64))
    {
        fs_fail((b"cannot truncate output\0".as_ptr() as i64));
    }
    if !(fs_write_all(v_fd, g_output, g_output_size) != 0) {
        fs_fail((b"cannot write output\0".as_ptr() as i64));
    }
    if ((raw_syscall(
        (91u64 as i64),
        v_fd,
        (493u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    )) < (0u64 as i64))
    {
        fs_fail((b"cannot make output executable\0".as_ptr() as i64));
    }
    if ((raw_syscall(
        (3u64 as i64),
        v_fd,
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
        (0u64 as i64),
    )) < (0u64 as i64))
    {
        fs_fail((b"cannot close output\0".as_ptr() as i64));
    }
    return (0u64 as i64);

    0
}
