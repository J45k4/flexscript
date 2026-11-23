// Instantiate this profile for each checked scratch capacity.

requires io_capacity==SCRATCH_CAPACITY;
requires writable_bytes(io_arena,io_capacity*33+8);
reads io_arena,io_capacity,io_code,io_flags,io_map,io_work;
modifies io_code,io_flags,io_map,io_work;
ensures io_code==io_arena;
ensures io_flags==io_code+io_capacity*16;
ensures io_map==io_flags+io_capacity;
ensures io_work==io_map+(io_capacity+1)*8;
ensures writable_bytes(io_code,io_capacity*16);
ensures writable_bytes(io_flags,io_capacity);
ensures writable_bytes(io_map,(io_capacity+1)*8);
ensures writable_bytes(io_work,io_capacity*8);
ensures disjoint_bytes(io_code,io_capacity*16,io_flags,io_capacity);
ensures disjoint_bytes(io_code,io_capacity*16,io_map,(io_capacity+1)*8);
ensures disjoint_bytes(io_code,io_capacity*16,io_work,io_capacity*8);
ensures disjoint_bytes(io_flags,io_capacity,io_map,(io_capacity+1)*8);
ensures disjoint_bytes(io_flags,io_capacity,io_work,io_capacity*8);
ensures disjoint_bytes(io_map,(io_capacity+1)*8,io_work,io_capacity*8);
fn SCRATCH_LAYOUT() {
    SCRATCH_PUBLICATION

    return 0;
}

