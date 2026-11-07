import "../libs/proof/memory.flex";
import "../libs/proof/memory-model.flex";
// Source memory bridge. Snapshots are explicit call-state fields; frames are
// evaluated once in the entry state, after ordered requirements. Accesses made
// while resolving those requirements/frames are retained and checked afterward.
global vm_memory=0;
global vm_used=0;
global vm_reads=0;
global vm_writes=0;
global vm_releases=0;
global vm_allocated=0;
global vm_choices=0;
global vm_choice_tail=0;
global vm_allocations=0;
global rm_model=0;
global rm_allocations=0;
global rm_identity=0;
fn vm_take(size) {let p=alloc(size+16);if p<0 {fail("cannot allocate memory proof state");}store64(p,vm_allocations);store64(p+8,size+16);vm_allocations=p;return p+16;}
fn vm_release() {while vm_allocations {let p=vm_allocations;vm_allocations=load64(p);syscall(11,p,load64(p+8),0,0,0,0);}if vm_memory {pb_release(vm_memory);vm_memory=0;}return 0;}
fn rm_take(size) {let p=alloc(size+16);if p<0 {vr_stopped=1;return 0;}store64(p,rm_allocations);store64(p+8,size+16);rm_allocations=p;return p+16;}
fn rm_release() {while rm_allocations {let p=rm_allocations;rm_allocations=load64(p);syscall(11,p,load64(p+8),0,0,0,0);}if rm_model {pbm_release(rm_model);rm_model=0;}return 0;}
fn vm_primitive(node) {
    let name=load64(node+8);let size=load64(node+16);if pf_function(name,size) {return 0;}
    if pf_name(name,size,"load8") {return 1;}if pf_name(name,size,"load64") {return 2;}
    if pf_name(name,size,"store8") {return 3;}if pf_name(name,size,"store64") {return 4;}if pf_name(name,size,"alloc") {return 5;}
    if load64(node)!=7 {if pf_name(name,size,"readable_bytes") {return 6;}if pf_name(name,size,"writable_bytes") {return 7;}if pf_name(name,size,"disjoint_bytes") {return 8;}if pf_name(name,size,"fresh_bytes") {return 9;}}return 0;
}
fn vm_validate(owner,node,kind) {
    let count=1;if kind==3 || kind==4 || kind==6 || kind==7 || kind==9 {count=2;}if kind==8 {count=4;}
    if load64(node+56)!=count {if load64(node)==7 {ph_error(node,"wrong builtin argument count");}ph_error(node,"wrong memory operation argument count");}
    if kind>=3 && kind<=5 && (load64(node)!=7 || ph_kind(owner)) {ph_error(node,"proof expressions cannot modify or allocate memory");}return 0;
}
// Frame info: ready, read regions, content-write regions, pending accesses,
// lifetime-release regions. Each region is an entry pointer/length/next tuple.
fn vm_info() {let p=vm_take(40);let i=0;while i<40 {store64(p+i,0);i=i+8;}return p;}
fn vm_entry(state,parent,entry) {
    let memory=load64(vm_memory+176);if parent {memory=load64(parent+96);if entry {memory=load64(parent+104);}}
    store64(state+96,memory);store64(state+104,memory);store64(state+112,memory);store64(state+120,vm_info());return 0;
}
fn vm_contains(regions,address) {
    let yes= -1;while regions {yes=pw_or(vf_context,yes,pb_member(vm_memory,load64(regions),load64(regions+8),address));regions=load64(regions+16);}return yes;
}
fn vm_frame_allows(state,frame,snapshot,address) {
    let allowed=vm_contains(frame,address);let entry=load64(state+104);
    if !vm_allocated || snapshot==entry {return allowed;}
    let current=pb_lookup(vm_memory,snapshot,address,0);let old=pb_lookup(vm_memory,entry,address,0);
    let identity=load64(current+40);let fresh=pw_and(vf_context,pw_truth(vf_context,identity),-pw_equal(vf_context,identity,load64(old+40)));
    return pw_or(vf_context,allowed,fresh);
}
fn vm_check_access(state,event) {
    let info=load64(state+120);let write=load64(event+16);let frame=load64(info+8);let declared=load64(load64(state)+96);let kind="read frame";
    if write==1 {frame=load64(info+16);declared=load64(load64(state)+112);kind="write frame";}
    if write==2 {frame=load64(info+32);declared=pm_clause(load64(state),9);kind="release frame";}if !declared {return 0;}
    let saved=load64(state+24);store64(state+24,load64(event+24));let p=load64(event);let n=load64(event+8);let bytes=load64(event+40);let safe=1;
    if bytes {let i=0;while i<bytes {safe=pw_and(vf_context,safe,vm_frame_allows(state,frame,load64(event+56),pw_add(vf_context,p,pw_constant(vf_context,i))));i=i+1;}}
    else {let address=pw_input(vf_context);safe=pw_or(vf_context,-pb_member(vm_memory,p,n,address),vm_frame_allows(state,frame,load64(event+56),address));}
    vf_obligation(state,load64(event+32),kind,safe);store64(state+24,saved);return 0;
}
fn vm_effect(state,node,p,n,write,bytes,snapshot) {
    if load64(state+24)== -1 {return 0;}let assuming=pm_assuming;
    if assuming {let caller=state;let trusted=0;while caller {if pt_trusted(load64(caller)) {trusted=1;}caller=load64(caller+72);}if !trusted {return 0;}}
    // A trusted body is assumed, but its specification's actual memory reads
    // still contribute dependencies and must respect enclosing read frames.
    pm_assuming=0;if write==2 {vm_releases=1;}else if write {vm_writes=1;}else {vm_reads=1;}
    let ancestor=state;while ancestor {let info=load64(ancestor+120);let event=vm_take(64);
        store64(event,p);store64(event+8,n);store64(event+16,write);store64(event+24,load64(state+24));store64(event+32,node);store64(event+40,bytes);store64(event+48,0);
        store64(event+56,snapshot);
        if load64(info) {vm_check_access(ancestor,event);}else {store64(event+48,load64(info+24));store64(info+24,event);}ancestor=load64(ancestor+72);
    }pm_assuming=assuming;return 0;
}
fn vm_declares(f,kind) {let clause=load64(f+64);while clause {if load64(clause)==kind {let item=load64(clause+8);while item {if load64(item)==10 {return 1;}item=load64(item+48);}}clause=load64(clause+48);}return 0;}
fn vm_effect_names(globals,memory) {let any=0;let i=0;while i<pf_gcount {if load64(globals+i*8) {any=1;}i=i+1;}
    if !memory || any {vf_effect_names(globals);}if memory {if any {print(1,", ");}print(1,"byte memory");}return 0;
}
fn rm_show() {
    if !rm_model {return 0;}print(1,"  entry memory observations (byte, read, write):\n");let i=0;let shown=0;let memory=load64(rm_model);
    while i<load64(memory+40) && shown<8 {let row=load64(memory+32)+i*48;if load64(row)==load64(memory+176) {
        let address=pbm_word(rm_model,load64(row+8));let cell=pbm_cell(rm_model,0,address);print(1,"    ");vf_hex(address);print(1,": ");vf_hex(load64(cell));
        print(1,", ");print(1,up_number(load64(cell+8)));print(1,", ");print(1,up_number(load64(cell+16)));print(1,"\n");shown=shown+1;
    }i=i+1;}if i<load64(memory+40) {print(1,"    ... additional memory observations omitted\n");}return 0;
}
fn vm_prepare(state) {
    let info=load64(state+120);let clause=load64(load64(state)+64);
    while clause {let kind=load64(clause);if kind==4 || kind==5 || kind==9 {let item=load64(clause+8);while item {
        if load64(item)==10 {let p=vf_eval(state,load64(item+8),1);let n=vf_eval(state,load64(item+16),1);vf_obligation(state,item,"memory frame validity",pb_valid(vm_memory,p,n));
            let region=vm_take(24);let offset=8;if kind==5 {offset=16;}if kind==9 {offset=32;}store64(region,p);store64(region+8,n);store64(region+16,load64(info+offset));store64(info+offset,region);
        }item=load64(item+48);
    }}clause=load64(clause+48);}
    store64(info,1);let event=load64(info+24);while event {vm_check_access(state,event);event=load64(event+48);}store64(info+24,0);return 0;
}
fn vm_eval(state,node,entry,kind) {
    vm_used=1;
    let args=vm_take(32);let part=load64(node+24);let i=0;while part {store64(args+i*8,vf_eval(state,part,entry));i=i+1;part=load64(part+48);}
    let snapshot=load64(state+96);if entry {snapshot=load64(state+104);}let p=load64(args);let result=vf_zero;
    if kind==5 {
        vm_allocated=1;let out=vm_take(16);if !pb_alloc(vm_memory,snapshot,p,load64(state+24),out) {return vf_unproved(node,"memory allocation circuit capacity exceeded");}
        result=load64(out);store64(state+96,load64(out+8));let choice=vm_take(40);
        store64(choice,node);store64(choice+8,result);store64(choice+16,load64(state+24));store64(choice+24,0);store64(choice+32,0);
        if vm_choice_tail {store64(vm_choice_tail+24,choice);}else {vm_choices=choice;}vm_choice_tail=choice;
    }
    else if kind==6 || kind==7 {result=pw_boolean(vf_context,pb_permission(vm_memory,snapshot,p,load64(args+8),kind==7));}
    else if kind==8 {result=pw_boolean(vf_context,pb_disjoint(vm_memory,p,load64(args+8),load64(args+16),load64(args+24)));}
    else if kind==9 {result=pw_boolean(vf_context,pb_fresh(vm_memory,snapshot,load64(state+104),p,load64(args+8)));}
    else {let bytes=1;if kind==2 || kind==4 {bytes=8;}let write=kind>=3;let out=vm_take(16);
        vm_effect(state,node,p,pw_constant(vf_context,bytes),write,bytes,snapshot);
        // This snapshot belongs to this execution path. Branch/return joins
        // supply guards when it is merged back into another state.
        let ok=0;if write {ok=pb_store(vm_memory,snapshot,p,load64(args+8),bytes,1,out);result=load64(args+8);if ok {store64(state+96,load64(out));}}
        else {ok=pb_load(vm_memory,snapshot,p,bytes,out);if ok {result=load64(out);}}
        if !ok {return vf_unproved(node,"memory circuit capacity exceeded");}let label="memory read safety";if write {label="memory write safety";}vf_obligation(state,node,label,load64(out+8));
        // Only safe accesses have a normal continuation. Their separate safety
        // obligations remain mandatory before this path can count as proved.
        store64(state+24,pw_and(vf_context,load64(state+24),load64(out+8)));
    }return result;
}
fn vm_frame_effects(state,site,write) {
    let offset=8;let declared=load64(load64(state)+96);if write {offset=16;declared=load64(load64(state)+112);}
    if write==2 {offset=32;declared=pm_clause(load64(state),9);}
    let region=load64(load64(state+120)+offset);
    if !declared {vm_effect(state,site,pw_constant(vf_context,1),pw_constant(vf_context,0x7fffffffffffffff),write,0,load64(state+96));}
    else {while region {let bytes=0;let count=load64(region+8);let meta=pw_meta(vf_context,count);
        // Enumerating every byte of a small constant region is exact. Larger
        // or symbolic regions retain the universally quantified address check.
        if load64(meta)==1 {let size=load64(meta+8);if size>0 && size<=64 {bytes=size;}}
        vm_effect(state,site,load64(region),count,write,bytes,load64(state+96));region=load64(region+16);}}return 0;
}
fn vm_havoc(state) {
    vm_used=1;let region=load64(load64(state+120)+16);let memory=load64(state+96);
    if !load64(load64(state)+112) {memory=pb_havoc(vm_memory,memory,pw_constant(vf_context,1),pw_constant(vf_context,0x7fffffffffffffff),load64(state+24));}
    else {while region {memory=pb_havoc(vm_memory,memory,load64(region),load64(region+8),load64(state+24));region=load64(region+16);}}
    if vm_allocated {memory=pb_fresh_havoc(vm_memory,memory,load64(state+104),load64(state+24));}
    store64(state+96,memory);return 0;
}
fn vm_summary(state,site,effect) {
    if load64(load64(effect+16)+pf_gcount*8) {vm_frame_effects(state,site,0);}
    let memory_effects=load64(load64(effect+24)+pf_gcount*8);
    if memory_effects&1 {vm_frame_effects(state,site,1);vm_havoc(state);}
    if memory_effects&2 {vm_frame_effects(state,site,2);vm_revoke(state);}
    if memory_effects&4 {vm_grow(state);}return 0;
}
fn vm_revoke(state) {
    vm_used=1;let region=load64(load64(state+120)+32);let memory=load64(state+96);
    if !pm_clause(load64(state),9) {memory=pb_revoke(vm_memory,memory,pw_constant(vf_context,1),pw_constant(vf_context,0x7fffffffffffffff),load64(state+24));}
    else {while region {memory=pb_revoke(vm_memory,memory,load64(region),load64(region+8),load64(state+24));region=load64(region+16);}}
    if vm_allocated {memory=pb_fresh_revoke(vm_memory,memory,load64(state+104),load64(state+24));}
    store64(state+96,memory);return 0;
}
fn vm_grow(state) {vm_used=1;vm_allocated=1;store64(state+96,pb_grow(vm_memory,load64(state+96),load64(state+24)));return 0;}
// Native replay keeps persistent byte writes and allocation ranges over the
// independently completed initial interval map. No program pointer is ever
// dereferenced. A native node is (parent, kind, pointer, length, value/identity).
fn rm_reset_choices() {rm_identity=0;let row=vm_choices;while row {store64(row+32,0);row=load64(row+24);}return 0;}
fn rm_metadata(snapshot,address,field) {
    while snapshot {if !vr_tick() {return 0;}
        if load64(snapshot+8)==3 && rm_member(load64(snapshot+16),load64(snapshot+24),address) {if field==24 {return load64(snapshot+32);}return 1;}
        snapshot=load64(snapshot);
    }return load64(pbm_cell(rm_model,0,address)+field);
}
fn rm_range_cell(snapshot,address,write,empty) {
    if empty==2 {let current=rm_metadata(snapshot,address,24);return current && current!=rm_metadata(write,address,24);}
    if empty {return !rm_metadata(snapshot,address,24);}let field=8;if write {field=16;}return rm_metadata(snapshot,address,field)!=0;
}
fn rm_range(snapshot,p,n,write,empty) {
    if n<0 || (n && (p<=0 || n-1>0x7fffffffffffffff-p)) {return 0;}if !n {return 1;}
    if !rm_range_cell(snapshot,p,write,empty) {return 0;}
    // Every initial or allocation boundary splits a constant-permission
    // interval. Checking all of them covers the full range, regardless of size.
    let i=0;while i<load64(rm_model+24) && !vr_stopped {let address=load64(load64(rm_model+16)+i*8);
        if rm_member(p,n,address) && !rm_range_cell(snapshot,address,write,empty) {return 0;}i=i+1;
    }
    let node=snapshot;while node && !vr_stopped {if !vr_tick() {return 0;}
        if load64(node+8)==3 {let start=load64(node+16);let end=start+load64(node+24);
            if rm_member(p,n,start) && !rm_range_cell(snapshot,start,write,empty) {return 0;}
            if rm_member(p,n,end) && !rm_range_cell(snapshot,end,write,empty) {return 0;}
        }node=load64(node);
    }return !vr_stopped;
}
fn rm_summary_choice(state) {
    // A summarized allocator has no expanded primitive choice. Its abstract
    // return can propose a concrete address/error for replay of the actual body.
    // This is only a witness heuristic: rm_allocate still checks the full range
    // and the source interpreter must reach the original failing obligation.
    let ancestor=state;while ancestor {let record=pm_models;while record {
        if load64(record)==load64(ancestor+80) && load64(record+24)==load64(ancestor) && load64(record+8) {return load64(load64(record+8)+32);}
        record=load64(record+16);
    }ancestor=load64(ancestor+72);}return 0;
}
fn rm_allocate(state,node,n) {
    let choice=vm_choices;let found=0;while choice && !found && !vr_stopped {
        if load64(choice)==node && !load64(choice+32) && pbm_bool(rm_model,load64(choice+16)) {found=1;}else {choice=load64(choice+24);}
    }
    let word=0;if choice {store64(choice+32,1);word=load64(choice+8);}else {word=rm_summary_choice(state);}
    if !word || load64(rm_model+64) {vr_stopped=1;return 0;}let result=pbm_word(rm_model,word);
    if load64(rm_model+64) {vr_stopped=1;return 0;}
    // The assignment proposes a choice; native checks independently establish
    // that it is an allowed allocation in this concrete execution state.
    if result<0 {vr_step(3,node,result);return result;}
    if !result || n<=0 || !rm_range(load64(state+96),result,n,0,1) {vr_stopped=1;return 0;}
    let cell=rm_take(40);if !cell {return 0;}rm_identity=rm_identity+1;
    store64(cell,load64(state+96));store64(cell+8,3);store64(cell+16,result);store64(cell+24,n);store64(cell+32,rm_identity);store64(state+96,cell);vr_step(3,node,result);return result;
}
fn rm_entry(state,parent,entry) {
    let snapshot=0;if parent {snapshot=load64(parent+96);if entry {snapshot=load64(parent+104);}}store64(state+96,snapshot);store64(state+104,snapshot);
    let info=rm_take(40);if !info {return 0;}let i=0;while i<40 {store64(info+i,0);i=i+8;}store64(state+120,info);return 0;
}
fn rm_member(p,n,address) {return n>=0 && (n==0 || (p>0 && n-1<=0x7fffffffffffffff-p)) && n && address>=p && address-p<n;}
fn rm_contains(regions,address) {while regions {if rm_member(load64(regions),load64(regions+8),address) {return 1;}regions=load64(regions+16);}return 0;}
fn rm_check_access(state,event) {
    let info=load64(state+120);let write=load64(event+16);let regions=load64(info+8);let declared=load64(load64(state)+96);let kind="read frame";
    if write==1 {regions=load64(info+16);declared=load64(load64(state)+112);kind="write frame";}
    if write==2 {regions=load64(info+32);declared=pm_clause(load64(state),9);kind="release frame";}if !declared {return 0;}
    let i=0;while i<load64(event+8) && !vr_stopped {let address=load64(event)+i;let current=rm_metadata(load64(event+40),address,24);let old=rm_metadata(load64(state+104),address,24);
        if !vr_stopped && !rm_contains(regions,address) && !(current && current!=old) {vr_failure(state,load64(event+24),kind);}i=i+1;}return 0;
}
fn rm_effect(state,node,p,bytes,write,snapshot) {
    let ancestor=state;while ancestor && !vr_stopped {let info=load64(ancestor+120);let event=rm_take(48);if !event {return 0;}
        store64(event,p);store64(event+8,bytes);store64(event+16,write);store64(event+24,node);store64(event+32,0);
        store64(event+40,snapshot);
        if load64(info) {rm_check_access(ancestor,event);}else {store64(event+32,load64(info+24));store64(info+24,event);}
        let call=state;while call && call!=ancestor && !vr_stopped {let site=load64(call+80);if site {let through=rm_take(48);if !through {return 0;}
            store64(through,p);store64(through+8,bytes);store64(through+16,write);store64(through+24,site);store64(through+32,0);
            store64(through+40,snapshot);
            if load64(info) {rm_check_access(ancestor,through);}else {store64(through+32,load64(info+24));store64(info+24,through);}
        }call=load64(call+72);}ancestor=load64(ancestor+72);
    }return 0;
}
fn rm_prepare(state) {
    let info=load64(state+120);let clause=load64(load64(state)+64);while clause && !vr_stopped {let kind=load64(clause);
        if kind==4 || kind==5 || kind==9 {let item=load64(clause+8);while item && !vr_stopped {if load64(item)==10 {
            let p=vr_eval(state,load64(item+8),1);let n=vr_eval(state,load64(item+16),1);
            if vr_stopped {return 0;}
            if n<0 || (n && (p<=0 || n-1>0x7fffffffffffffff-p)) {vr_failure(state,item,"memory frame validity");}
            let region=rm_take(24);if !region {return 0;}let offset=8;if kind==5 {offset=16;}if kind==9 {offset=32;}store64(region,p);store64(region+8,n);store64(region+16,load64(info+offset));store64(info+offset,region);
        }item=load64(item+48);}}clause=load64(clause+48);
    }store64(info,1);let event=load64(info+24);while event && !vr_stopped {rm_check_access(state,event);event=load64(event+32);}return 0;
}
fn rm_byte(snapshot,address) {while snapshot && !vr_stopped {if !vr_tick() {return 0;}
    if load64(snapshot+8)==1 && load64(snapshot+16)==address {return load64(snapshot+32);}
    if load64(snapshot+8)==3 && rm_member(load64(snapshot+16),load64(snapshot+24),address) {return 0;}snapshot=load64(snapshot);
}return load64(pbm_cell(rm_model,0,address));}
fn rm_eval(state,node,entry,kind) {
    if !rm_model {vr_stopped=1;return 0;}let args=rm_take(32);if !args {return 0;}let part=load64(node+24);let i=0;
    while part && !vr_stopped {store64(args+i*8,vr_eval(state,part,entry));i=i+1;part=load64(part+48);}if vr_stopped {return 0;}
    let p=load64(args);let snapshot=load64(state+96);if entry {snapshot=load64(state+104);}
    if kind==5 {return rm_allocate(state,node,p);}
    if kind==6 || kind==7 {return rm_range(snapshot,p,load64(args+8),kind==7,0);}
    if kind==9 {return rm_range(snapshot,p,load64(args+8),load64(state+104),2);}
    if kind==8 {let n=load64(args+8);let q=load64(args+16);let m=load64(args+24);if !pbm_valid(rm_model,p,n) || !pbm_valid(rm_model,q,m) {return 0;}return !n || !m || (p<=q && n<=q-p) || (q<p && m<=p-q);}
    let bytes=1;if kind==2 || kind==4 {bytes=8;}let write=kind>=3;rm_effect(state,node,p,bytes,write,snapshot);if vr_stopped {return 0;}
    let permitted=rm_range(snapshot,p,bytes,write,0);if vr_stopped || load64(rm_model+64) {vr_stopped=1;return 0;}
    if !permitted {let label="memory read safety";if write {label="memory write safety";}vr_failure(state,node,label);vr_stopped=1;return 0;}
    let value=0;i=0;while i<bytes && !vr_stopped {if write {let cell=rm_take(40);if !cell {return 0;}store64(cell,snapshot);store64(cell+8,1);store64(cell+16,p+i);store64(cell+24,1);store64(cell+32,(load64(args+8)>>(i*8))&255);snapshot=cell;}
        else {value=value|(rm_byte(snapshot,p+i)<<(i*8));}i=i+1;
    }if write {store64(state+96,snapshot);return load64(args+8);}return value;
}
