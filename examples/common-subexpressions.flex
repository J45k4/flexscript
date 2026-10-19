// --stats reports one common expression reused with --ir-opt basic.
// The second x*y becomes a load of a. Both modes return 85.
fn compute(x,y) {
    let a=x*y;
    let b=x*y+1;
    return a+b;
}
fn main() {return compute(6,7);}
