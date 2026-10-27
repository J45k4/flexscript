// Shared UI arena and UTF-8/JSON output. Embedders supply alloc and syscall ABI.
global m_blocks=0;
global m_used=0;
global m_capacity=0;
fn m_len(s) {let n=0;if s {while load8(s+n) {n=n+1;}}return n;}
fn m_print(fd,s) {return syscall(1,fd,s,m_len(s),0,0,0);}
fn m_die(s) {m_print(2,"Monolith: ");m_print(2,s);m_print(2,"\n");syscall(60,1,0,0,0,0,0);return 0;}
fn m_assert(ok,s) {if !ok {m_die(s);}return 0;}
fn m_take(n) {
    m_assert(n>=0 && n<16777216,"allocation limit");n=(n+7)/8*8;
    if !m_blocks || n>m_capacity-m_used {
        let size=65536;if n+16>size {size=(n+4111)/4096*4096;}
        let p=alloc(size);m_assert(p>0,"allocation failed");
        store64(p,m_blocks);store64(p+8,size);m_blocks=p;m_capacity=size-16;m_used=0;
    }
    let p=m_blocks+16+m_used;m_used=m_used+n;return p;
}
fn m_mark() {m_used=m_capacity;return m_blocks;}
fn m_state() {let p=m_take(24);store64(p,m_blocks);store64(p+8,m_used);store64(p+16,m_capacity);return p;}
fn m_restore(p) {m_blocks=load64(p);m_used=load64(p+8);m_capacity=load64(p+16);return 0;}
fn m_fresh() {m_blocks=0;m_used=0;m_capacity=0;return 0;}
fn m_free_state(state) {let p=load64(state);while p {let next=load64(p);syscall(11,p,load64(p+8),0,0,0,0);p=next;}return 0;}
fn m_reset(mark) {
    while m_blocks!=mark {let p=m_blocks;m_blocks=load64(p);syscall(11,p,load64(p+8),0,0,0,0);}
    m_capacity=0;if m_blocks {m_capacity=load64(m_blocks+8)-16;}m_used=m_capacity;return 0;
}
fn m_copy(to,from,n) {let i=0;while i<n {store8(to+i,load8(from+i));i=i+1;}return to;}
fn m_slice(s,n) {let p=m_take(n+1);m_copy(p,s,n);store8(p+n,0);return p;}
fn m_eq(a,b) {if !a || !b {return a==b;}let i=0;while load8(a+i) && load8(a+i)==load8(b+i) {i=i+1;}return load8(a+i)==load8(b+i);}
fn m_cat(a,b) {let n=m_len(a);let k=m_len(b);let p=m_take(n+k+1);m_copy(p,a,n);m_copy(p+n,b,k);store8(p+n+k,0);return p;}
fn m_int(n) {
    let p=m_take(32);let i=31;store8(p+i,0);m_assert(n>=0,"negative integer");
    while n>=10 {i=i-1;store8(p+i,48+n%10);n=n/10;}i=i-1;store8(p+i,48+n);return p+i;
}
fn m_number(s) {
    let n=0;let i=0;if !m_len(s) {return -1;}
    while load8(s+i) {let c=load8(s+i);if c<48 || c>57 || n>(9223372036854775807-c+48)/10 {return -1;}n=n*10+c-48;i=i+1;}return n;
}
fn m_buffer() {let b=m_take(24);store64(b,0);store64(b+8,0);store64(b+16,0);return b;}
fn m_append(b,s,n) {
    let size=load64(b+8);let cap=load64(b+16);m_assert(n>=0 && size+n<8388608,"response limit");
    if size+n+1>cap {let next=1024;while next<size+n+1 {next=next*2;}let p=m_take(next);m_copy(p,load64(b),size);store64(b,p);store64(b+16,next);}
    m_copy(load64(b)+size,s,n);store64(b+8,size+n);store8(load64(b)+size+n,0);return b;
}
fn m_text(b,s) {return m_append(b,s,m_len(s));}
fn m_data(b) {if !load64(b) {m_text(b,"");}return load64(b);}
fn m_escape(b,s,json) {
    let i=0;if !s {s="";}if json {m_text(b,"\"");}
    while load8(s+i) {
        let c=load8(s+i);
        if json {
            if c==34 {m_text(b,"\\\"");}else if c==92 {m_text(b,"\\\\");}
            else if c<32 {let hex="0123456789abcdef";m_text(b,"\\u00");m_append(b,hex+(c>>4),1);m_append(b,hex+(c&15),1);}
            else {m_append(b,s+i,1);}
        }else {
            if c==38 {m_text(b,"&amp;");}else if c==60 {m_text(b,"&lt;");}else if c==62 {m_text(b,"&gt;");}
            else if c==34 {m_text(b,"&quot;");}else if c==39 {m_text(b,"&#39;");}else {m_append(b,s+i,1);}
        }i=i+1;
    }
    if json {m_text(b,"\"");}return b;
}
