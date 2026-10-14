import "../../lib/f64.flex";
// Queries are materialized immutable row sets. Free their independent arena.
fn flexdb_query(db) {if !fd_ready(db) {return 0;}let q=load64(db+208);if q {store64(db+208,0);return q;}q=alloc(32);if q<=0 {fd_panic();}store64(q+24,db);return q;}
// Keep one small arena per database; closed query handles/results remain invalid.
fn flexdb_query_close(q) {let db=load64(q+24);let p=load64(q);if p && !load64(p) && load64(p+8)<=65536 && !load64(db+208) {store64(q+8,0);store64(db+208,q);return 1;}fd_clear(q);syscall(11,q,32,0,0,0,0);return 1;}
fn fd_query_cache_close(db) {let q=load64(db+208);if q {fd_clear(q);syscall(11,q,32,0,0,0,0);store64(db+208,0);}return 1;}
fn fd_relation(q,types) {let p=fd_alloc(q,24);store64(p,fd_size(types));store64(p+8,fd_vec(q));store64(p+16,types);return p;}
fn flexdb_count(result) {return fd_size(load64(result+8));}
fn flexdb_columns(result) {return load64(result);}
fn flexdb_at(result,index) {if index<0 || index>=flexdb_count(result) {return 0;}return fd_at(load64(result+8),index);}
fn fd_query_result(q,t) {
    if !fd_table_ready(t) || load64(t)!=load64(q+24) {fd_error(load64(q+24),"query/table database mismatch");return 0;}
    let types=fd_vec(q);let schema=load64(t+16);let i=0;while i<fd_size(schema) {fd_push(q,types,load64(fd_at(schema,i)+8));i=i+1;}
    return fd_relation(q,types);
}
fn flexdb_scan(q,t) {
    let result=fd_query_result(q,t);if !result {return 0;}let rows=load64(t+24);let i=0;while i<fd_size(rows) {let row=fd_at(rows,i);if !row {row=fd_table_row(t,i);if !row {return 0;}}if load64(row+8) {fd_push(q,load64(result+8),row);}i=i+1;}return result;
}
fn fd_compare(a,b) {
    let kind=load64(a);if kind==1 {let x=load64(a+8);let y=load64(b+8);if x<y {return -1;}return x>y;}
    if kind==4 {let x=load64(a+8);let y=load64(b+8);if f64_is_nan(x) || f64_is_nan(y) {return 2;}if f64_lt(x,y) {return -1;}return f64_gt(x,y);}
    let n=load64(a+16);let m=load64(b+16);let i=0;while i<n && i<m {let x=load8(load64(a+8)+i);let y=load8(load64(b+8)+i);if x<y {return -1;}if x>y {return 1;}i=i+1;}if n<m {return -1;}return n>m;
}
fn flexdb_eq() {return 0;}
fn flexdb_ne() {return 1;}
fn flexdb_lt() {return 2;}
fn flexdb_le() {return 3;}
fn flexdb_gt() {return 4;}
fn flexdb_ge() {return 5;}
fn fd_matches(a,op,b) {
    if !load64(a) || !load64(b) {return 0;}let cmp=fd_compare(a,b);
    if op==0 {return cmp==0;}if op==1 {return cmp!=0;}if cmp==2 {return 0;}
    if op==2 {return cmp<0;}if op==3 {return cmp<=0;}if op==4 {return cmp>0;}return cmp>=0;
}
fn flexdb_where(q,input,column,op,value) {
    let db=load64(q+24);if !input || !value || column<0 || column>=load64(input) || op<0 || op>5 {fd_error(db,"invalid filter");return 0;}
    if load64(value) && load64(value)!=fd_at(load64(input+16),column) {fd_error(db,"filter type mismatch");return 0;}
    let result=fd_relation(q,load64(input+16));let i=0;while i<flexdb_count(input) {let row=flexdb_at(input,i);if fd_matches(flexdb_cell(row,column),op,value) {fd_push(q,load64(result+8),row);}i=i+1;}return result;
}
fn flexdb_where_null(q,input,column,is_null) {
    if !input || column<0 || column>=load64(input) {fd_error(load64(q+24),"invalid null filter");return 0;}
    let result=fd_relation(q,load64(input+16));let i=0;while i<flexdb_count(input) {let row=flexdb_at(input,i);if (!load64(flexdb_cell(row,column)))==(is_null!=0) {fd_push(q,load64(result+8),row);}i=i+1;}return result;
}
fn fd_join_hash(v) {let kind=load64(v);let word=load64(v+8);if kind==1 {return fd_auto_hash(1,word);}if kind==4 {if !(word&0x7fffffffffffffff) {word=0;}return fd_auto_hash(1,word);}return fd_hash_bytes(word,load64(v+16));}
// Hash the right relation; reverse insertion preserves its existing row order.
fn flexdb_join(q,left,lcol,right,rcol) {
    let db=load64(q+24);if !left || !right || lcol<0 || lcol>=load64(left) || rcol<0 || rcol>=load64(right) {fd_error(db,"invalid join columns");return 0;}
    if fd_at(load64(left+16),lcol)!=fd_at(load64(right+16),rcol) {fd_error(db,"join type mismatch");return 0;}
    let types=fd_clone_vec(q,load64(left+16));if !fd_append(q,types,load64(load64(right+16)+16),load64(load64(right+16))) {fd_panic();}let result=fd_relation(q,types);
    let count=flexdb_count(right);if !count || !flexdb_count(left) {return result;}let cap=1;while cap<count*2 {cap=cap*2;}let heads=fd_alloc(q,cap*8);let i=0;while i<cap {store64(heads+i*8,0);i=i+1;}let nodes=fd_alloc(q,count*16);i=count-1;
    while i>=0 {let row=flexdb_at(right,i);let value=flexdb_cell(row,rcol);if load64(value) {let slot=fd_join_hash(value)&(cap-1);let node=nodes+i*16;store64(node,row);store64(node+8,load64(heads+slot*8));store64(heads+slot*8,node);}i=i-1;}
    i=0;while i<flexdb_count(left) {let l=flexdb_at(left,i);let value=flexdb_cell(l,lcol);if load64(value) {let node=load64(heads+(fd_join_hash(value)&(cap-1))*8);while node {let r=load64(node);
        if fd_matches(value,0,flexdb_cell(r,rcol)) {let row=fd_alloc(q,16+load64(result)*8);store64(row,0);store64(row+8,load64(result));fd_copy(row+16,l+16,load64(l+8)*8);fd_copy(row+16+load64(l+8)*8,r+16,load64(r+8)*8);fd_push(q,load64(result+8),row);}node=load64(node+8);}}
        i=i+1;
    }return result;
}
fn flexdb_project(q,input,columns) {
    if !input || fd_size(columns)<1 {fd_error(load64(q+24),"empty projection");return 0;}let types=fd_vec(q);let i=0;
    while i<fd_size(columns) {let c=fd_at(columns,i);if c<0 || c>=load64(input) {fd_error(load64(q+24),"invalid projection column");return 0;}fd_push(q,types,fd_at(load64(input+16),c));i=i+1;}
    let result=fd_relation(q,types);i=0;while i<flexdb_count(input) {let r=flexdb_at(input,i);let row=fd_alloc(q,16+fd_size(columns)*8);store64(row,load64(r));store64(row+8,fd_size(columns));let j=0;while j<fd_size(columns) {store64(row+16+j*8,flexdb_cell(r,fd_at(columns,j)));j=j+1;}fd_push(q,load64(result+8),row);i=i+1;}return result;
}
fn flexdb_selection(q) {return fd_vec(q);}
fn flexdb_pick(q,columns,index) {fd_push(q,columns,index);return columns;}
fn flexdb_limit(q,input,offset,count) {
    if !input || offset<0 || count<0 {fd_error(load64(q+24),"invalid limit");return 0;}let result=fd_relation(q,load64(input+16));let i=offset;let n=0;while i<flexdb_count(input) && n<count {fd_push(q,load64(result+8),flexdb_at(input,i));i=i+1;n=n+1;}return result;
}
