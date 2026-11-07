import "cnf.flex";
// Exact finite-word circuits. Production words have width 64; power-of-two
// smaller widths support exhaustive independent tests of the same lowering.
// Boolean literals: 1=true, -1=false; sign negates a gate's output.
// Context: width, gates used/cap/pointer, hash cap/pointer, words used/cap/pointer,
// sticky error, word metadata pointer, allocation size, four scratch literals (128 bytes).
// Gate record: kind (0=input,1=and,2=xor,3=select,4=true), a,b,c.
fn pw_context(width,gate_capacity,word_capacity) {
    if width<1 || width>64 || (width&(width-1)) || gate_capacity<1 || gate_capacity>131072 || word_capacity<1 || word_capacity>65536 {return 0;}
    let buckets=2;while buckets<gate_capacity*2 {buckets=buckets*2;}
    let size=128+gate_capacity*32+buckets*8+width*word_capacity*8+word_capacity*24;let p=alloc(size);if p<0 {return 0;}
    store64(p,width);store64(p+8,1);store64(p+16,gate_capacity);store64(p+24,p+128);
    store64(p+32,buckets);store64(p+40,p+128+gate_capacity*32);store64(p+48,0);store64(p+56,word_capacity);
    store64(p+64,p+128+gate_capacity*32+buckets*8);store64(p+72,0);store64(p+80,load64(p+64)+width*word_capacity*8);store64(p+88,size);
    let i=0;while i<buckets {store64(load64(p+40)+i*8,0);i=i+1;}
    let gate=load64(p+24);store64(gate,4);store64(gate+8,0);store64(gate+16,0);store64(gate+24,0);return p;
}
fn pw_bad(context) {store64(context+72,1);return 0;}
fn pw_valid_literal(context,literal) {let n=load64(context+8);return literal && literal>= -n && literal<=n;}
fn pw_gate(context,kind,a,b,c) {
    if load64(context+72) {return 0;}
    if kind<0 || kind>3 {return pw_bad(context);}
    if kind && (!pw_valid_literal(context,a) || !pw_valid_literal(context,b) || (kind==3 && !pw_valid_literal(context,c))) {return pw_bad(context);}
    let slot=0;let table=load64(context+40);let mask=load64(context+32)-1;
    if kind {
        slot=((kind*0x9e3779b1)^(a*0x85ebca6b)^(b*0xc2b2ae35)^(c*0x27d4eb2f))&mask;
        while load64(table+slot*8) {let id=load64(table+slot*8);let row=load64(context+24)+(id-1)*32;
            if load64(row)==kind && load64(row+8)==a && load64(row+16)==b && load64(row+24)==c {return id;}slot=(slot+1)&mask;
        }
    }
    let count=load64(context+8);if count>=load64(context+16) {return pw_bad(context);}let row=load64(context+24)+count*32;
    store64(row,kind);store64(row+8,a);store64(row+16,b);store64(row+24,c);store64(context+8,count+1);
    if kind {store64(table+slot*8,count+1);}return count+1;
}
fn pw_and(context,a,b) {
    if !pw_valid_literal(context,a) || !pw_valid_literal(context,b) {return pw_bad(context);}
    if a== -1 || b== -1 || a== -b {return -1;}if a==1 {return b;}if b==1 || a==b {return a;}
    if a>1 {let row=load64(context+24)+(a-1)*32;if load64(row)==1 {
        if b==load64(row+8) || b==load64(row+16) {return a;}
        if b== -load64(row+8) || b== -load64(row+16) {return -1;}
    }}
    if b>1 {let row=load64(context+24)+(b-1)*32;if load64(row)==1 {
        if a==load64(row+8) || a==load64(row+16) {return b;}
        if a== -load64(row+8) || a== -load64(row+16) {return -1;}
    }}
    // Masking a disjunction removes any arm containing the opposite mask.
    // This keeps independent bit-field identities independent in the CNF.
    let disjunction=a;let fact=b;let pass=0;
    while pass<2 {
        if disjunction< -1 {let row=load64(context+24)+(-disjunction-1)*32;if load64(row)==1 {
            let x= -load64(row+8);let y= -load64(row+16);if x==fact || y==fact {return fact;}
            let arm=x;let other=y;let side=0;while side<2 {let impossible=arm== -fact;
                if arm>1 {let child=load64(context+24)+(arm-1)*32;if load64(child)==1 && (load64(child+8)== -fact || load64(child+16)== -fact) {impossible=1;}}
                if impossible {return pw_and(context,other,fact);}arm=y;other=x;side=side+1;
            }
        }}disjunction=b;fact=a;pass=pass+1;
    }
    if a>b {let t=a;a=b;b=t;}return pw_gate(context,1,a,b,0);
}
fn pw_or(context,a,b) {let result=pw_and(context,-a,-b);if !result {return 0;}return -result;}
fn pw_xor(context,a,b) {
    if !pw_valid_literal(context,a) || !pw_valid_literal(context,b) {return pw_bad(context);}
    if a==b {return -1;}if a== -b {return 1;}if a== -1 {return b;}if b== -1 {return a;}if a==1 {return -b;}if b==1 {return -a;}
    let invert=0;if a<0 {a= -a;invert=!invert;}if b<0 {b= -b;invert=!invert;}
    // A selected arm compared with itself reduces under the selector without
    // splitting on every data bit. This is a Boolean identity, not a path fact.
    let selected=a;let other=b;let pass=0;
    while pass<2 {let row=load64(context+24)+(selected-1)*32;
        if load64(row)==3 {let yes=load64(row+16);let no=load64(row+24);
            if yes==other || yes== -other || no==other || no== -other {
                let result=pw_select(context,load64(row+8),pw_xor(context,yes,other),pw_xor(context,no,other));if invert {return -result;}return result;
            }
        }selected=b;other=a;pass=pass+1;
    }
    if a>b {let t=a;a=b;b=t;}let result=pw_gate(context,2,a,b,0);if invert {return -result;}return result;
}
fn pw_select(context,condition,yes,no) {
    if !pw_valid_literal(context,condition) || !pw_valid_literal(context,yes) || !pw_valid_literal(context,no) {return pw_bad(context);}
    if condition==1 {return yes;}if condition== -1 {return no;}if yes==no {return yes;}
    // Correlated arms occur in comparisons against constants. Reduce them
    // before CNF emission instead of hiding a unit behind duplicate literals.
    if condition==yes {return pw_or(context,condition,no);}
    if condition== -yes {return pw_and(context,-condition,no);}
    if condition==no {return pw_and(context,condition,yes);}
    if condition== -no {return pw_or(context,-condition,yes);}
    if yes== -no {return -pw_xor(context,condition,yes);}
    if yes==1 {return pw_or(context,condition,no);}if no== -1 {return pw_and(context,condition,yes);}
    if yes== -1 {return pw_and(context,-condition,no);}if no==1 {return pw_or(context,-condition,yes);}
    if condition<0 {condition= -condition;let t=yes;yes=no;no=t;}return pw_gate(context,3,condition,yes,no);
}
fn pw_word(context) {
    let count=load64(context+48);if load64(context+72) || count>=load64(context+56) {return pw_bad(context);}
    let meta=load64(context+80)+count*24;store64(meta,0);store64(meta+8,0);store64(meta+16,0);
    store64(context+48,count+1);return load64(context+64)+count*load64(context)*8;
}
fn pw_constant(context,value) {
    let word=pw_word(context);if !word {return 0;}pw_note(context,word,1,value,0);let i=0;while i<load64(context) {let lit= -1;if (value>>i)&1 {lit=1;}store64(word+i*8,lit);i=i+1;}return word;
}
fn pw_meta(context,word) {return load64(context+80)+(word-load64(context+64))/(load64(context)*8)*24;}
fn pw_note(context,word,kind,a,b) {if word {let meta=pw_meta(context,word);store64(meta,kind);store64(meta+8,a);store64(meta+16,b);}return word;}
fn pw_input(context) {
    let word=pw_word(context);if !word {return 0;}let i=0;while i<load64(context) {store64(word+i*8,pw_gate(context,0,0,0,0));i=i+1;}return word;
}
fn pw_boolean(context,literal) {let word=pw_constant(context,0);if !word || !pw_valid_literal(context,literal) {return pw_bad(context);}store64(word,literal);return pw_note(context,word,0,0,0);}
fn pw_not(context,a) {
    if !a {return pw_bad(context);}let word=pw_word(context);if !word {return 0;}let i=0;while i<load64(context) {store64(word+i*8,-load64(a+i*8));i=i+1;}return word;
}
fn pw_truth(context,a) {
    if !a {return pw_bad(context);}let result= -1;let i=0;while i<load64(context) {result=pw_or(context,result,load64(a+i*8));i=i+1;}return result;
}
fn pw_bits(context,a,b,op) {
    if !a || !b {return pw_bad(context);}let word=pw_word(context);if !word {return 0;}let i=0;
    while i<load64(context) {let x=load64(a+i*8);let y=load64(b+i*8);let result=0;
        if op==38 {result=pw_and(context,x,y);}else if op==124 {result=pw_or(context,x,y);}else if op==94 {result=pw_xor(context,x,y);}else {return pw_bad(context);}
        store64(word+i*8,result);i=i+1;
    }return word;
}
fn pw_choose(context,condition,a,b) {
    if !a || !b || !pw_valid_literal(context,condition) {return pw_bad(context);}if condition==1 || a==b {return a;}if condition== -1 {return b;}let word=pw_word(context);if !word {return 0;}let i=0;
    while i<load64(context) {store64(word+i*8,pw_select(context,condition,load64(a+i*8),load64(b+i*8)));i=i+1;}return word;
}
fn pw_add_carry(context,a,b,carry) {
    if !a || !b {return pw_bad(context);}let word=pw_word(context);if !word {return 0;}let i=0;
    while i<load64(context) {let x=load64(a+i*8);let y=load64(b+i*8);let xy=pw_xor(context,x,y);
        store64(word+i*8,pw_xor(context,xy,carry));carry=pw_or(context,pw_and(context,x,y),pw_and(context,xy,carry));i=i+1;
    }return word;
}
fn pw_add(context,a,b) {
    if !a || !b {return pw_bad(context);}let original_a=a;let original_b=b;
    // Collapse constant offsets modulo the word width, including (x-k)+k.
    // Metadata is only a description of the actual bits, never an assumption.
    if load64(pw_meta(context,a))==1 {let swap=a;a=b;b=swap;}
    if load64(pw_meta(context,b))==1 {
        let offset=load64(pw_meta(context,b)+8);let meta=pw_meta(context,a);let scanning=1;
        while scanning {
            let kind=load64(meta);
            if (kind==43 || kind==45) && load64(pw_meta(context,load64(meta+16)))==1 {
                let value=load64(pw_meta(context,load64(meta+16))+8);if kind==45 {value= -value;}offset=offset+value;a=load64(meta+8);meta=pw_meta(context,a);
            }else {scanning=0;}
        }
        let mask= -1;if load64(context)<64 {mask=(1<<load64(context))-1;}offset=offset&mask;
        if !offset {return a;}b=pw_constant(context,offset);if !b {return 0;}
        return pw_note(context,pw_add_carry(context,a,b,-1),43,a,b);
    }
    return pw_note(context,pw_add_carry(context,a,b,-1),43,original_a,original_b);
}
fn pw_subtract(context,a,b) {
    if !a || !b {return pw_bad(context);}if a==b {return pw_constant(context,0);}
    let added=pw_meta(context,a);if load64(added)==43 {
        if load64(added+8)==b {return load64(added+16);}if load64(added+16)==b {return load64(added+8);}
    }
    let original=b;let meta=pw_meta(context,b);let offset=0;
    // Exact modulo-2^width identity: a-(b+k) == (a-b)-k. Reassociate
    // constant offsets so consecutive loop ranks share their subtraction circuit.
    while load64(meta)==43 && load64(pw_meta(context,load64(meta+16)))==1 {
        offset=offset+load64(pw_meta(context,load64(meta+16))+8);b=load64(meta+8);meta=pw_meta(context,b);
    }
    let result=pw_add_carry(context,a,pw_not(context,b),1);
    if offset {result=pw_add_carry(context,result,pw_not(context,pw_constant(context,offset)),1);}
    return pw_note(context,result,45,a,original);
}
fn pw_negate(context,a) {return pw_add_carry(context,pw_not(context,a),pw_constant(context,0),1);}
fn pw_equal(context,a,b) {
    if !a || !b {return pw_bad(context);}let result=1;let i=0;
    while i<load64(context) {result=pw_and(context,result,-pw_xor(context,load64(a+i*8),load64(b+i*8)));i=i+1;}return result;
}
fn pw_unsigned_less(context,a,b) {
    if !a || !b {return pw_bad(context);}let result= -1;let i=0;
    while i<load64(context) {let x=load64(a+i*8);let y=load64(b+i*8);result=pw_select(context,pw_xor(context,x,y),-x,result);i=i+1;}return result;
}
fn pw_signed_less(context,a,b) {
    if !a || !b {return pw_bad(context);}let sign=(load64(context)-1)*8;let x=load64(a+sign);let y=load64(b+sign);
    return pw_select(context,pw_xor(context,x,y),x,pw_unsigned_less(context,a,b));
}
fn pw_multiply(context,a,b) {
    if !a || !b {return pw_bad(context);}let result=pw_constant(context,0);let width=load64(context);let i=0;
    while i<width {let part=pw_word(context);if !part {return 0;}let j=0;
        while j<width {let lit= -1;if j>=i {lit=pw_and(context,load64(a+(j-i)*8),load64(b+i*8));}store64(part+j*8,lit);j=j+1;}
        result=pw_add(context,result,part);i=i+1;
    }return result;
}
fn pw_shift(context,a,amount,right) {
    if !a || !amount {return pw_bad(context);}let width=load64(context);let step=1;let stage=0;let result=a;
    while step<width {let word=pw_word(context);if !word {return 0;}let i=0;
        while i<width {let source=i-step;let fill= -1;if right {source=i+step;fill=load64(result+(width-1)*8);}
            if source>=0 && source<width {fill=load64(result+source*8);}
            store64(word+i*8,pw_select(context,load64(amount+stage*8),fill,load64(result+i*8)));i=i+1;
        }result=word;step=step*2;stage=stage+1;
    }return result;
}
// Truncation toward zero and dividend-signed remainder. out has three words:
// quotient vector, remainder vector, safety literal (nonzero divisor/no overflow).
fn pw_divrem(context,a,b,out) {
    store64(out,0);store64(out+8,0);store64(out+16,0);if !a || !b {return pw_bad(context);}
    let width=load64(context);let sign_a=load64(a+(width-1)*8);let sign_b=load64(b+(width-1)*8);
    let ua=pw_choose(context,sign_a,pw_negate(context,a),a);let ub=pw_choose(context,sign_b,pw_negate(context,b),b);
    let quotient=pw_word(context);let remainder=pw_constant(context,0);if !ua || !ub || !quotient || !remainder {return 0;}
    let i=width;while i>0 {i=i-1;let shifted=pw_word(context);if !shifted {return 0;}
        let carry=load64(remainder+(width-1)*8);store64(shifted,load64(ua+i*8));let j=1;
        while j<width {store64(shifted+j*8,load64(remainder+(j-1)*8));j=j+1;}
        let ge=pw_or(context,carry,-pw_unsigned_less(context,shifted,ub));store64(quotient+i*8,ge);
        remainder=pw_choose(context,ge,pw_subtract(context,shifted,ub),shifted);if !remainder {return 0;}
    }
    let q=pw_choose(context,pw_xor(context,sign_a,sign_b),pw_negate(context,quotient),quotient);
    let r=pw_choose(context,sign_a,pw_negate(context,remainder),remainder);
    let overflow=pw_and(context,pw_equal(context,a,pw_constant(context,1<<(width-1))),pw_equal(context,b,pw_constant(context,-1)));
    let safe=pw_and(context,pw_truth(context,b),-overflow);store64(out,q);store64(out+8,r);store64(out+16,safe);return !load64(context+72);
}
// Compiler-token operations. out=(value vector, safety literal). Logical
// short circuit is handled by the source executor when guarding RHS safety;
// these logical value circuits themselves are pure.
fn pw_binary(context,op,a,b,out) {
    let word=0;let safe=1;store64(out,0);store64(out+8,0);if !a || !b {return pw_bad(context);}
    if op==43 {word=pw_add(context,a,b);}else if op==45 {word=pw_subtract(context,a,b);}
    else if op==42 {word=pw_multiply(context,a,b);}
    else if op==38 || op==124 || op==94 {word=pw_bits(context,a,b,op);}
    else if op==265 || op==266 {word=pw_shift(context,a,b,op==266);}
    else if op==259 || op==260 {let predicate=pw_equal(context,a,b);if op==260 {predicate= -predicate;}word=pw_boolean(context,predicate);}
    else if op==60 {word=pw_boolean(context,pw_signed_less(context,a,b));}
    else if op==62 {word=pw_boolean(context,pw_signed_less(context,b,a));}
    else if op==261 {word=pw_boolean(context,-pw_signed_less(context,b,a));}
    else if op==262 {word=pw_boolean(context,-pw_signed_less(context,a,b));}
    else if op==263 {word=pw_boolean(context,pw_and(context,pw_truth(context,a),pw_truth(context,b)));}
    else if op==264 {word=pw_boolean(context,pw_or(context,pw_truth(context,a),pw_truth(context,b)));}
    else if op==47 || op==37 {
        let results=alloc(24);if results<0 {return pw_bad(context);}pw_divrem(context,a,b,results);
        word=load64(results);if op==37 {word=load64(results+8);}safe=load64(results+16);syscall(11,results,24,0,0,0,0);
    }else {return pw_bad(context);}
    store64(out,word);store64(out+8,safe);return word && safe && !load64(context+72);
}
fn pw_unary(context,op,a) {
    if op==45 {return pw_negate(context,a);}if op==126 {return pw_not(context,a);}if op==33 {return pw_boolean(context,-pw_truth(context,a));}return pw_bad(context);
}
fn pw_emit(context,formula,a,b,c,d,count) {
    let scratch=context+96;store64(scratch,a);store64(scratch+8,b);store64(scratch+16,c);store64(scratch+24,d);
    if !pv_clause(formula,scratch,count) {return pw_bad(context);}return 1;
}
fn pw_cnf_marked(context,extra_clauses,marked) {
    if load64(context+72) || extra_clauses<0 || extra_clauses>131072 {return 0;}
    let gates=load64(context+8);let formula=pv_formula(gates,gates*4+extra_clauses+1,gates*12+extra_clauses+1);if !formula {return 0;}
    pw_emit(context,formula,1,0,0,0,1);let id=2;
    while id<=gates {let row=load64(context+24)+(id-1)*32;let kind=load64(row);let a=load64(row+8);let b=load64(row+16);let c=load64(row+24);
        if marked && !load64(marked+id*8) {kind=0;}
        if kind==1 {
            pw_emit(context,formula,-id,a,0,0,2);pw_emit(context,formula,-id,b,0,0,2);pw_emit(context,formula,id,-a,-b,0,3);
        }else if kind==2 {
            pw_emit(context,formula,-a,-b,-id,0,3);pw_emit(context,formula,a,b,-id,0,3);
            pw_emit(context,formula,a,-b,id,0,3);pw_emit(context,formula,-a,b,id,0,3);
        }else if kind==3 {
            pw_emit(context,formula,-a,-b,id,0,3);pw_emit(context,formula,-a,b,-id,0,3);
            pw_emit(context,formula,a,-c,id,0,3);pw_emit(context,formula,a,c,-id,0,3);
        }else if kind!=0 {pw_bad(context);}
        id=id+1;
    }
    if load64(context+72) {syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);return 0;}return formula;
}
fn pw_cnf(context,extra_clauses) {return pw_cnf_marked(context,extra_clauses,0);}
// Keep only the transitive Boolean cone of this query. Gate numbers stay
// unchanged so checked SAT assignments still decode the original input words.
fn pw_cnf_query(context,condition) {
    if load64(context+72) || !pw_valid_literal(context,condition) {return 0;}
    let size=(load64(context+8)+1)*8;let marked=alloc(size);if marked<0 {return 0;}
    let id=0;while id<=load64(context+8) {store64(marked+id*8,0);id=id+1;}
    let root=condition;if root<0 {root= -root;}store64(marked+root*8,1);id=load64(context+8);
    while id>1 {
        if load64(marked+id*8) {let row=load64(context+24)+(id-1)*32;let kind=load64(row);let count=0;
            if kind==1 || kind==2 {count=2;}else if kind==3 {count=3;}
            let i=1;while i<=count {let child=load64(row+i*8);if child<0 {child= -child;}store64(marked+child*8,1);i=i+1;}
        }id=id-1;
    }
    let formula=pw_cnf_marked(context,1,marked);syscall(11,marked,size,0,0,0,0);
    if formula {pw_emit(context,formula,condition,0,0,0,1);}return formula;
}
fn pw_model_word(context,word,assignment) {
    let result=0;let i=0;while i<load64(context) {let lit=load64(word+i*8);let id=lit;if id<0 {id= -id;}let value=load64(assignment+id*8);
        if (lit>0 && value==1) || (lit<0 && value== -1) {result=result|(1<<i);}i=i+1;
    }return result;
}
fn pw_release(context) {if context {syscall(11,context,load64(context+88),0,0,0,0);}return 0;}
