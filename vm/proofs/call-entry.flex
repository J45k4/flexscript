import "../call-frame.flex";

// Production call entry: the first checked path of the complete entry proof.
// The remaining paths (header/capacity rejection with symbolic metadata, and
// the acceptance transition) are retained in proofs/pending/call-entry.flex
// until the argument-copy loop has a checked summary; the verifier currently
// builds the whole production body's circuit for every root, so any root whose
// path passes the header check needs that loop demand reduced first.

// Out-of-range index or a full frame stack: the production guard rejects
// before touching any byte memory, and every other global is preserved.
requires index < 0 || index >= function_count || vm_depth >= 1024;
reads vm_depth,vm_error,function_count;
modifies vm_error;
ensures result == 0 && vm_error == 4;
ensures vm_depth == old(vm_depth);
fn enter_rejects_bad_index(index,return_pc) {return vm_enter(index,return_pc);}
