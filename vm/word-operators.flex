// Operand words accepted by the binary bytecode instruction.
fn vm_binary_operator(op) {
    return op==43 || op==45 || op==42 || op==47 || op==37 || op==38 || op==124 || op==94
        || op==265 || op==266 || op==259 || op==260 || op==60 || op==62 || op==261 || op==262;
}
