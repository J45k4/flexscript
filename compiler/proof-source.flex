import "proof-quantifier.flex";
import "proof-functions.flex";
import "proof-trusted.flex";
import "proof-memory.flex";
// Contracts share the compiler's lexer and operator precedence. Source copies
// retain annotation text and locations while erasure preserves byte offsets.
global pf_ready=0;
global pf_verifying=0;
global pf_functions=0;
global pf_count=0;
global pf_globals=0;
global pf_gcount=0;
global pf_copies=0;
global pf_nodes=0;
global pf_used=0;
global pf_spans=0;
global pf_span_count=0;
global pf_module=0;
global pf_current=0;
global pf_locals=0;
global pf_lcount=0;
global pf_slots=0;
global pf_depth=0;
global pf_phase=0;
global pf_old_depth=0;
global pf_expr_depth=0;
global pf_lowerings=0;
global pf_ghost_slots=0;
global pf_proof_depth=0;
global pf_has_helpers=0;
// Node: kind,a,b,c,byte offset,module,next,extra. Function: name,size,module,
// fn offset,body offset,end,parameters,arity,contracts,flags,body AST,slots,
// read frame (96), assertion marker (104), write frame (112), frame flags (120).
fn pf_node(kind,a,b,c,site) {
    if pf_used>=131072 {fail("proof syntax capacity exceeded");}let p=pf_nodes+pf_used*64;pf_used=pf_used+1;
    store64(p,kind);store64(p+8,a);store64(p+16,b);store64(p+24,c);store64(p+32,site);store64(p+40,pf_module);store64(p+48,0);store64(p+56,0);return p;
}
fn pf_span(start,end) {
    if pf_span_count>=16384 {fail("too many verifier annotations");}let p=pf_spans+pf_span_count*24;pf_span_count=pf_span_count+1;
    store64(p,pf_module);store64(p+8,start);store64(p+16,end);return 0;
}
fn pf_select(module) {select_module(module);source=load64(pf_copies+module*8);pf_module=module;return 0;}
fn pf_name(name,size,text) {return equal(name,size,text,length(text));}
fn pf_function(name,size) {let i=0;while i<pf_count {let f=pf_functions+i*128;if equal(name,size,load64(f),load64(f+8)) {return f;}i=i+1;}return 0;}
fn pf_global(name,size) {let i=0;while i<pf_gcount {let g=pf_globals+i*32;if equal(name,size,load64(g),load64(g+8)) {return i;}i=i+1;}return -1;}
fn pf_proof_keyword(text) {
    if !is(text) {return 0;}let name=source+token_start;let size=token_size;
    if pf_function(name,size) || pf_global(name,size)>=0 {return 0;}
    let i=0;while i<pf_lcount {let local=pf_locals+i*32;if equal(name,size,load64(local),load64(local+8)) {return 0;}i=i+1;}return 1;
}
fn pf_binding(name,size) {
    let i=pf_lcount;while i>0 {i=i-1;let p=pf_locals+i*32;if equal(name,size,load64(p),load64(p+8)) {
        let slot=load64(p+16);if !pf_phase && load64(pf_ghost_slots+slot*8) {fail("ghost values cannot be used in executable expressions");}return slot;
    }}
    let g=pf_global(name,size);if g>=0 {return -2-g;}fail("undefined name in verifier expression");return -1;
}
fn pf_local(name,size) {
    if reserved(name,size) || pf_lcount>=4096 || pf_slots>=4096 {fail("invalid verifier local declaration");}
    let i=pf_lcount;while i>0 {i=i-1;let p=pf_locals+i*32;if load64(p+24)==pf_depth && equal(name,size,load64(p),load64(p+8)) {fail("duplicate local");}}
    let p=pf_locals+pf_lcount*32;store64(p,name);store64(p+8,size);store64(p+16,pf_slots);store64(p+24,pf_depth);
    store64(pf_ghost_slots+pf_slots*8,pf_proof_depth!=0);
    pf_lcount=pf_lcount+1;pf_slots=pf_slots+1;return pf_slots-1;
}
fn pf_primary() {
    let site=token_start;let node=0;
    if token==257 {node=pf_node(1,token_value,0,0,site);next();}
    else if token==258 {node=pf_node(8,0,0,0,site);next();}
    else if token==40 {next();node=pf_expression(1);expect(41);}
    else if token==45 || token==33 || token==126 {let op=token;next();node=pf_node(4,op,pf_expression(11),0,site);}
    else if token==256 {
        let name=source+token_start;let size=token_size;next();
        if pf_phase && token==256 && (pf_name(name,size,"forall") || pf_name(name,size,"exists")) {
            let kind=21;if pf_name(name,size,"exists") {kind=22;}node=pq_parse(kind,site);
        }else if pf_phase && pq_binding(name,size)>=0 {node=pf_node(23,pq_binding(name,size),0,0,site);}
        else if pf_phase==2 && pf_name(name,size,"result") {
            if pf_old_depth {fail("result is not available in old expressions");}node=pf_node(5,0,0,0,site);
        }else if token==40 && pf_name(name,size,"old") && pf_phase {
            if pf_phase!=2 || pf_old_depth {fail("old is allowed only once in a postcondition expression");}
            next();pf_old_depth=1;node=pf_node(6,pf_expression(1),0,0,site);pf_old_depth=0;expect(41);
        }else if token==40 {
            let call_kind=7;if pf_phase {call_kind=24;if pf_phase==1 || pf_phase==2 {call_kind=26;}}
            next();let head=0;let tail=0;let count=0;
            if token!=41 {let more=1;while more {let argument=pf_expression(1);if tail {store64(tail+48,argument);}else {head=argument;}tail=argument;count=count+1;
                if token==44 {next();}else {more=0;}
            }}expect(41);node=pf_node(call_kind,name,size,head,site);store64(node+56,count);
        }else {let binding= -1;if !pf_phase || pf_phase==3 {binding=pf_binding(name,size);}node=pf_node(2,name,size,binding,site);}
    }else {fail("expected verifier expression");}return node;
}
fn pf_expression(minimum) {
    pf_expr_depth=pf_expr_depth+1;if pf_expr_depth>128 {fail("verifier expression nesting limit exceeded");}
    let left=pf_primary();let priority=precedence(token);
    while priority>=minimum && priority {let op=token;let site=token_start;next();let right=pf_expression(priority+1);left=pf_node(3,op,left,right,site);priority=precedence(token);}
    pf_expr_depth=pf_expr_depth-1;return left;
}
fn pf_loop() {
    let head=0;let tail=0;let measure=0;
    while pf_proof_keyword("invariant") || pf_proof_keyword("decreases") {
        let site=token_start;let kind=19;if is("decreases") {kind=20;if measure {fail("duplicate loop decreases clause");}measure=1;}
        next();pf_phase=3;let first=pf_expression(1);let last=first;let count=1;
        if kind==20 {while token==44 {if count>=16 {fail("too many decreases tuple components");}next();let part=pf_expression(1);store64(last+48,part);last=part;count=count+1;}}
        pf_phase=0;if pf_proof_depth {pf_phase=3;}if token!=59 {fail("expected ';' after loop annotation");}pf_span(site,pos);next();let clause=pf_node(kind,first,0,0,site);
        if tail {store64(tail+48,clause);}else {head=clause;}tail=clause;store64(pf_current+72,load64(pf_current+72)|4);
    }
    if !is("while") {fail("loop annotation must attach to the next while");}
    let site=token_start;let visible=pf_slots;if pf_proof_depth {visible=visible|65536;}next();let condition=pf_expression(1);let body=pf_block();let loop=pf_node(15,condition,body,head,site);store64(loop+56,visible);return loop;
}
// Local declaration names are kept for abstract loop-head diagnostics.
fn pf_slot_node(node,slot) {
    if !node {return 0;}let kind=load64(node);if kind==11 && load64(node+8)==slot {return node;}
    if kind==16 {let child=load64(node+8);while child {let result=pf_slot_node(child,slot);if result {return result;}child=load64(child+48);}}
    if kind==14 {let result=pf_slot_node(load64(node+16),slot);if result {return result;}return pf_slot_node(load64(node+24),slot);}
    if kind==15 {return pf_slot_node(load64(node+16),slot);}return 0;
}
fn pf_statement() {
    let site=token_start;let node=0;pf_phase=0;if pf_proof_depth {pf_phase=3;}
    if pf_proof_keyword("ghost") {
        next();if !is("let") {fail("ghost must introduce a let declaration");}let saved=pf_proof_depth;pf_proof_depth=pf_proof_depth+1;
        node=pf_statement();pf_proof_depth=saved;pf_span(site,token_start);store64(pf_current+72,load64(pf_current+72)|8);
    }else if pf_proof_keyword("proof") {
        next();pf_proof_depth=pf_proof_depth+1;node=pf_block();pf_proof_depth=pf_proof_depth-1;
        pf_span(site,token_start);store64(pf_current+72,load64(pf_current+72)|8);
    }else if is("let") {next();if token!=256 {fail("expected local name");}let name=source+token_start;let size=token_size;next();expect(61);let value=pf_expression(1);expect(59);
        node=pf_node(11,pf_local(name,size),value,name,site);store64(node+56,size);
    }else if is("return") {if pf_proof_depth && (!ph_kind(pf_current) || pf_proof_depth>1) {fail("proof code cannot return from an executable function");}
        next();let value=pf_expression(1);if ph_kind(pf_current)==4 && (load64(value)!=1 || load64(value+8)!=0) {fail("lemma returns must be literal zero");}
        node=pf_node(13,value,0,0,site);expect(59);}
    else if is("if") {next();let condition=pf_expression(1);let yes=pf_block();let no=0;if is("else") {next();if is("if") {no=pf_statement();}else {no=pf_block();}}node=pf_node(14,condition,yes,no,site);}
    else if is("while") || pf_proof_keyword("invariant") || pf_proof_keyword("decreases") {node=pf_loop();}
    else if token==123 {node=pf_block();}
    else if pf_proof_keyword("assert") {
        next();pf_phase=3;let condition=pf_expression(1);pf_phase=0;if pf_proof_depth {pf_phase=3;}if token!=59 {fail("expected ';' after verifier assertion");}
        pf_span(site,pos);next();node=pf_node(18,condition,0,0,site);store64(pf_current+72,load64(pf_current+72)|2);
    }else {
        if token==256 {let name=source+token_start;let size=token_size;next();if token==61 {let slot=pf_binding(name,size);
            if pf_proof_depth && (slot<0 || !load64(pf_ghost_slots+slot*8)) {fail("proof code can assign only ghost variables");}
            next();node=pf_node(12,slot,pf_expression(1),0,site);expect(59);}}
        if !node {pos=site;next();let expression=pf_expression(1);if pf_proof_depth && load64(expression)==24 {store64(expression,25);}node=pf_node(17,expression,0,0,site);expect(59);}
    }pf_phase=0;if pf_proof_depth {pf_phase=3;}return node;
}
fn pf_block() {
    let site=token_start;expect(123);pf_depth=pf_depth+1;if pf_depth>128 {fail("verifier block nesting limit exceeded");}
    let saved=pf_lcount;let head=0;let tail=0;while token!=125 {if !token {fail("unterminated verifier block");}let statement=pf_statement();
        if tail {store64(tail+48,statement);}else {head=statement;}tail=statement;
    }expect(125);pf_lcount=saved;pf_depth=pf_depth-1;return pf_node(16,head,0,0,site);
}
fn pf_body(f) {
    if load64(f+80) {return load64(f+80);}pf_current=f;pf_select(load64(f+16));pos=load64(f+32);next();pf_phase=0;pf_proof_depth=0;if ph_kind(f) {pf_proof_depth=1;pf_phase=3;}
    pf_lcount=0;pf_slots=0;pf_depth=1;let i=0;while i<load64(f+56) {let p=load64(f+48)+i*32;pf_local(load64(p),load64(p+8));i=i+1;}
    pf_depth=0;let body=pf_block();store64(f+80,body);store64(f+88,pf_slots);return body;
}
fn pf_resolve_spec(node,f) {
    if !node {return 0;}let kind=load64(node);
    if kind==2 {let name=load64(node+8);let size=load64(node+16);let i=0;let binding= -1;
        while i<load64(f+56) {let p=load64(f+48)+i*32;if equal(name,size,load64(p),load64(p+8)) {binding=i;}i=i+1;}
        if binding<0 {let g=pf_global(name,size);if g>=0 {binding= -2-g;}}
        if binding== -1 {pf_select(load64(node+40));token_start=load64(node+32);fail("undefined contract name; only parameters and globals are in scope");}store64(node+24,binding);
    }else if kind==24 || kind==26 {let argument=load64(node+24);while argument {pf_resolve_spec(argument,f);argument=load64(argument+48);}}
    else if kind==5 && ph_kind(f)==4 {ph_error(node,"lemma postconditions cannot use result");}
    else if kind==21 || kind==22 {pf_resolve_spec(load64(node+8),f);pf_resolve_spec(load64(node+16),f);pf_resolve_spec(load64(node+24),f);}
    else if kind==3 {pf_resolve_spec(load64(node+16),f);pf_resolve_spec(load64(node+24),f);}
    else if kind==4 {pf_resolve_spec(load64(node+16),f);}else if kind==6 {pf_resolve_spec(load64(node+8),f);}
    else if kind==8 {fail("strings are not supported in verifier expressions");}return 0;
}
fn pf_frame() {
    if is("nothing") {next();return 0;}
    let head=0;let tail=0;let more=1;
    while more {
        if token!=256 || is("nothing") {fail("expected global name in effect frame");}
        let node=pf_node(9,source+token_start,token_size,-1,token_start);next();
        if token==40 {
            if !pf_name(load64(node+8),load64(node+16),"bytes") {fail("expected bytes(pointer,length) in memory frame");}
            next();pf_phase=1;let pointer=pf_expression(1);expect(44);let count=pf_expression(1);expect(41);pf_phase=0;
            store64(node,10);store64(node+8,pointer);store64(node+16,count);store64(node+24,0);
        }
        if tail {store64(tail+48,node);}else {head=node;}tail=node;
        if token==44 {next();}else {more=0;}
    }return head;
}
fn pf_resolve_frame(clause,f) {
    let kind=load64(clause);let offset=96;let empty_bit=1;let full_bit=2;
    if kind==5 {offset=112;empty_bit=4;full_bit=8;}
    if kind==9 {empty_bit=16;full_bit=32;}
    let flags=load64(f+120);let item=load64(clause+8);
    if (!item && (flags&full_bit)) || (item && (flags&empty_bit)) {
        pf_select(load64(clause+40));token_start=load64(clause+32);fail("nothing cannot be mixed with nonempty effect locations");
    }
    if item {flags=flags|full_bit;}else {flags=flags|empty_bit;}store64(f+120,flags);
    let frame=load64(f+offset);if kind==9 {frame=0;}
    if !frame && kind!=9 {frame=alloc((pf_gcount+1)*8);if frame<0 {fail("cannot allocate effect frame");}
        let i=0;while i<=pf_gcount {store64(frame+i*8,0);i=i+1;}store64(f+offset,frame);
    }
    while item {if load64(item)==10 {pf_resolve_spec(load64(item+8),f);pf_resolve_spec(load64(item+16),f);}
        else {if kind==9 {ph_error(item,"release frames require bytes(pointer,length) regions");}let g=pf_global(load64(item+8),load64(item+16));
        if g<0 {pf_select(load64(item+40));token_start=load64(item+32);fail("effect locations must name declared globals");}
        store64(item+24,g);store64(frame+g*8,1);}item=load64(item+48);
    }return 0;
}
fn pf_scan() {
    let head=0;let tail=0;let flags=0;let seen_function=0;let definition_kind=0;let definition_start=0;
    while token {
        let site=token_start;
        if is("requires") || is("ensures") || is("verify") || is("reads") || is("modifies") || is("releases") || is("decreases") || is("trusted") || is("terminates") {
            let kind=1;if is("ensures") {kind=2;}if is("verify") {kind=3;if flags&1 {fail("duplicate verify marker");}flags=flags|1;}
            if is("reads") {kind=4;}if is("modifies") {kind=5;}if is("decreases") {kind=6;if flags&2 {fail("duplicate function decreases clause");}flags=flags|2;}
            if is("trusted") {kind=7;if flags&4 {fail("duplicate trusted marker");}flags=flags|4;}
            if is("terminates") {kind=8;if flags&8 {fail("duplicate terminates marker");}flags=flags|8;}
            if is("releases") {kind=9;}
            next();let expression=0;if kind<3 {pf_phase=kind;expression=pf_expression(1);pf_phase=0;}else if kind==4 || kind==5 || kind==9 {expression=pf_frame();}
            else if kind==6 {pf_phase=1;expression=pf_expression(1);let last=expression;let count=1;
                while token==44 {if count>=16 {fail("too many decreases tuple components");}next();let part=pf_expression(1);store64(last+48,part);last=part;count=count+1;}pf_phase=0;
            }
            if token!=59 {fail("expected ';' after function contract");}pf_span(site,pos);next();let clause=pf_node(kind,expression,0,0,site);
            if tail {store64(tail+48,clause);}else {head=clause;}tail=clause;
        }else if is("spec") || is("lemma") {definition_kind=2;if is("lemma") {definition_kind=4;}definition_start=site;next();if !is("fn") {fail("spec or lemma must directly precede fn");}pf_has_helpers=1;}
        else if is("fn") {
            if pf_count>=2048 {fail("too many verifier functions");}next();if token!=256 {fail("expected function name");}
            let f=pf_functions+pf_count*128;let clear=0;while clear<128 {store64(f+clear,0);clear=clear+8;}
            let name=source+token_start;let size=token_size;if reserved(name,size) || pf_function(name,size) || pf_global(name,size)>=0 {fail("invalid or duplicate function");}
            store64(f,name);store64(f+8,size);store64(f+16,pf_module);store64(f+24,site);store64(f+64,head);
            let function_flags=definition_kind;if flags&4 {function_flags=function_flags|8;}if flags&8 {function_flags=function_flags|16;}
            store64(f+104,function_flags);if head || definition_kind {store64(f+72,1);}pf_count=pf_count+1;head=0;tail=0;flags=0;seen_function=1;
            next();expect(40);pf_lcount=0;pf_slots=0;pf_depth=1;pf_proof_depth=0;
            if token!=41 {let more=1;while more {if token!=256 {fail("expected parameter name");}
                if load64(f+64) && (is("result") || is("old")) {fail("contract parameters cannot be named result or old");}
                pf_local(source+token_start,token_size);next();if token==44 {next();}else {more=0;}
            }}expect(41);let params=alloc(pf_lcount*32+8);if params<0 {fail("cannot allocate verifier parameters");}net_copy(params,pf_locals,pf_lcount*32);
            store64(f+48,params);store64(f+56,pf_lcount);store64(f+32,token_start);expect(123);let braces=1;
            while braces {if !token {fail("unterminated function");}if is("assert") || is("invariant") || is("decreases") || is("ghost") || is("proof") {store64(f+104,load64(f+104)|1);}if token==123 {braces=braces+1;}if token==125 {braces=braces-1;}
                if !braces {store64(f+40,pos);}next();
            }
            if definition_kind {pf_span(definition_start,load64(f+40));definition_kind=0;}
        }else {
            if head {fail("function contract must attach to the next function in this file");}
            if is("global") {
                if seen_function || pf_gcount>=2048 {fail("globals must precede functions");}next();if token!=256 {fail("expected global name");}
                let name=source+token_start;let size=token_size;if reserved(name,size) || pf_function(name,size) || pf_global(name,size)>=0 {fail("invalid or duplicate global");}
                next();expect(61);let sign=1;if token==45 {sign= -1;next();}if token!=257 {fail("global initializer must be an integer literal");}
                let g=pf_globals+pf_gcount*32;store64(g,name);store64(g+8,size);store64(g+16,token_value*sign);store64(g+24,pf_module);pf_gcount=pf_gcount+1;next();expect(59);
            }else if is("lowering") {pf_lowerings=1;while token && token!=59 {next();}expect(59);}
            else {fail("expected global, lowering or function definition");}
        }
    }if head {fail("function contract has no following function");}return 0;
}
fn pf_prepare() {
    if pf_ready || frontend_language || tx_recording {return 0;}pf_ready=1;let found=pf_verifying;let i=0;
    while i<module_count && !found {select_module(i);pos=load64(modules+i*64+48);next();
        while token && !found {if token==256 && (is("requires") || is("ensures") || is("verify") || is("assert") || is("modifies") || is("reads") || is("releases") || is("trusted") || is("terminates") || is("invariant") || is("decreases") || is("ghost") || is("proof") || is("spec") || is("lemma")) {found=1;}next();}i=i+1;
    }if !found {return 0;}
    pf_functions=alloc(2048*128);pf_globals=alloc(2048*32);pf_copies=alloc(256*8);pf_nodes=alloc(131072*64);pf_spans=alloc(16384*24);pf_locals=alloc(4096*32);pf_ghost_slots=alloc(4096*8);
    if pf_functions<0 || pf_globals<0 || pf_copies<0 || pf_nodes<0 || pf_spans<0 || pf_locals<0 || pf_ghost_slots<0 {fail("cannot allocate verifier syntax");}
    pf_count=0;pf_gcount=0;pf_used=0;pf_span_count=0;pf_lowerings=0;pf_has_helpers=0;i=0;
    while i<module_count {let m=modules+i*64;let copy=alloc(load64(m+16)+1);if copy<0 {fail("cannot retain verifier source");}net_copy(copy,load64(m+8),load64(m+16));store64(pf_copies+i*8,copy);i=i+1;}
    i=0;while i<module_count {pf_select(i);pos=load64(modules+i*64+48);next();pf_scan();i=i+1;}
    i=0;while i<pf_count {let f=pf_functions+i*128;let clause=load64(f+64);while clause {if load64(clause)<4 {pf_resolve_spec(load64(clause+8),f);}else if load64(clause)<6 || load64(clause)==9 {pf_resolve_frame(clause,f);}else {let part=load64(clause+8);while part {pf_resolve_spec(part,f);part=load64(part+48);}}clause=load64(clause+48);}
        if load64(f+104) || load64(f+72) || pf_has_helpers {pf_body(f);}i=i+1;
    }
    ph_validate();
    i=0;while i<pf_span_count {let span=pf_spans+i*24;let bytes=load64(modules+load64(span)*64+8);let at=load64(span+8);
        while at<load64(span+16) {let c=load8(bytes+at);if c!=10 && c!=13 {store8(bytes+at,32);}at=at+1;}i=i+1;
    }return 0;
}
