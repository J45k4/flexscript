// Finite, exact instantiation of signed half-open ranges. Capacity is checked
// against the current path, never assumed to be a property of the source.
global pq_names=0;
global pq_depth=0;
global vq_values=0;
global vq_instances=0;
global rq_values=0;
fn pq_binding(name,size) {
    let i=pq_depth;while i>0 {i=i-1;let p=pq_names+i*16;if equal(name,size,load64(p),load64(p+8)) {return i;}}return -1;
}
fn pq_parse(kind,site) {
    if !pq_names {pq_names=alloc(128*16);if pq_names<0 {fail("cannot allocate quantifier scope");}}
    if pq_depth>=128 {fail("quantifier scope depth exceeded");}
    if token!=256 || is("result") || is("old") || reserved(source+token_start,token_size) {fail("expected quantifier bound name");}
    let name=source+token_start;let size=token_size;next();if !is("in") {fail("expected in after quantifier name");}next();
    let start=pf_expression(1);expect(46);expect(46);let end=pf_expression(1);expect(58);
    let slot=pq_depth;store64(pq_names+slot*16,name);store64(pq_names+slot*16+8,size);pq_depth=pq_depth+1;
    let condition=pf_expression(1);pq_depth=pq_depth-1;let node=pf_node(kind,start,end,condition,site);store64(node+56,slot);return node;
}
fn vq_eval(state,node,entry) {
    if !vq_values {vq_values=alloc(128*8);if vq_values<0 {fail("cannot allocate symbolic quantifier bindings");}}
    let start=vf_eval(state,load64(node+8),entry);let end=vf_eval(state,load64(node+16),entry);
    if vf_problem || load64(vf_context+72) {return vf_zero;}
    let path=load64(state+24);let nonempty=pw_signed_less(vf_context,start,end);let count=pw_subtract(vf_context,end,start);
    let within=pw_or(vf_context,-nonempty,-pw_unsigned_less(vf_context,pw_constant(vf_context,64),count));
    if within!=1 && path!= -1 {
        let checked=vf_query(pw_and(vf_context,path,-within));vf_query_release();
        if checked!=2 {return vf_unproved(node,"quantifier range could not be proved to contain at most 64 values");}
    }
    let all=load64(node)==21;let answer= -1;if all {answer=1;}let i=0;let slot=load64(node+56);let assumptions=path;
    while i<64 && nonempty!= -1 && !vf_problem && !load64(vf_context+72) {
        let offset=pw_constant(vf_context,i);let candidate=pw_add(vf_context,start,offset);
        let member=pw_and(vf_context,nonempty,pw_unsigned_less(vf_context,offset,count));
        // Signed membership also excludes wrapping candidates explicitly. The
        // checked cardinality bound guarantees these instances cover the range.
        member=pw_and(vf_context,member,pw_and(vf_context,-pw_signed_less(vf_context,candidate,start),pw_signed_less(vf_context,candidate,end)));
        store64(state+24,pw_and(vf_context,path,member));
        if load64(state+24)!= -1 {
            if vq_instances>=4096 {vf_unproved(node,"quantifier instantiation capacity exceeded");}
            else {vq_instances=vq_instances+1;store64(vq_values+slot*8,candidate);
                let value=pw_truth(vf_context,vf_eval(state,load64(node+24),entry));
                if pm_assuming {assumptions=pw_and(vf_context,assumptions,pw_or(vf_context,-member,load64(state+24)));}
                if all {answer=pw_and(vf_context,answer,pw_or(vf_context,-member,value));}
                else {answer=pw_or(vf_context,answer,pw_and(vf_context,member,value));}
            }
        }i=i+1;
    }
    store64(state+24,assumptions);return pw_boolean(vf_context,answer);
}
fn rq_eval(state,node,entry) {
    if !rq_values {rq_values=alloc(128*8);if rq_values<0 {vr_stopped=1;return 0;}}
    let start=vr_eval(state,load64(node+8),entry);let end=vr_eval(state,load64(node+16),entry);let count=0;
    if start<end {count=end-start;if count<0 || count>64 {vr_stopped=1;return 0;}}
    let all=load64(node)==21;let answer=all;let i=0;let slot=load64(node+56);
    // Both quantifiers require every member's predicate to be well-defined.
    while i<count && !vr_stopped {store64(rq_values+slot*8,start+i);let value=vr_eval(state,load64(node+24),entry)!=0;
        if all {answer=answer && value;}else {answer=answer || value;}i=i+1;
    }return answer;
}
