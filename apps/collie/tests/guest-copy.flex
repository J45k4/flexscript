import "../lib/json.flex";
import "../guest/runtime.flex";
fn main(argc,argv){
    h_environment(argc,argv);let n=0;
    while n<=65{let a=0;while a<8{let b=0;while b<8{
        let source=alloc(96);let target=alloc(96);let i=0;while i<96{store8(source+i,(i*37+11)%256);store8(target+i,0xa5);i=i+1;}
        h_assert(db_copy(target+b,source+a,n)==target+b,"copy returns target");i=0;while i<96{let expected=0xa5;if i>=b && i<b+n{expected=((i-b+a)*37+11)%256;}h_assert(load8(target+i)==expected,"unaligned copy data and write canaries");h_assert(load8(source+i)==(i*37+11)%256,"source remains unchanged");i=i+1;}b=b+1;
    }a=a+1;}n=n+1;}
    h_assert(db_copy(0,0,-9223372036854775807-1)==0,"negative lengths remain a no-op");let p=alloc(64);let i=0;while i<64{store8(p+i,i);i=i+1;}db_copy(p+1,p,31);i=0;while i<=31{h_assert(load8(p+i)==0,"forward overlap retains byte-copy semantics");i=i+1;}i=0;while i<64{store8(p+i,i);i=i+1;}db_copy(p,p+1,31);i=0;while i<31{h_assert(load8(p+i)==i+1,"backward overlap");i=i+1;}
    h_print(1,"PASS guest copy: all source/destination alignments, lengths 0..65, canaries and overlapping ranges\n");return 0;
}
