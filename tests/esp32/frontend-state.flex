global reference_count=0;
fn bump(p,i) {let at=p+i*8;let n=load64(at)+4294967297;store64(at,n);reference_count=reference_count+1;return n;}
fn main() {
    let p=alloc(32);if p<=0 {return 2;}store64(p,7);store64(p+8,9);store64(p+16,11);store64(p+24,13);
    let sum=0;let i=0;while i<4 {sum=sum+bump(p,i);i=i+1;}
    let arithmetic=(-17/5 == -3) && (-17%5 == -2) && (3<<65 == 6) && (-8>>65 == -4);
    let guarded=(0 && 1/0==0) || (1 || 1/0==0);
    return !(reference_count==4 && sum==17179869228 && arithmetic && guarded);
}
