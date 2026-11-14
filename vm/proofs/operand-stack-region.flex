// Checked subregion permission used to compose the local operand-stack proofs.
// Mapping ownership itself is an initialization premise, not established here.
requires offset >= 0 && offset <= 524280;
requires writable_bytes(stack,524288);
ensures writable_bytes(stack+offset,8);
lemma fn operand_stack_slot_permission(stack,offset) {}
