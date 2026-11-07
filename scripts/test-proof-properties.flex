import "lib/host.flex";
import "../libs/proof.flex";
global pp_checks=0;
fn pp_check(ok,message) {h_assert(ok,message);pp_checks=pp_checks+1;return 0;}
fn pp_query(context,condition,expected,witness,wanted) {
    let formula=pw_cnf(context,1);pp_check(formula,"property circuit capacity");pw_emit(context,formula,condition,0,0,0,1);
    let search=pv_search(formula,262144);pp_check(search,"property search allocation");let result=pv_decide(search,200000000,200000000);
    h_print(1,h_cat3("property result=",h_int(result),h_cat3(" gates=",h_int(load64(context+8)),h_cat3(" work=",h_int(load64(search+64)),"\n"))));
    pp_check(result==expected,"property decision differs");
    if witness {pp_check(result==1 && pw_model_word(context,witness,load64(search+8))==wanted,"unexpected decoded counterexample");}
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);
    syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);return 0;
}
fn pp_field() {
    let c=pw_context(64,131072,1024);let word=pw_input(c);let mask=pw_input(c);let value=pw_input(c);
    let result=pw_bits(c,pw_bits(c,word,pw_not(c,mask),38),pw_bits(c,value,mask,38),124);
    let inside=pw_equal(c,pw_bits(c,result,mask,38),pw_bits(c,value,mask,38));
    let outside=pw_equal(c,pw_bits(c,result,pw_not(c,mask),38),pw_bits(c,word,pw_not(c,mask),38));
    pp_query(c,-pw_and(c,inside,outside),2,0,0);pw_release(c);return 0;
}
fn pp_overflow() {
    let c=pw_context(64,131072,1024);let x=pw_input(c);let one=pw_constant(c,1);let max=pw_constant(c,0x7fffffffffffffff);
    let result=pw_add(c,x,one);let requirement=pw_signed_less(c,x,max);let guarantee=pw_signed_less(c,x,result);
    pp_query(c,pw_and(c,requirement,-guarantee),2,0,0);pp_query(c,-guarantee,1,x,0x7fffffffffffffff);pw_release(c);return 0;
}
fn pp_clamp() {
    let c=pw_context(64,131072,1024);let x=pw_input(c);let limit=pw_input(c);let zero=pw_constant(c,0);
    let result=pw_choose(c,pw_signed_less(c,x,zero),zero,pw_choose(c,pw_signed_less(c,limit,x),limit,x));
    let requirement= -pw_signed_less(c,limit,zero);let guarantee=pw_and(c,-pw_signed_less(c,result,zero),-pw_signed_less(c,limit,result));
    pp_query(c,pw_and(c,requirement,-guarantee),2,0,0);pw_release(c);return 0;
}
fn pp_slice() {
    let c=pw_context(4,4096,1024);let x=pw_input(c);let y=pw_input(c);let sum=pw_add(c,x,y);
    // This substantial unused cone must have no influence on a sum query.
    let ignored=alloc(24);pw_divrem(c,x,y,ignored);syscall(11,ignored,24,0,0,0,0);
    let a=0;while a<16 {let b=0;while b<16 {
        let inputs=pw_and(c,pw_equal(c,x,pw_constant(c,a)),pw_equal(c,y,pw_constant(c,b)));
        let equality=pw_equal(c,sum,pw_constant(c,(a+b)&15));let good=0;
        while good<2 {let condition=pw_and(c,inputs,equality);if !good {condition=pw_and(c,inputs,-equality);}
            let formula=pw_cnf_query(c,condition);pp_check(formula,"query cone allocation");let search=pv_search(formula,8192);pp_check(search,"query search allocation");
            let result=pv_decide(search,2000000,2000000);let expected=2;if good {expected=1;}pp_check(result==expected,"sliced sum differs from native arithmetic");
            if good {pp_check(pw_model_word(c,x,load64(search+8))==a && pw_model_word(c,y,load64(search+8))==b,"sliced input model differs");}
            syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);
            syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);good=good+1;
        }b=b+1;
    }a=a+1;}pw_release(c);return 0;
}
fn pp_boolean_value(kind,x,y) {
    if kind==0 {return 0;}if kind==1 {return 1;}if kind==2 {return x;}if kind==3 {return !x;}if kind==4 {return y;}return !y;
}
fn pp_select_truth() {
    let c=pw_context(1,4096,1024);let x=pw_input(c);let y=pw_input(c);let choices=alloc(48);
    store64(choices,-1);store64(choices+8,1);store64(choices+16,load64(x));store64(choices+24,-load64(x));store64(choices+32,load64(y));store64(choices+40,-load64(y));
    let yes=0;while yes<6 {let no=0;while no<6 {
        let selected=pw_select(c,load64(x),load64(choices+yes*8),load64(choices+no*8));let bits=0;
        while bits<4 {let xv=bits&1;let yv=(bits>>1)&1;let wanted=pp_boolean_value(no,xv,yv);if xv {wanted=pp_boolean_value(yes,xv,yv);}
            let bound_x=load64(x);let bound_y=load64(y);if !xv {bound_x= -bound_x;}if !yv {bound_y= -bound_y;}
            let correct=selected;if !wanted {correct= -correct;}let inputs=pw_and(c,bound_x,bound_y);let good=0;
            while good<2 {let condition=pw_and(c,inputs,correct);if !good {condition=pw_and(c,inputs,-correct);}
                let formula=pw_cnf_query(c,condition);pp_check(formula,"Boolean query allocation");let search=pv_search(formula,8192);pp_check(search,"Boolean query search");
                let expected=2;if good {expected=1;}pp_check(pv_decide(search,2000000,2000000)==expected,"select circuit differs from native Boolean branch");
                syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);
                syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);good=good+1;
            }bits=bits+1;
        }no=no+1;
    }yes=yes+1;}syscall(11,choices,48,0,0,0,0);pw_release(c);return 0;
}
fn pp_offsets() {
    let k=0;while k<16 {
        let c=pw_context(4,131072,8192);let x=pw_input(c);let y=pw_input(c);
        let shifted=pw_add(c,pw_add(c,y,pw_constant(c,k)),pw_constant(c,8));let result=pw_subtract(c,x,shifted);
        let cancellation=pw_add(c,pw_subtract(c,x,pw_constant(c,k)),pw_constant(c,k));
        let mixed=pw_add(c,pw_subtract(c,x,pw_constant(c,k)),pw_constant(c,8));
        let reversed=pw_add(c,pw_add(c,pw_constant(c,k),x),pw_constant(c,8));
        let boolean=pw_subtract(c,x,pw_add(c,y,pw_boolean(c,pw_truth(c,x))));
        let cancel_left=pw_subtract(c,pw_add(c,x,y),x);let cancel_right=pw_subtract(c,pw_add(c,x,y),y);
        let a=0;while a<16 {let b=0;while b<16 {
            let inputs=pw_and(c,pw_equal(c,x,pw_constant(c,a)),pw_equal(c,y,pw_constant(c,b)));
            let equality=pw_equal(c,result,pw_constant(c,(a-b-k-8)&15));
            equality=pw_and(c,equality,pw_equal(c,cancellation,pw_constant(c,a)));
            equality=pw_and(c,equality,pw_equal(c,mixed,pw_constant(c,(a-k+8)&15)));
            equality=pw_and(c,equality,pw_equal(c,reversed,pw_constant(c,(a+k+8)&15)));
            equality=pw_and(c,equality,pw_equal(c,cancel_left,pw_constant(c,b)));
            equality=pw_and(c,equality,pw_equal(c,cancel_right,pw_constant(c,a)));
            equality=pw_and(c,equality,pw_equal(c,boolean,pw_constant(c,(a-b-(a!=0))&15)));let good=0;
            while good<2 {let condition=pw_and(c,inputs,equality);if !good {condition=pw_and(c,inputs,-equality);}
                let formula=pw_cnf_query(c,condition);pp_check(formula,"offset query allocation");let search=pv_search(formula,8192);pp_check(search,"offset query search");
                let expected=2;if good {expected=1;}pp_check(pv_decide(search,2000000,2000000)==expected,"offset reassociation differs from native words");
                syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);
                syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);good=good+1;
            }b=b+1;
        }a=a+1;}pw_release(c);k=k+1;
    }return 0;
}
fn pp_absorption() {
    let c=pw_context(1,4096,1024);let x=pw_input(c);let y=pw_input(c);let z=pw_input(c);let a=load64(x);let b=load64(y);let d=load64(z);
    let values=alloc(96);store64(values,pw_and(c,pw_and(c,a,b),a));store64(values+8,pw_and(c,pw_and(c,a,b),-a));
    store64(values+16,pw_and(c,b,pw_and(c,a,b)));store64(values+24,pw_and(c,-b,pw_and(c,a,b)));
    store64(values+32,pw_and(c,-pw_and(c,a,b),a));store64(values+40,pw_and(c,b,-pw_and(c,a,b)));
    store64(values+48,pw_or(c,-pw_and(c,d,pw_and(c,a,b)),pw_and(c,a,b)));
    store64(values+56,pw_and(c,pw_and(c,a,b),d));
    let masked=pw_or(c,pw_and(c,a,-b),pw_and(c,d,b));store64(values+64,pw_and(c,masked,b));store64(values+72,pw_and(c,-b,masked));
    store64(values+80,pw_xor(c,b,pw_select(c,a,b,d)));store64(values+88,pw_xor(c,-pw_select(c,a,-b,d),-d));let bits=0;
    while bits<8 {let xv=bits&1;let yv=(bits>>1)&1;let zv=(bits>>2)&1;let bound=pw_and(c,pw_equal(c,x,pw_constant(c,xv)),pw_equal(c,y,pw_constant(c,yv)));
        bound=pw_and(c,bound,pw_equal(c,z,pw_constant(c,zv)));let expected=alloc(96);store64(expected,xv && yv);store64(expected+8,0);store64(expected+16,xv && yv);store64(expected+24,0);
        store64(expected+32,!(xv && yv) && xv);store64(expected+40,yv && !(xv && yv));store64(expected+48,1);store64(expected+56,xv && yv && zv);store64(expected+64,zv && yv);store64(expected+72,xv && !yv);
        store64(expected+80,!xv && (zv!=yv));store64(expected+88,xv && ((!yv)!=zv));let correct=1;let i=0;
        while i<12 {let literal=load64(values+i*8);if !load64(expected+i*8) {literal= -literal;}correct=pw_and(c,correct,literal);i=i+1;}
        pp_query(c,pw_and(c,bound,-correct),2,0,0);pp_query(c,pw_and(c,bound,correct),1,0,0);syscall(11,expected,96,0,0,0,0);bits=bits+1;
    }syscall(11,values,96,0,0,0,0);pw_release(c);return 0;
}
fn main(argc,argv) {h_environment(argc,argv);pp_field();pp_overflow();pp_clamp();pp_slice();pp_select_truth();pp_offsets();pp_absorption();h_print(1,h_cat3("PASS: ",h_int(pp_checks)," universal word-property checks\n"));return 0;}
