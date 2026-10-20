// The shared effect pass proves this call has no observable effects.
fn clean(x) {return x+1;}
fn compute(x,y) {
    let a=x*y;
    clean(x);
    let b=x*y; // Reuses a without removing clean() or its argument.
    return a+b;
}
fn main(argc,argv) {return compute(argc,7);}
