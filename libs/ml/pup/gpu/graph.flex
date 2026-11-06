// Dependency-aware fusion and physical storage placement for immutable tensors.
import "common.flex";
global cg_nodes=0;
global cg_count=0;
global cg_state=0;
global cg_users=0;
global cg_placed=0;
global cg_joined=0;
// Per node: output target, skipped, fused activation, residual producer,
// residual first, alias destination (plus one), alias byte displacement.
fn cg_state_at(i) {return cg_state+i*56;}
fn cg_field(i,offset) {return load64(cg_state_at(i)+offset);}
fn cg_put(i,offset,value) {store64(cg_state_at(i)+offset,value);return value;}
fn cg_root(i) {
    let offset=0;let steps=0;while cg_field(i,40) {offset=offset+cg_field(i,48);i=cg_field(i,40)-1;steps=steps+1;h_assert(steps<=cg_count,"cyclic tensor placement");}let p=h_take(16);store64(p,i);store64(p+8,offset);return p;
}
fn cg_shape_equal(a,b) {return h_bytes(a,b,32);}
fn cg_user_list(i) {return load64(cg_users+i*8);}
fn cg_graph(nodes,count,residual,shared,joins) {
    cg_nodes=nodes;cg_count=count;cg_state=h_take(count*56);h_zero(cg_state,count*56);cg_users=h_take(count*8);let i=0;
    while i<count {store64(cg_users+i*8,j_array());cg_put(i,0,i);i=i+1;}
    i=0;while i<count {let n=cg_node(nodes,i);let p=load64(n+192);let q=load64(n+200);h_assert(p>= -1 && p<i && q>= -1 && q<i,"invalid graph dependency");if p>=0 {j_push(cg_user_list(p),j_int(i));}if q>=0 {j_push(cg_user_list(q),j_int(i));}i=i+1;}
    i=0;while i<count {let node=cg_node(nodes,i);if load64(node)==12 && !load64(node+216) {
        let uses=cg_user_list(i);let s=-1;let matches=0;let j=0;while j<j_count(uses) {let at=j_value(j_at(uses,j));let candidate=cg_node(nodes,at);if load64(candidate)==24 && !load64(candidate+216) {s=at;matches=matches+1;}j=j+1;}
        if matches==1 && j_count(cg_user_list(s))==1 {let target=j_value(j_at(cg_user_list(s),0));let n=cg_node(nodes,target);let a=load64(n+192);let b=load64(n+200);let valid=load64(n)==5 && ((a==i && b==s) || (a==s && b==i));j=0;let seen_s=0;let seen_t=0;while j<j_count(uses) {let at=j_value(j_at(uses,j));if at==s {seen_s=1;}else if at==target {seen_t=1;}else {valid=0;}j=j+1;}if valid && seen_s && seen_t {cg_put(i,0,target);cg_put(i,16,1);cg_put(s,8,1);cg_put(target,8,1);}}
    }i=i+1;}
    if residual {i=0;while i<count {let n=cg_node(nodes,i);if load64(n)==3 {let side=0;let found=0;while side<2 && !found {let target=load64(n+192+side*8);let other=load64(n+200-side*8);let producer=-1;let j=0;while j<count {let p=cg_node(nodes,j);if (load64(p)==12 || load64(p)==29) && !load64(p+216) && (j==target || (cg_field(j,16) && cg_field(j,0)==target)) {producer=j;}j=j+1;}
        if producer>=0 && other>=0 && other<producer {let t=cg_node(nodes,target);let uses=cg_user_list(target);if !load64(t+216) && j_count(uses)==1 && j_value(j_at(uses,0))==i && cg_shape_equal(n+64,n+96) && cg_shape_equal(n+64,n+128) && cg_product(n+64,0,4)==cg_product(cg_node(nodes,producer)+64,0,4) {cg_put(producer,24,other+1);cg_put(producer,32,side==1);cg_put(producer,0,i);cg_put(i,8,1);found=1;}}side=side+1;}}i=i+1;}}
    i=0;while i<count {let n=cg_node(nodes,i);let axis=cg_param(n,0);if load64(n)==26 && load64(n+192)>=0 && cg_product(n+96,0,axis)==1 {cg_put(i,40,load64(n+192)+1);cg_put(i,48,cg_param(n,1)*cg_product(n+96,axis+1,4)*4);cg_put(i,8,1);}i=i+1;}
    cg_placed=cg_place_joins(!shared);cg_joined=0;if joins {cg_joined=cg_fold_joins();}return 0;
}
fn cg_place_joins(exclusive) {
    let placed=0;let i=cg_count-1;while i>=0 {let n=cg_node(cg_nodes,i);let axis=cg_param(n,0);if !cg_field(i,8) && load64(n)==25 && cg_product(n+64,0,axis)==1 {
        let a=load64(n+192);let b=load64(n+200);let valid=a>=0 && b>=0;if valid && exclusive {valid=j_count(cg_user_list(a))==1 && j_count(cg_user_list(b))==1 && !load64(cg_node(cg_nodes,a)+216) && !load64(cg_node(cg_nodes,b)+216);}
        if valid {let out=cg_root(i);let target=load64(out);let offset=load64(out+8);let parent=h_take(16);store64(parent,a);store64(parent+8,b);let pending=h_take(16);store64(pending,-1);store64(pending+8,-1);let side=0;
            while side<2 && valid {let p=load64(parent+side*8);let delta=0;if side {delta=cg_product(n+96,0,4)*4;}let root=cg_root(p);if load64(root)!=target || load64(root+8)!=offset+delta {
                if cg_field(p,40) || p==target || cg_product(cg_node(cg_nodes,p)+64,0,4)!=cg_product(n+96+side*32,0,4) || (side && a==b && load64(pending)>=0 && load64(pending)!=offset+delta) {valid=0;}else {store64(pending+side*8,offset+delta);}
            }side=side+1;}
            if valid {side=0;while side<2 {let delta=load64(pending+side*8);if delta>=0 {let p=load64(parent+side*8);cg_put(p,40,target+1);cg_put(p,48,delta);}side=side+1;}cg_put(i,8,1);placed=placed+1;}
        }
    }i=i-1;}return placed;
}
fn cg_fold_joins() {
    let folded=0;let changed=1;while changed {changed=0;let i=0;while i<cg_count {let n=cg_node(cg_nodes,i);if !cg_field(i,8) && load64(n)==25 && cg_product(n+64,0,cg_param(n,0))==1 && load64(n+192)>=0 && load64(n+200)>=0 {
        let a=cg_root(load64(n+192));let b=cg_root(load64(n+200));let base=load64(a);let left=load64(a+8);if base==load64(b) && left+cg_product(n+96,0,4)*4==load64(b+8) {let out=cg_root(i);let target=load64(out);let offset=load64(out+8);let valid=1;if base!=target || left!=offset {if base==target || left || cg_product(n+64,0,4)!=cg_product(cg_node(cg_nodes,base)+64,0,4) {valid=0;}else {cg_put(base,40,target+1);cg_put(base,48,offset);}}if valid {cg_put(i,8,1);folded=folded+1;changed=1;}}
    }i=i+1;}}return folded;
}
