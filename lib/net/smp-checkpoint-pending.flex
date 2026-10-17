import "smp-checkpoint.flex";
import "smp-durable.flex";
// Stateless storage-facing helpers. Neither function starts media writes,
// advances a rollback anchor nor acknowledges the durable gate.
fn ck_pending_seal(key,scope,out,capacity,work,work_capacity) {
    let bytes=sd_checkpoint_peek();if bytes<=0 {return bytes;}if !sd_external(key,16) || !sd_external(scope,16) || !sd_external(out,capacity) || !sd_external(work,work_capacity) {return -22;}
    return ck_seal(key,scope,sd_checkpoint_sequence,sd_checkpoint_revision,sd_checkpoint_buffer,bytes,out,capacity,work,work_capacity);
}
// Workspace112+payload bytes:CMAC scratch/tag then private decoded staging.
// Validate all aliases before clearing anything. A valid MAC with different
// payload is still the wrong transaction. No decoded bytes are published.
fn ck_pending_verify(key,scope,frame,size,work,work_capacity) {
    let bytes=sd_checkpoint_peek();if bytes<=0 {return bytes;}if work_capacity<112+bytes || !sd_external(key,16) || !sd_external(scope,16) || !sd_external(frame,size) || !sd_external(work,work_capacity) {return -22;}
    if !ck_disjoint(key,scope,frame,size,work+112,bytes,work,112) {return -22;}
    let r=ck_open(key,scope,sd_checkpoint_sequence,sd_checkpoint_revision,frame,size,work+112,bytes,work,112);
    if r>=0 {if r!=bytes || !nb_equal(work+112,sd_checkpoint_buffer,bytes) {r=-74;}else {r=0;}}nb_zero(work,112+bytes);return r;
}
