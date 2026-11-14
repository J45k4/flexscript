import "lib/host.flex";
import "../libs/proof.flex";
import "../libs/proof/memory.flex";
import "../libs/proof/memory-model.flex";
global bm_checks=0;
fn bm_check(condition,message) {h_assert(condition,message);bm_checks=bm_checks+1;return 0;}
fn bm_context(width) {
    let words=pw_context(width,131072,65536);bm_check(words,"word allocation");let nodes=512;if width==8 {nodes=64;}
    let memory=pb_context(words,nodes,4096,16384,128);bm_check(memory,"memory allocation");return memory;
}
fn bm_close(memory) {let words=load64(memory);pb_release(memory);pw_release(words);return 0;}
fn bm_query(memory,condition,expected,label) {
    let words=load64(memory);let axioms=pb_constraints(memory);bm_check(axioms && !load64(memory+112),"memory axiom capacity");
    let formula=pw_cnf_query(words,pw_and(words,axioms,condition));bm_check(formula,"memory CNF allocation");let search=pv_search(formula,262144);bm_check(search,"memory search allocation");
    // Witness queries use the same input-first policy as source requirement
    // consistency. Both policies independently check the resulting evidence.
    let result=0;if expected==1 {result=pv_decide_inputs(search,200000000,200000000);}else {result=pv_decide(search,200000000,200000000);}
    if result!=expected {h_print(2,h_cat3(label,": result=",h_cat3(h_int(result)," gates=",h_cat3(h_int(load64(words+8)),"\n",""))));}
    bm_check(result==expected,label);
    if result==1 {let model=pbm_replay(memory,load64(search+8),200000000);if !model {h_print(2,h_cat3("memory completion failed: ",label,"\n"));}
        bm_check(model,"SAT memory model did not replay as concrete intervals");
        bm_check(pbm_bool(model,condition) && pbm_bool(model,axioms),"concrete gate evaluation contradicted SAT query");pbm_release(model);
    }
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);return 0;
}
fn bm_geometry() {
    let memory=bm_context(8);let c=load64(memory);let p=0;while p<8 {let n=0;while n<8 {
        let valid=pb_valid(memory,pw_constant(c,p),pw_constant(c,n));let expected=n==0 || p>0;
        bm_check(valid==1 || valid== -1,"constant geometry did not simplify");bm_check((valid==1)==expected,"small region validity differs");n=n+1;
    }p=p+1;}
    bm_check(pb_valid(memory,pw_constant(c,127),pw_constant(c,1))==1,"last positive byte rejected");
    bm_check(pb_valid(memory,pw_constant(c,127),pw_constant(c,2))== -1,"signed address overflow accepted");
    bm_check(pb_valid(memory,pw_constant(c,-1),pw_constant(c,0))==1,"empty region requires a live pointer");
    bm_check(pb_valid(memory,pw_constant(c,1),pw_constant(c,-1))== -1,"negative length accepted");
    p=1;while p<5 {let n=0;while n<4 {let q=1;while q<5 {let m=0;while m<4 {
        let expected=n==0 || m==0 || p+n<=q || q+m<=p;
        bm_check((pb_disjoint(memory,pw_constant(c,p),pw_constant(c,n),pw_constant(c,q),pw_constant(c,m))==1)==expected,"region disjointness differs from native intervals");m=m+1;
    }q=q+1;}n=n+1;}p=p+1;}bm_close(memory);return 0;
}
fn bm_membership_oracle() {
    let p=0;while p<16 {
        let memory=bm_context(8);let c=load64(memory);let n=0;
        while n<16 {let address=0;while address<16 {
            let valid=p>0 && n>0;
            let expected=valid && address>=p && address<p+n;
            let point=pw_constant(c,address);let start=pw_constant(c,p);let length=pw_constant(c,n);
            let actual=pb_member(memory,start,length,point);
            bm_check((actual==1)==expected && (actual==1 || actual== -1),"membership differs from native interval matrix");
            point=pw_add(c,pw_constant(c,address-1),pw_constant(c,1));
            actual=pb_member(memory,start,length,point);
            bm_check((actual==1)==expected && (actual==1 || actual== -1),"wrapped-offset membership differs from native intervals");
            address=address+1;
        }n=n+1;}bm_close(memory);p=p+1;
    }
    let words=h_take(64);store64(words,0);store64(words+8,1);store64(words+16,2);store64(words+24,8);
    store64(words+32,0x7fffffffffffffff);store64(words+40,0x7ffffffffffffffe);store64(words+48,-1);store64(words+56,0x8000000000000000);
    p=0;while p<8 {let memory=bm_context(64);let c=load64(memory);let start=load64(words+p*8);let ni=0;
        while ni<8 {let length=load64(words+ni*8);let ai=0;while ai<8 {let address=load64(words+ai*8);
            let valid=start>0 && length>0 && length<=0x7fffffffffffffff-start+1;
            let expected=valid && address>=start && address<=start+length-1;
            let actual=pb_member(memory,pw_constant(c,start),pw_constant(c,length),pw_constant(c,address));
            bm_check((actual==1)==expected && (actual==1 || actual== -1),"64-bit boundary membership differs from native intervals");ai=ai+1;
        }ni=ni+1;}bm_close(memory);p=p+1;
    }
    return 0;
}
fn bm_alias() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_input(c);let q=pw_input(c);let one=pw_constant(c,1);
    let a=pb_lookup(memory,root,p,0);let b=pb_lookup(memory,root,q,0);let same=pw_equal(c,p,q);
    let equal=pw_equal(c,load64(a+16),load64(b+16));equal=pw_and(c,equal,pw_equal(c,load64(a+40),load64(b+40)));
    equal=pw_and(c,equal,pw_and(c,-pw_xor(c,load64(a+24),load64(b+24)),-pw_xor(c,load64(a+32),load64(b+32))));
    bm_query(memory,pw_and(c,same,-equal),2,"aliased initial cells differ");
    let writable=pb_permission(memory,root,p,one,1);let readable=pb_permission(memory,root,q,one,0);
    bm_query(memory,pw_and(c,same,pw_and(c,writable,-readable)),2,"write permission did not imply aliased read permission");
    bm_query(memory,pw_and(c,same,pw_and(c,readable,-writable)),1,"read-only memory was excluded");
    bm_close(memory);return 0;
}
fn bm_ranges() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_constant(c,10);let length=pw_constant(c,1000000);
    let whole=pb_permission(memory,root,p,length,1);let inside=pb_permission(memory,root,pw_constant(c,999999),pw_constant(c,8),0);
    bm_query(memory,pw_and(c,whole,-inside),2,"large region did not grant interior access");
    let empty=pb_permission(memory,root,pw_constant(c,-1),pw_constant(c,0),1);bm_check(empty==1,"empty permission is not true");
    let invalid=pb_permission(memory,root,pw_constant(c,0),pw_constant(c,1),0);bm_check(invalid== -1,"null byte can be readable");
    let lower=pb_permission(memory,root,pw_constant(c,9),pw_constant(c,1),0);bm_query(memory,pw_and(c,whole,-lower),1,"permissions escaped before a region");
    let upper=pb_permission(memory,root,pw_constant(c,1000010),pw_constant(c,1),0);bm_query(memory,pw_and(c,whole,-upper),1,"permissions escaped after a region");
    bm_close(memory);return 0;
}
fn bm_store() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_input(c);let q=pw_input(c);let value=pw_input(c);let one=pw_constant(c,1);let out=h_take(16);
    let allowed=pb_permission(memory,root,p,one,1);bm_check(pb_store(memory,root,p,value,1,1,out),"byte store construction");let after=load64(out);let safe=load64(out+8);
    bm_check(pb_load(memory,after,q,1,out),"byte load construction");let got=load64(out);let read_safe=load64(out+8);let alias=pw_equal(c,p,q);let low=pw_bits(c,value,pw_constant(c,255),38);
    let correct=pw_and(c,safe,pw_and(c,read_safe,pw_equal(c,got,low)));bm_query(memory,pw_and(c,allowed,pw_and(c,alias,-correct)),2,"byte store/load alias or truncation differs");
    let old=pb_lookup(memory,root,p,0);bm_query(memory,pw_and(c,allowed,pw_and(c,alias,-pw_equal(c,load64(old+16),low))),1,"store overwrote its old snapshot");
    let before=pb_lookup(memory,root,q,0);let current=pb_lookup(memory,after,q,0);bm_query(memory,pw_and(c,-alias,-pw_equal(c,load64(before+16),load64(current+16))),2,"byte store changed a nonaliased byte");
    bm_close(memory);return 0;
}
fn bm_word() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_constant(c,11);let out=h_take(16);let allowed=pb_permission(memory,root,p,pw_constant(c,8),1);
    let value=pw_constant(c,0xfedcba9876543210);bm_check(pb_store(memory,root,p,value,8,1,out),"unaligned word store");let after=load64(out);let correct=load64(out+8);let i=0;
    while i<8 {bm_check(pb_load(memory,after,pw_constant(c,11+i),1,out),"word byte extraction");correct=pw_and(c,correct,pw_and(c,load64(out+8),pw_equal(c,load64(out),pw_constant(c,(0xfedcba9876543210>>(i*8))&255))));i=i+1;}
    bm_check(pb_load(memory,after,p,8,out),"unaligned word load");correct=pw_and(c,correct,pw_and(c,load64(out+8),pw_equal(c,load64(out),value)));
    bm_query(memory,pw_and(c,allowed,-correct),2,"little-endian word roundtrip differs");
    bm_check(pb_store(memory,after,pw_constant(c,14),pw_constant(c,255),1,1,out),"overlapping byte overwrite");let mixed=load64(out);bm_check(pb_load(memory,mixed,p,8,out),"mixed-width read");
    bm_query(memory,pw_and(c,allowed,-pw_equal(c,load64(out),pw_constant(c,0xfedcba98ff543210))),2,"overlapping byte/word writes differ");bm_close(memory);return 0;
}
fn bm_frames() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_input(c);let n=pw_constant(c,4);let q=pw_input(c);let next=pb_havoc(memory,root,p,n,1);
    let a=pb_lookup(memory,root,q,0);let b=pb_lookup(memory,next,q,0);let outside= -pb_member(memory,p,n,q);
    bm_query(memory,pw_and(c,outside,-pw_equal(c,load64(a+16),load64(b+16))),2,"havoc escaped its frame");
    let same=pw_and(c,-pw_xor(c,load64(a+24),load64(b+24)),-pw_xor(c,load64(a+32),load64(b+32)));same=pw_and(c,same,pw_equal(c,load64(a+40),load64(b+40)));
    bm_query(memory,-same,2,"content havoc changed permissions or allocation identity");
    bm_query(memory,pw_and(c,pb_member(memory,p,n,q),-pw_equal(c,load64(a+16),load64(b+16))),1,"havoc did not permit changed data");
    let at_p=pb_lookup(memory,next,p,0);bm_query(memory,pw_and(c,pw_equal(c,p,q),-pw_equal(c,load64(at_p+16),load64(b+16))),2,"havoc maps gave aliased addresses different values");
    let condition=pw_gate(c,0,0,0,0);let joined=pb_join(memory,condition,next,root);let value=pb_lookup(memory,joined,q,0);
    bm_query(memory,pw_and(c,-condition,-pw_equal(c,load64(value+16),load64(a+16))),2,"join changed the unselected snapshot");bm_close(memory);return 0;
}
fn bm_lifetime() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_constant(c,20);let n=pw_constant(c,8);let original=pb_permission(memory,root,p,n,1);
    let released=pb_free(memory,root,p,n,1);let current=pb_permission(memory,released,p,n,0);bm_query(memory,pw_and(c,original,current),2,"released memory remained readable");
    bm_query(memory,original,1,"release invalidated an entry snapshot");
    let out=h_take(16);bm_check(pb_load(memory,released,p,8,out),"released word load construction");bm_query(memory,load64(out+8),2,"released load was considered safe");
    let revoked=pb_revoke(memory,root,p,n,1);let before=pb_lookup(memory,root,p,0);let after=pb_lookup(memory,revoked,p,0);
    bm_query(memory,pw_and(c,-load64(before+24),load64(after+24)),2,"revocation granted read permission");
    bm_query(memory,pw_and(c,original,-load64(after+24)),1,"revocation could not remove permission");
    bm_query(memory,pw_and(c,original,load64(after+32)),1,"revocation upper bound forced release");
    bm_close(memory);return 0;
}
fn bm_allocations() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let n=pw_constant(c,8);let out=h_take(16);
    bm_check(pb_alloc(memory,root,n,1,out),"allocation construction");let p=load64(out);let allocated=load64(out+8);let success=pw_signed_less(c,pb_zero(memory),p);
    bm_check(pb_load(memory,allocated,p,8,out),"new allocation load");let correct=pw_and(c,load64(out+8),pw_equal(c,load64(out),pb_zero(memory)));
    bm_query(memory,pw_and(c,success,-correct),2,"new allocation was not readable and zero initialized");bm_query(memory,success,1,"successful allocation impossible");
    bm_query(memory,pw_signed_less(c,p,pb_zero(memory)),1,"allocation failure was excluded");
    let released=pb_free(memory,allocated,p,n,1);bm_check(pb_alloc(memory,released,n,1,out),"reallocation construction");let q=load64(out);let reallocated=load64(out+8);let reused=pw_and(c,success,pw_equal(c,p,q));
    let old=pb_lookup(memory,allocated,p,0);let fresh=pb_lookup(memory,reallocated,q,0);
    bm_query(memory,pw_and(c,reused,pw_equal(c,load64(old+40),load64(fresh+40))),2,"reused address kept the old allocation identity");
    bm_query(memory,pw_and(c,reused,pw_equal(c,p,pw_constant(c,16))),1,"released address could not be reused");
    bm_check(pb_alloc(memory,root,pw_constant(c,0),1,out),"empty allocation construction");bm_query(memory,-pw_signed_less(c,load64(out),pb_zero(memory)),2,"empty allocation did not fail");bm_close(memory);return 0;
}
fn bm_fresh_frames() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_input(c);let n=pw_constant(c,8);let out=h_take(16);
    let live=pb_permission(memory,root,p,n,1);bm_check(pb_alloc(memory,root,n,1,out),"fresh allocation construction");let q=load64(out);let success=pw_signed_less(c,pb_zero(memory),q);
    bm_query(memory,pw_and(c,live,pw_and(c,success,-pb_disjoint(memory,p,n,q,n))),2,"fresh allocation overlapped an existing region");bm_close(memory);
    memory=bm_context(64);c=load64(memory);root=load64(memory+176);p=pw_constant(c,10);n=pw_constant(c,8);live=pb_permission(memory,root,p,n,1);
    let partial=pb_free(memory,root,p,pw_constant(c,4),1);bm_check(pb_alloc(memory,partial,n,1,out),"partial release allocation construction");q=load64(out);
    bm_query(memory,pw_and(c,live,pw_equal(c,q,p)),2,"allocation reused bytes that survived a partial release");
    let still_readable=pb_permission(memory,partial,p,n,0);bm_query(memory,pw_and(c,live,still_readable),2,"partial release left a full readable range");
    let tail=pb_permission(memory,partial,pw_constant(c,14),pw_constant(c,4),1);bm_query(memory,pw_and(c,live,-tail),2,"partial release revoked an unrelated tail");bm_close(memory);return 0;
}
fn bm_offsets() {
    let base=1;while base<=125 {let length=0;while length<=4 {
        let memory=bm_context(8);let c=load64(memory);let p=pw_constant(c,base);let n=pw_constant(c,length);let offset=0;
        while offset<256 {let at=pw_add(c,p,pw_constant(c,offset));let actual=pb_member(memory,p,n,at);let address=(base+offset)&255;
            let valid=length==0 || base+length-1<=127;let expected=valid && address>=base && address<base+length;
            bm_check(actual==1 || actual== -1,"constant offset membership did not simplify");bm_check((actual==1)==expected,"offset normalization differs from native wrapped addresses");offset=offset+1;
        }bm_close(memory);length=length+1;
    }if base==1 {base=64;}else if base==64 {base=125;}else {base=126;}}
    return 0;
}
fn bm_native_permissions() {
    let start=0;while start<10 {let count=0;while count<4 {
        let memory=bm_context(8);let c=load64(memory);let root=load64(memory+176);let empty=pb_free(memory,root,pw_constant(c,1),pw_constant(c,127),1);let out=h_take(16);
        bm_check(pb_alloc(memory,empty,pw_constant(c,4),1,out),"native permission allocation");let address=load64(out);let allocated=load64(out+8);
        let final=pb_free(memory,allocated,pw_constant(c,5),pw_constant(c,2),1);let predicate=pb_permission(memory,final,pw_constant(c,start),pw_constant(c,count),1);
        let expected=1;let i=start;while i<start+count {if i!=4 && i!=7 {expected=0;}i=i+1;}
        let correct=predicate;if !expected {correct= -correct;}let bound=pw_equal(c,address,pw_constant(c,4));
        bm_query(memory,pw_and(c,bound,correct),1,"native interval permission model was excluded");bm_query(memory,pw_and(c,bound,-correct),2,"range permission differs from native enumeration");
        bm_close(memory);count=count+1;
    }start=start+1;}return 0;
}
fn bm_address_identities() {
    let memory=bm_context(8);let c=load64(memory);let x=pw_input(c);let y=pw_input(c);let shifted_x=pw_add(c,x,pw_constant(c,200));let shifted_y=pw_add(c,y,pw_constant(c,200));
    bm_query(memory,pw_xor(c,pb_address_equal(memory,shifted_x,shifted_y),pw_equal(c,x,y)),2,"equal offset address normalization differs");
    bm_query(memory,pb_address_equal(memory,x,pw_add(c,x,pw_constant(c,128))),2,"different wrapped offsets can alias");
    bm_query(memory,-pb_address_equal(memory,pw_subtract(c,shifted_x,pw_constant(c,201)),pw_add(c,x,pw_constant(c,255))),2,"mixed offset address normalization differs");
    let base=pw_input(c);let left=pw_add(c,base,x);let right=pw_add(c,base,y);
    bm_query(memory,pw_xor(c,pb_address_equal(memory,left,right),pw_equal(c,left,right)),2,"symbolic offset cancellation differs from bit-level addition");
    bm_query(memory,pw_xor(c,pb_address_equal(memory,base,left),pw_equal(c,base,left)),2,"zero offset cancellation differs from bit-level addition");
    bm_close(memory);return 0;
}
fn bm_completion() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let out=h_take(16);
    bm_check(pb_alloc(memory,root,pw_constant(c,16),1,out),"concrete allocation construction");let p=load64(out);let allocated=load64(out+8);
    let address=pw_add(c,p,pw_constant(c,1));bm_check(pb_store(memory,allocated,address,pw_constant(c,0xfedcba9876543210),8,1,out),"concrete store construction");let stored=load64(out);
    let released=pb_free(memory,stored,pw_add(c,p,pw_constant(c,4)),pw_constant(c,2),1);
    let all=pb_permission(memory,released,p,pw_constant(c,16),0);let front=pb_permission(memory,released,p,pw_constant(c,4),1);
    let condition=pw_and(c,pw_equal(c,p,pw_constant(c,1000000)),pw_and(c,-all,front));let axioms=pb_constraints(memory);
    let formula=pw_cnf_query(c,pw_and(c,condition,axioms));bm_check(formula,"concrete model formula");let search=pv_search(formula,262144);bm_check(search,"concrete model search");
    bm_check(pv_decide(search,200000000,200000000)==1,"concrete model existence");let assignment=load64(search+8);let model=pbm_replay(memory,assignment,200000000);bm_check(model,"concrete model completion");
    let before=pbm_index(model,allocated);let after=pbm_index(model,stored);let final=pbm_index(model,released);let i=0;
    while i<16 {let a=pbm_cell(model,before,1000000+i);let b=pbm_cell(model,after,1000000+i);let d=pbm_cell(model,final,1000000+i);let expected=0;
        if i>=1 && i<=8 {expected=(0xfedcba9876543210>>((i-1)*8))&255;}let live=i!=4 && i!=5;
        bm_check(load64(a)==0 && load64(a+8) && load64(a+16),"concrete old allocation was mutated");
        bm_check(load64(b)==expected && load64(b+8) && load64(b+16),"concrete native byte order differs");
        bm_check(load64(d)==expected && load64(d+8)==live && load64(d+16)==live,"concrete partial release differs");i=i+1;
    }
    bm_check(pbm_permission(model,final,1000006,10,1) && !pbm_permission(model,final,1000003,4,0),"concrete interval permission differs");
    bm_check(pbm_permission(model,final,-1,0,1) && !pbm_permission(model,final,0,1,0),"concrete empty/null semantics differ");
    bm_check(!pbm_permission(model,final,0x7fffffffffffffff,2,0),"concrete overflowing range accepted");pbm_release(model);
    bm_check(!pbm_replay(memory,assignment,1),"concrete completion ignored budget exhaustion");
    // Corrupt a derived observation, keeping the actual operation unchanged.
    // The native interval execution must reject it even if the byte was never
    // used by the SAT query. This is independent of checking the original CNF.
    let cached=load64(memory+56);let saved=load64(cached+16);store64(cached+16,pw_constant(c,999));
    bm_check(!pbm_replay(memory,assignment,200000000),"concrete completion accepted a corrupted observed byte");store64(cached+16,saved);
    let region=load64(memory+80);let predicate=load64(region+32);store64(region+32,-predicate);
    bm_check(!pbm_replay(memory,assignment,200000000),"concrete completion accepted a corrupted whole-range predicate");store64(region+32,predicate);
    let identity=load64(allocated+48);store64(allocated+48,pw_constant(c,0));
    bm_check(!pbm_replay(memory,assignment,200000000),"concrete completion accepted a reused allocation identity");store64(allocated+48,identity);
    let gate=load64(c+24);store64(gate,0);bm_check(!pbm_replay(memory,assignment,200000000),"concrete completion accepted a malformed constant gate");store64(gate,4);
    model=pbm_replay(memory,assignment,200000000);bm_check(model,"restored model failed completion");pbm_release(model);
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);bm_close(memory);
    // The concrete model also covers addresses never mentioned by a load.
    memory=bm_context(64);c=load64(memory);root=load64(memory+176);let permitted=pb_permission(memory,root,pw_constant(c,10),pw_constant(c,1000000),1);
    axioms=pb_constraints(memory);formula=pw_cnf_query(c,pw_and(c,axioms,permitted));bm_check(formula,"large concrete formula");search=pv_search(formula,262144);bm_check(search,"large concrete search");
    bm_check(pv_decide(search,200000000,200000000)==1,"large concrete model existence");model=pbm_replay(memory,load64(search+8),200000000);bm_check(model,"large concrete completion");
    bm_check(pbm_permission(model,0,10,1000000,1) && load64(pbm_cell(model,0,555555)+16),"unobserved interior lost permission");pbm_release(model);
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);bm_close(memory);return 0;
}
fn bm_heap_closure() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_constant(c,16);let one=pw_constant(c,1);
    let grown=pb_grow(memory,root,1);let before=pb_lookup(memory,root,p,0);let after=pb_lookup(memory,grown,p,0);
    let live=pw_truth(c,load64(before+40));let same=pw_equal(c,load64(before+16),load64(after+16));
    same=pw_and(c,same,pw_equal(c,load64(before+40),load64(after+40)));
    same=pw_and(c,same,pw_and(c,-pw_xor(c,load64(before+24),load64(after+24)),-pw_xor(c,load64(before+32),load64(after+32))));
    bm_query(memory,pw_and(c,live,-same),2,"allocation closure changed still-live storage");
    let fresh=pw_and(c,-live,load64(after+32));
    bm_query(memory,pw_and(c,fresh,pw_equal(c,load64(after+16),pw_constant(c,42))),1,"allocation closure cannot introduce written fresh storage");
    bm_query(memory,pw_and(c,fresh,pw_equal(c,load64(before+40),load64(after+40))),2,"allocation closure reused a prior identity");
    let changed=pb_fresh_havoc(memory,grown,root,1);let bytes=pb_lookup(memory,changed,p,0);
    bm_query(memory,pw_and(c,fresh,-pw_equal(c,load64(after+16),load64(bytes+16))),1,"fresh-content havoc preserved new storage");
    bm_query(memory,pw_and(c,live,-pw_equal(c,load64(before+16),load64(bytes+16))),2,"fresh-content havoc changed existing storage");
    bm_query(memory,pw_and(c,fresh,-load64(bytes+32)),2,"fresh-content havoc removed permissions");
    let revoked=pb_fresh_revoke(memory,changed,root,1);let cell=pb_lookup(memory,revoked,p,0);
    bm_query(memory,pw_and(c,fresh,-load64(cell+24)),1,"fresh release could not revoke new storage");
    bm_query(memory,pw_and(c,load64(before+32),-load64(cell+32)),2,"fresh release revoked existing storage");
    bm_query(memory,-pw_equal(c,load64(cell+16),load64(bytes+16)),2,"fresh release changed contents");
    let own_entry=pb_fresh_havoc(memory,grown,grown,1);let own=pb_lookup(memory,own_entry,p,0);
    bm_query(memory,-pw_equal(c,load64(own+16),load64(after+16)),2,"callee considered caller allocation fresh");
    let disabled=pb_grow(memory,pb_fresh_revoke(memory,pb_fresh_havoc(memory,grown,root,-1),root,-1),-1);let off=pb_lookup(memory,disabled,p,0);
    bm_query(memory,-pw_equal(c,load64(off+16),load64(after+16)),2,"disabled heap abstraction changed contents");
    bm_query(memory,pw_xor(c,load64(off+32),load64(after+32)),2,"disabled heap abstraction changed permissions");
    let freed=pb_free(memory,grown,p,one,1);let again=pb_grow(memory,freed,1);let second=pb_lookup(memory,again,p,0);
    bm_query(memory,pw_and(c,fresh,pw_and(c,load64(second+32),pw_equal(c,load64(after+40),load64(second+40)))),2,"allocation closure reused a released generation");
    bm_query(memory,pw_and(c,fresh,load64(second+32)),1,"allocation closure cannot reuse released addresses");
    bm_close(memory);
    memory=bm_context(64);c=load64(memory);root=load64(memory+176);p=pw_input(c);let q=pw_input(c);grown=pb_grow(memory,root,1);
    let a=pb_lookup(memory,grown,p,0);let b=pb_lookup(memory,grown,q,0);same=pw_equal(c,load64(a+16),load64(b+16));same=pw_and(c,same,-pw_xor(c,load64(a+32),load64(b+32)));
    bm_query(memory,pw_and(c,pw_equal(c,p,q),-same),2,"allocation closure lost alias congruence");bm_close(memory);
    memory=bm_context(64);c=load64(memory);root=load64(memory+176);grown=pb_grow(memory,root,1);
    let range=pb_permission(memory,grown,pw_constant(c,10),pw_constant(c,1000000),1);
    bm_query(memory,range,1,"allocation closure cannot complete a full fresh interval");
    let forbidden=pb_permission(memory,grown,pw_constant(c,0),pw_constant(c,1),1);bm_check(forbidden== -1,"allocation closure granted null access");bm_close(memory);return 0;
}
fn bm_fresh_predicates() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let p=pw_constant(c,16);let n=pw_constant(c,4);let out=h_take(16);
    bm_query(memory,pb_fresh(memory,root,root,p,n),2,"entry storage claimed fresh");
    bm_check(pb_fresh(memory,root,root,pw_constant(c,-1),pw_constant(c,0))==1,"empty fresh region rejected");
    bm_check(pb_fresh(memory,root,root,pw_constant(c,0),pw_constant(c,1))== -1,"null fresh region accepted");
    let grown=pb_grow(memory,root,1);let whole=pb_fresh(memory,grown,root,p,n);
    bm_query(memory,whole,1,"whole fresh interval cannot be completed");
    let tail=pb_fresh(memory,grown,root,pw_constant(c,18),pw_constant(c,2));bm_query(memory,pw_and(c,whole,-tail),2,"fresh interval omitted an interior byte");
    let preexisting=pb_permission(memory,root,pw_constant(c,18),pw_constant(c,1),1);
    bm_query(memory,pw_and(c,preexisting,whole),2,"fresh interval included an existing byte");
    let unreadable= -pb_permission(memory,grown,p,n,0);bm_query(memory,pw_and(c,whole,unreadable),1,"freshness implicitly granted read permission");
    // Release is a separate scenario. Prior negative-range queries retain
    // their independent witness maps; do not make those unrelated witnesses
    // part of every later scenario's formula.
    bm_close(memory);memory=bm_context(64);c=load64(memory);root=load64(memory+176);p=pw_constant(c,16);n=pw_constant(c,4);
    grown=pb_grow(memory,root,1);whole=pb_fresh(memory,grown,root,p,n);
    let revoked=pb_revoke(memory,grown,p,n,1);let after=pb_fresh(memory,revoked,root,p,n);
    bm_query(memory,pw_and(c,whole,-after),1,"freshness survived every possible release");
    let freed=pb_free(memory,grown,p,n,1);bm_query(memory,pb_fresh(memory,freed,root,p,n),2,"freed bytes still fresh");
    bm_close(memory);memory=bm_context(64);c=load64(memory);root=load64(memory+176);p=pw_constant(c,16);n=pw_constant(c,4);
    grown=pb_grow(memory,root,1);freed=pb_free(memory,grown,p,n,1);
    bm_check(pb_alloc(memory,freed,n,1,out),"reallocation after abstract growth");let result=load64(out);let allocated=load64(out+8);
    bm_query(memory,pw_and(c,pw_equal(c,result,p),-pb_fresh(memory,allocated,grown,p,n)),2,"concrete reallocation did not differ from abstract generation");
    bm_close(memory);return 0;
}
fn bm_heap_corruption() {
    let memory=bm_context(64);let c=load64(memory);let root=load64(memory+176);let grown=pb_grow(memory,root,1);let p=pw_constant(c,16);let n=pw_constant(c,2);
    let fresh=pb_fresh(memory,grown,root,p,n);let writable=pb_permission(memory,grown,p,n,1);let changed=pb_fresh_havoc(memory,grown,root,1);
    pb_lookup(memory,changed,p,0);let axioms=pb_constraints(memory);let formula=pw_cnf_query(c,pw_and(c,axioms,pw_and(c,fresh,writable)));bm_check(formula,"heap corruption formula");
    let search=pv_search(formula,262144);bm_check(search,"heap corruption search");bm_check(pv_decide_inputs(search,200000000,200000000)==1,"heap corruption model existence");
    let assignment=load64(search+8);let model=pbm_replay(memory,assignment,200000000);bm_check(model,"heap corruption baseline completion");pbm_release(model);
    let identity=load64(grown+48);store64(grown+48,pw_constant(c,0));bm_check(!pbm_replay(memory,assignment,200000000),"completion accepted a corrupt abstract generation");store64(grown+48,identity);
    store64(grown+40,-1);bm_check(!pbm_replay(memory,assignment,200000000),"completion ignored a disabled allocation closure");store64(grown+40,1);
    store64(changed+56,changed);bm_check(!pbm_replay(memory,assignment,200000000),"completion accepted a cyclic fresh-storage reference");store64(changed+56,root);
    let region=load64(memory+80);let entry=load64(region+24);store64(region+24,grown);
    bm_check(!pbm_replay(memory,assignment,200000000),"completion ignored the freshness reference snapshot");store64(region+24,entry);
    let predicate=load64(region+32);store64(region+32,-predicate);bm_check(!pbm_replay(memory,assignment,200000000),"completion accepted a corrupt fresh-range predicate");store64(region+32,predicate);
    bm_check(!pbm_replay(memory,assignment,1),"abstract memory completion ignored its work budget");
    model=pbm_replay(memory,assignment,200000000);bm_check(model,"restored abstract model failed completion");pbm_release(model);
    syscall(11,search,104+(load64(formula)+1)*16+load64(search+48)*32,0,0,0,0);syscall(11,formula,64+load64(formula+24)*16+load64(formula+32)*8,0,0,0,0);bm_close(memory);return 0;
}
fn bm_limits() {
    let c=pw_context(8,4096,1024);bm_check(!pb_context(c,128,4,4,4),"allocation identities can overflow their domain");let memory=pb_context(c,1,4,4,4);let root=load64(memory+176);
    bm_check(!pb_havoc(memory,root,pw_constant(c,1),pw_constant(c,1),1) && !pb_constraints(memory),"node exhaustion accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,1,8,4);root=load64(memory+176);pb_lookup(memory,root,pw_constant(c,1),0);pb_lookup(memory,root,pw_constant(c,2),0);
    bm_check(!pb_constraints(memory),"probe exhaustion accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);pb_lookup(memory,load64(memory+176)+1,pw_constant(c,1),0);
    bm_check(!pb_constraints(memory),"malformed snapshot accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);bm_check(!pb_disjoint(memory,123,pw_constant(c,1),pw_constant(c,1),pw_constant(c,1)) && !pb_constraints(memory),"malformed region accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);let out=h_take(16);bm_check(!pb_store(memory,load64(memory+176),123,pw_constant(c,1),1,1,out) && !pb_constraints(memory),"malformed store accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);bm_check(!pb_load(memory,load64(memory+176),123,1,out) && !pb_constraints(memory),"malformed load accepted evidence");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);root=load64(memory+176);bm_check(!pb_fresh(memory,root,root+1,pw_constant(c,1),pw_constant(c,1)) && !pb_constraints(memory),"malformed freshness reference accepted");pb_release(memory);pw_release(c);
    c=pw_context(8,4096,1024);memory=pb_context(c,8,4,4,4);root=load64(memory+176);bm_check(!pb_node(memory,9,root,pw_constant(c,2),pw_constant(c,126),0,1,0) && !pb_constraints(memory),"malformed allocation-closure domain accepted");pb_release(memory);pw_release(c);return 0;
}
fn bm_distinct_cells() {
    // A 32-byte metadata read must not spend gates comparing the contents of
    // cells whose addresses are already definitely different. The former
    // eager congruence construction exhausted this context before querying.
    let c=pw_context(64,32768,4096);bm_check(c,"distinct-cell word context");
    let memory=pb_context(c,16,128,256,16);bm_check(memory,"distinct-cell memory context");let root=load64(memory+176);
    let grant=pb_permission(memory,root,pw_constant(c,4096),pw_constant(c,32),1);let safe=1;let out=h_take(16);let i=0;
    while i<32 {bm_check(pb_load(memory,root,pw_constant(c,4096+i),1,out),"distinct-cell load capacity");safe=pw_and(c,safe,load64(out+8));i=i+1;}
    bm_query(memory,grant,1,"distinct-cell writable model");bm_query(memory,pw_and(c,grant,-safe),2,"distinct-cell read permissions");
    bm_check(!load64(c+72) && load64(c+8)<32768,"distinct cells exhausted a bounded circuit");bm_close(memory);return 0;
}
fn main(argc,argv) {
    h_environment(argc,argv);bm_geometry();bm_membership_oracle();h_print(1,"PASS: memory geometry and membership oracle\n");bm_alias();h_print(1,"PASS: memory aliasing\n");bm_ranges();h_print(1,"PASS: memory ranges\n");
    bm_store();h_print(1,"PASS: byte stores\n");bm_word();h_print(1,"PASS: word stores\n");bm_frames();h_print(1,"PASS: memory frames\n");bm_lifetime();h_print(1,"PASS: lifetimes\n");bm_allocations();h_print(1,"PASS: allocations\n");
    bm_fresh_frames();h_print(1,"PASS: allocation frames\n");bm_offsets();h_print(1,"PASS: wrapped address offsets\n");
    bm_native_permissions();h_print(1,"PASS: native interval oracle\n");bm_address_identities();h_print(1,"PASS: address identities\n");bm_completion();h_print(1,"PASS: concrete memory completion and corruption checks\n");
    bm_heap_closure();h_print(1,"PASS: allocation closure and fresh storage\n");bm_fresh_predicates();h_print(1,"PASS: fresh interval predicates\n");
    bm_heap_corruption();h_print(1,"PASS: abstract memory corruption rejection\n");bm_distinct_cells();h_print(1,"PASS: bounded distinct-cell observations\n");bm_limits();
    h_print(1,h_cat3("PASS: ",h_int(bm_checks)," memory-engine checks with independent SAT/UNSAT evidence\n"));return 0;
}
