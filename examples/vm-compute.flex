fn sum(n) {
    let value=0;let i=0;
    while i<n {value=value+i;i=i+1;}
    return value;
}
fn main() {
    let i=0;let value=0;
    while i<40 {value=value+sum(1000);i=i+1;}
    return value!=19980000;
}
