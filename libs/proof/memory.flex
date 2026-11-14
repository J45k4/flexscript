import "word.flex";
// Persistent byte memory. Every cell is (byte, read, write, allocation identity).
// The initial map and havoc maps are finite observations of total functions;
// equal addresses must have equal observations. Range predicates use explicit
// negative witnesses and universal constraints at all observed addresses.
// Context (192): words, node table/count/cap, probe table/count/cap, lookup
// table/count/cap, region table/count/cap, axioms, error, size, dummy cell, root.
// Node (80): kind,parent,p,n,value,guard,identity,other,processed lookups,bounds seen.
// Kinds: 0 initial, 1 byte write, 2 content havoc, 3 allocation, 4 exact release,
// 5 conditional join, 6 permission/lifetime revocation upper bound,
// 7 fresh-content havoc, 8 fresh-lifetime revocation (other = entry snapshot),
// 9 allocation closure over nonlive bytes. Its identity is a generation label:
// only same-address identity comparisons across snapshots are meaningful for
// this abstraction; it does not claim all fresh bytes belong to one object.
// Cell/probe/cache (48): state/address/byte/read literal/write literal/identity.
// Region (80): state,p,n,write,predicate,witness,processed lookups/nodes,valid,empty.
fn pb_bad(memory) {store64(memory+112,1);pw_bad(load64(memory));return memory+128;}
fn pb_zero(memory) {return load64(memory+144);}
fn pb_word_valid(memory,word) {
    let c=load64(memory);let start=load64(c+64);let stride=load64(c)*8;
    return word>=start && word<start+load64(c+48)*stride && (word-start)%stride==0;
}
fn pb_state_valid(memory,state) {let start=load64(memory+8);return state>=start && state<start+load64(memory+16)*80 && (state-start)%80==0;}
fn pb_same(memory,a,b) {if a==b {return 1;}let i=0;while i<load64(load64(memory)) {if load64(a+i*8)!=load64(b+i*8) {return 0;}i=i+1;}return 1;}
fn pb_constant(memory,word,value) {let i=0;while i<load64(load64(memory)) {let literal= -1;if (value>>i)&1 {literal=1;}if load64(word+i*8)!=literal {return 0;}i=i+1;}return 1;}
fn pb_address_part(memory,word,offset_part) {
    let c=load64(memory);let offset=0;let meta=pw_meta(c,word);let scanning=1;
    while scanning {let kind=load64(meta);if (kind==43 || kind==45) && load64(pw_meta(c,load64(meta+16)))==1 {
        let value=load64(pw_meta(c,load64(meta+16))+8);if kind==45 {value= -value;}offset=offset+value;word=load64(meta+8);meta=pw_meta(c,word);
    }else {scanning=0;}}
    if !offset_part {return word;}if load64(c)<64 {offset=offset&((1<<load64(c))-1);}return offset;
}
fn pb_address_equal(memory,a,b) {
    let c=load64(memory);let am=pw_meta(c,a);let bm=pw_meta(c,b);
    // Addition is cancellative modulo the word width, including wrapped
    // addresses and symbolic offsets. No allocation or no-overflow premise.
    if load64(am)==43 && load64(bm)==43 {
        if pb_same(memory,load64(am+8),load64(bm+8)) {return pw_equal(c,load64(am+16),load64(bm+16));}
        if pb_same(memory,load64(am+8),load64(bm+16)) {return pw_equal(c,load64(am+16),load64(bm+8));}
        if pb_same(memory,load64(am+16),load64(bm+8)) {return pw_equal(c,load64(am+8),load64(bm+16));}
        if pb_same(memory,load64(am+16),load64(bm+16)) {return pw_equal(c,load64(am+8),load64(bm+8));}
    }
    if load64(am)==43 {if pb_same(memory,b,load64(am+8)) {return -pw_truth(c,load64(am+16));}if pb_same(memory,b,load64(am+16)) {return -pw_truth(c,load64(am+8));}}
    if load64(bm)==43 {if pb_same(memory,a,load64(bm+8)) {return -pw_truth(c,load64(bm+16));}if pb_same(memory,a,load64(bm+16)) {return -pw_truth(c,load64(bm+8));}}
    let left=a;let right=b;let lo=0;let ro=0;let meta=pw_meta(c,left);let scanning=1;
    while scanning {let kind=load64(meta);if (kind==43 || kind==45) && load64(pw_meta(c,load64(meta+16)))==1 {
        let offset=load64(pw_meta(c,load64(meta+16))+8);if kind==45 {offset= -offset;}lo=lo+offset;left=load64(meta+8);meta=pw_meta(c,left);
    }else {scanning=0;}}
    meta=pw_meta(c,right);scanning=1;while scanning {let kind=load64(meta);if (kind==43 || kind==45) && load64(pw_meta(c,load64(meta+16)))==1 {
        let offset=load64(pw_meta(c,load64(meta+16))+8);if kind==45 {offset= -offset;}ro=ro+offset;right=load64(meta+8);meta=pw_meta(c,right);
    }else {scanning=0;}}
    if load64(c)<64 {let mask=(1<<load64(c))-1;lo=lo&mask;ro=ro&mask;}
    if lo==ro {return pw_equal(c,left,right);}if pb_same(memory,left,right) {return -1;}return pw_equal(c,a,b);
}
fn pb_axiom(memory,predicate) {
    let c=load64(memory);if !pw_valid_literal(c,predicate) {pb_bad(memory);return 0;}
    store64(memory+104,pw_and(c,load64(memory+104),predicate));return !load64(c+72);
}
fn pb_valid(memory,p,n) {
    if !pb_word_valid(memory,p) || !pb_word_valid(memory,n) {pb_bad(memory);return 0;}
    let c=load64(memory);let zero=pb_zero(memory);let empty= -pw_truth(c,n);
    if empty==1 {return 1;}if pb_constant(memory,n,1) {return pw_signed_less(c,zero,p);}
    if load64(pw_meta(c,n))==1 {
        let length=load64(pw_meta(c,n)+8);let sign=1<<(load64(c)-1);let mask= -1;if load64(c)<64 {mask=(1<<load64(c))-1;}length=length&mask;
        if length&sign {return -1;}let maximum=sign-1;
        return pw_and(c,pw_signed_less(c,zero,p),-pw_unsigned_less(c,pw_constant(c,maximum-length+1),p));
    }
    let last=pw_subtract(c,pw_add(c,p,n),pw_constant(c,1));
    let positive=pw_signed_less(c,zero,p);let fits=pw_and(c,-pw_signed_less(c,last,zero),-pw_unsigned_less(c,last,p));
    return pw_and(c,-pw_signed_less(c,n,zero),pw_or(c,empty,pw_and(c,positive,fits)));
}
fn pb_member(memory,p,n,address) {
    let c=load64(memory);let valid=pb_valid(memory,p,n);if !valid || !pb_word_valid(memory,address) {pb_bad(memory);return 0;}
    if pb_same(memory,p,address) {return pw_and(c,valid,pw_truth(c,n));}
    if pb_same(memory,pb_address_part(memory,p,0),pb_address_part(memory,address,0)) {
        let offset=pb_address_part(memory,address,1)-pb_address_part(memory,p,1);
        return pw_and(c,valid,pw_unsigned_less(c,pw_constant(c,offset),n));
    }
    // For a valid nonwrapping region, (p+offset) is a member exactly when
    // the unsigned word offset is below n. The identity includes wrapped
    // and negative offsets; no signed-overflow assumption is introduced.
    let meta=pw_meta(c,address);if load64(meta)==43 {
        if pb_same(memory,p,load64(meta+8)) {return pw_and(c,valid,pw_unsigned_less(c,load64(meta+16),n));}
        if pb_same(memory,p,load64(meta+16)) {return pw_and(c,valid,pw_unsigned_less(c,load64(meta+8),n));}
    }
    if pb_constant(memory,n,1) {return pw_and(c,valid,pb_address_equal(memory,address,p));}
    // For a valid nonwrapping region, unsigned(address-p)<n is exact for all
    // word addresses. Separate constant offsets before subtraction so nested
    // forms such as (p+index)+byte cancel their common symbolic base as well.
    let base=pb_address_part(memory,address,0);let origin=pb_address_part(memory,p,0);
    let distance=pw_subtract(c,base,origin);
    let offset=pb_address_part(memory,address,1)-pb_address_part(memory,p,1);
    if offset {distance=pw_add(c,distance,pw_constant(c,offset));}
    return pw_and(c,valid,pw_unsigned_less(c,distance,n));
}
fn pb_disjoint(memory,p,n,q,m) {
    let c=load64(memory);let valid=pw_and(c,pb_valid(memory,p,n),pb_valid(memory,q,m));if !valid {return 0;}let one=pw_constant(c,1);
    if pb_constant(memory,n,1) && pb_constant(memory,m,1) {return pw_and(c,valid,-pb_address_equal(memory,p,q));}
    let plast=pw_subtract(c,pw_add(c,p,n),one);let qlast=pw_subtract(c,pw_add(c,q,m),one);
    let overlap=pw_and(c,pw_truth(c,n),pw_truth(c,m));
    overlap=pw_and(c,overlap,pw_and(c,-pw_unsigned_less(c,qlast,p),-pw_unsigned_less(c,plast,q)));
    return pw_and(c,valid,-overlap);
}
fn pb_node(memory,kind,parent,p,n,value,guard,other) {
    let c=load64(memory);let count=load64(memory+16);
    if load64(memory+112) || load64(c+72) || count>=load64(memory+24) || kind<0 || kind>9 || !pw_valid_literal(c,guard) {pb_bad(memory);return 0;}
    if kind && !pb_state_valid(memory,parent) {pb_bad(memory);return 0;}
    if kind==5 || kind==7 || kind==8 {if !pb_state_valid(memory,other) {pb_bad(memory);return 0;}}
    else if kind && (!pb_word_valid(memory,p) || !pb_word_valid(memory,n)) {pb_bad(memory);return 0;}
    if kind==1 && !pb_word_valid(memory,value) {pb_bad(memory);return 0;}
    if kind==9 && (!pb_constant(memory,p,1) || !pb_constant(memory,n,(1<<(load64(c)-1))-1)) {pb_bad(memory);return 0;}
    let node=load64(memory+8)+count*80;let i=0;while i<80 {store64(node+i,0);i=i+8;}
    store64(node,kind);store64(node+8,parent);store64(node+16,p);store64(node+24,n);store64(node+32,value);store64(node+40,guard);store64(node+56,other);
    if kind==3 || kind==9 {store64(node+48,pw_constant(c,count+1));}store64(memory+16,count+1);return node;
}
fn pb_context(words,nodes,probes,lookups,regions) {
    if !words || load64(words)<8 || load64(words+72) || nodes<1 || nodes>4096 || probes<1 || probes>4096 || lookups<1 || lookups>16384 || regions<1 || regions>1024 {return 0;}
    if load64(words)<64 && nodes>=(1<<(load64(words)-1)) {return 0;}
    let size=192+nodes*80+probes*48+lookups*48+regions*80;let p=alloc(size);if p<0 {return 0;}
    let i=0;while i<192 {store64(p+i,0);i=i+8;}
    store64(p,words);store64(p+8,p+192);store64(p+24,nodes);store64(p+32,p+192+nodes*80);store64(p+48,probes);
    store64(p+56,load64(p+32)+probes*48);store64(p+72,lookups);store64(p+80,load64(p+56)+lookups*48);store64(p+96,regions);store64(p+104,1);store64(p+120,size);
    let zero=pw_constant(words,0);store64(p+144,zero);store64(p+152,-1);store64(p+160,-1);store64(p+168,zero);
    store64(p+176,pb_node(p,0,0,zero,zero,zero,1,0));if load64(words+72) {pb_release(p);return 0;}return p;
}
fn pb_release(memory) {return syscall(11,memory,load64(memory+120),0,0,0,0);}
fn pb_byte(memory,value,fresh) {
    let c=load64(memory);let word=pw_word(c);if !word {return 0;}let i=0;
    while i<load64(c) {let literal= -1;if i<8 {if fresh {literal=pw_gate(c,0,0,0,0);}else {literal=load64(value+i*8);}}store64(word+i*8,literal);i=i+1;}return word;
}
fn pb_probe(memory,array,address,parent) {
    let c=load64(memory);let count=load64(memory+40);let table=load64(memory+32);let i=0;
    while i<count {let row=table+i*48;if load64(row)==array && pb_same(memory,load64(row+8),address) {return row;}i=i+1;}
    if count>=load64(memory+48) {return pb_bad(memory);}let row=table+count*48;let kind=load64(array);
    store64(row,array);store64(row+8,address);store64(row+16,pb_zero(memory));store64(row+24,-1);store64(row+32,-1);store64(row+40,pb_zero(memory));
    if kind==0 || kind==2 || kind==7 || kind==9 {store64(row+16,pb_byte(memory,0,1));}
    if kind==0 || kind==6 || kind==8 || kind==9 {store64(row+24,pw_gate(c,0,0,0,0));store64(row+32,pw_gate(c,0,0,0,0));
        if kind==9 {let live=pw_gate(c,0,0,0,0);store64(row+40,pw_choose(c,live,load64(array+48),pb_zero(memory)));
            pb_axiom(memory,pw_or(c,-load64(row+24),live));pb_axiom(memory,pw_or(c,-load64(row+32),load64(row+24)));
        }else if kind==6 || kind==8 {store64(row+40,pw_choose(c,pw_gate(c,0,0,0,0),load64(parent+40),pb_zero(memory)));}
        else {store64(row+40,pw_input(c));}
    }
    if load64(c+72) {return pb_bad(memory);}store64(memory+40,count+1);
    if kind==0 {
        let live=pw_truth(c,load64(row+40));let read=load64(row+24);let write=load64(row+32);let sign=load64(load64(row+40)+(load64(c)-1)*8);
        pb_axiom(memory,pw_or(c,-live,sign));pb_axiom(memory,pw_or(c,-read,live));pb_axiom(memory,pw_or(c,-write,read));
        pb_axiom(memory,pw_or(c,pw_signed_less(c,pb_zero(memory),address),pw_and(c,-live,pw_and(c,-read,-write))));
    }
    i=0;while i<count {let previous=table+i*48;if load64(previous)==array {
        let same=pb_address_equal(memory,address,load64(previous+8));
        // A definitely distinct address needs no congruence constraint. Avoid
        // building unused byte/identity equalities before simplifying false
        // implies equality; large contiguous reads otherwise exhaust gates.
        if same!= -1 {let equal=pw_equal(c,load64(row+16),load64(previous+16));
            equal=pw_and(c,equal,-pw_xor(c,load64(row+24),load64(previous+24)));equal=pw_and(c,equal,-pw_xor(c,load64(row+32),load64(previous+32)));
            equal=pw_and(c,equal,pw_equal(c,load64(row+40),load64(previous+40)));pb_axiom(memory,pw_or(c,-same,equal));
        }
    }i=i+1;}return row;
}
fn pb_lookup(memory,state,address,depth) {
    let c=load64(memory);if load64(memory+112) || load64(c+72) || depth>256 || !pb_state_valid(memory,state) || !pb_word_valid(memory,address) {return pb_bad(memory);}
    let i=0;while i<load64(memory+64) {let cached=load64(memory+56)+i*48;if load64(cached)==state && pb_same(memory,load64(cached+8),address) {return cached;}i=i+1;}
    let kind=load64(state);let parent=0;let other=0;let condition=load64(state+40);
    if !kind {parent=pb_probe(memory,state,address,0);}
    else {
        parent=pb_lookup(memory,load64(state+8),address,depth+1);
        if kind==5 {other=pb_lookup(memory,load64(state+56),address,depth+1);}
        else {
            if kind==7 || kind==8 {let entry=pb_lookup(memory,load64(state+56),address,depth+1);
                condition=pw_and(c,condition,pw_and(c,pw_truth(c,load64(parent+40)),-pw_equal(c,load64(parent+40),load64(entry+40))));
            }else if kind==9 {condition=pw_and(c,condition,pw_signed_less(c,pb_zero(memory),address));}
            else {condition=pw_and(c,condition,pb_member(memory,load64(state+16),load64(state+24),address));}
            if kind==9 {condition=pw_and(c,condition,-pw_truth(c,load64(parent+40)));}
            if (kind==2 || kind==6 || kind==7 || kind==8 || kind==9) && condition!= -1 {other=pb_probe(memory,state,address,parent);}
        }
    }
    let count=load64(memory+64);if load64(memory+112) || load64(c+72) || count>=load64(memory+72) {return pb_bad(memory);}
    let row=load64(memory+56)+count*48;let offset=0;while offset<48 {store64(row+offset,load64(parent+offset));offset=offset+8;}store64(row,state);store64(row+8,address);store64(memory+64,count+1);
    if kind==1 {store64(row+16,pw_choose(c,condition,load64(state+32),load64(parent+16)));}
    else if (kind==2 || kind==7) && other {store64(row+16,pw_choose(c,condition,load64(other+16),load64(parent+16)));}
    else if kind==3 {
        store64(row+16,pw_choose(c,condition,pb_zero(memory),load64(parent+16)));store64(row+24,pw_or(c,condition,load64(parent+24)));store64(row+32,pw_or(c,condition,load64(parent+32)));
        store64(row+40,pw_choose(c,condition,load64(state+48),load64(parent+40)));
    }else if kind==4 {
        store64(row+24,pw_and(c,-condition,load64(parent+24)));store64(row+32,pw_and(c,-condition,load64(parent+32)));store64(row+40,pw_choose(c,condition,pb_zero(memory),load64(parent+40)));
    }else if kind==5 || ((kind==6 || kind==8 || kind==9) && other) {
        if kind==6 || kind==8 {
            let r=load64(other+24);let w=load64(other+32);let id=load64(other+40);
            let permitted=pw_and(c,pw_or(c,-r,load64(parent+24)),pw_or(c,-w,load64(parent+32)));
            permitted=pw_and(c,permitted,pw_and(c,pw_or(c,-w,r),pw_or(c,-r,pw_truth(c,id))));
            // Probe construction already chooses exactly parent identity or
            // zero; no search over an arbitrary 64-bit identity is needed.
            pb_axiom(memory,pw_or(c,-condition,permitted));
        }
        if kind==5 {store64(row+16,pw_choose(c,condition,load64(parent+16),load64(other+16)));store64(row+24,pw_select(c,condition,load64(parent+24),load64(other+24)));store64(row+32,pw_select(c,condition,load64(parent+32),load64(other+32)));store64(row+40,pw_choose(c,condition,load64(parent+40),load64(other+40)));}
        else {if kind==9 {store64(row+16,pw_choose(c,condition,load64(other+16),load64(parent+16)));}
            store64(row+24,pw_select(c,condition,load64(other+24),load64(parent+24)));store64(row+32,pw_select(c,condition,load64(other+32),load64(parent+32)));store64(row+40,pw_choose(c,condition,load64(other+40),load64(parent+40)));}
    }
    if load64(c+72) {return pb_bad(memory);}return row;
}
// Range mode: 0 = readable, 1 = writable, otherwise an entry snapshot whose
// same-address identities must differ from the current nonzero identities.
fn pb_access(memory,state,address,mode) {
    let c=load64(memory);let cell=pb_lookup(memory,state,address,0);
    if mode==0 {return load64(cell+24);}if mode==1 {return load64(cell+32);}
    let entry=pb_lookup(memory,mode,address,0);
    // Allocation closure preserves every live parent identity. Relative to
    // that parent (or a content-only version), freshness is exactly a new live
    // byte. Avoid a 64-bit identity disequality for this common summary case.
    if load64(state)==9 && pb_permission_base(load64(state+8))==pb_permission_base(mode) {
        return pw_and(c,pw_truth(c,load64(cell+40)),-pw_truth(c,load64(entry+40)));
    }
    return pw_and(c,pw_truth(c,load64(cell+40)),-pw_equal(c,load64(cell+40),load64(entry+40)));
}
fn pb_permission(memory,state,p,n,write) {if write!=0 && write!=1 {pb_bad(memory);return 0;}return pb_predicate(memory,state,p,n,write);}
fn pb_fresh(memory,state,entry,p,n) {if !pb_state_valid(memory,entry) {pb_bad(memory);return 0;}return pb_predicate(memory,state,p,n,entry);}
fn pb_predicate(memory,state,p,n,write) {
    if !pb_state_valid(memory,state) {pb_bad(memory);return 0;}let c=load64(memory);let valid=pb_valid(memory,p,n);if !valid {return 0;}let count=load64(memory+88);let i=0;
    if valid== -1 {return -1;}if pb_constant(memory,n,0) {return 1;}
    if pb_constant(memory,n,1) {return pw_and(c,valid,pb_access(memory,state,p,write));}
    while i<count {let row=load64(memory+80)+i*80;if load64(row)==state && load64(row+24)==write && pb_same(memory,load64(row+8),p) && pb_same(memory,load64(row+16),n) {return load64(row+32);}i=i+1;}
    if count>=load64(memory+96) {pb_bad(memory);return 0;}let row=load64(memory+80)+count*80;let empty= -pw_truth(c,n);let predicate=pw_and(c,valid,pw_or(c,empty,pw_gate(c,0,0,0,0)));
    store64(row,state);store64(row+8,p);store64(row+16,n);store64(row+24,write);store64(row+32,predicate);store64(row+40,pw_input(c));store64(row+48,0);store64(row+56,0);store64(row+64,valid);store64(row+72,empty);store64(memory+88,count+1);
    // A nonempty positive range must have a representative even when no load
    // observes it. Transition intersections below cover changes inside it.
    pb_lookup(memory,state,p,0);
    pb_lookup(memory,state,pw_add(c,p,n),0);
    let witness=load64(row+40);let access=pb_access(memory,state,witness,write);
    let failed=pw_and(c,valid,pw_and(c,-empty,-predicate));pb_axiom(memory,pw_or(c,-failed,pw_and(c,pb_member(memory,p,n,witness),-access)));return predicate;
}
fn pb_permission_base(state) {let count=0;while (load64(state)==1 || load64(state)==2 || load64(state)==7) && count<256 {state=load64(state+8);count=count+1;}return state;}
fn pb_constraints(memory) {
    let c=load64(memory);let changed=1;
    while changed && !load64(memory+112) && !load64(c+72) {
        let before=load64(memory+64);let boundary=0;
        // Membership changes only at interval boundaries. Register starts and
        // one-past ends as well as negative witnesses; a partial release must
        // not hide live bytes later in a requested allocation or permission range.
        while boundary<load64(memory+16) && !load64(memory+112) && !load64(c+72) {let node=load64(memory+8)+boundary*80;let kind=load64(node);
            if (kind==3 || kind==4 || kind==6) && !load64(node+72) {store64(node+72,1);
                if load64(node+40)!= -1 {pb_lookup(memory,load64(node+8),load64(node+16),0);pb_lookup(memory,load64(node+8),pw_add(c,load64(node+16),load64(node+24)),0);}
            }boundary=boundary+1;
        }
        let r=0;
        while r<load64(memory+88) && !load64(memory+112) && !load64(c+72) {let region=load64(memory+80)+r*80;let k=load64(region+56);
            while k<load64(memory+16) && !load64(memory+112) && !load64(c+72) {let node=load64(memory+8)+k*80;
                if load64(node)==3 && pb_permission_base(load64(region))==pb_permission_base(load64(node+8)) {
                    let active=pw_and(c,load64(region+32),load64(node+40));pb_axiom(memory,pw_or(c,-active,pb_disjoint(memory,load64(region+8),load64(region+16),load64(node+16),load64(node+24))));
                }k=k+1;
            }store64(region+56,k);let i=load64(region+48);
            while i<load64(memory+64) && !load64(memory+112) && !load64(c+72) {let address=load64(load64(memory+56)+i*48+8);let access=pb_access(memory,load64(region),address,load64(region+24));
                let inside=pw_and(c,load64(region+32),pb_member(memory,load64(region+8),load64(region+16),address));pb_axiom(memory,pw_or(c,-inside,access));i=i+1;
            }store64(region+48,i);r=r+1;
        }
        let k=0;while k<load64(memory+16) && !load64(memory+112) && !load64(c+72) {let node=load64(memory+8)+k*80;
            if load64(node)==3 {let i=load64(node+64);
                while i<load64(memory+64) && !load64(memory+112) && !load64(c+72) {let address=load64(load64(memory+56)+i*48+8);let cell=pb_lookup(memory,load64(node+8),address,0);
                    let inside=pw_and(c,load64(node+40),pb_member(memory,load64(node+16),load64(node+24),address));pb_axiom(memory,pw_or(c,-inside,-pw_truth(c,load64(cell+40))));i=i+1;
                }store64(node+64,i);
            }k=k+1;
        }changed=before!=load64(memory+64);
    }
    if load64(memory+112) || load64(c+72) {return 0;}return load64(memory+104);
}
fn pb_load(memory,state,address,bytes,out) {
    let c=load64(memory);store64(out,0);store64(out+8,0);
    if bytes!=1 && bytes!=load64(c)/8 {pb_bad(memory);return 0;}let safe=pb_valid(memory,address,pw_constant(c,bytes));if !safe {return 0;}let result=pw_word(c);if !result {pb_bad(memory);return 0;}
    let i=0;while i<load64(c) {store64(result+i*8,-1);i=i+1;}i=0;
    while i<bytes {let at=pw_add(c,address,pw_constant(c,i));let cell=pb_lookup(memory,state,at,0);safe=pw_and(c,safe,load64(cell+24));let bit=0;
        while bit<8 {store64(result+(i*8+bit)*8,load64(load64(cell+16)+bit*8));bit=bit+1;}i=i+1;
    }store64(out,result);store64(out+8,safe);return !load64(memory+112) && !load64(c+72);
}
fn pb_store(memory,state,address,value,bytes,guard,out) {
    let c=load64(memory);store64(out,0);store64(out+8,0);
    if (bytes!=1 && bytes!=load64(c)/8) || !pb_word_valid(memory,value) {pb_bad(memory);return 0;}
    let safe=pb_valid(memory,address,pw_constant(c,bytes));if !safe {return 0;}let current=state;let i=0;
    while i<bytes {let at=pw_add(c,address,pw_constant(c,i));let cell=pb_lookup(memory,state,at,0);safe=pw_and(c,safe,load64(cell+32));let byte=pw_word(c);if !byte {pb_bad(memory);return 0;}let bit=0;
        while bit<load64(c) {let literal= -1;if bit<8 {literal=load64(value+(i*8+bit)*8);}store64(byte+bit*8,literal);bit=bit+1;}
        current=pb_node(memory,1,current,at,pw_constant(c,1),byte,guard,0);i=i+1;
    }store64(out,current);store64(out+8,safe);return !load64(memory+112) && !load64(c+72);
}
fn pb_havoc(memory,state,p,n,guard) {return pb_node(memory,2,state,p,n,0,guard,0);}
fn pb_free(memory,state,p,n,guard) {return pb_node(memory,4,state,p,n,0,guard,0);}
fn pb_revoke(memory,state,p,n,guard) {return pb_node(memory,6,state,p,n,0,guard,0);}
fn pb_fresh_havoc(memory,state,entry,guard) {return pb_node(memory,7,state,0,0,0,guard,entry);}
fn pb_fresh_revoke(memory,state,entry,guard) {return pb_node(memory,8,state,0,0,0,guard,entry);}
fn pb_grow(memory,state,guard) {let c=load64(memory);return pb_node(memory,9,state,pw_constant(c,1),pw_constant(c,(1<<(load64(c)-1))-1),0,guard,0);}
fn pb_join(memory,condition,yes,no) {
    if !pb_state_valid(memory,yes) || !pb_state_valid(memory,no) || !pw_valid_literal(load64(memory),condition) {pb_bad(memory);return 0;}
    if condition==1 || yes==no {return yes;}if condition== -1 {return no;}return pb_node(memory,5,yes,0,0,0,condition,no);
}
fn pb_alloc(memory,state,n,guard,out) {
    let c=load64(memory);store64(out,0);store64(out+8,0);if !pb_word_valid(memory,n) || !pw_valid_literal(c,guard) {pb_bad(memory);return 0;}
    let result=pw_input(c);if !result {pb_bad(memory);return 0;}let positive=pw_signed_less(c,pb_zero(memory),result);let failed=pw_signed_less(c,result,pb_zero(memory));
    let valid=pw_and(c,pw_signed_less(c,pb_zero(memory),n),pb_valid(memory,result,n));pb_axiom(memory,pw_or(c,-guard,pw_or(c,failed,pw_and(c,positive,valid))));
    let next=pb_node(memory,3,state,result,n,0,pw_and(c,guard,positive),0);store64(out,result);store64(out+8,next);return !load64(memory+112) && !load64(c+72);
}
