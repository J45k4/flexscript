import "../word-operators.flex";

reads nothing;
modifies nothing;
ensures result==((op>=259 && op<=262) || (op>=265 && op<=266)
    || (op>=42 && op<=43) || (op>=37 && op<=38) || op==45 || op==47
    || op==60 || op==62 || op==94 || op==124);
fn word_proof_operator_set(op) {return vm_binary_operator(op);}
