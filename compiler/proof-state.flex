// Shared storage layout only; symbolic and concrete evaluators remain separate.
// State: function, locals, old parameters, live path, return value, call depth,
// current globals, old globals, returned globals, parent call, successful return
// path, entry-measure tuple pointer, current/old/returned memory, frame context.
// Concrete replay does not use the return-path accumulator.
// Each call snapshots globals after its argument expressions have executed.
fn ps_state_size(f) {return 128+(load64(f+88)+load64(f+56)+pf_gcount*3+16)*8;}
fn ps_state_pointers(state) {
    let f=load64(state);store64(state+8,state+128);store64(state+16,state+128+load64(f+88)*8);
    store64(state+48,load64(state+16)+load64(f+56)*8);store64(state+56,load64(state+48)+pf_gcount*8);
    store64(state+64,load64(state+56)+pf_gcount*8);store64(state+88,load64(state+64)+pf_gcount*8);return 0;
}
fn ps_state(f,args,globals,path,level,parent,zero) {
    let state=alloc(ps_state_size(f));if state<0 {fail("cannot allocate proof state");}
    store64(state,f);ps_state_pointers(state);store64(state+24,path);store64(state+32,zero);store64(state+40,level);store64(state+72,parent);
    store64(state+96,0);store64(state+104,0);store64(state+112,0);store64(state+120,0);
    store64(state+80,0);let i=0;while i<16 {store64(load64(state+88)+i*8,zero);i=i+1;}i=0;
    while i<load64(f+88) {store64(load64(state+8)+i*8,zero);i=i+1;}i=0;
    while i<load64(f+56) {let value=load64(args+i*8);store64(load64(state+8)+i*8,value);store64(load64(state+16)+i*8,value);i=i+1;}i=0;
    while i<pf_gcount {let value=load64(globals+i*8);store64(load64(state+48)+i*8,value);store64(load64(state+56)+i*8,value);store64(load64(state+64)+i*8,value);i=i+1;}
    return state;
}
fn ps_clone(state,path) {
    let size=ps_state_size(load64(state));let copy=alloc(size);if copy<0 {fail("cannot clone proof state");}
    net_copy(copy,state,size);ps_state_pointers(copy);store64(copy+24,path);return copy;
}
fn ps_release(state) {syscall(11,state,ps_state_size(load64(state)),0,0,0,0);return 0;}
