# Bounded SysV callbacks for the optional libslirp network backend.
# No guest code or guest pointers execute here. All destinations are host-owned.
.intel_syntax noprefix
.text
.global slirp_send
slirp_send:
    cld
    mov rax, rsi
    cmp rsi, 14
    jb dropped
    cmp rsi, 2040
    ja dropped
    mov r8, [rdx+24]
    mov r9, r8
    sub r9, [rdx+16]
    cmp r9, 128
    jae dropped
    mov r9, r8
    and r9d, 127
    shl r9, 11
    lea r9, [rdx+r9+16384]
    mov [r9], rsi
    mov rcx, rsi
    mov rsi, rdi
    lea rdi, [r9+8]
    rep movsb
    inc r8
    mov [rdx+24], r8
    ret
dropped:
    inc QWORD PTR [rdx+32]
    ret
.org 256,0x90
.global slirp_clock
slirp_clock:
    sub rsp, 24
    mov eax, 228
    mov edi, 1
    mov rsi, rsp
    syscall
    test rax, rax
    jnz clock_zero
    mov rax, [rsp]
    imul rax, rax, 1000000000
    add rax, [rsp+8]
clock_return:
    add rsp, 24
    ret
clock_zero:
    xor eax, eax
    jmp clock_return
.org 384,0x90
.global slirp_noop
slirp_noop:
    xor eax, eax
    ret
.org 400,0x90
.global slirp_guest_error
slirp_guest_error:
    inc QWORD PTR [rsi+40]
    ret
.org 512,0x90
.global slirp_add_poll
slirp_add_poll:
    mov rax, [rdx+48]
    cmp rax, 1024
    jae poll_overflow
    lea rcx, [rdx+rax*8+512]
    mov [rcx], edi
    mov r8d, esi
    and r8d, 25
    mov r9d, esi
    and r9d, 2
    shl r9d, 1
    or r8d, r9d
    and esi, 4
    shr esi, 1
    or r8d, esi
    mov [rcx+4], r8w
    mov WORD PTR [rcx+6], 0
    inc QWORD PTR [rdx+48]
    ret
poll_overflow:
    mov QWORD PTR [rdx+56], 1
    mov eax, -1
    ret
.org 768,0x90
.global slirp_revents
slirp_revents:
    cmp edi, 1024
    jae revents_zero
    cmp rdi, [rsi+48]
    jae revents_zero
    movzx eax, WORD PTR [rsi+rdi*8+518]
    mov ecx, eax
    and eax, 25
    mov edx, ecx
    and edx, 2
    shl edx, 1
    or eax, edx
    and ecx, 4
    shr ecx, 1
    or eax, ecx
    ret
revents_zero:
    xor eax, eax
    ret

# State-stream callbacks use a separate, trusted context:
# buffer pointer, capacity, position, error. They never accept guest pointers.
.org 1024, 0x90
.global slirp_state_write
slirp_state_write:
    cld
    mov r8, rdx
    mov r9, [r8+16]
    cmp r9, [r8+8]
    ja stream_error
    mov rcx, [r8+8]
    sub rcx, r9
    cmp rsi, rcx
    ja stream_error
    mov rax, rsi
    mov rcx, rsi
    mov rsi, rdi
    mov rdi, [r8]
    add rdi, r9
    rep movsb
    add [r8+16], rax
    ret
stream_error:
    mov QWORD PTR [r8+24], 1
    mov rax, -1
    ret

.org 1152, 0x90
.global slirp_state_read
slirp_state_read:
    cld
    mov r8, rdx
    mov r9, [r8+16]
    cmp r9, [r8+8]
    ja stream_error
    mov rcx, [r8+8]
    sub rcx, r9
    cmp rsi, rcx
    ja stream_error
    mov rax, rsi
    mov rcx, rsi
    mov rsi, [r8]
    add rsi, r9
    rep movsb
    add [r8+16], rax
    ret
