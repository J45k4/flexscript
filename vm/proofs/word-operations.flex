import "../word-operations.flex";
import "../word-operators.flex";
import "../../compiler/word-operations.flex";

// Compare the actual interpreter and folding code separately with the source
// word operation. These roots use arbitrary operand words. Division and
// remainder have their own nontrapping and trap profiles.
reads nothing;
modifies nothing;
ensures result==(a + b);
fn word_proof_add(a,b) {
    let interpreted=vm_binary(43,a,b);
    let folded=word_binary_result(43,a,b);
    let can_fold=word_binary_can_fold(43,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a - b);
fn word_proof_subtract(a,b) {
    let interpreted=vm_binary(45,a,b);
    let folded=word_binary_result(45,a,b);
    let can_fold=word_binary_can_fold(45,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a * b);
fn word_proof_multiply(a,b) {
    let interpreted=vm_binary(42,a,b);
    let folded=word_binary_result(42,a,b);
    let can_fold=word_binary_can_fold(42,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a & b);
fn word_proof_and(a,b) {
    let interpreted=vm_binary(38,a,b);
    let folded=word_binary_result(38,a,b);
    let can_fold=word_binary_can_fold(38,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a | b);
fn word_proof_or(a,b) {
    let interpreted=vm_binary(124,a,b);
    let folded=word_binary_result(124,a,b);
    let can_fold=word_binary_can_fold(124,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a ^ b);
fn word_proof_xor(a,b) {
    let interpreted=vm_binary(94,a,b);
    let folded=word_binary_result(94,a,b);
    let can_fold=word_binary_can_fold(94,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a << b);
fn word_proof_shift_left(a,b) {
    let interpreted=vm_binary(265,a,b);
    let folded=word_binary_result(265,a,b);
    let can_fold=word_binary_can_fold(265,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a >> b);
fn word_proof_shift_right(a,b) {
    let interpreted=vm_binary(266,a,b);
    let folded=word_binary_result(266,a,b);
    let can_fold=word_binary_can_fold(266,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a == b);
fn word_proof_equal(a,b) {
    let interpreted=vm_binary(259,a,b);
    let folded=word_binary_result(259,a,b);
    let can_fold=word_binary_can_fold(259,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a != b);
fn word_proof_not_equal(a,b) {
    let interpreted=vm_binary(260,a,b);
    let folded=word_binary_result(260,a,b);
    let can_fold=word_binary_can_fold(260,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a < b);
fn word_proof_less(a,b) {
    let interpreted=vm_binary(60,a,b);
    let folded=word_binary_result(60,a,b);
    let can_fold=word_binary_can_fold(60,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a > b);
fn word_proof_greater(a,b) {
    let interpreted=vm_binary(62,a,b);
    let folded=word_binary_result(62,a,b);
    let can_fold=word_binary_can_fold(62,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a <= b);
fn word_proof_at_most(a,b) {
    let interpreted=vm_binary(261,a,b);
    let folded=word_binary_result(261,a,b);
    let can_fold=word_binary_can_fold(261,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

reads nothing;
modifies nothing;
ensures result==(a >= b);
fn word_proof_at_least(a,b) {
    let interpreted=vm_binary(262,a,b);
    let folded=word_binary_result(262,a,b);
    let can_fold=word_binary_can_fold(262,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

requires b!=0 && !(a==0x8000000000000000 && b==(-1));
reads nothing;
modifies nothing;
ensures result==(a / b);
fn word_proof_divide(a,b) {
    let interpreted=vm_binary(47,a,b);
    let folded=word_binary_result(47,a,b);
    let can_fold=word_binary_can_fold(47,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

requires b!=0 && !(a==0x8000000000000000 && b==(-1));
reads nothing;
modifies nothing;
ensures result==(a % b);
fn word_proof_remainder(a,b) {
    let interpreted=vm_binary(37,a,b);
    let folded=word_binary_result(37,a,b);
    let can_fold=word_binary_can_fold(37,a,b);
    assert can_fold;
    assert folded==interpreted;
    return interpreted;
}

requires (op==47 || op==37) && (b==0 || (a==0x8000000000000000 && b==(-1)));
reads vm_error;
modifies vm_error;
ensures result==0 && vm_error==2;
fn word_proof_trap(op,a,b) {
    let fold=word_binary_can_fold(op,a,b);
    assert !fold;
    return vm_binary(op,a,b);
}

// One is a safe divisor, so the interpreter's error identifies rejection of
// the opcode itself independently of operand-dependent arithmetic traps.
requires vm_error==0;
reads vm_error;
modifies vm_error;
ensures result <= 1 && result >= 0;
ensures (result==1 && vm_error==0) || (result==0 && vm_error==9);
fn word_proof_operator_interpreter(op) {
    let admitted=vm_binary_operator(op);
    vm_binary(op,1,1);
    return admitted;
}

requires !(op>=259 && op<=262) && !(op>=265 && op<=266);
requires !(op>=42 && op<=43) && !(op>=37 && op<=38);
requires op!=45 && op!=47 && op!=60 && op!=62 && op!=94 && op!=124;
reads vm_error;
modifies vm_error;
ensures result==0 && vm_error==9;
fn word_proof_unknown(op,a,b) {
    let admitted=vm_binary_operator(op);
    let can_fold=word_binary_can_fold(op,a,b);
    assert !admitted;
    assert !can_fold;
    return vm_binary(op,a,b);
}
