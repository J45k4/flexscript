// Compare shared IR with:
// flex run --interpret --ir-opt=none --stats examples/ir-optimization.flex
// flex run --interpret --ir-opt=basic --stats examples/ir-optimization.flex
fn compute(value) {
    let factor=(2+3)*(8-1);
    if 0 {return value*999;}
    return value+factor;
}
fn main() {return compute(7);}
