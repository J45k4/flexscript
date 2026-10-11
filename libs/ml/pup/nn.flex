import "graph.flex";
fn pg_dims3(a,b,c) {let p=alloc(24);store64(p,a);store64(p+8,b);store64(p+16,c);return p;}
fn pg_matmul(a,b) {
    if pg_rank(a)!=2 || pg_rank(b)!=2 || pg_dim(a,1)!=pg_dim(b,0) {pg_error("matmul requires [M,K] and [K,N]");}
    let m=pg_dim(a,0);let k=pg_dim(a,1);let n=pg_dim(b,1);
    let left=pg_reshape(a,3,pg_dims3(m,1,k));let right=pg_permute(b,2,pg_dims3(1,0,0));right=pg_reshape(right,3,pg_dims3(1,n,k));
    let products=pg_binary(5,left,right);let contraction=pg_permute(products,3,pg_dims3(2,0,1));let result=pg_reduce(contraction,3,1);
    // Optional scheduling hint; the graph still consists solely of primitives.
    store64(result+96,a);store64(result+104,b);return result;
}
fn pg_dense(x,w,b) {return pg_binary(3,pg_matmul(x,w),b);}
