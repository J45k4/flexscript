import "lib/host.flex";
import "../libs/proof.flex";
import "../libs/proof/word.flex";
global tw_checks=0;
global tw_cases=0;
fn tw_check(ok,message) {h_assert(ok,message);tw_checks=tw_checks+1;return 0;}
fn tw_signed(value,width) {if width==64 {return value;}let mask=(1<<width)-1;value=value&mask;if value&(1<<(width-1)) {return value-(1<<width);}return value;}
fn tw_mask(width) {if width==64 {return -1;}return (1<<width)-1;}
fn tw_bind(context,formula,word,value) {
    let i=0;while i<load64(context) {let lit=load64(word+i*8);if !((value>>i)&1) {lit= -lit;}
        tw_check(pw_emit(context,formula,lit,0,0,0,1),"input binding capacity");i=i+1;
    }return 0;
}
fn tw_op(context,op,a,b) {
    let out=h_take(16);tw_check(pw_binary(context,op,a,b,out),"compiler-token operator lowering");return load64(out);
}
fn tw_build(context,a,b,out) {
    store64(out,tw_op(context,43,a,b));store64(out+8,tw_op(context,45,a,b));store64(out+16,tw_op(context,42,a,b));
    store64(out+24,tw_op(context,38,a,b));store64(out+32,tw_op(context,124,a,b));store64(out+40,tw_op(context,94,a,b));
    store64(out+48,pw_unary(context,45,a));store64(out+56,pw_unary(context,126,a));
    store64(out+64,tw_op(context,265,a,b));store64(out+72,tw_op(context,266,a,b));
    store64(out+80,tw_op(context,259,a,b));store64(out+88,tw_op(context,60,a,b));
    store64(out+96,tw_op(context,261,a,b));store64(out+104,tw_op(context,263,a,pw_constant(context,1)));
    store64(out+112,pw_unary(context,33,a));store64(out+120,pw_choose(context,pw_truth(context,a),a,b));
    let division=h_take(16);let remainder=h_take(16);
    tw_check(pw_binary(context,47,a,b,division) && pw_binary(context,37,a,b,remainder),"division/remainder lowering");
    store64(out+128,load64(division));store64(out+136,load64(remainder));store64(out+144,load64(division+8));
    tw_check(load64(division+8)==load64(remainder+8),"division/remainder must share trap conditions");return 0;
}
fn tw_expected(a,b,width,out) {
    a=tw_signed(a,width);b=tw_signed(b,width);let mask=tw_mask(width);let shift=b&(width-1);
    store64(out,(a+b)&mask);store64(out+8,(a-b)&mask);store64(out+16,(a*b)&mask);
    store64(out+24,(a&b)&mask);store64(out+32,(a|b)&mask);store64(out+40,(a^b)&mask);
    store64(out+48,(-a)&mask);store64(out+56,(~a)&mask);store64(out+64,(a<<shift)&mask);store64(out+72,(a>>shift)&mask);
    store64(out+80,a==b);store64(out+88,a<b);store64(out+96,a<=b);store64(out+104,a!=0);store64(out+112,a==0);
    let choice=b;if a {choice=a;}store64(out+120,choice&mask);
    let safe=b!=0 && !(a==tw_signed(1<<(width-1),width) && b== -1);store64(out+144,safe);
    if safe {store64(out+128,(a/b)&mask);store64(out+136,(a%b)&mask);}return 0;
}
fn tw_run(context,formula,search,a,b,outputs,x,y,base_clauses,base_literals,expected) {
    store64(formula+8,base_clauses);store64(formula+16,base_literals);tw_bind(context,formula,a,x);tw_bind(context,formula,b,y);
    tw_expected(x,y,load64(context),expected);let result=pv_decide(search,20000000,20000000);
    tw_check(result==1,"constrained arithmetic circuit must be satisfiable");let assignment=load64(search+8);let i=0;
    while i<18 {if i<16 || load64(expected+144) {
        let got=pw_model_word(context,load64(outputs+i*8),assignment);let want=load64(expected+i*8);
        if got!=want {h_print(2,h_cat3("word mismatch op=",h_int(i),h_cat3(" x=",h_int(x),h_cat3(" y=",h_int(y),h_cat3(" got=",h_int(got),h_cat3(" expected=",h_int(want),"\n"))))));}
        tw_check(got==want,"word circuit differs from native reference");
    }i=i+1;}
    let safe=load64(outputs+144);let id=safe;if id<0 {id= -id;}let safe_value=load64(assignment+id*8);if safe<0 {safe_value= -safe_value;}
    tw_check((safe_value==1)==load64(expected+144),"division trap predicate differs");
    // A changed output bit must be impossible, not just absent from one model.
    let selected=tw_cases%16;let bit=tw_cases%load64(context);let lit=load64(load64(outputs+selected*8)+bit*8);
    if (load64(expected+selected*8)>>bit)&1 {lit= -lit;}
    tw_check(pw_emit(context,formula,lit,0,0,0,1),"negative output constraint");
    tw_check(pv_decide(search,20000000,20000000)==2,"wrong output bit was not refuted with checked evidence");tw_cases=tw_cases+1;return 0;
}
fn tw_suite(width,exhaustive) {
    let context=pw_context(width,131072,2048);tw_check(context,"word context allocation");let a=pw_input(context);let b=pw_input(context);
    let outputs=h_take(152);let expected=h_take(152);tw_build(context,a,b,outputs);tw_check(!load64(context+72),"word circuit capacity");
    let formula=pw_cnf(context,width*2+1);tw_check(formula,"CNF construction");let search=pv_search(formula,load64(context+8)*2+8);tw_check(search,"search allocation");
    let clauses=load64(formula+8);let literals=load64(formula+16);
    if exhaustive {let x=0;while x<(1<<width) {let y=0;while y<(1<<width) {tw_run(context,formula,search,a,b,outputs,x,y,clauses,literals,expected);y=y+1;}x=x+1;}}
    else {
        let values=h_take(128);store64(values,0);store64(values+8,1);store64(values+16,-1);store64(values+24,0x8000000000000000);
        store64(values+32,0x7fffffffffffffff);store64(values+40,0x8000000000000001);store64(values+48,-7);store64(values+56,3);
        store64(values+64,63);store64(values+72,64);store64(values+80,65);store64(values+88,-64);
        store64(values+96,0x123456789abcdef0);store64(values+104,0xfedcba9876543210);store64(values+112,-3);store64(values+120,7);
        let i=0;while i<16 {let j=0;while j<16 {tw_run(context,formula,search,a,b,outputs,load64(values+i*8),load64(values+j*8),clauses,literals,expected);j=j+1;}i=i+1;}
    }
    h_print(1,h_cat3("PASS: word width ",h_int(width),h_cat3("; circuit gates=",h_int(load64(context+8)),"\n")));
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);pw_release(context);return 0;
}
fn tw_limits() {
    tw_check(!pw_context(3,32,32),"unsupported width rejected");let tiny=pw_context(64,2,2);pw_input(tiny);
    tw_check(load64(tiny+72) && !pw_cnf(tiny,0),"gate exhaustion cannot produce a formula");pw_release(tiny);
    tiny=pw_context(64,256,1);pw_constant(tiny,0);tw_check(!pw_constant(tiny,1) && !pw_cnf(tiny,0),"word exhaustion cannot produce a formula");pw_release(tiny);
    tiny=pw_context(64,256,8);tw_check(!pw_and(tiny,0,1) && !pw_cnf(tiny,0),"invalid literal cannot produce a formula");pw_release(tiny);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);tw_suite(1,1);tw_suite(2,1);tw_suite(4,1);tw_suite(64,0);tw_limits();
    h_print(1,h_cat3("PASS: ",h_int(tw_checks),h_cat3(" word checks across ",h_int(tw_cases)," assignments; checked SAT and UNSAT evidence\n")));return 0;
}
