// Direct Flexscript word IR -> Xtensa LX7 -> ESP32-S3 ROM image.
// Native instruction encoding uses no assembler or C compiler. Optional
// ELF linking resolves vendor relocations externally; no RTOS is required.
// Private call0 ABI: a2:a3 accumulator, a14 frame, a1 descending stack.
// Code and data occupy disjoint physical SRAM despite the IRAM/DRAM aliases.
global esp32_target=0;
// Larger S3 RAM-only SDK profile; physical alias boundary remains explicit.
global esp_s3_sdk=0;
global esp_s3_xip=0;
global esp_platform_path=0;
global esp_platform_entry=-1;
global esp_code_base=0x40380000;
global esp_data_base=0x3fcb0000;
global esp_stack_floor=0x3fcd0000;
global esp_stack_top=0x3fcd8000;
global esp_ir=0;
global esp_ir_size=0;
global esp_map=0;
global esp_ir_jumps=0;
global esp_local_slots=0;
global esp_functions=0;
global esp_seen=0;
global esp_fixups=0;
global esp_fixup_count=0;
global esp_trap=1024;
global esp_dispatch=-1;
global esp_irq_tail_index=-1;
global esp_irq_entry=0;
global esp_c_thunks=0;
global esp_param_masks=0;
global esp_iram_functions=0;
global esp_elf=0;
global esp_radio=0;
global esp_btdm=0;
global esp_flash=0;
global esp_iram_size=0;
global esp_c_enabled=0;
global esp_imports=0;
global esp_import_count=0;
global esp_import_used=0;
global esp_elf_names=0;
global esp_elf_name_size=0;

global esp_push_entry=0;
fn esp_code_capacity() {if esp_s3_xip {return 98304;}if esp_s3_sdk {return 196608;}return 131072;}
fn esp_native_heap_begin() {if esp_s3_xip {return 0x3fcb0000;}if esp_s3_sdk {return 0x3fcc4000;}if esp_btdm {return 0x3ffb6400;}return esp_data_base+65536;}
fn esp_native_heap_end() {if esp_s3_xip {return 0x3fcb2000;}if esp_s3_sdk {return 0x3fcc6000;}if esp_btdm {return 0x3ffb8000;}return esp_data_base+98304;}

// Logical output keeps its existing sparse flash offset; physical S3 IROM
// is not a linear continuation of IRAM. Every materialized PC uses this map.
fn esp_irom_base() {if esp_s3_xip {return 0x42000000;}return 0x400d0000;}
fn esp_code_address(offset) {if esp_flash && offset>=0x50000 {return esp_irom_base()+offset-0x50000;}return esp_code_base+offset;}
fn esp_ins(n) {if esp_flash && output_size+3>0x350000 {fail("ESP32 flash code exceeds 3 MiB");}if output_size+3>esp_code_capacity() && !esp_flash {if esp_s3_sdk {fail("ESP32-S3 SDK machine code exceeds 192 KiB IRAM region");}fail("ESP32 machine code exceeds 128 KiB IRAM region");}emit(n);emit(n>>8);emit(n>>16);return 0;}
fn esp_rrr(op,d,s,t) {esp_ins(op|(d<<12)|(s<<8)|(t<<4));return 0;}
fn esp_mov(d,s) {esp_rrr(0x200000,d,s,s);return 0;}
fn esp_movi(r,n) {
    if n< -2048 || n>2047 {fail("Xtensa immediate out of range");}
    esp_ins(0xa002|(r<<4)|((n&0xf00)<<0)|((n&255)<<16));return 0;
}
fn esp_addi(d,s,n) {
    if n< -128 || n>127 {fail("Xtensa addi out of range");}
    esp_ins(0xc002|(d<<4)|(s<<8)|((n&255)<<16));return 0;
}
fn esp_slli(d,s,n) {
    if n<1 || n>31 {fail("Xtensa shift out of range");}
    let v=32-n;esp_ins(0x010000|(d<<12)|(s<<8)|((v&15)<<4)|((v&16)<<16));return 0;
}
fn esp_ext(d,s,start,bits) {
    esp_ins(0x040000|((bits-1)<<20)|(d<<12)|((start&15)<<8)|(s<<4)|((start&16)<<12));return 0;
}
fn esp_const(r,n) {
    // Fixed 21 bytes, also used for forward function-address relocations.
    n=(n<<32)>>32;
    let d0=((n+128)&255)-128;n=(n-d0)>>8;
    let d1=((n+128)&255)-128;n=(n-d1)>>8;
    let d2=((n+128)&255)-128;n=(n-d2)>>8;
    esp_movi(r,n);esp_slli(r,r,8);esp_addi(r,r,d2);
    esp_slli(r,r,8);esp_addi(r,r,d1);esp_slli(r,r,8);esp_addi(r,r,d0);return 0;
}
fn esp_imm(r,n) {let v=(n<<32)>>32;if v>= -2048 && v<=2047 {esp_movi(r,v);}else {esp_const(r,v);}return 0;}
fn esp_mem(op,r,base,offset) {
    if offset<0 || offset>1020 || offset%4 {fail("Xtensa memory offset out of range");}
    esp_ins(op|(r<<4)|(base<<8)|((offset/4)<<16));return 0;
}
fn esp_load(r,base,offset) {return esp_mem(0x2002,r,base,offset);}
fn esp_store(r,base,offset) {return esp_mem(0x6002,r,base,offset);}
fn esp_jump() {let at=output_size;esp_ins(6);return at;}
fn esp_patch_jump(at,to) {
    let delta=esp_code_address(to)-esp_code_address(at)-4;if delta< -131072 || delta>131071 {fail("Xtensa jump out of range");}
    let old=output_size;output_size=at;esp_ins(6|((delta&262143)<<6));output_size=old;return 0;
}
fn esp_j(to) {let delta=esp_code_address(to)-esp_code_address(output_size)-4;if delta< -131072 || delta>131071 {esp_const(13,esp_code_address(to));esp_ins(0x0000a0|(13<<8));return 0;}let at=esp_jump();esp_patch_jump(at,to);return 0;}
// Register comparison branches use signed 8-bit byte displacements.
// 1=eq,9=ne,2=lt,10=ge,3=ltu,11=geu.
fn esp_branch(kind,s,t) {let at=output_size;esp_ins(7|(s<<8)|(t<<4)|(kind<<12));return at;}
fn esp_patch_branch(at,to) {
    let delta=esp_code_address(to)-esp_code_address(at)-4;if delta< -128 || delta>127 {fail("Xtensa branch out of range");}
    store8(output+at+2,delta);return 0;
}
fn esp_cjump(kind,s,t) {let skip=esp_branch(kind^8,s,t);let at=esp_jump();esp_patch_branch(skip,output_size);return at;}
fn esp_guard(kind,s,t) {let at=esp_branch(kind,s,t);esp_j(esp_trap);esp_patch_branch(at,output_size);return 0;}
fn esp_stack_check() {esp_imm(9,esp_data_base+20);esp_load(9,9,0);esp_guard(11,1,9);return 0;}
fn esp_push() {esp_addi(1,1,-8);esp_stack_check();esp_store(2,1,0);esp_store(3,1,4);return 0;}
fn esp_pop(lo,hi) {esp_load(lo,1,0);esp_load(hi,1,4);esp_addi(1,1,8);return 0;}
fn esp_local(slot) {slot=load64(esp_local_slots+slot*8);esp_imm(8,-8*(slot+1));esp_rrr(0x800000,8,14,8);return 0;}
fn esp_epilogue() {
    esp_mov(1,14);esp_load(0,1,0);esp_load(14,1,4);esp_addi(1,1,16);esp_ins(0x80);return 0;
}
fn esp_neg(lo,hi) {
    esp_movi(7,0);esp_ins(0x600000|(6<<12)|(lo<<4));
    let at=esp_branch(1,lo,7);esp_addi(hi,hi,1);esp_patch_branch(at,output_size);
    esp_ins(0x600000|(hi<<12)|(hi<<4));esp_mov(lo,6);return 0;
}
fn esp_bool(invert) {
    esp_rrr(0x200000,6,2,3);esp_movi(7,0);esp_movi(2,invert);
    let at=esp_branch(1,6,7);esp_movi(2,1-invert);esp_patch_branch(at,output_size);esp_movi(3,0);return 0;
}
fn esp_compare(op) {
    // Inputs a4:a5 and a2:a3, result a2:a3. High words signed, low unsigned.
    if op==259 || op==260 {
        esp_rrr(0x300000,6,4,2);esp_rrr(0x300000,7,5,3);esp_rrr(0x200000,6,6,7);
        esp_movi(7,0);esp_movi(2,op==259);let at=esp_branch(1,6,7);
        esp_movi(2,op==260);esp_patch_branch(at,output_size);esp_movi(3,0);return 0;
    }
    if op==62 || op==262 {esp_mov(6,4);esp_mov(4,2);esp_mov(2,6);esp_mov(6,5);esp_mov(5,3);esp_mov(3,6);}
    let yes=esp_branch(2,5,3);let no=esp_branch(2,3,5);
    let low=0;if op==261 || op==262 {low=esp_branch(11,2,4);}else {low=esp_branch(3,4,2);}
    esp_patch_branch(no,output_size);esp_movi(2,0);let end=esp_jump();
    esp_patch_branch(yes,output_size);esp_patch_branch(low,output_size);esp_movi(2,1);
    esp_patch_jump(end,output_size);esp_movi(3,0);return 0;
}
fn esp_shift(op) {
    // Hardware shift counts are five bits; Flexscript masks to six bits.
    esp_ext(6,2,0,6);esp_movi(7,32);let large=esp_branch(11,6,7);
    esp_movi(7,0);let zero=esp_branch(1,6,7);
    if op==265 {
        esp_ins(0x401000|(6<<8));esp_rrr(0xa10000,3,5,0);esp_rrr(0xa10000,2,4,0);
        esp_ins(0x600000|(7<<12)|(6<<4));esp_ins(0x400000|(7<<8));
        esp_ins(0x910000|(7<<12)|(4<<4));esp_rrr(0x200000,3,3,7);
    }else {
        esp_ins(0x400000|(6<<8));esp_ins(0x910000|(2<<12)|(4<<4));esp_ins(0xb10000|(3<<12)|(5<<4));
        esp_ins(0x600000|(7<<12)|(6<<4));esp_ins(0x401000|(7<<8));
        esp_rrr(0xa10000,7,5,0);esp_rrr(0x200000,2,2,7);
    }
    let end=esp_jump();esp_patch_branch(zero,output_size);esp_mov(2,4);esp_mov(3,5);let end2=esp_jump();
    esp_patch_branch(large,output_size);esp_addi(6,6,-32);
    if op==265 {esp_ins(0x401000|(6<<8));esp_rrr(0xa10000,3,4,0);esp_movi(2,0);}
    else {esp_ins(0x400000|(6<<8));esp_ins(0xb10000|(2<<12)|(5<<4));esp_ins(0x310000|(3<<12)|(15<<8)|(5<<4));}
    esp_patch_jump(end,output_size);esp_patch_jump(end2,output_size);return 0;
}
fn esp_divide(remainder) {
    esp_rrr(0x200000,8,2,3);esp_movi(9,0);esp_guard(9,8,9);
    // MIN/-1 must trap for division and remainder, as on the native backend.
    esp_imm(8,0x80000000);let safe1=esp_branch(9,5,8);let safe2=esp_branch(9,4,9);
    esp_movi(8,-1);let safe3=esp_branch(9,2,8);esp_guard(9,3,8);
    esp_patch_branch(safe1,output_size);esp_patch_branch(safe2,output_size);esp_patch_branch(safe3,output_size);
    esp_ext(10,5,31,1);esp_rrr(0x300000,11,5,3);esp_ext(11,11,31,1);
    esp_movi(9,0);let positive=esp_branch(1,10,9);esp_neg(4,5);esp_patch_branch(positive,output_size);
    esp_ext(8,3,31,1);let dpositive=esp_branch(1,8,9);esp_neg(2,3);esp_patch_branch(dpositive,output_size);
    esp_movi(6,0);esp_movi(7,0);esp_movi(8,0);esp_movi(9,0);esp_movi(12,64);
    let loop=output_size;
    esp_ext(15,5,31,1);esp_ext(13,8,31,1);esp_rrr(0x800000,9,9,9);esp_rrr(0x200000,9,9,13);
    esp_rrr(0x800000,8,8,8);esp_rrr(0x200000,8,8,15);
    esp_ext(13,4,31,1);esp_rrr(0x800000,5,5,5);esp_rrr(0x200000,5,5,13);esp_rrr(0x800000,4,4,4);
    esp_ext(13,6,31,1);esp_rrr(0x800000,7,7,7);esp_rrr(0x200000,7,7,13);esp_rrr(0x800000,6,6,6);
    let skip=esp_branch(3,9,3);let take=esp_branch(3,3,9);let skip2=esp_branch(3,8,2);
    esp_patch_branch(take,output_size);
    esp_movi(13,1);let borrow=esp_branch(3,8,2);esp_movi(13,0);esp_patch_branch(borrow,output_size);
    esp_rrr(0xc00000,8,8,2);esp_rrr(0xc00000,9,9,3);esp_rrr(0xc00000,9,9,13);esp_addi(6,6,1);
    esp_patch_branch(skip,output_size);esp_patch_branch(skip2,output_size);
    esp_addi(12,12,-1);esp_movi(13,0);let done=esp_branch(1,12,13);esp_j(loop);esp_patch_branch(done,output_size);
    if remainder {esp_mov(2,8);esp_mov(3,9);}else {esp_mov(2,6);esp_mov(3,7);}
    let sign=11;if remainder {sign=10;}esp_movi(13,0);let finish=esp_branch(1,sign,13);esp_neg(2,3);esp_patch_branch(finish,output_size);return 0;
}
fn esp_binary(op) {
    esp_pop(4,5);
    if op==43 {
        esp_rrr(0x800000,6,4,2);esp_movi(7,1);let at=esp_branch(3,6,4);esp_movi(7,0);esp_patch_branch(at,output_size);
        esp_rrr(0x800000,3,5,3);esp_rrr(0x800000,3,3,7);esp_mov(2,6);
    }else if op==45 {
        esp_movi(6,1);let at=esp_branch(3,4,2);esp_movi(6,0);esp_patch_branch(at,output_size);
        esp_rrr(0xc00000,2,4,2);esp_rrr(0xc00000,3,5,3);esp_rrr(0xc00000,3,3,6);
    }else if op==42 {
        esp_rrr(0xa20000,6,4,2);esp_rrr(0x820000,7,5,2);esp_rrr(0x800000,6,6,7);
        esp_rrr(0x820000,7,4,3);esp_rrr(0x800000,6,6,7);esp_rrr(0x820000,2,4,2);esp_mov(3,6);
    }else if op==47 || op==37 {esp_divide(op==37);}
    else if op==38 || op==124 || op==94 {
        let code=0x100000;if op==124 {code=0x200000;}else if op==94 {code=0x300000;}
        esp_rrr(code,2,4,2);esp_rrr(code,3,5,3);
    }else if op==265 || op==266 {esp_shift(op);}
    else {esp_compare(op);}return 0;
}
fn esp_pointer() {esp_movi(7,0);esp_guard(1,5,7);return 0;}
fn esp_builtin(kind) {
    if kind==49 {esp_movi(2,1);esp_movi(3,0);return 0;}
    if kind==48 {esp_sr_read(2,177);esp_movi(3,0);return 0;}
    if kind==47 {esp_imm(2,esp_data_base);esp_movi(3,0);return 0;}
    if kind==46 {return esp_context_switch();}
    if kind==44 || kind==45 {return esp_c_call(kind==45);}
    if kind==32 {esp_ins(0x03ea20);esp_movi(3,0);return 0;}
    if kind==33 {esp_ins(0x006f20);esp_j(output_size);return 0;}
    if kind==36 {esp_ins(0x006f20);esp_movi(3,0);return 0;}
    if kind==38 || kind==43 {let sr=226;if kind==43 {sr=228;}esp_ins(0x030020|(sr<<8));esp_movi(3,0);return 0;}
    if kind==40 {esp_ins(0x007000);esp_movi(2,0);esp_movi(3,0);return 0;}
    if kind==35 {
        esp_load(4,1,8);esp_load(5,1,12);esp_pointer();esp_mov(8,4);esp_ins(0x0008c0);esp_addi(1,1,16);return 0;
    }
    if kind==37 || kind==39 || kind==41 || kind==42 {
        esp_pop(2,3);let sr=230;if kind==39 {sr=228;}else if kind==41 {sr=226;}else if kind==42 {sr=227;}
        esp_ins(0x130020|(sr<<8));esp_ins(0x002010);esp_movi(2,0);esp_movi(3,0);return 0;
    }
    if kind==5 {
        esp_imm(8,esp_data_base+16);esp_load(9,8,0);esp_movi(7,0);esp_guard(1,9,7);
        esp_pop(2,3);esp_movi(7,0);let badhi=esp_cjump(9,3,7);let zero=esp_cjump(1,2,7);
        esp_imm(8,32768);let large=esp_cjump(3,8,2);esp_addi(6,2,7);esp_imm(8,-8);esp_rrr(0x100000,6,6,8);
        esp_imm(8,esp_data_base);esp_load(4,8,0);esp_rrr(0x800000,6,4,6);let limit=esp_native_heap_end();esp_imm(9,limit);
        let full=esp_cjump(3,9,6);esp_store(6,8,0);esp_mov(2,4);esp_movi(3,0);esp_movi(7,0);
        let loop=output_size;let done=esp_branch(11,4,6);esp_ins(0x4002|(7<<4)|(4<<8));esp_addi(4,4,1);esp_j(loop);
        esp_patch_branch(done,output_size);let finish=esp_jump();
        esp_patch_jump(badhi,output_size);esp_patch_jump(large,output_size);esp_patch_jump(full,output_size);
        esp_movi(2,-12);esp_movi(3,-1);let out=esp_jump();esp_patch_jump(zero,output_size);esp_movi(2,-22);esp_movi(3,-1);esp_patch_jump(out,output_size);esp_patch_jump(finish,output_size);return 0;
    }
    if kind==3 || kind==4 || kind==31 {esp_pop(2,3);}esp_pop(4,5);esp_pointer();
    if kind==30 || kind==31 {
        esp_ext(6,4,0,2);esp_movi(7,0);esp_guard(1,6,7);esp_ins(0x0020c0);
        if kind==30 {esp_load(2,4,0);esp_movi(3,0);}else {esp_store(2,4,0);esp_movi(2,0);esp_movi(3,0);}
        esp_ins(0x0020c0);return 0;
    }
    if kind==1 {esp_ins(2|(2<<4)|(4<<8));esp_movi(3,0);}
    else if kind==2 {
        esp_movi(2,0);esp_movi(3,0);let i=0;
        while i<8 {esp_ins(2|(6<<4)|(4<<8)|(i<<16));if i%4 {esp_slli(6,6,(i%4)*8);}let r=2+i/4;esp_rrr(0x200000,r,r,6);i=i+1;}
    }else if kind==3 {esp_ins(0x4002|(2<<4)|(4<<8));}
    else if kind==4 {
        let i=0;while i<8 {esp_ext(6,2+i/4,(i%4)*8,8);esp_ins(0x4002|(6<<4)|(4<<8)|(i<<16));i=i+1;}
        // Stores return the complete input word, including store8 truncation.
    }else {fail("unsupported ESP32 builtin");}return 0;
}
fn esp_end(index) {if index+1<function_count {return load64(functions+(index+1)*32+16);}return esp_ir_size;}
fn esp_reachable(main_index) {
    store64(esp_seen+main_index*8,1);let changed=1;
    while changed {
        changed=0;let i=0;while i<function_count {
            if load64(esp_seen+i*8)==1 {
                store64(esp_seen+i*8,2);changed=1;
                let pc=load64(functions+i*32+16)+16;let end=esp_end(i);
                while pc<end {
                    let op=load64(esp_ir+pc);let arg=load64(esp_ir+pc+8);
                    if op==24 || op==26 {store64(esp_c_thunks+arg*8,1);esp_c_enabled=1;}
                    if op==26 || op==27 {store64(esp_iram_functions+arg*8,1);}
                    if op==25 {store64(esp_import_used+arg*8,1);}
                    if op==8 || op==23 || op==24 || op==26 || op==27 {if !load64(esp_seen+arg*8) {store64(esp_seen+arg*8,1);}}
                    else if op==17 {if arg>=44 && arg<=46 {esp_c_enabled=1;}if arg!=1 && arg!=2 && arg!=3 && arg!=4 && arg!=5 && (arg<30 || arg>49) {fail("ESP32 has no Linux syscalls or dynamic FFI; use a bare-metal platform adapter");}}
                    else if (op<1 || op>16) && (op<19 || op>22) && op!=23 && op!=24 && op!=25 && op!=26 && op!=27 {fail("unsupported ESP32 IR instruction");}
                    pc=pc+16;
                }
            }i=i+1;
        }
    }return 0;
}
// A RAM callback must not immediately jump back into cached native helpers.
// Follow direct calls and named callback references; dynamic C function pointers
// retain the linked vendor object's own placement contract.
fn esp_iram_closure() {
    let changed=1;while changed {changed=0;let i=0;while i<function_count {
        if load64(esp_iram_functions+i*8)==1 {store64(esp_iram_functions+i*8,2);changed=1;
            let pc=load64(functions+i*32+16)+16;let end=esp_end(i);while pc<end {
                let op=load64(esp_ir+pc);let arg=load64(esp_ir+pc+8);
                if op==8 || op==23 || op==24 || op==26 || op==27 {if !load64(esp_iram_functions+arg*8) {store64(esp_iram_functions+arg*8,1);}}
                pc=pc+16;
            }
        }i=i+1;
    }}return 0;
}
fn esp_call(index) {
    if esp_fixup_count>=65536 {fail("too many ESP32 call relocations");}
    let site=esp_fixups+esp_fixup_count*16;store64(site,output_size|(8<<32));store64(site+8,index);esp_fixup_count=esp_fixup_count+1;
    esp_const(8,0);esp_ins(0x0008c0);return 0;
}
// Window save/fill sequences adapted from Cadence/Espressif xtensa_vectors.S
// (MIT; full notice in docs/licenses/xtensa-window-vectors.txt).
fn esp_window_mem(load,reg,base,offset) {
    if offset< -64 || offset> -4 || offset%4 {fail("invalid Xtensa window save offset");}
    let op=0x490000;if load {op=0x090000;}esp_ins(op|(((offset+64)/4)<<12)|(base<<8)|(reg<<4));return 0;
}
fn esp_window_vectors() {
    let saved=output_size;let group=0;while group<3 {
        let count=4+group*4;let base=count+1;let fill=0;while fill<2 {
            output_size=group*128+fill*64;
            if !fill {
                esp_window_mem(0,0,base,-16);
                if group {esp_window_mem(1,0,1,-12);}
                let r=1;while r<4 {esp_window_mem(0,r,base,-16+r*4);r=r+1;}
                r=4;while r<count {esp_window_mem(0,r,0,-count*4+(r-4)*4);r=r+1;}
                esp_ins(0x003400);
            }else {
                let r=0;while r<3 {esp_window_mem(1,r,base,-16+r*4);r=r+1;}
                if group {esp_window_mem(1,count-1,1,-12);}
                esp_window_mem(1,3,base,-4);r=4;
                while r<count {esp_window_mem(1,r,count-1,-count*4+(r-4)*4);r=r+1;}
                esp_ins(0x003500);
            }fill=fill+1;
        }group=group+1;
    }output_size=saved;return 0;
}
fn esp_c_call(wide) {
    // Isolate every windowed C call from live ancestor C windows. A private
    // call0 frame changes a1; spilling an older C ancestor through that changed
    // child SP corrupts its base-save area. Snapshot all ARs and WB/WS, run C
    // with a fresh window root, then restore the prior bank before unwinding.
    // Layout: C args 0/4, result 8/12, FP/PS/a0/original-SP 16..28,
    // synthetic root ancestor 96, AR[64] 128..383, WB/WS 384/388.
    esp_mov(6,1);esp_imm(7,-416);esp_rrr(0x800000,1,1,7);esp_imm(7,-16);esp_rrr(0x100000,1,1,7);esp_stack_check();esp_addi(9,1,-16);esp_imm(7,esp_data_base+20);esp_load(7,7,0);esp_guard(11,9,7);
    esp_store(14,1,16);esp_store(0,1,24);esp_store(6,1,28);esp_sr_read(5,230);esp_store(5,1,20);
    esp_ins(0x006f20); // mask IRQs while rotating/snapshotting the register bank
    esp_imm(7,~262144);esp_rrr(0x100000,2,2,7);esp_movi(7,15);esp_rrr(0x200000,2,2,7);esp_sr_write(2,230);esp_ins(0x002010);
    esp_sr_write(1,212);esp_sr_read(2,72);esp_store(2,1,384);esp_sr_read(2,73);esp_store(2,1,388);
    let i=0;while i<16 {esp_store(i,1,128+i*4);i=i+1;}
    let block=1;while block<4 {
        esp_ins(0x408040);esp_sr_write(0,211);esp_sr_read(0,212);i=1;while i<16 {esp_store(i,0,128+block*64+i*4);i=i+1;}esp_sr_read(1,211);esp_store(1,0,128+block*64);block=block+1;
    }
    // Install a new C window root at WB=0. No old C ancestor may be spilled
    // using this private stack pointer. Its complete bank remains in memory.
    esp_movi(0,0);esp_sr_write(0,72);esp_ins(0x002010);esp_sr_read(1,212);esp_movi(2,1);esp_sr_write(2,73);esp_ins(0x002010);
    esp_load(6,1,28);esp_addi(4,1,96);esp_addi(5,1,-16);esp_store(4,5,4);
    esp_load(4,6,8);esp_store(4,1,0);esp_load(4,6,0);esp_store(4,1,4);
    esp_load(8,6,64);esp_load(5,6,68);esp_movi(7,0);esp_guard(1,5,7);esp_guard(9,8,7);
    let r=0;while r<6 {esp_load(10+r,6,56-r*8);r=r+1;}esp_load(6,1,20);
    esp_ext(4,6,4,1);esp_ext(5,6,0,4);esp_movi(7,0);let ordinary=esp_branch(1,4,7);let masked=esp_branch(9,5,7);esp_addi(6,6,1);esp_patch_branch(masked,output_size);esp_patch_branch(ordinary,output_size);
    esp_imm(7,~16);esp_rrr(0x100000,6,6,7);esp_imm(7,262144);esp_rrr(0x200000,6,6,7);esp_sr_write(6,230);esp_ins(0x002010);esp_ins(0x0008e0);
    // Capture the C result before restoring the old register bank.
    esp_store(10,1,8);esp_store(11,1,12);esp_ins(0x006f20);esp_store(2,1,392);esp_imm(7,~262144);esp_rrr(0x100000,2,2,7);esp_movi(7,15);esp_rrr(0x200000,2,2,7);esp_sr_write(2,230);esp_ins(0x002010);esp_sr_write(1,212);
    esp_load(2,1,384);esp_sr_write(2,72);esp_ins(0x002010);
    block=1;while block<4 {esp_ins(0x408040);esp_sr_read(0,212);i=1;while i<16 {esp_load(i,0,128+block*64+i*4);i=i+1;}esp_load(0,0,128+block*64);block=block+1;}
    esp_ins(0x408040);esp_sr_read(0,212);esp_load(2,0,388);esp_sr_write(2,73);i=1;while i<16 {esp_load(i,0,128+i*4);i=i+1;}esp_load(0,0,128);
    esp_load(2,1,8);if wide {esp_load(3,1,12);}else {esp_movi(3,0);}
    esp_load(6,1,20);
    // IRQ masking is an intentional side effect of C/OSI calls. Preserve the
    // returned INTLEVEL for ordinary calls, but restore the interrupt entry's
    // EXCM/INTLEVEL contract when this bridge was entered inside an ISR.
    esp_ext(7,6,4,1);esp_movi(8,0);let from_isr=esp_branch(9,7,8);
    esp_load(7,1,392);esp_ext(7,7,0,4);esp_imm(8,~15);esp_rrr(0x100000,6,6,8);esp_rrr(0x200000,6,6,7);esp_patch_branch(from_isr,output_size);
    esp_load(14,1,16);esp_load(0,1,24);esp_load(1,1,28);esp_addi(1,1,72);esp_sr_write(6,230);esp_ins(0x002010);return 0;
}
fn esp_c_callback(index) {
    // Eight unsigned C argument words, eight 64-bit Flexscript parameters.
    // Full a2:a3 return also supports a C uint64_t callback result.
    while output_size%4 {emit(0);}store64(esp_c_thunks+index*8,output_size);
    esp_ins(0x000136|(24<<12)); // entry a1,192
    esp_mov(15,15); // trigger any overlapping ancestor window spills first
    esp_store(0,1,16);esp_sr_read(8,230);esp_store(8,1,20);
    let mask=load64(esp_param_masks+index*8);let i=0;while i<6 {if mask&(1<<i) {esp_store(2+i,1,64+i*4);}i=i+1;}
    if mask&64 {esp_load(8,1,192);esp_store(8,1,88);}if mask&128 {esp_load(8,1,196);esp_store(8,1,92);}
    esp_imm(7,~262144);esp_sr_read(8,230);esp_rrr(0x100000,8,8,7);esp_sr_write(8,230);esp_ins(0x002010);
    esp_mov(6,1);esp_addi(1,1,-80);esp_stack_check();esp_movi(14,0);esp_movi(3,0);i=0;
    while i<8 {if mask&(1<<i) {esp_load(2,6,64+i*4);esp_store(2,1,(7-i)*8);esp_store(3,1,(7-i)*8+4);}i=i+1;}
    esp_call(index);esp_addi(1,1,80);esp_load(0,1,16);
    // Restore C window state while carrying the callback's INTLEVEL changes.
    esp_sr_read(9,230);esp_ext(9,9,0,4);esp_load(8,1,20);esp_imm(7,~15);esp_rrr(0x100000,8,8,7);esp_rrr(0x200000,8,8,9);esp_sr_write(8,230);esp_ins(0x002010);esp_ins(0x000090);return 0;
}
fn esp_callback(op,arity) {
    expect(40);if token!=256 {fail("esp32_callback expects a function name");}
    let name=source+token_start;let size=token_size;next();expect(41);
    if call_count>=65536 {fail("too many callback references");}
    let site=calls+call_count*32;store64(site,name);store64(site+8,size);
    store64(site+16,vm_emit(op,0)+8);store64(site+24,arity);call_count=call_count+1;return 0;
}
fn esp_reference(index,cabi) {
    if esp_fixup_count>=65536 {fail("too many ESP32 callback relocations");}
    let site=esp_fixups+esp_fixup_count*16;store64(site,output_size|(2<<32)|(cabi<<40));store64(site+8,index);esp_fixup_count=esp_fixup_count+1;
    esp_const(2,0);esp_movi(3,0);return 0;
}
fn esp_sr_read(reg,sr) {esp_ins(0x030000|(sr<<8)|(reg<<4));return 0;}
fn esp_sr_write(reg,sr) {esp_ins(0x130000|(sr<<8)|(reg<<4));return 0;}
fn esp_interrupt_entry() {
    // Level-1 interrupts arrive through the kernel/user exception vectors.
    // Preserve every visible register plus SAR, loops, EPC1 and PS; callbacks
    // use the ordinary private call0 ABI. EXCM prevents nested level-1 entry.
    esp_irq_entry=output_size;let irq_frame=112;if esp_c_enabled {irq_frame=192;esp_addi(1,1,-96);esp_addi(1,1,-96);}else {esp_addi(1,1,-112);}esp_store(0,1,0);
    let i=2;while i<16 {esp_store(i,1,i*4);i=i+1;}
    esp_imm(2,irq_frame);esp_rrr(0x800000,2,1,2);esp_store(2,1,4);esp_sr_read(2,177);esp_store(2,1,64);
    esp_sr_read(2,230);esp_store(2,1,68);esp_sr_read(2,3);esp_store(2,1,72);
    i=0;while i<3 {esp_sr_read(2,i);esp_store(2,1,76+i*4);i=i+1;}
    if esp_c_enabled {
        esp_sr_read(2,224);esp_store(2,1,88);esp_movi(2,1);esp_sr_write(2,224);esp_ins(0x002010);
        esp_user_read(2,232);esp_store(2,1,92);esp_user_read(2,233);esp_store(2,1,96);esp_user_read(2,231);esp_store(2,1,100);
        i=0;while i<16 {esp_rfr(2,i);esp_store(2,1,104+i*4);i=i+1;}
    }
    // Preserve the interrupted C frame's 16-byte base-save area above us.
    // Native ISR bodies run with window checking disabled; C bridges reenable it.
    esp_sr_read(2,230);esp_imm(3,~262144);esp_rrr(0x100000,2,2,3);esp_sr_write(2,230);esp_ins(0x002010);
    esp_imm(8,esp_data_base+16);esp_load(2,8,0);esp_addi(2,2,1);esp_store(2,8,0);
    esp_sr_read(2,232);esp_movi(3,4);esp_guard(1,2,3);esp_stack_check();
    esp_sr_read(2,226);esp_sr_read(3,228);esp_rrr(0x100000,2,2,3);esp_movi(3,0);esp_push();esp_call(esp_dispatch);esp_addi(1,1,8);
    esp_imm(8,esp_data_base+16);esp_load(2,8,0);esp_addi(2,2,-1);esp_store(2,8,0);
    // Optional scheduling tail: ISR callbacks have returned and this task's
    // complete exception frame is still on its own stack. The private ABI
    // preserves it across a full context switch; RFE happens on resumption.
    // Mask every interrupt before dropping into ordinary task scheduling.
    if esp_irq_tail_index>=0 {
        esp_ins(0x006f20);esp_ins(0x002010);esp_load(2,1,68);esp_movi(3,0);esp_push();esp_call(esp_irq_tail_index);esp_addi(1,1,8);
        esp_ins(0x006f20);esp_ins(0x002010);
    }
    if esp_c_enabled {
        i=0;while i<16 {esp_load(2,1,104+i*4);esp_wfr(i,2);i=i+1;}
        esp_load(2,1,92);esp_user_write(2,232);esp_load(2,1,96);esp_user_write(2,233);esp_load(2,1,100);esp_user_write(2,231);esp_load(2,1,88);esp_sr_write(2,224);esp_ins(0x002010);
    }
    esp_load(2,1,64);esp_sr_write(2,177);esp_load(2,1,72);esp_sr_write(2,3);
    i=0;while i<3 {esp_load(2,1,76+i*4);esp_sr_write(2,i);i=i+1;}
    esp_load(2,1,68);esp_sr_write(2,230);esp_ins(0x002010);
    esp_load(0,1,0);i=2;while i<16 {esp_load(i,1,i*4);i=i+1;}
    if irq_frame==192 {esp_addi(1,1,96);esp_addi(1,1,96);}else {esp_addi(1,1,112);}esp_ins(0x003000);return 0;
}
// Keep ordinary IR jumps at three bytes. Only out-of-range edges grow to a
// fixed 24-byte absolute jump; a13 is scratch at an IR instruction boundary.
// Re-emitting one function until no edge grows also handles cascaded ranges.
fn esp_ir_jump(pc) {
    let wide=load64(esp_ir_jumps+pc/2)>>32;
    store64(esp_ir_jumps+pc/2,output_size|(wide<<32));
    if wide {esp_const(13,0);esp_ins(0x0000a0|(13<<8));}else {esp_jump();}return 0;
}
fn esp_function(index) {
    let begin=output_size;let relocations=esp_fixup_count;let stable=0;
    let pc=load64(functions+index*32+16);let slots=load64(esp_ir+pc+8);let end=esp_end(index);
    // Local addresses cannot escape the word IR. Keep source parameter indices,
    // but reserve stack words only for slots read anywhere in the function.
    esp_local_slots=alloc(slots*8+8);if esp_local_slots<0 {fail("cannot allocate ESP32 local-use table");}
    let scan=pc+16;while scan<end {if load64(esp_ir+scan)==3 {store64(esp_local_slots+load64(esp_ir+scan+8)*8,1);}scan=scan+16;}
    let i=0;let used=0;let mask=0;while i<slots {
        if load64(esp_local_slots+i*8) {store64(esp_local_slots+i*8,used);used=used+1;if i<8 {mask=mask|(1<<i);}}
        else {store64(esp_local_slots+i*8,-1);}i=i+1;
    }store64(esp_param_masks+index*8,mask);
    let frame=((used*8+15)/16)*16;if frame>16384 {fail("ESP32 function frame exceeds 16 KiB");}
    while !stable {
        output_size=begin;esp_fixup_count=relocations;esp_function_body(index,frame);stable=1;
        let pc=load64(functions+index*32+16)+16;let end=esp_end(index);
        while pc<end {
            let op=load64(esp_ir+pc);if op>=10 && op<=12 {
                let edge=load64(esp_ir_jumps+pc/2);let at=edge&4294967295;
                let to=load64(esp_map+load64(esp_ir+pc+8)/2);
                let delta=esp_code_address(to)-esp_code_address(at)-4;
                if !(edge>>32) && (delta< -131072 || delta>131071) {
                    store64(esp_ir_jumps+pc/2,at|(1<<32));stable=0;
                }
            }pc=pc+16;
        }
    }return 0;
}
fn esp_function_body(index,frame) {
    store64(esp_functions+index*8,output_size);
    let entry=functions+index*32;let pc=load64(entry+16);let slots=load64(esp_ir+pc+8);let arity=load64(entry+24);
    esp_addi(1,1,-16);esp_stack_check();esp_store(0,1,0);esp_store(14,1,4);esp_mov(14,1);
    esp_imm(8,-frame);esp_rrr(0x800000,1,1,8);esp_stack_check();
    let end=esp_end(index);let i=0;while i<slots {
        if load64(esp_local_slots+i*8)>=0 {
            if i<arity {esp_imm(8,16+(arity-i-1)*8);esp_rrr(0x800000,8,14,8);esp_load(2,8,0);esp_load(3,8,4);}
            else {esp_movi(2,0);esp_movi(3,0);}
            esp_local(i);esp_store(2,8,0);esp_store(3,8,4);
        }i=i+1;
    }
    pc=pc+16;
    while pc<end {
        store64(esp_map+pc/2,output_size);
        let op=load64(esp_ir+pc);let arg=load64(esp_ir+pc+8);
        if op==1 {esp_imm(2,arg);esp_imm(3,arg>>32);}
        else if op==2 {esp_imm(8,esp_code_address(esp_push_entry));esp_ins(0x0008c0);}
        else if op==3 || op==4 {
            // A dead store leaves the accumulator (and all RHS effects) intact.
            if load64(esp_local_slots+arg*8)>=0 {esp_local(arg);if op==3 {esp_load(2,8,0);esp_load(3,8,4);}else {esp_store(2,8,0);esp_store(3,8,4);}}
        }
        else if op==5 || op==6 {esp_imm(8,esp_data_base+arg);if op==5 {esp_load(2,8,0);esp_load(3,8,4);}else {esp_store(2,8,0);esp_store(3,8,4);}}
        else if op==7 {esp_binary(arg);}
        else if op==25 {esp_imm(8,esp_data_base+load64(esp_imports+arg*24+16));esp_load(2,8,0);esp_movi(3,0);}
        else if op==23 || op==24 || op==26 || op==27 {esp_reference(arg,op==24 || op==26);}
        else if op==8 {esp_call(arg);esp_imm(8,load64(functions+arg*32+24)*8);esp_rrr(0x800000,1,1,8);}
        else if op==9 {esp_epilogue();}
        else if op==10 || op==11 || op==12 {
            if op!=10 {esp_rrr(0x200000,6,2,3);esp_movi(7,0);let kind=1;if op==11 {kind=9;}let skip=esp_branch(kind,6,7);esp_ir_jump(pc);esp_patch_branch(skip,output_size);}
            else {esp_ir_jump(pc);}
        }else if op==13 || op==15 {esp_bool(op==15);}
        else if op==14 {esp_neg(2,3);}
        else if op==16 {esp_movi(7,-1);esp_rrr(0x300000,2,2,7);esp_rrr(0x300000,3,3,7);}
        else if op==17 {esp_builtin(arg);}
        else if op==19 || op==20 {esp_word_io(op==20);}
        else if op==21 || op==22 {esp_state_index(arg,op==22);}
        else {fail("unsupported ESP32 instruction");}pc=pc+16;
    }
    return 0;
}
// Portable FIR3 operands hold a byte base plus a checked array word span.
// Keep all64 index bits until after the bounds check; stores retain a2:a3.
fn esp_state_index(arg,storing) {
    if storing {esp_pop(4,5);}else {esp_mov(4,2);esp_mov(5,3);}
    esp_movi(7,0);esp_guard(1,5,7);esp_imm(8,arg>>32);esp_guard(3,4,8);
    esp_slli(6,4,3);esp_imm(8,esp_data_base+(arg&4294967295));esp_rrr(0x800000,8,8,6);
    if storing {esp_store(2,8,0);esp_store(3,8,4);}else {esp_load(2,8,0);esp_load(3,8,4);}return 0;
}
// FIR word messages use UART0's configured console: eight little-endian bytes.
// Reads block for a complete word; a successful write returns its input word.
fn esp_word_io(reading) {
    let uart=0x60000000;let count_bits=10;if esp32_target==2 {uart=0x3ff40000;count_bits=8;}esp_imm(8,uart);
    if reading {esp_movi(2,0);esp_movi(3,0);}let i=0;while i<8 {
        let loop=output_size;
        // Classic erratum3.21: no interrupt may split status/FIFO access.
        // Restore the exact caller PS while waiting for the next byte.
        if reading && esp32_target==2 {esp_ins(0x006fa0);}
        esp_ins(0x0020c0);esp_load(6,8,28);let start=16;let threshold=126;let condition=3;
        if reading {start=0;threshold=0;condition=9;}esp_ext(6,6,start,count_bits);esp_movi(9,threshold);let ready=esp_branch(condition,6,9);
        if reading && esp32_target==2 {esp_sr_write(10,230);esp_ins(0x002010);}
        esp_j(loop);esp_patch_branch(ready,output_size);
        let word=2;if i>=4 {word=3;}let shift=(i&3)*8;
        if reading {esp_load(7,8,0);esp_ins(0x0020c0);if esp32_target==2 {esp_sr_write(10,230);esp_ins(0x002010);}esp_ext(7,7,0,8);if shift {esp_slli(7,7,shift);}esp_rrr(0x200000,word,word,7);}
        else {esp_ext(7,word,shift,8);esp_store(7,8,0);}esp_ins(0x0020c0);i=i+1;
    }if !reading {let flush=output_size;esp_ins(0x0020c0);esp_load(6,8,28);let bits=count_bits;if esp32_target==2 {bits=12;}esp_ext(6,6,16,bits);esp_movi(9,0);let done=esp_branch(1,6,9);esp_j(flush);esp_patch_branch(done,output_size);}return 0;
}
fn esp_write_register(address,value) {esp_imm(8,address);esp_imm(2,value);esp_ins(0x0020c0);esp_store(2,8,0);esp_ins(0x0020c0);return 0;}
fn esp_fault_byte() {
    // a7 byte; no stack, allocation or external call in the fail-stop path.
    let uart=0x60000000;if esp32_target==2 {uart=0x3ff40000;}esp_imm(8,uart);esp_movi(11,1000);let loop=output_size;
    esp_load(9,8,28);esp_ext(9,9,16,10);esp_movi(12,126);let ready=esp_branch(3,9,12);esp_addi(11,11,-1);esp_movi(12,0);let timeout=esp_branch(1,11,12);esp_j(loop);
    esp_patch_branch(ready,output_size);esp_ins(0x0020c0);esp_store(7,8,0);esp_ins(0x0020c0);esp_patch_branch(timeout,output_size);return 0;
}
fn esp_fault_report() {
    esp_movi(7,33);esp_fault_byte();let field=0;while field<4 {
        let sr=232;if field==1 {sr=177;}if field==2 {sr=238;}if field==3 {sr=230;}esp_sr_read(6,sr);
        let n=0;while n<8 {esp_ext(7,6,28-n*4,4);esp_addi(7,7,48);esp_movi(12,58);let digit=esp_branch(3,7,12);esp_addi(7,7,39);esp_patch_branch(digit,output_size);esp_fault_byte();n=n+1;}
        esp_movi(7,32);esp_fault_byte();field=field+1;
    }esp_movi(7,13);esp_fault_byte();esp_movi(7,10);esp_fault_byte();return 0;
}
fn esp_start(main_index) {
    while output_size<1024 {emit(0);}
    esp_write_register(esp_data_base+4,0x54524150);if esp_flash {esp_fault_report();}esp_j(output_size);while output_size%4 {emit(0);}let entry=output_size;
    esp_movi(2,15);esp_ins(0x13e620);esp_ins(0x002010); // PS: call0, ring0, interrupts masked.
    // Drop the ROM caller's register windows before installing our private root.
    esp_movi(2,0);esp_sr_write(2,72);esp_ins(0x002010);esp_movi(2,1);esp_sr_write(2,73);esp_ins(0x002010);
    esp_imm(1,esp_stack_top);esp_movi(14,0);
    if esp_c_enabled {esp_movi(2,1);esp_sr_write(2,224);esp_ins(0x002010);}
    esp_imm(2,esp_code_base);esp_ins(0x13e720);esp_ins(0x002010); // VECBASE; rsync
    // RTC and timer-group watchdogs may have been enabled by ROM/download stub.
    if esp32_target==2 {
        esp_write_register(0x3ff480a4,0x50d83aa1);esp_write_register(0x3ff4808c,0);esp_write_register(0x3ff480a4,0);
        esp_write_register(0x3ff5f064,0x50d83aa1);esp_write_register(0x3ff5f048,0);esp_write_register(0x3ff5f064,0);
        esp_write_register(0x3ff60064,0x50d83aa1);esp_write_register(0x3ff60048,0);esp_write_register(0x3ff60064,0);
    }else {
    esp_write_register(0x600080b0,0x50d83aa1);esp_write_register(0x60008098,0);esp_write_register(0x600080b0,0);
    esp_write_register(0x600080b8,0x8f1d312a);esp_write_register(0x600080b4,0x80000000);esp_write_register(0x600080b8,0);
    esp_write_register(0x6001f064,0x50d83aa1);esp_write_register(0x6001f048,0);esp_write_register(0x6001f064,0);
    esp_write_register(0x60020064,0x50d83aa1);esp_write_register(0x60020048,0);esp_write_register(0x60020064,0);
    }
    esp_write_register(esp_data_base+20,esp_stack_floor);let native_heap=esp_native_heap_begin();esp_write_register(esp_data_base,native_heap);if esp_flash {esp_call(find(functions,function_count,"esp_xip_enable",14));esp_rrr(0x200000,6,2,3);esp_movi(7,0);esp_guard(1,6,7);}if esp_platform_entry>=0 {esp_call(esp_platform_entry);esp_rrr(0x200000,6,2,3);esp_movi(7,0);esp_guard(1,6,7);}esp_call(main_index);
    esp_imm(8,esp_data_base+8);esp_store(2,8,0);esp_store(3,8,4);
    esp_write_register(esp_data_base+4,0x444f4e45);esp_j(output_size);
    let i=0;while i<1024 {esp_patch_jump(i,esp_trap);i=i+64;}esp_window_vectors();return entry;
}
fn esp32_finish() {
    let main_index=find(functions,function_count,"main",4);
    if main_index<0 || load64(functions+main_index*32+24) {fail("ESP32 requires main() with no parameters");}
    if esp_s3_sdk && vm_heap_used>16384 {fail("ESP32-S3 SDK static data exceeds 16 KiB");}if vm_heap_used>65536 {fail("ESP32 static data exceeds 64 KiB");}if esp_radio && vm_heap_used>32768 {fail("ESP32 radio static data overlaps reserved ROM SRAM");}
    esp_ir=output;esp_ir_size=output_size;esp_seen=alloc(function_count*8);esp_c_thunks=alloc(function_count*8);esp_param_masks=alloc(function_count*8);esp_iram_functions=alloc(function_count*8);esp_map=alloc(esp_ir_size/2);esp_ir_jumps=alloc(esp_ir_size/2);
    esp_functions=alloc(function_count*8);esp_fixups=alloc(65536*16);esp_fixup_count=0;
    if esp_ir_jumps<0 || esp_iram_functions<0 || esp_param_masks<0 || esp_c_thunks<0 || esp_seen<0 || esp_map<0 || esp_functions<0 || esp_fixups<0 {fail("cannot allocate ESP32 backend tables");}
    esp_import_used=alloc(esp_import_count*8+8);if esp_import_used<0 {fail("cannot allocate ESP32 import table");}
    if esp_platform_path {esp_platform_entry=find(functions,function_count,"esp_platform_init",17);if esp_platform_entry>=0 {if load64(functions+esp_platform_entry*32+24) {fail("esp_platform_init must take no parameters");}esp_reachable(esp_platform_entry);}}
    esp_reachable(main_index);if esp_flash {let map=find(functions,function_count,"esp_xip_enable",14);if map<0 || load64(functions+map*32+24) {if esp_s3_xip {fail("esp32s3-xip-elf requires esp_xip_enable() from platform/esp32s3-xip.flex");}fail("esp32-xip-elf requires esp_xip_enable() from platform/esp32-xip.flex");}esp_reachable(map);}esp_dispatch=find(functions,function_count,"esp_irq_dispatch",16);
    if esp_dispatch>=0 {if load64(functions+esp_dispatch*32+24)!=1 {fail("esp_irq_dispatch must take one parameter");}esp_reachable(esp_dispatch);}
    esp_irq_tail_index=find(functions,function_count,"esp_irq_epilogue",16);
    if esp_irq_tail_index>=0 {
        if esp_dispatch<0 {fail("esp_irq_epilogue requires esp_irq_dispatch");}
        if load64(functions+esp_irq_tail_index*32+24)!=1 {fail("esp_irq_epilogue must take one parameter");}
        esp_reachable(esp_irq_tail_index);store64(esp_iram_functions+esp_irq_tail_index*8,1);
    }
    esp_iram_closure();
    output=alloc(output_limit);if output<0 {fail("cannot allocate ESP32 machine code");}output_size=0;
    let entry=esp_start(main_index);esp_push_entry=output_size;esp_push();esp_ins(0x80);if esp_dispatch>=0 {esp_interrupt_entry();esp_patch_jump(0x300,esp_irq_entry);esp_patch_jump(0x340,esp_irq_entry);}
    let flash_init=-1;let i=0;if esp_flash {
        flash_init=find(functions,function_count,"esp_xip_enable",14);esp_function(flash_init);
        i=0;while i<function_count {if load64(esp_seen+i*8) && load64(esp_iram_functions+i*8) && i!=flash_init {esp_function(i);}i=i+1;}
        i=0;while i<function_count {if load64(esp_c_thunks+i*8) && load64(esp_iram_functions+i*8) {esp_c_callback(i);}i=i+1;}
        while output_size%4 {emit(0);}esp_iram_size=output_size;if esp_iram_size>esp_code_capacity() {if esp_s3_xip {fail("ESP32-S3 cached SRAM callbacks exceed 96 KiB IRAM region");}fail("ESP32 SRAM callbacks exceed 128 KiB IRAM region");}while output_size<0x50000 {emit(0);}
    }
    i=0;while i<function_count {if load64(esp_seen+i*8) && i!=flash_init && (!esp_flash || !load64(esp_iram_functions+i*8)) {esp_function(i);}i=i+1;}
    i=0;while i<function_count {if load64(esp_c_thunks+i*8) && (!esp_flash || !load64(esp_iram_functions+i*8)) {esp_c_callback(i);}i=i+1;}
    let code_size=output_size;if code_size>esp_code_capacity() && !esp_flash {if esp_s3_sdk {fail("ESP32-S3 SDK machine code exceeds 192 KiB IRAM region");}fail("ESP32 machine code exceeds 128 KiB IRAM region");}
    i=0;while i<esp_fixup_count {let site=esp_fixups+i*16;let encoded=load64(site);output_size=encoded&4294967295;let reg=(encoded>>32)&15;let table=esp_functions;if encoded>>40 {table=esp_c_thunks;}esp_const(reg,esp_code_address(load64(table+load64(site+8)*8)));i=i+1;}
    output_size=code_size;i=0;
    while i<function_count {
        if load64(esp_seen+i*8) {
            let pc=load64(functions+i*32+16)+16;let end=esp_end(i);
            while pc<end {
                let op=load64(esp_ir+pc);if op>=10 && op<=12 {
                    let edge=load64(esp_ir_jumps+pc/2);let at=edge&4294967295;let to=load64(esp_map+load64(esp_ir+pc+8)/2);
                    if edge>>32 {output_size=at;esp_const(13,esp_code_address(to));output_size=code_size;}
                    else {esp_patch_jump(at,to);}
                }pc=pc+16;
            }
        }i=i+1;
    }
    while output_size%4 {emit(0);}code_size=output_size;let code=output;
    if esp_elf {esp_elf_image(code,code_size,entry);return 0;}
    let used=0;i=0;while i<esp_import_count {used=used+load64(esp_import_used+i*8);i=i+1;}if used {fail("esp32_external requires an esp32-elf or esp32s3-elf link target");}
    // ROM image: 24-byte S3 header, two RAM segments, XOR checksum, SHA-256 suffix (also checked by ROM when hash_appended is zero).
    output=alloc(code_size+vm_heap_used+128);if output<0 {fail("cannot allocate ESP32 firmware image");}output_size=0;
    emit(0xe9);emit(2);emit(2);emit(0x20);emit32(esp_code_base+entry);
    emit(0xee);emit(0);emit(0);emit(0);let chip=9;if esp32_target==2 {chip=0;}emit(chip);emit(0);emit(0);emit(0);emit(0);emit(255);emit(255);
    while output_size<23 {emit(0);}emit(1);
    let checksum=0xef;emit32(esp_code_base);emit32(code_size);i=0;
    while i<code_size {let byte=load8(code+i);emit(byte);checksum=checksum^byte;i=i+1;}
    emit32(esp_data_base);emit32(vm_heap_used);i=0;
    while i<vm_heap_used {let byte=load8(vm_heap+i);emit(byte);checksum=checksum^byte;i=i+1;}
    while output_size%16!=15 {emit(0);}emit(checksum);
    up_k=alloc(512);up_hash=alloc(64);up_words=alloc(512);up_block=alloc(64);up_digest=alloc(65);
    if up_k<0 || up_hash<0 || up_words<0 || up_block<0 || up_digest<0 {fail("cannot allocate ESP32 image digest");}
    up_sha_constants();let digest=up_sha256(output,output_size);i=0;
    while i<64 {emit(up_hex(load8(digest+i))*16+up_hex(load8(digest+i+1)));i=i+2;}return 0;
}

fn esp_external() {
    expect(40);if token!=258 || token_size<3 || token_size>130 {fail("esp32_external expects a symbol string");}
    let name=source+token_start+1;let size=token_size-2;let i=0;while i<size {let c=load8(name+i);if !((c>=65 && c<=90) || (c>=97 && c<=122) || c==95 || (i && c>=48 && c<=57)) {fail("invalid ESP32 external symbol name");}i=i+1;}
    if !esp_imports {esp_imports=alloc(4096*24);if esp_imports<0 {fail("cannot allocate ESP32 imports");}}
    i=0;while i<esp_import_count && !equal(name,size,load64(esp_imports+i*24),load64(esp_imports+i*24+8)) {i=i+1;}
    if i==esp_import_count {if i>=4096 {fail("too many ESP32 imports");}let slot=vm_allocate(8);if slot<0 {fail("cannot allocate ESP32 import pointer");}store64(esp_imports+i*24,name);store64(esp_imports+i*24+8,size);store64(esp_imports+i*24+16,slot);esp_import_count=esp_import_count+1;}
    next();expect(41);vm_emit(25,i);return 0;
}
fn esp_elf16(n) {emit(n);emit(n>>8);return 0;}
fn esp_elf_name(name,size) {let offset=esp_elf_name_size;let i=0;while i<size {store8(esp_elf_names+esp_elf_name_size,load8(name+i));esp_elf_name_size=esp_elf_name_size+1;i=i+1;}store8(esp_elf_names+esp_elf_name_size,0);esp_elf_name_size=esp_elf_name_size+1;return offset;}
fn esp_elf_symbol(name,size,value,bytes,kind,section) {emit32(esp_elf_name(name,size));emit32(value);emit32(bytes);emit(kind);emit(0);esp_elf16(section);return 0;}
fn esp_elf_section(name,kind,flags,address,offset,size,link,info,align,entry) {emit32(name);emit32(kind);emit32(flags);emit32(address);emit32(offset);emit32(size);emit32(link);emit32(info);emit32(align);emit32(entry);return 0;}
fn esp_elf_image(code,code_size,entry) {
    let string_capacity=1;let symbols=1;let i=0;
    while i<function_count {if load64(esp_c_thunks+i*8) {symbols=symbols+1;string_capacity=string_capacity+load64(functions+i*32+8)+1;}i=i+1;}
    i=0;while i<global_count {symbols=symbols+1;string_capacity=string_capacity+load64(globals+i*32+8)+1;i=i+1;}
    let imports=0;i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {imports=imports+1;symbols=symbols+1;string_capacity=string_capacity+load64(esp_imports+i*24+8)+1;}i=i+1;}
    esp_elf_names=alloc(string_capacity);if esp_elf_names<0 {fail("cannot allocate ESP32 ELF names");}esp_elf_name_size=1;
    let headers=116;let nsections=8;let nloads=2;let iram=code_size;let flash_size=0;if esp_flash {headers=148;nsections=9;nloads=3;iram=esp_iram_size;flash_size=code_size-0x50000;}
    let flash_at=headers+iram;let data_at=flash_at+flash_size;let imports_at=data_at+vm_heap_used;let info_at=imports_at+imports*8;let symbols_at=info_at+32;
    let strings_at=symbols_at+symbols*16;let names_at=strings_at+string_capacity;
    let names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,";if esp_flash {names=".text,.data,.flex.imports,.flex.info,.symtab,.strtab,.shstrtab,.flex.irom,";}let names_size=length(names)+1;
    let sections_at=(names_at+names_size+3)&~3;output=alloc(sections_at+nsections*40);if output<0 {fail("cannot allocate ESP32 ELF image");}output_size=0;
    emit(127);emit(69);emit(76);emit(70);emit(1);emit(1);emit(1);while output_size<16 {emit(0);}
    esp_elf16(2);esp_elf16(94);emit32(1);emit32(esp_code_base+entry);emit32(52);emit32(sections_at);emit32(0);
    esp_elf16(52);esp_elf16(32);esp_elf16(nloads);esp_elf16(40);esp_elf16(nsections);esp_elf16(7);
    i=0;while i<nloads {let base=esp_code_base;let offset=headers;let size=iram;let flags=5;if i==1 {base=esp_data_base;offset=data_at;size=vm_heap_used;flags=6;}if i==2 {base=esp_irom_base();offset=flash_at;size=flash_size;}
        emit32(1);emit32(offset);emit32(base);emit32(base);emit32(size);emit32(size);emit32(flags);emit32(4);i=i+1;}
    i=0;while i<iram {emit(load8(code+i));i=i+1;}i=0;while i<flash_size {emit(load8(code+0x50000+i));i=i+1;}i=0;while i<vm_heap_used {emit(load8(vm_heap+i));i=i+1;}
    // Record import symbol-name offsets and the in-DRAM pointer slots to patch.
    let import_offsets=alloc(esp_import_count*8+8);if import_offsets<0 {fail("cannot allocate ESP32 ELF import offsets");}
    i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {let at=esp_elf_name(load64(esp_imports+i*24),load64(esp_imports+i*24+8));store64(import_offsets+i*8,at);emit32(at);emit32(esp_data_base+load64(esp_imports+i*24+16));}i=i+1;}
    emit32(1);let chip=9;if esp32_target==2 {chip=0;}emit32(chip);emit32(esp_code_base);emit32(esp_data_base);emit32(esp_stack_floor);emit32(esp_stack_top);let hb=esp_native_heap_begin();let he=esp_native_heap_end();emit32(hb);emit32(he);
    i=0;while i<16 {emit(0);i=i+1;}
    i=0;while i<function_count {if load64(esp_c_thunks+i*8) {let section=1;if esp_flash && load64(esp_c_thunks+i*8)>=0x50000 {section=8;}esp_elf_symbol(load64(functions+i*32),load64(functions+i*32+8),esp_code_address(load64(esp_c_thunks+i*8)),0,18,section);}i=i+1;}
    i=0;while i<global_count {esp_elf_symbol(load64(globals+i*32),load64(globals+i*32+8),esp_data_base+load64(globals+i*32+16),8,17,2);i=i+1;}
    i=0;while i<esp_import_count {if load64(esp_import_used+i*8) {emit32(load64(import_offsets+i*8));emit32(0);emit32(0);emit(16);emit(0);esp_elf16(0);}i=i+1;}
    if esp_elf_name_size!=string_capacity || output_size!=strings_at {fail("internal ESP32 ELF layout mismatch");}
    i=0;while i<string_capacity {emit(load8(esp_elf_names+i));i=i+1;}emit(0);i=0;while i<names_size-1 {let c=load8(names+i);if c==44 {c=0;}emit(c);i=i+1;}
    while output_size<sections_at {emit(0);}i=0;while i<40 {emit(0);i=i+1;}
    esp_elf_section(1,1,6,esp_code_base,headers,iram,0,0,4,0);esp_elf_section(7,1,3,esp_data_base,data_at,vm_heap_used,0,0,8,0);
    esp_elf_section(13,1,0,0,imports_at,imports*8,0,0,4,8);esp_elf_section(27,1,0,0,info_at,32,0,0,4,0);
    esp_elf_section(38,2,0,0,symbols_at,symbols*16,6,1,4,16);esp_elf_section(46,3,0,0,strings_at,string_capacity,0,0,1,0);
    esp_elf_section(54,3,0,0,names_at,names_size,0,0,1,0);if esp_flash {esp_elf_section(64,1,6,esp_irom_base(),flash_at,flash_size,0,0,4,0);}return 0;
}

fn esp_user_read(reg,sr) {esp_ins(0xe30000|(reg<<12)|(sr<<4));return 0;}
fn esp_user_write(reg,sr) {esp_ins(0xf30000|(sr<<8)|(reg<<4));return 0;}
fn esp_rfr(reg,fp) {esp_ins(0xfa0040|(reg<<12)|(fp<<8));return 0;}
fn esp_wfr(fp,reg) {esp_ins(0xfa0050|(fp<<12)|(reg<<8));return 0;}
fn esp_context_pointer(reg,high) {
    esp_movi(7,0);esp_guard(1,high,7);esp_ext(6,reg,0,4);esp_guard(1,6,7);
    esp_imm(7,esp_data_base+24);esp_guard(11,reg,7);esp_imm(7,esp_stack_floor-512);esp_guard(11,7,reg);return 0;
}
fn esp_context_switch() {
    // 512-byte context: all 64 ARs, PC/window/special registers and FPU state.
    // This is a task operation, never an ISR operation. EXCSAVE3..5 are scratch
    // while INTLEVEL=15; no call or allocation occurs during the switch.
    esp_load(8,1,8);esp_load(5,1,12);esp_context_pointer(8,5);
    esp_load(9,1,0);esp_load(5,1,4);esp_context_pointer(9,5);esp_addi(1,1,16);
    esp_imm(4,esp_data_base+16);esp_load(5,4,0);esp_movi(7,0);esp_guard(1,5,7);
    esp_ins(0x006f20);esp_store(2,8,272);esp_ext(4,2,18,1);esp_guard(1,4,7);
    esp_sr_write(8,212);esp_sr_write(9,213);let resume=output_size;esp_const(2,0);esp_store(2,8,256);
    esp_sr_read(2,72);esp_store(2,8,260);esp_sr_read(2,73);esp_store(2,8,264);esp_sr_read(2,3);esp_store(2,8,268);
    let i=0;while i<3 {esp_sr_read(2,i);esp_store(2,8,276+i*4);i=i+1;}
    esp_user_read(2,231);esp_store(2,8,288);esp_sr_read(2,224);esp_store(2,8,292);esp_movi(2,1);esp_sr_write(2,224);esp_ins(0x002010);
    esp_user_read(2,232);esp_store(2,8,296);esp_user_read(2,233);esp_store(2,8,300);
    esp_imm(4,esp_data_base+20);esp_load(2,4,0);esp_store(2,8,304);
    i=0;while i<16 {esp_rfr(2,i);esp_store(2,8,320+i*4);i=i+1;}
    i=0;while i<16 {esp_store(i,8,i*4);i=i+1;}
    let block=1;while block<4 {
        esp_ins(0x408040);esp_sr_write(0,211);esp_sr_read(0,212);
        i=1;while i<16 {esp_store(i,0,block*64+i*4);i=i+1;}
        esp_sr_read(1,211);esp_store(1,0,block*64);block=block+1;
    }
    esp_sr_read(0,213);esp_load(2,0,260);esp_sr_write(2,72);esp_ins(0x002010);
    // Load inactive windows first and the resumed private window last.
    block=1;while block<4 {esp_ins(0x408040);esp_sr_read(0,213);i=1;while i<16 {esp_load(i,0,block*64+i*4);i=i+1;}esp_load(0,0,block*64);block=block+1;}
    esp_ins(0x408040);esp_sr_read(0,213);
    i=0;while i<16 {esp_load(2,0,320+i*4);esp_wfr(i,2);i=i+1;}
    esp_load(2,0,296);esp_user_write(2,232);esp_load(2,0,300);esp_user_write(2,233);
    esp_load(2,0,264);esp_sr_write(2,73);esp_load(2,0,268);esp_sr_write(2,3);
    i=0;while i<3 {esp_load(2,0,276+i*4);esp_sr_write(2,i);i=i+1;}
    esp_load(2,0,288);esp_user_write(2,231);esp_load(2,0,292);esp_sr_write(2,224);
    esp_load(2,0,304);esp_imm(4,esp_data_base+20);esp_store(2,4,0);
    esp_load(2,0,272);esp_sr_write(2,211);i=1;while i<16 {esp_load(i,0,i*4);i=i+1;}
    esp_load(8,0,256);esp_sr_read(2,211);esp_sr_write(2,230);esp_ins(0x002010);esp_ins(0x0008a0);
    let end=output_size;output_size=resume;esp_const(2,esp_code_address(end));output_size=end;esp_movi(2,0);esp_movi(3,0);return 0;
}
