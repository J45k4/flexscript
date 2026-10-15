import "gatt-server-fixture.flex";
fn go_guard(c,write) {
    let i=0;while i<32 {let p=c+224+i;if write {store8(p,165);}else if load8(p)!=165 {return 0;}i=i+1;}
    i=773;while i<776 {if write {store8(c+i,165);store8(c+i+520,165);}else if load8(c+i)!=165 || load8(c+i+520)!=165 {return 0;}i=i+1;}
    i=3344;while i<3920 {if write {store8(c+i,165);}else if load8(c+i)!=165 {return 0;}i=i+1;}
    i=4048;while i<4096 {if write {store8(c+i,165);}else if load8(c+i)!=165 {return 0;}i=i+1;}return 1;
}
fn go_canaries(write) {
    let i=384;while i<512 {if write {store8(ga_work+i,165);}else if load8(ga_work+i)!=165 {return 0;}i=i+1;}
    i=1;while i<=ga_count {let p=ga_at(i);if load64(p+40)>load64(p+48) {return 0;}let j=104;while j<120 {if write {store8(p+j,165);}else if load8(p+j)!=165 {return 0;}j=j+1;}
        if load64(p+64)!=4 {let cap=load64(p+48);let end=(cap+7)&~7;let data=load64(p+32);j=cap;while j<end {if write {store8(data+j,165);}else if load8(data+j)!=165 {return 0;}j=j+1;}}
        i=i+1;}
    i=ga_pool_used;while i<ga_pool_capacity {if write {store8(ga_pool+i,165);}else if load8(ga_pool+i)!=165 {return 0;}i=i+1;}
    i=0;while i<ga_links {if !go_guard(ga_slot(i),write) {return 0;}i=i+1;}return 1;
}
fn go_number(n) {let p=alloc(32);if n<0 {syscall(1,2,"-",1,0,0,0);n= -n;}let size=nb_number(p,n,10);syscall(1,2,p,size,0,0,0);syscall(1,2," ",1,0,0,0);return 0;}
fn main(argc,argv) {
    let pages=syscall(9,0,20480,3,34,-1,0);if pages<0 || syscall(10,pages+16384,4096,0,0,0,0) {return 3;}let work=pages+16384-ga_size(32,2,2048);gd_wire=alloc(1024);gd_expected=alloc(1024);gd_uuid=alloc(32);gd_body=alloc(1024);if gd_db_config(work,ga_size(32,2,2048),32,argc>1) || ga_open(1) || !go_canaries(1) {return 3;}
    let pages2=syscall(9,0,135168,3,34,-1,0);if pages2<0 || syscall(10,pages2+131072,4096,0,0,0,0) {return 3;}let input=alloc(131072);let size=0;let reading=1;while reading && size<131072 {let n=syscall(0,0,input+size,131072-size,0,0,0);if n<0 {return 3;}if !n {reading=0;}else {size=size+n;}}
    if size==131072 {let more=syscall(0,0,gd_wire,1,0,0,0);if more {return 1;}}
    let wire=pages2+131072-size;nb_copy(wire,input,size);let at=0;let count=0;let error=0;let prefix=alloc(2);
    while at<size && !error {if size-at<4 {error= -74;}else {let n=ga_u16(wire+at);let security=ga_u16(wire+at+2);at=at+4;if n>size-at {error= -74;}else {let r=ga_input(1,wire+at,n,security,ga_now+1);at=at+n;count=count+1;if r<0 {error=r;}else {r=ga_next_packet(1);if r<0 {error=r;}else {ga_put16(prefix,r);syscall(1,1,prefix,2,0,0,0);if r {syscall(1,1,ga_packet,r,0,0,0);if ga_packet_sent(1,ga_now+1) {error= -71;}}if gd_events(1) {error= -71;}}}}}if !go_canaries(0) {return 7;}if count>4096 {error= -90;}}
    go_number(error);go_number(count);syscall(1,2,"\n",1,0,0,0);if error {return 1;}return 0;
}
