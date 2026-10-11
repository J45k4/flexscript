// Upper bound for the current unscaled Qwen3 recipe. The checkpoint and free
// device memory can impose a smaller context; prompts must leave a reply slot.
fn ll_context_max() {return 40960;}
