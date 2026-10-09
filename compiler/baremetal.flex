// Freestanding x86-64 image generation, entirely in Flexscript.
// Multiboot 1 address fields let QEMU load this flat image at 4 MiB.
// CPU bootstrap: protected mode -> identity-mapped long mode -> main().
// No assembler, linker, libc or Linux runtime is involved in the guest.
fn bm_hex_digit(c) {
    if c>=48 && c<=57 {return c-48;}
    if c>=65 && c<=70 {return c-55;}
    fail("invalid backend opcode");return 0;
}
fn bm_hex(text) {
    let i=0;while load8(text+i) {
        if load8(text+i)==32 {i=i+1;}
        else {emit(bm_hex_digit(load8(text+i))*16+bm_hex_digit(load8(text+i+1)));i=i+2;}
    }return 0;
}
fn baremetal_builtin(kind) {
    if kind==7 {bm_hex("5A 31 C0 EC");} // pop rdx; xor eax,eax; in al,dx
    else if kind==8 {bm_hex("58 5A EE 31 C0");} // pop rax; pop rdx; out dx,al; result=0
    else if kind==9 {bm_hex("FA F4 EB FC");} // cli; hlt; jmp hlt forever
    else if kind==10 {bm_hex("5A 31 C0 66 ED");} // in ax,dx
    else if kind==11 {bm_hex("58 5A 66 EF 31 C0");} // out dx,ax
    else if kind==12 {bm_hex("5A ED");} // in eax,dx; EAX zero-extends RAX
    else if kind==13 {bm_hex("58 5A EF 31 C0");} // out dx,eax
    else {fail("invalid bare-metal builtin");}
    return 0;
}
// A six-word System V AMD64 callback into a Flexscript function. The callback
// pushes C argument registers in source order for Flexscript's stack ABI.
fn baremetal_callback() {
    if !baremetal_target {fail("native_callback requires --target baremetal-x86_64");}
    expect(40);if token!=256 {fail("native_callback expects a function name");}
    let name=source+token_start;let size=token_size;next();expect(41);
    if call_count>=65536 {fail("too many calls");}
    let skip=jump(233);let address=output_size;
    bm_hex("55 48 89 E5 57 56 52 51 41 50 41 51 E8");
    let site=calls+call_count*32;store64(site,name);store64(site+8,size);
    store64(site+16,output_size);store64(site+24,6);call_count=call_count+1;emit32(0);
    epilogue();patch_jump(skip);bm_hex("48 8D 05");emit32(address-output_size-4);return 0;
}
fn baremetal_initialize() {
    let base=4194304;
    emit32(0x1badb002);emit32(0x10003);emit32(-(0x1badb002+0x10003));
    emit32(base);emit32(base);emit32(0);emit32(0);emit32(base+120);
    while output_size<120 {emit(0);}
    bm_hex("FA FC BC");emit32(0x300000); // cli; cld; mov esp,3 MiB
    emit(163);emit32(base+32); // preserve Multiboot EAX magic
    bm_hex("89 1D");emit32(base+40); // preserve boot information pointer
    // Zero six page-table pages at 1 MiB.
    emit(191);emit32(0x100000);bm_hex("31 C0 B9");emit32(6144);bm_hex("F3 AB");
    bm_hex("C7 05");emit32(0x100000);emit32(0x101003);
    bm_hex("C7 05");emit32(0x101000);emit32(0x102003);
    bm_hex("C7 05");emit32(0x101008);emit32(0x103003);
    bm_hex("C7 05");emit32(0x101010);emit32(0x104003);
    bm_hex("C7 05");emit32(0x101018);emit32(0x105003);
    // 2048 supervisor/RW 2-MiB pages map four GiB, including PCI framebuffers.
    emit(191);emit32(0x102000);emit(184);emit32(0x83);emit(185);emit32(2048);
    let page_loop=output_size;
    bm_hex("89 07 05");emit32(0x200000);bm_hex("83 C7 08 E2");emit(page_loop-output_size-1);
    bm_hex("0F 20 E0 0D");emit32(0x620);bm_hex("0F 22 E0"); // PAE, OSFXSR, OSXMMEXCPT
    bm_hex("0F 20 C0 83 E0 F3 83 C8 02 0F 22 C0 DB E3"); // enable x87/SSE; fninit
    emit(184);emit32(0x100000);bm_hex("0F 22 D8"); // CR3 = PML4
    emit(185);emit32(0xc0000080);bm_hex("0F 32 0D");emit32(0x100);bm_hex("0F 30"); // EFER.LME
    bm_hex("0F 01 15");let gdtr_fix=output_size;emit32(0); // lgdt [absolute address]
    bm_hex("0F 20 C0 0D");emit32(0x80000000);bm_hex("0F 22 C0"); // CR0.PG
    emit(234);let long_fix=output_size;emit32(0);emit(8);emit(0); // far jump selector 8
    patch32(long_fix,base+output_size);
    // 64-bit code, data selector 16, a private downward-growing stack.
    bm_hex("66 B8 10 00 8E D8 8E C0 8E D0 48 31 ED 48 BC");emit64(0x300000);
    emit(232);native_main_call=output_size;emit32(0);
    baremetal_builtin(9); // returning from main halts safely
    while output_size%8 {emit(0);}
    let gdt=base+output_size;
    emit64(0);emit64(0x00af9a000000ffff);emit64(0x00cf92000000ffff);
    patch32(gdtr_fix,base+output_size);emit(23);emit(0);emit32(gdt);
    return 0;
}
fn baremetal_finish() {
    // Keep the image below the fixed 16-MiB heap. The current target requires
    // >=64 MiB RAM; memory-map-driven allocation is a later platform feature.
    if output_size>1048576 {fail("bare-metal kernel image exceeds 1 MiB");}
    patch32(20,4194304+output_size);return 0;
}
