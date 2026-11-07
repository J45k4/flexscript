// Concrete completion of a symbolic byte-memory model. This module does not
// call the circuit builder, SAT search, symbolic lookup, or permission encoder.
// It decodes input bits, evaluates gates, then executes native interval maps.
// Every interval is checked in full; large ranges are never byte samples.
// A failure to construct/check a completion means no replayed counterexample.
// Internal callers supply live, bounded circuit/memory buffers, not file data.
// Context (160): memory, gate values, points/count/cap, cells/size, work/error,
// width/mask/sign, own size, decoded probes/count, nodes/count, regions/count.
// Concrete cell (32): byte, read, write, allocation identity.
// Decoded node (64): kind,parent,p,n,value,guard,identity,other.
fn pbm_bad(model) {store64(model+64,1);return 0;}
fn pbm_tick(model) {let left=load64(model+56);if left<=0 {return pbm_bad(model);}store64(model+56,left-1);return 1;}
fn pbm_norm(model,value) {return value&load64(model+80);}
fn pbm_less(model,a,b) {
    if load64(model+72)==64 {return (a^load64(model+88))<(b^load64(model+88));}return a<b;
}
fn pbm_positive(model,value) {return value && !(value&load64(model+88));}
fn pbm_valid(model,p,n) {
    if n&load64(model+88) {return 0;}if !n {return 1;}if !pbm_positive(model,p) {return 0;}
    // This subtraction does not wrap: both operands are in the positive domain.
    let maximum=pbm_norm(model,load64(model+88)-1);return n-1<=maximum-p;
}
fn pbm_member(model,p,n,address) {
    if !n || !pbm_valid(model,p,n) {return 0;}return !pbm_less(model,address,p) && pbm_less(model,address,pbm_norm(model,p+n));
}
fn pbm_bool(model,literal) {
    let id=literal;if id<0 {id= -id;}let c=load64(load64(model));
    if id<1 || id>load64(c+8) {return pbm_bad(model);}let value=load64(load64(model+8)+id*8);
    if value!=1 && value!= -1 {return pbm_bad(model);}if literal<0 {value= -value;}return value==1;
}
fn pbm_word(model,word) {
    let c=load64(load64(model));let start=load64(c+64);let stride=load64(c)*8;
    if word<start || word>=start+load64(c+48)*stride || (word-start)%stride {return pbm_bad(model);}
    let result=0;let i=0;while i<load64(model+72) {if pbm_bool(model,load64(word+i*8)) {result=result|(1<<i);}i=i+1;}return result;
}
fn pbm_gates(model,assignment) {
    let c=load64(load64(model));let i=1;
    while i<=load64(c+8) {if !pbm_tick(model) {return 0;}let row=load64(c+24)+(i-1)*32;let kind=load64(row);let result=0;
        if i==1 && kind!=4 {return pbm_bad(model);}
        if kind==0 {let value=load64(assignment+i*8);if value!=1 && value!= -1 {return pbm_bad(model);}result=value==1;}
        else if kind==4 {if i!=1 {return pbm_bad(model);}result=1;}
        else if kind>=1 && kind<=3 {
            let j=1;let count=2;if kind==3 {count=3;}while j<=count {let id=load64(row+j*8);if id<0 {id= -id;}if id<1 || id>=i {return pbm_bad(model);}j=j+1;}
            let a=pbm_bool(model,load64(row+8));let b=pbm_bool(model,load64(row+16));
            if kind==1 {result=a && b;}else if kind==2 {result=a!=b;}else {result=b;if !a {result=pbm_bool(model,load64(row+24));}}
        }else {return pbm_bad(model);}let literal= -1;if result {literal=1;}store64(load64(model+8)+i*8,literal);i=i+1;
    }return !load64(model+64);
}
fn pbm_point(model,address) {
    let count=load64(model+24);let table=load64(model+16);let at=count;
    while at>0 && pbm_less(model,address,load64(table+(at-1)*8)) {if !pbm_tick(model) {return 0;}at=at-1;}
    if at && load64(table+(at-1)*8)==address {return 1;}
    if count>=load64(model+32) {return pbm_bad(model);}let i=count;while i>at {store64(table+i*8,load64(table+(i-1)*8));i=i-1;}
    store64(table+at*8,address);store64(model+24,count+1);return 1;
}
fn pbm_bounds(model,p,n) {if n && pbm_valid(model,p,n) {pbm_point(model,p);pbm_point(model,pbm_norm(model,p+n));}return !load64(model+64);}
fn pbm_index(model,state) {
    let memory=load64(model);let start=load64(memory+8);
    if state<start || state>=start+load64(memory+16)*80 || (state-start)%80 {pbm_bad(model);return -1;}return (state-start)/80;
}
fn pbm_decode(model) {
    let memory=load64(model);let i=0;pbm_point(model,0);pbm_point(model,1);pbm_point(model,load64(model+88));
    while i<load64(model+128) {if !pbm_tick(model) {return 0;}let src=load64(memory+8)+i*80;let dst=load64(model+120)+i*64;let kind=load64(src);
        if kind<0 || kind>9 || (!i && kind) || (i && !kind) {return pbm_bad(model);}store64(dst,kind);store64(dst+8,-1);store64(dst+56,-1);
        if kind {let parent=pbm_index(model,load64(src+8));if parent<0 || parent>=i {return pbm_bad(model);}store64(dst+8,parent);}
        store64(dst+16,0);store64(dst+24,0);store64(dst+32,0);store64(dst+40,pbm_bool(model,load64(src+40)));store64(dst+48,0);
        if kind==5 || kind==7 || kind==8 {let other=pbm_index(model,load64(src+56));if other<0 || other>=i {return pbm_bad(model);}store64(dst+56,other);}
        else if kind {let p=pbm_word(model,load64(src+16));let n=pbm_word(model,load64(src+24));store64(dst+16,p);store64(dst+24,n);pbm_bounds(model,p,n);}
        if kind==1 {store64(dst+32,pbm_word(model,load64(src+32)));}
        if kind==3 || kind==9 {store64(dst+48,pbm_word(model,load64(src+48)));}i=i+1;
    }i=0;
    while i<load64(model+112) {if !pbm_tick(model) {return 0;}let src=load64(memory+32)+i*48;let dst=load64(model+104)+i*48;let state=pbm_index(model,load64(src));
        if state<0 {return 0;}let kind=load64(load64(model+120)+state*64);if kind!=0 && kind!=2 && kind!=6 && kind!=7 && kind!=8 && kind!=9 {return pbm_bad(model);}
        let address=pbm_word(model,load64(src+8));store64(dst,state);store64(dst+8,address);store64(dst+16,pbm_word(model,load64(src+16)));
        store64(dst+24,pbm_bool(model,load64(src+24)));store64(dst+32,pbm_bool(model,load64(src+32)));store64(dst+40,pbm_word(model,load64(src+40)));
        pbm_point(model,address);pbm_point(model,pbm_norm(model,address+1));i=i+1;
    }i=0;
    while i<load64(memory+64) {if !pbm_tick(model) {return 0;}let src=load64(memory+56)+i*48;let address=pbm_word(model,load64(src+8));pbm_point(model,address);pbm_point(model,pbm_norm(model,address+1));i=i+1;}i=0;
    while i<load64(model+144) {if !pbm_tick(model) {return 0;}let src=load64(memory+80)+i*80;let dst=load64(model+136)+i*40;
        store64(dst,pbm_index(model,load64(src)));let p=pbm_word(model,load64(src+8));let n=pbm_word(model,load64(src+16));
        let mode=load64(src+24);if mode!=0 && mode!=1 {let reference=pbm_index(model,mode);if reference<0 {return 0;}mode=reference+2;}
        store64(dst+8,p);store64(dst+16,n);store64(dst+24,mode);store64(dst+32,pbm_bool(model,load64(src+32)));pbm_bounds(model,p,n);i=i+1;
    }return !load64(model+64);
}
// Extend each finite map between observations. Exact observations remain
// distinct single bytes; all geometry boundaries also split the map. A proposed
// extension is accepted only after every full interval obligation is checked.
fn pbm_probe(model,state,address) {
    let selected=0;let i=0;while i<load64(model+112) {if !pbm_tick(model) {return 0;}let row=load64(model+104)+i*48;
        if load64(row)==state && !pbm_less(model,address,load64(row+8)) {
            if !selected || pbm_less(model,load64(selected+8),load64(row+8)) {selected=row;}
        }i=i+1;
    }return selected;
}
fn pbm_cell_at(model,state,point) {return load64(model+40)+(state*load64(model+24)+point)*32;}
fn pbm_cell(model,state,address) {
    if state<0 || state>=load64(model+128) || !load64(model+40) {pbm_bad(model);return 0;}
    let lo=0;let hi=load64(model+24);let points=load64(model+16);
    while lo+1<hi {let mid=(lo+hi)/2;if pbm_less(model,address,load64(points+mid*8)) {hi=mid;}else {lo=mid;}}
    return pbm_cell_at(model,state,lo);
}
fn pbm_cells(model) {
    let total=load64(model+24)*load64(model+128);if total>2097152 {return pbm_bad(model);}
    let size=total*32;let cells=alloc(size);if cells<0 {return pbm_bad(model);}store64(model+40,cells);store64(model+48,size);let i=0;
    while i<load64(model+128) {let node=load64(model+120)+i*64;let kind=load64(node);let j=0;
        while j<load64(model+24) {if !pbm_tick(model) {return 0;}let address=load64(load64(model+16)+j*8);let dst=pbm_cell_at(model,i,j);let parent=0;let k=0;
            if kind {parent=pbm_cell_at(model,load64(node+8),j);}
            while k<32 {let value=0;if parent {value=load64(parent+k);}store64(dst+k,value);k=k+8;}
            let active=load64(node+40) && pbm_member(model,load64(node+16),load64(node+24),address);
            if kind==7 || kind==8 {let entry=pbm_cell_at(model,load64(node+56),j);active=load64(node+40) && load64(parent+24) && load64(parent+24)!=load64(entry+24);}
            if kind==9 {active=active && !load64(parent+24);}
            if !kind || ((kind==2 || kind==6 || kind==7 || kind==8 || kind==9) && active) {let probe=pbm_probe(model,i,address);
                if probe {
                    if kind!=6 && kind!=8 {store64(dst,load64(probe+16));}
                    if kind!=2 && kind!=7 {store64(dst+8,load64(probe+24));store64(dst+16,load64(probe+32));store64(dst+24,load64(probe+40));}
                }
                if !kind && !pbm_positive(model,address) {store64(dst+8,0);store64(dst+16,0);store64(dst+24,0);}
                if kind==6 || kind==8 {
                    // Outside an exact observation, remove any permission or
                    // identity that cannot be preserved from this parent cell.
                    if load64(dst+24)!=load64(parent+24) {store64(dst+24,0);}
                    store64(dst+8,load64(dst+8) && load64(parent+8) && load64(dst+24));
                    store64(dst+16,load64(dst+16) && load64(parent+16) && load64(dst+8));
                }
                if kind==9 && load64(dst+24) && load64(dst+24)!=load64(node+48) {return pbm_bad(model);}
            }else if kind==1 && active {store64(dst,load64(node+32));}
            else if kind==3 && active {
                if load64(parent+24) {return pbm_bad(model);}store64(dst,0);store64(dst+8,1);store64(dst+16,1);store64(dst+24,load64(node+48));
            }else if kind==4 && active {store64(dst+8,0);store64(dst+16,0);store64(dst+24,0);}
            else if kind==5 && !load64(node+40) {let other=pbm_cell_at(model,load64(node+56),j);k=0;while k<32 {store64(dst+k,load64(other+k));k=k+8;}}
            if load64(dst)<0 || load64(dst)>255 || (load64(dst+16) && !load64(dst+8)) || (load64(dst+8) && !load64(dst+24)) {return pbm_bad(model);}
            if !kind && load64(dst+24) && !(load64(dst+24)&load64(model+88)) {return pbm_bad(model);}j=j+1;
        }
        if kind==3 && load64(node+40) {
            if !load64(node+24) || !pbm_valid(model,load64(node+16),load64(node+24)) || load64(node+48)!=i+1 {return pbm_bad(model);}
        }
        if kind==9 && (load64(node+48)!=i+1 || load64(node+16)!=1 || load64(node+24)!=load64(model+88)-1) {return pbm_bad(model);}
        i=i+1;
    }return !load64(model+64);
}
fn pbm_access(model,state,address,mode) {
    let cell=pbm_cell(model,state,address);if !cell {return 0;}
    if mode==0 {return load64(cell+8)!=0;}if mode==1 {return load64(cell+16)!=0;}
    let entry=pbm_cell(model,mode-2,address);if !entry {return 0;}return load64(cell+24) && load64(cell+24)!=load64(entry+24);
}
fn pbm_permission(model,state,p,n,write) {
    if !pbm_valid(model,p,n) {return 0;}if !n {return 1;}let cell=pbm_cell(model,state,p);if !cell {return 0;}
    if !pbm_access(model,state,p,write) {return 0;}let i=0;
    while i<load64(model+24) {if !pbm_tick(model) {return 0;}let address=load64(load64(model+16)+i*8);
        if pbm_member(model,p,n,address) && !pbm_access(model,state,address,write) {return 0;}i=i+1;
    }return 1;
}
fn pbm_check(model) {
    let memory=load64(model);let i=0;
    // Check every original probe, including maps hidden by a transition. The
    // lookup checks below separately check the actual snapshot observations.
    while i<load64(model+112) {if !pbm_tick(model) {return 0;}let row=load64(model+104)+i*48;let found=pbm_probe(model,load64(row),load64(row+8));
        if !found {return pbm_bad(model);}let k=16;while k<48 {if load64(found+k)!=load64(row+k) {return pbm_bad(model);}k=k+8;}i=i+1;
    }i=0;
    while i<load64(memory+64) {if !pbm_tick(model) {return 0;}let row=load64(memory+56)+i*48;let state=pbm_index(model,load64(row));let cell=pbm_cell(model,state,pbm_word(model,load64(row+8)));
        if !cell || load64(cell)!=pbm_word(model,load64(row+16)) || load64(cell+8)!=pbm_bool(model,load64(row+24)) || load64(cell+16)!=pbm_bool(model,load64(row+32)) || load64(cell+24)!=pbm_word(model,load64(row+40)) {return pbm_bad(model);}i=i+1;
    }i=0;
    while i<load64(model+144) {if !pbm_tick(model) {return 0;}let row=load64(model+136)+i*40;
        if pbm_permission(model,load64(row),load64(row+8),load64(row+16),load64(row+24))!=load64(row+32) {return pbm_bad(model);}i=i+1;
    }return !load64(model+64);
}
fn pbm_release(model) {
    if !model {return 0;}if load64(model+40) {syscall(11,load64(model+40),load64(model+48),0,0,0,0);}return syscall(11,model,load64(model+96),0,0,0,0);
}
fn pbm_replay(memory,assignment,budget) {
    if !memory || !assignment || budget<=0 || load64(memory+112) {return 0;}let c=load64(memory);if load64(c+72) {return 0;}
    let gates=load64(c+8)+1;let probes=load64(memory+40);let nodes=load64(memory+16);let regions=load64(memory+88);
    let size=160+gates*8+16384*8+probes*48+nodes*64+regions*40;let model=alloc(size);if model<0 {return 0;}let i=0;while i<160 {store64(model+i,0);i=i+8;}
    store64(model,memory);store64(model+8,model+160);store64(model+16,model+160+gates*8);store64(model+32,16384);store64(model+56,budget);
    store64(model+72,load64(c));let mask= -1;if load64(c)<64 {mask=(1<<load64(c))-1;}store64(model+80,mask);store64(model+88,1<<(load64(c)-1));store64(model+96,size);
    store64(model+104,load64(model+16)+16384*8);store64(model+112,probes);store64(model+120,load64(model+104)+probes*48);store64(model+128,nodes);
    store64(model+136,load64(model+120)+nodes*64);store64(model+144,regions);
    if !pbm_gates(model,assignment) || !pbm_decode(model) || !pbm_cells(model) || !pbm_check(model) {pbm_release(model);return 0;}return model;
}
