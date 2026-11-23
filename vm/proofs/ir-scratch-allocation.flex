// Growth and reuse branches of the production optimizer arena.

requires count>=1 && count<=16777216;
requires io_capacity==0 || io_capacity>=256 && io_capacity<count;
requires (io_capacity&(io_capacity-1))==0;
requires count>io_capacity;
modifies io_arena,io_capacity;
ensures result==0 || result==-1;
ensures result!=0 || io_capacity>=count;
ensures result!=0 || io_capacity>=256 && io_capacity<=16777216;
ensures result!=0 || (io_capacity&(io_capacity-1))==0;
ensures result!=0 || writable_bytes(io_arena,io_capacity*33+8);

fn io_grow_optimizer_scratch(count) {
    if count>io_capacity {
        let capacity=io_capacity;if !capacity {capacity=256;}
        invariant capacity>=256 && capacity<=16777216;
        invariant (capacity&(capacity-1))==0;
        decreases 16777216-capacity;
        while capacity<count {
            proof {io_scratch_double_capacity(capacity,count);assert capacity*2>=256;}
            capacity=capacity*2;
        }
        io_arena=alloc(capacity*33+8);if io_arena<0 {return -1;}io_capacity=capacity;
        proof {assert count<=io_capacity;assert writable_bytes(io_arena,io_capacity*33+8);}
    }
    return 0;
}

requires capacity>=1 && capacity<count && count<=16777216;
requires (capacity&(capacity-1))==0;
ensures capacity*2>=1 && capacity*2<=16777216;
ensures (capacity*2&(capacity*2-1))==0;
ensures 16777216-capacity*2<16777216-capacity;
lemma fn io_scratch_double_capacity(capacity,count) {
    if capacity>8388608 {
        assert (capacity&8388608)!=0;
        assert ((capacity-1)&8388608)!=0;
        assert (capacity&(capacity-1))!=0;
    }
    assert capacity<=8388608;
    assert capacity*2==capacity<<1;
    assert (capacity*2-1)>>1==capacity-1;
    assert ((capacity*2&(capacity*2-1))>>1)==(capacity&(capacity-1));
    assert ((capacity*2&(capacity*2-1))&1)==0;
    assert capacity*2>capacity;
}

requires count>=1 && count<=io_capacity && io_capacity<=16777216;
requires io_capacity>=256 && (io_capacity&(io_capacity-1))==0;
requires writable_bytes(io_arena,io_capacity*33+8);
modifies nothing;
ensures result==0;
ensures io_capacity==old(io_capacity) && io_arena==old(io_arena);
ensures writable_bytes(io_arena,io_capacity*33+8);
fn io_reuse_optimizer_scratch(count) {
    proof {assert count<=io_capacity;}
    if count>io_capacity {
        proof {assert 0;}
        let capacity=io_capacity;if !capacity {capacity=256;}
        invariant capacity>=256 && capacity<=16777216;
        invariant (capacity&(capacity-1))==0;
        decreases 16777216-capacity;
        while capacity<count {
            proof {io_scratch_double_capacity(capacity,count);assert capacity*2>=256;}
            capacity=capacity*2;
        }
        io_arena=alloc(capacity*33+8);if io_arena<0 {return -1;}io_capacity=capacity;
        proof {assert count<=io_capacity;assert writable_bytes(io_arena,io_capacity*33+8);}
    }
    proof {assert writable_bytes(io_arena,io_capacity*33+8);}
    return 0;
}

