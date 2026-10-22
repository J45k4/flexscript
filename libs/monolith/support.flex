import "../ui/support.flex";
// Linux web transport helpers.
fn m_now() {let p=m_take(16);m_assert(syscall(228,1,p,0,0,0,0)==0,"clock failed");return load64(p)*1000+load64(p+8)/1000000;}
fn m_wait(fd,events,deadline) {
    let p=m_take(8);while 1 {let left=deadline-m_now();if left<=0 {return 0;}store64(p,(fd&0xffffffff)|(events<<32));let r=syscall(7,p,1,left,0,0,0);if r!=-4 {return r>0;}}return 0;
}
fn m_send_for(fd,p,n,timeout) {
    let end=m_now()+timeout;
    while n {let k=syscall(44,fd,p,n,16384,0,0);if k>0 {p=p+k;n=n-k;}else if k==-11 {if !m_wait(fd,4,end) {return 0;}}else if k!=-4 {return 0;}if m_now()>end {return 0;}}return 1;
}
fn m_send(fd,p,n) {return m_send_for(fd,p,n,1000);}
fn m_utf8(s) {
    let i=0;let size=m_len(s);
    while i<size {
        let c=load8(s+i);let n=1;let value=c;let min=0;
        if c>=128 {
            if c>=194 && c<=223 {n=2;value=c&31;min=128;}
            else if c>=224 && c<=239 {n=3;value=c&15;min=2048;}
            else if c>=240 && c<=244 {n=4;value=c&7;min=65536;}else {return 0;}
            if i+n>size {return 0;}let k=1;while k<n {let next=load8(s+i+k);if next<128 || next>191 {return 0;}value=(value<<6)|(next&63);k=k+1;}
            if value<min || value>1114111 || (value>=55296 && value<=57343) {return 0;}
        }i=i+n;
    }return 1;
}
fn m_read_file(path) {
    let fd=syscall(2,path,0x80000,0,0,0,0);m_assert(fd>=0,m_cat("cannot open ",path));let b=m_buffer();let scratch=m_take(4096);
    while 1 {let n=syscall(0,fd,scratch,4096,0,0,0);if n>0 {m_append(b,scratch,n);}else if n!=-4 {m_assert(n==0,"file read failed");syscall(3,fd,0,0,0,0,0);return m_data(b);}}return 0;
}
