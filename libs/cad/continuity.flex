// Deterministic breadth-first path plus the intended nets in the entire
// reachable component. The displayed shortest path alone can hide a short.
import "studio/pcad-trace-graph.flex";

fn pgt_path(previous,from,to) {
    let edges=cg_array();let at=to;
    while at && at!=from && !cg_error {
        let edge=load64(previous+load64(at)*8);
        cg_push(edges,edge);at=load64(edge);
    }
    let path=j_array();let i=cg_count(edges)-1;
    while i>=0 && !cg_error {
        let edge=cg_at(edges,i);let start=load64(edge);let end=load64(edge+8);
        let row=j_object();
        cg_j_text(row,"from",load64(start+8));cg_j_text(row,"to",load64(end+8));
        cg_j_text(row,"fromLabel",load64(start+16));cg_j_text(row,"toLabel",load64(end+16));
        cg_j_text(row,"kind",load64(edge+16));cg_j_text(row,"record_id",load64(edge+24));cg_j_text(row,"label",load64(edge+32));
        j_add(path,0,row);i=i-1;
    }
    return path;
}
fn pgt_trace(g,request) {
    let net=j_string(request,"net_id");let ends=j_get(request,"ends");
    if !pgt_id(net) || j_kind(ends)!=3 || cg_j_count(ends)!=2 {return cg_fail("Choose a net and two terminals");}
    let a=load64(ends+16);let b=load64(a+24);
    if !m_eq(j_string(a,"kind"),"terminal") || !m_eq(j_string(b,"kind"),"terminal") {
        return cg_fail("Choose two distinct terminals on the intended net");
    }
    let from=pgt_find(g,pgt_end(a));let to=pgt_find(g,pgt_end(b));
    if cg_error || !from || !to || from==to || !m_eq(load64(from+24),net) || !m_eq(load64(to+24),net) {
        return cg_fail("The two distinct terminals must belong to the declared net");
    }
    let count=cg_count(load64(g+8));let previous=m_take(count*8);let queue=m_take(count*8);
    let i=0;while i<count {store64(previous+i*8,0);i=i+1;}
    store64(previous+load64(from)*8,1);store64(queue,from);
    let used=1;let reached=j_object();let no_connects=j_array();i=0;
    while i<used && !cg_error {
        let row=load64(queue+i*8);let intent=load64(row+24);
        if m_len(intent) && !m_eq(intent,net) {cg_j_int(reached,intent,1);}
        if load64(row+40) {
            let node=j_object();
            cg_j_text(node,"id",load64(row+8));cg_j_text(node,"label",load64(row+16));j_add(no_connects,0,node);
        }
        let edge=load64(row+32);
        while edge && !cg_error {
            if !cg_step() {return 0;}
            let next=load64(edge+8);let offset=load64(next)*8;
            if !load64(previous+offset) {
                store64(previous+offset,edge);store64(queue+used*8,next);used=used+1;
            }
            edge=load64(edge+40);
        }
        i=i+1;
    }
    let out=j_object();let conflicts=j_array();let conflict_ids=j_array();let path=j_array();
    let names=load64(load64(g+24)+16);
    while names {
        let id=load64(names+32);
        if j_get(reached,id) {j_add(conflict_ids,0,j_text(id));j_add(conflicts,0,j_text(j_value(names)));}
        names=load64(names+24);
    }
    let status="open";let unchecked=load64(g+32);
    if cg_j_count(unchecked) {status="unresolved";}
    if load64(previous+load64(to)*8) {status="connected";path=pgt_path(previous,from,to);}
    if cg_error {return 0;}
    cg_j_text(out,"format","pcad-trace-1");cg_j_text(out,"net_id",net);
    cg_j_text(out,"from",load64(from+8));cg_j_text(out,"to",load64(to+8));cg_j_text(out,"state",status);
    j_add(out,"path",path);j_add(out,"conflicts",conflicts);j_add(out,"conflict_net_ids",conflict_ids);j_add(out,"no_connects",no_connects);
    j_add(out,"unchecked",j_parse(j_encode(unchecked)));
    return out;
}

fn pcad_trace(document,request) {
    let graph=pgt_build(document);
    if !graph {return pc_error();}
    let out=pgt_trace(graph,request);
    if !out {return pc_error();}
    return out;
}

fn pcad_required_traces(document) {
    cg_begin();
    let out=j_object();let reports=j_array();
    cg_j_text(out,"format","pcad-required-traces-1");j_add(out,"traces",reports);
    let requirements=j_get(j_get(document,"electrical"),"required_traces");
    if !requirements || (j_kind(requirements)==3 && !cg_j_count(requirements)) {
        cg_j_text(out,"status","unknown");cg_j_text(out,"reason","No full-system continuity paths are declared");
        return out;
    }
    if j_kind(requirements)!=3 || cg_j_count(requirements)>16 {
        cg_j_text(out,"status","checks_failed");cg_j_text(out,"reason","Declare at most sixteen full-system continuity paths");
        return out;
    }
    let graph=pgt_build(document);
    if !graph {
        cg_j_text(out,"status","unknown");cg_j_text(out,"reason",cg_error);
        return out;
    }
    let failed=0;let unknown=0;let used=j_object();let pairs=j_object();
    let row=load64(requirements+16);
    while row {
        let id=j_string(row,"id");let trace=0;
        if pgt_id(id) && !j_get(used,id) {trace=pgt_trace(graph,row);}
        else {cg_fail("A required path needs a stable unique ID");}
        if trace {
            let from=j_string(trace,"from");let to=j_string(trace,"to");
            let key=m_cat(from,m_cat("/",to));let reverse=m_cat(to,m_cat("/",from));
            if j_get(pairs,key) || j_get(pairs,reverse) {
                cg_fail("A pair of terminals can be required only once");trace=0;
            }else {cg_j_int(pairs,key,1);}
        }
        if !trace {
            trace=j_object();cg_j_text(trace,"state","invalid");cg_j_text(trace,"error",cg_error);
            failed=failed+1;cg_error=0;
        }else if m_eq(j_string(trace,"state"),"open") || cg_j_count(j_get(trace,"conflicts")) || cg_j_count(j_get(trace,"no_connects")) {
            failed=failed+1;
        }else if cg_j_count(j_get(trace,"unchecked")) {unknown=unknown+1;}
        cg_j_int(used,id,1);cg_j_text(trace,"id",id);j_add(reports,0,trace);
        row=load64(row+24);
    }
    let status="checks_passed";
    if unknown {status="unknown";}
    if failed {status="checks_failed";}
    cg_j_text(out,"status",status);cg_j_int(out,"failed",failed);cg_j_int(out,"unchecked",unknown);
    return out;
}
