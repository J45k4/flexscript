// Call generated entry after seeding every callee-saved register.
.text
.global jit_check_abi
.type jit_check_abi,%function
jit_check_abi:
stp x29,x30,[sp,#-16]!
stp x19,x20,[sp,#-16]!
stp x21,x22,[sp,#-16]!
stp x23,x24,[sp,#-16]!
stp x25,x26,[sp,#-16]!
stp x27,x28,[sp,#-16]!
mov x16,x0
mov x0,x1
mov x19,#19
mov x20,#20
mov x21,#21
mov x22,#22
mov x23,#23
mov x24,#24
mov x25,#25
mov x26,#26
mov x27,#27
mov x28,#28
mov x29,#29
blr x16
cmp x19,#19
b.ne .Lfail
cmp x20,#20
b.ne .Lfail
cmp x21,#21
b.ne .Lfail
cmp x22,#22
b.ne .Lfail
cmp x23,#23
b.ne .Lfail
cmp x24,#24
b.ne .Lfail
cmp x25,#25
b.ne .Lfail
cmp x26,#26
b.ne .Lfail
cmp x27,#27
b.ne .Lfail
cmp x28,#28
b.ne .Lfail
cmp x29,#29
b.ne .Lfail
mov x0,#0
b .Lrestore
.Lfail:
mov x0,#1
.Lrestore:
ldp x27,x28,[sp],#16
ldp x25,x26,[sp],#16
ldp x23,x24,[sp],#16
ldp x21,x22,[sp],#16
ldp x19,x20,[sp],#16
ldp x29,x30,[sp],#16
ret
.section .note.GNU-stack,"",@progbits
