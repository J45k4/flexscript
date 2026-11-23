fn exercise_growth(old_capacity,count,expected) {
    io_capacity=old_capacity;
    io_arena=0;
    if io_grow_optimizer_scratch(count)!=0 || io_capacity!=expected || io_arena<=0 {return 2;}
    store8(io_arena,79);
    store64(io_arena+expected*33,0x9cf00000+count);
    if load8(io_arena)!=79 || load64(io_arena+expected*33)!=0x9cf00000+count {return 3;}
    let arena=io_arena;
    if io_reuse_optimizer_scratch(count)!=0 || io_arena!=arena || io_capacity!=expected {return 4;}
    if load64(io_arena+expected*33)!=0x9cf00000+count {return 5;}
    return 0;
}
fn test_growth() {
    if exercise_growth(0,1,256) {return 2;}
    let capacity=256;
    while capacity<16777216 {
        let status=exercise_growth(capacity,capacity+1,capacity*2);
        if status {return status;}
        status=exercise_growth(0,capacity,capacity);
        if status {return status;}
        capacity=capacity*2;
    }
    return 0;
}

fn exercise_layout() {
    let code_size=io_capacity<<4;
    let map_size=(io_capacity<<3)+8;
    let work_size=io_capacity<<3;
    if io_code!=io_arena || io_flags-io_code!=code_size || io_map-io_flags!=io_capacity || io_work-io_map!=map_size {return 2;}
    if io_work+work_size-io_arena!=33*io_capacity+8 {return 3;}
    store64(io_code+code_size-8,11);
    store8(io_flags+io_capacity-1,23);
    store64(io_map+map_size-8,37);
    store64(io_work+work_size-8,51);
    if load64(io_code+code_size-8)!=11 || load8(io_flags+io_capacity-1)!=23 {return 4;}
    if load64(io_map+map_size-8)!=37 || load64(io_work+work_size-8)!=51 {return 5;}
    return 0;
}

fn test_scratch_layout() {
    let level=8;
    while level<=24 {
        io_capacity=1<<level;
        io_arena=alloc(io_capacity*33+8);
        if io_arena<=0 {return 1;}
        // Publish the checked scratch layout.
        let stopped=exercise_layout();
        if stopped {return stopped;}
        level=level+1;
    }
    return 0;
}

fn main() {
    let status=test_growth();
    if status {return status;}
    return test_scratch_layout();
}
