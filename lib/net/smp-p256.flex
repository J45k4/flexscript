import "bytes.flex";
// P-256 byte-array boundary. SMP private scalars,public X/Y andDHKey use
// little-endian32-byte scalars. The vendor hook takes conventional big endian.
// Caller-owned256-byte staging;all used staging is wiped after provider calls.
// Inputs/outputs may overlap each other,but never the used scratch.
fn p256_range(p,n) {return p>0 && n>=0 && p<=9223372036854775807-n;}
fn p256_overlap(a,an,b,bn) {return an && bn && a<b+bn && b<a+an;}
fn p256_reverse(out,input,n) {let i=0;while i<n {store8(out+i,load8(input+n-1-i));i=i+1;}return 0;}
fn p256_area(p,n,work) {return p256_range(p,n) && !p256_overlap(p,n,work,256) && smp_p256_external(p,n);}
fn p256_work(work,capacity) {return capacity>=256 && p256_range(work,capacity);}
fn p256_finish(work,r) {nb_zero(work,256);return r;}
fn p256_validate(peer,work,capacity) {
    if !p256_work(work,capacity) || !p256_area(peer,64,work) {return -22;}let r=smp_p256_ready(work,256);if r {return r;}nb_zero(work,256);p256_reverse(work,peer,32);p256_reverse(work+32,peer+32,32);r=smp_p256_backend(1,work,0,0);return p256_finish(work,r);
}
fn p256_public(private,out,work,capacity) {
    if !p256_work(work,capacity) || !p256_area(private,32,work) || !p256_area(out,64,work) {return -22;}let r=smp_p256_ready(work,256);if r {return r;}nb_zero(work,256);p256_reverse(work,private,32);r=smp_p256_backend(2,work,work+96,0);if !r {p256_reverse(out,work+96,32);p256_reverse(out+32,work+128,32);}return p256_finish(work,r);
}
fn p256_shared(private,peer,out,work,capacity) {
    if !p256_work(work,capacity) || !p256_area(private,32,work) || !p256_area(peer,64,work) || !p256_area(out,32,work) {return -22;}let r=smp_p256_ready(work,256);if r {return r;}nb_zero(work,256);p256_reverse(work,private,32);p256_reverse(work+32,peer,32);p256_reverse(work+64,peer+32,32);r=smp_p256_backend(3,work,work+32,work+96);if !r {p256_reverse(out,work+96,32);}return p256_finish(work,r);
}
// Output96:private scalar,public X,public Y. Entropy is mandatory in the hook;
// this layer supplies no fallback RNG anddoes not activate pairing/security.
fn p256_keypair(out,work,capacity) {
    if !p256_work(work,capacity) || !p256_area(out,96,work) {return -22;}let r=smp_p256_ready(work,256);if r {return r;}nb_zero(work,256);r=smp_p256_backend(4,work,work+32,0);if !r {p256_reverse(out,work,32);p256_reverse(out+32,work+32,32);p256_reverse(out+64,work+64,32);}return p256_finish(work,r);
}
