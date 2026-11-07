import "lib/proof-harness.flex";
fn pm_test_count(text,needle) {let i=0;let count=0;while i<h_len(text) {if h_starts(text+i,needle) {count=count+1;}i=i+1;}return count;}
fn suite(compiler) {
    t_init(compiler);
    let p=ps_verify("ensures result==old(x); fn helper(x){return x;} ensures result==x; fn first(x){return helper(x);} ensures result==x; fn second(x){return helper(helper(x));}",0,"Verified roots: 3/3");
    t_assert(pm_test_count(h_out(p),"VERIFY helper\n")==1,"callee body was checked repeatedly");
    ps_verify("requires n>=0; ensures result==0; decreases n; fn countdown(n){if n==0{return 0;}return countdown(n-1);}",0,"termination by checked recursive measures");
    ps_verify("requires n>=0; decreases n; fn countdown(n){if n==0{return 0;}return countdown(n-1);}",0,"Verified roots: 1/1");
    ps_verify("requires n>=0; ensures result==old(n); decreases n; fn count(n){if n==0{return 0;}n=n-1;return count(n)+1;}",0,"Verified roots: 1/1");
    ps_verify("requires n>=0; ensures result==0; decreases n; fn left(n){if n==0{return 0;}return right(n-1);} requires n>=0; ensures result==0; decreases n; fn right(n){if n==0{return 0;}return left(n-1);}",0,"Verified roots: 2/2");
    ps_verify("requires x>=0 && x<3; requires y>=0 && y<3; ensures result==0; decreases x,y; fn pair(x,y){if y{return pair(x,y-1);}if x{return pair(x-1,2);}return 0;}",0,"Verified roots: 1/1");
    ps_verify("requires n==1; ensures result==0; decreases n; fn stuck(n){if n==0{return 0;}return stuck(n);}",1,"COUNTEREXAMPLE: recursive decreases progress");
    ps_verify("requires n>=0 && n<100; ensures result==0; decreases n; fn grows(n){return grows(n+1);}",1,"COUNTEREXAMPLE: recursive decreases progress");
    ps_verify("requires n<0; decreases n; fn negative(n){return 0;}",1,"COUNTEREXAMPLE: function decreases lower bound");
    ps_verify("requires n>=0; ensures result==0; fn no_measure(n){if n==0{return 0;}return no_measure(n-1);}",1,"recursive calls require function decreases clauses");
    p=ps_verify("ensures 0; fn circle(){return circle();}",1,"recursive calls require function decreases clauses");
    t_assert(!h_has(h_out(p),"PROVED: supported"),"circular contract reported total correctness");
    ps_verify("ensures 0; decreases 0; fn circle(){return circle();}",1,"COUNTEREXAMPLE: recursive decreases progress");
    ps_verify("requires n>=0; ensures 0; decreases n; fn bad_base(n){if n==0{return 0;}return bad_base(n-1);}",1,"COUNTEREXAMPLE: postcondition");
    ps_verify("requires n>=0; ensures result==0; decreases n; fn a(n){if n==0{return 0;}return b(n-1);} requires n>=0; ensures result==0; decreases n,0; fn b(n){if n==0{return 0;}return a(n-1);}",1,"recursive decreases tuples must have the same arity");
    ps_verify("requires n>=0; ensures result==0; decreases n; fn a(n){if n==0{return 0;}return b(n-1);} requires n>=0; ensures result==0; fn b(n){if n==0{return 0;}return a(n-1);}",1,"recursive calls require function decreases clauses");
    ps_verify("requires n>=0; requires m>=0; ensures result==0; decreases n,m; fn outer(n,m){return inner(n);} requires n>=0; ensures result==0; decreases n; fn inner(n){if n==0{return 0;}return inner(n-1);}",0,"Verified roots: 2/2");
    p=ps_verify("ensures result==0; fn caller(){return liar();} ensures result==0; fn liar(){return 1;}",1,"unresolved dependency: liar");
    t_assert(!h_has(h_out(p),"RESULT caller\nPROVED:"),"invalid dependency allowed caller proof");
    p=ps_verify("ensures result==0; fn caller(){return wrapper(0);} ensures result==0; fn wrapper(p){return load64(p);}",1,"unresolved dependency: wrapper");
    t_assert(!h_has(h_out(p),"RESULT caller\nPROVED:"),"external body became an implicit assumption");
    p=ps_verify("global g=0; requires g==0; ensures g==0; fn caller(){return liar();} modifies nothing; ensures result==0; fn liar(){g=1;return 0;}",1,"unresolved dependency: liar");
    t_assert(!h_has(h_out(p),"RESULT caller\nPROVED:"),"invalid effect frame allowed caller proof");
    p=ps_verify("ensures result==1; fn caller(){return weak();} ensures result>=0; fn weak(){return 1;}",1,"abstract call countermodel");
    t_assert(!h_has(h_out(p),"COUNTEREXAMPLE:"),"weak contract was reported as an executable bug");
    ps_verify("requires x==0; ensures result==0; fn caller(x){return mutate(x);} requires x==0; ensures result==x; fn mutate(x){x=1;return x;}",1,"COUNTEREXAMPLE: postcondition in caller");
    ps_verify("requires x==0; ensures result==1; fn caller(x){return mutate(x);} requires x==0; ensures result==x; fn mutate(x){x=1;return x;}",1,"abstract call countermodel");
    ps_verify("requires x==0; ensures result==1; fn caller(x){return mutate(x);} ensures x==old(x)+1; ensures result==x; fn mutate(x){x=x+1;return x;}",0,"Verified roots: 2/2");
    ps_verify("global g=0; requires g==0; ensures g==0; fn caller(){change();return 0;} modifies g; ensures result==0; fn change(){g=1;return 0;}",1,"COUNTEREXAMPLE: postcondition in caller");
    ps_verify("global g=0; requires g==0; fn caller(){assert g==0;change();assert g==0;return 0;} modifies g; ensures result==0; fn change(){g=1;return 0;}",1,"COUNTEREXAMPLE: assertion in caller");
    ps_verify("global g=0; requires g==0; ensures result==0; fn caller(){let saved=g;change();return saved;} modifies g; ensures result==0; fn change(){g=1;return 0;}",0,"Verified roots: 2/2");
    ps_verify("global g=0; modifies nothing; fn caller(){return change();} modifies g; ensures result==0; fn change(){g=1;return 0;}",1,"COUNTEREXAMPLE: write frame in caller");
    ps_verify("global g=0; reads nothing; fn caller(){return read();} reads g; ensures result==g; fn read(){return g;}",1,"COUNTEREXAMPLE: read frame in caller");
    ps_verify("global g=0; requires g>=0; ensures g==0; modifies g; decreases g; fn zero(){if g==0{return 0;}g=g-1;return zero();}",0,"Verified roots: 1/1");
    ps_verify("global g=0; requires g==2; ensures g==0; fn caller(){return zero();} requires g>=0; modifies g; ensures g==0; decreases g; fn zero(){if g==0{return 0;}g=g-1;return zero();}",0,"Verified roots: 2/2");
    ps_verify("ensures result==0; fn independent(){return 0;} fn unused(p){return load64(p);}",0,"Verified roots: 1/1");
    p=ps_verify("ensures result==0; fn independent(){if 0{return bad();}return 0;} ensures result==0; fn bad(){return 1;}",1,"RESULT independent\nPROVED:");
    t_assert(!h_has(h_out(p),"unresolved dependency: bad"),"unexecuted call created a summary dependency");
    ps_verify("requires n==0; ensures result==0; fn unreachable(n){if n{return unreachable(n-1);}return 0;}",0,"Verified roots: 1/1");
    ps_verify("ensures result==1; ensures 1/result==1; fn one(){return 1;} ensures result==1; fn caller(){return one();}",0,"Verified roots: 2/2");
    ps_verify("ensures 1/result==1; fn one(){return 1;} verify; fn caller(){return one();}",0,"Verified roots: 2/2");
    ps_bad("decreases n; decreases n; fn main(n){return 0;}","duplicate function decreases clause");
    ps_bad("decreases old(n); fn main(n){return 0;}","old is allowed only once in a postcondition");
    ps_bad("decreases result; fn main(){return 0;}","undefined contract name");
    ps_bad("decreases local; fn main(){let local=0;return 0;}","undefined contract name");
    ps_bad("decreases call(); fn main(){return 0;} fn call(){return 0;}","specification calls require");
    ps_bad("decreases 0;", "function contract has no following function");
    t_native("decreases -1; fn main(){return 42;}",42,"");
    h_check(h_run(h_args(t_compiler,t_fixture,0,0,0,0)),42,"");t_checks=t_checks+1;
    let annotated=h_sha(t_binary);t_program("fn main(){return 42;}");t_compile();t_assert(h_equal(annotated,h_sha(t_binary)),"function measure changed executable bytes");
    let text=h_buffer();let i=0;while i<40 {
        h_text(text,h_cat3("ensures result==x; fn chain",h_int(i),"(x){return "));
        if i==39 {h_text(text,"x;");}else {h_text(text,h_cat3("chain",h_int(i+1),"(x);"));}h_text(text,"}\n");i=i+1;
    }
    p=ps_verify(h_data(text),0,"Verified roots: 40/40");t_assert(pm_test_count(h_out(p),"VERIFY ")==40,"modular worklist repeated or omitted a body");
    h_save(h_join(t_work,"recursive.flex"),"requires n>=0;ensures result==0;decreases n;fn descend(n){if n==0{return 0;}return descend(n-1);}");
    ps_verify("import \"recursive.flex\";requires n>=0;ensures result==0;fn caller(n){return descend(n);}",0,"Verified roots: 2/2");
    return t_done();
}
fn main(argc,argv) {return t_entry(argc,argv);}
