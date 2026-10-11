# Auditable source for the bounded address translator embedded in
# x86-jit-memory.flex. SysV scratch registers only; no guest code is copied.
# RDI=CPU, RAX=guest VA, ECX=width, R8=write. RAX=host pointer or zero.
# Cross-page/unsupported/faulting accesses return zero for interpreter retry.
.intel_syntax noprefix
.text
.global xj_memory
xj_memory:
    mov r9d, ecx
    test r8d, r8d
    jz width_saved
    bts r9, 32
width_saved:
    mov r10, rax
    mov edx, eax
    and edx, 4095
    add edx, ecx
    cmp edx, 4096
    ja fail
    # Share the generation-tagged read TLB with the interpreter. Native
    # execution explicitly enables it; direct diagnostic calls bypass it.
    test r8d, r8d
    jnz uncached
    cmp QWORD PTR [rdi+424], 0
    je uncached
    mov r11, r10
    and r11, -4096
    mov rdx, r10
    shr rdx, 12
    and edx, 3
    imul edx, edx, 24
    lea rdx, [rdi+rdx+800]
    mov rax, [rdi+400]
    cmp [rdx+16], rax
    jne uncached
    cmp [rdx], r11
    jne uncached
    mov rax, [rdx+8]
    mov edx, r10d
    and edx, 4095
    or rax, rdx
    mov rdx, [rdi+304]
    mov ecx, r9d
    sub rdx, rcx
    jc fail
    cmp rax, rdx
    ja fail
    add rax, [rdi+296]
    ret
uncached:
    mov rax, r10
    bt QWORD PTR [rdi+152], 31
    jnc physical
    test QWORD PTR [rdi+168], 32
    jz fail
    test QWORD PTR [rdi+176], 256
    jz fail
    mov rdx, rax
    sar rdx, 47
    test rdx, rdx
    jz canonical
    cmp rdx, -1
    jne fail
canonical:
    mov rax, [rdi+160]
    mov r11, 0x000ffffffffff000
    and rax, r11
    mov esi, 39
walk:
    mov rdx, r10
    mov ecx, esi
    shr rdx, cl
    and edx, 511
    lea rax, [rax+rdx*8]
    mov rdx, [rdi+304]
    sub rdx, 8
    jc fail
    cmp rax, rdx
    ja fail
    mov r11, rax
    shr r11, 12
    mov rdx, [rdi+432]
    bts [rdx], r11
    mov r11, [rdi+296]
    mov rax, [r11+rax]
    test al, 1
    jz fail
    test BYTE PTR [rdi+376], 3
    jz write_permission
    test al, 4
    jz fail
write_permission:
    test r8d, r8d
    jz permitted
    test al, 2
    jnz permitted
    test BYTE PTR [rdi+376], 3
    jnz fail
    test DWORD PTR [rdi+152], 0x10000
    jnz fail
permitted:
    mov r11, 0x000ffffffffff000
    mov rdx, rax
    and rax, r11
    cmp esi, 12
    je leaf
    test dl, 128
    jz descend
    cmp esi, 39
    je descend
    mov ecx, esi
    mov rdx, 1
    shl rdx, cl
    dec rdx
    mov r11, rdx
    not r11
    and rax, r11
    and rdx, r10
    or rax, rdx
    jmp physical
 descend:
    sub esi, 9
    jmp walk
leaf:
    mov rdx, r10
    and edx, 4095
    or rax, rdx
physical:
    mov rdx, [rdi+304]
    mov ecx, r9d
    sub rdx, rcx
    jc fail
    cmp rax, rdx
    ja fail
    test r8d, r8d
    jz pointer
    mov r11, rax
    shr r11, 12
    mov rdx, [rdi+432]
    bt [rdx], r11
    jc watched_write
    xor r8d, r8d
    jmp pointer
watched_write:
    inc QWORD PTR [rdi+400]
pointer:
    test r8d, r8d
    jnz host_pointer
    cmp QWORD PTR [rdi+424], 0
    je host_pointer
    # A write cleared R8 for the store guard; never seed a read entry from a
    # write, which may have just invalidated a watched page-table mapping.
    # R9 retains width; preserve a separate access-kind bit in its high half.
    bt r9, 32
    jc host_pointer
    mov rdx, r10
    shr rdx, 12
    and edx, 3
    imul edx, edx, 24
    lea rdx, [rdi+rdx+800]
    mov r11, r10
    and r11, -4096
    mov [rdx], r11
    mov r11, rax
    and r11, -4096
    mov [rdx+8], r11
    mov r11, [rdi+400]
    mov [rdx+16], r11
host_pointer:
    add rax, [rdi+296]
    ret
fail:
    xor eax, eax
    ret
# Native block chaining: cached blocks with unchanged code/mapping generation
# jump directly to their successor without returning through Flexscript/FFI.
.org 768,0x90
.global xj_dispatch
xj_dispatch:
    mov rsi, [rdi+992]
    mov rax, [rdi+128]
    mov rdx, rax
    shr rdx, 17
    xor rdx, rax
    mov rcx, 0x9e3779b97f4a7c15
    imul rdx, rcx
    shr rdx, 32
    and edx, 32767
    shl rdx, 8
    lea rdx, [rsi+rdx+64]
    cmp [rdx], rax
    jne done
    mov rax, [rdi+144]
    cmp [rdx+8], rax
    jne done
    cmp QWORD PTR [rdx+56], 3
    jne done
    mov rax, [rdi+400]
    cmp [rdx+16], rax
    jne done
    mov rax, [rdi+768]
    sub rax, [rdi+312]
    cmp rax, [rdx+32]
    jb done
    sub rdx, rsi
    sub rdx, 64
    shl rdx, 4
    add rdx, [rsi]
    jmp rdx
 done:
    mov eax, 1
    ret
# Bounded REP helper. Caller validates both entire physical ranges first.
# RDI=destination, RSI=source (zero for STOS), RDX=count, RCX=element bytes,
# R8=STOS value, R9=direction stride. Host DF remains clear on every path.
.org 1536,0x90
.global xj_rep
xj_rep:
    cld
    test r9, r9
    js backward
    mov r10, rcx
    mov rcx, rdx
    test rsi, rsi
    jz forward_store
    cmp r10d, 8
    je copy8
    cmp r10d, 4
    je copy4
    cmp r10d, 2
    je copy2
    rep movsb
    ret
 copy8:
    rep movsq
    ret
 copy4:
    rep movsd
    ret
 copy2:
    rep movsw
    ret
 forward_store:
    mov rax, r8
    cmp r10d, 8
    je store8
    cmp r10d, 4
    je store4
    cmp r10d, 2
    je store2
    rep stosb
    ret
 store8:
    rep stosq
    ret
 store4:
    rep stosd
    ret
 store2:
    rep stosw
    ret
 backward:
    test rsi, rsi
    jz backward_store
 backward_copy:
    cmp ecx, 8
    je back_copy8
    cmp ecx, 4
    je back_copy4
    cmp ecx, 2
    je back_copy2
    mov al, [rsi]
    mov [rdi], al
    jmp back_copy_next
 back_copy8:
    mov rax, [rsi]
    mov [rdi], rax
    jmp back_copy_next
 back_copy4:
    mov eax, [rsi]
    mov [rdi], eax
    jmp back_copy_next
 back_copy2:
    mov ax, [rsi]
    mov [rdi], ax
 back_copy_next:
    add rsi, r9
    add rdi, r9
    dec rdx
    jnz backward_copy
    ret
 backward_store:
    mov rax, r8
 back_store_loop:
    cmp ecx, 8
    je back_store8
    cmp ecx, 4
    je back_store4
    cmp ecx, 2
    je back_store2
    mov [rdi], al
    jmp back_store_next
 back_store8:
    mov [rdi], rax
    jmp back_store_next
 back_store4:
    mov [rdi], eax
    jmp back_store_next
 back_store2:
    mov [rdi], ax
 back_store_next:
    add rdi, r9
    dec rdx
    jnz back_store_loop
    ret
.section .note.GNU-stack,"",@progbits
