// Relax native source branches using recorded instruction boundaries, never
// by decoding bytes (which may be writable strings or embedded asset data).
// Records: original start/target, opcode, short flag, current displacement
// site/width, and savings before/after the original instruction.
global native_branches=0;
global native_branch_count=0;
global native_branch_mode=0;
global native_branch_cursor=0;
global native_branch_overflow=0;
fn native_branch_begin() {
    native_branch_count=0;native_branch_cursor=0;native_branch_overflow=0;
    native_branch_mode=0;
    if !frontend_language && (native_link_replay || native_keep_unused) {native_branch_mode=1;}
    return 0;
}
fn native_branch_emit(opcode) {
    if native_branch_mode==1 && native_branch_count>=131072 {native_branch_overflow=1;return 0;}
    if !native_branches {native_branches=alloc(131072*64);if native_branches<0 {fail("cannot allocate native branches");}}
    let index=native_branch_count;
    if native_branch_mode==2 {index=native_branch_cursor;native_branch_cursor=index+1;if index>=native_branch_count {fail("native branch replay differs");}}
    let r=native_branches+index*64;
    if native_branch_mode==1 {
        native_branch_count=index+1;store64(r,output_size);store64(r+8,-1);store64(r+16,opcode);store64(r+24,0);
    }else if load64(r+16)!=opcode {fail("native branch opcode differs");}
    let width=4;
    if load64(r+24) {
        width=1;let op=opcode-16;if opcode==233 {op=235;}emit(op);
    }else {if opcode!=233 {emit(15);}emit(opcode);}
    store64(r+32,output_size);store64(r+40,width);
    if width==1 {emit(0);}else {emit32(0);}return -index-1;
}
fn native_branch_patch(handle,target) {
    let r=native_branches+(-handle-1)*64;let at=load64(r+32);let width=load64(r+40);
    if native_branch_mode==1 {store64(r+8,target);}
    let distance=target-at-width;
    if width==1 {if distance< -128 || distance>127 {fail("native short branch out of range");}store8(output+at,distance);}
    else {patch32(at,distance);}return 0;
}
fn native_branch_prefix() {
    let saved=0;let i=0;while i<native_branch_count {
        let r=native_branches+i*64;store64(r+48,saved);
        if load64(r+24) {let bytes=4;if load64(r+16)==233 {bytes=3;}saved=saved+bytes;}
        store64(r+56,saved);i=i+1;
    }return saved;
}
fn native_branch_position(position) {
    // Prefix values are a snapshot: selecting another short branch during
    // this iteration must not change the layout used to assess its neighbours.
    let lo=0;let hi=native_branch_count;
    while lo<hi {let mid=(lo+hi)/2;if load64(native_branches+mid*64)<position {lo=mid+1;}else {hi=mid;}}
    if !lo {return position;}return position-load64(native_branches+(lo-1)*64+56);
}
fn native_branch_relax() {
    native_branch_mode=0;
    if native_branch_overflow || !native_branch_count {return 0;}
    let changed=1;let rounds=0;
    // Shortening is monotonic. The cap bounds pathological layout work; any
    // branches left long remain valid even if further rounds could shrink them.
    while changed && rounds<64 {
        native_branch_prefix();changed=0;let i=0;
        while i<native_branch_count {
            let r=native_branches+i*64;let start=load64(r);let target=load64(r+8);
            if target<0 {fail("unpatched native branch");}
            if !load64(r+24) {
                let distance=native_branch_position(target)-(start-load64(r+48))-2;
                if target>start {let saved=4;if load64(r+16)==233 {saved=3;}distance=distance-saved;}
                if distance>= -128 && distance<=127 {store64(r+24,1);changed=1;}
            }i=i+1;
        }rounds=rounds+1;
    }
    let saved=native_branch_prefix();
    if saved {native_branch_cursor=0;native_branch_mode=2;}return saved;
}
fn native_branch_end() {
    if native_branch_mode==2 && native_branch_cursor!=native_branch_count {fail("native branch count differs");}
    native_branch_mode=0;return 0;
}
