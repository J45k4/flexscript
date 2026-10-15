import "../../lib/net/ble-host.flex";
fn bo_canary(work) {let i=0;while i<4 {let p=bh_slot(i);let j=0;while j<4 {if load8(p+1284+j)!=165 || load8(p+2316+j)!=165 {return 0;}j=j+1;}i=i+1;}i=0;while i<8 {let j=314;while j<320 {if load8(work+1536+i*320+j)!=165 {return 0;}j=j+1;}i=i+1;}return 1;}
fn bo_number(n) {let p=alloc(32);if n<0 {syscall(1,2,"-",1,0,0,0);n= -n;}let size=nb_number(p,n,10);syscall(1,2,p,size,0,0,0);syscall(1,2," ",1,0,0,0);return 0;}
fn main() {
    let pages=syscall(9,0,20480,3,34,-1,0);if pages<0 || syscall(10,pages+16384,4096,0,0,0,0) {return 3;}let work=pages+16384-13376;if bh_init(work,13376,4) {return 3;}
    let connect=alloc(32);nb_zero(connect,32);store8(connect,4);store8(connect+1,62);store8(connect+2,19);store8(connect+3,1);bh_put16(connect+5,64);store8(connect+7,1);bh_put16(connect+15,24);bh_put16(connect+19,400);if bh_input(connect,22,0)!=1 || bh_consume_event() {return 3;}
    let i=0;while i<4 {let p=bh_slot(i);let j=0;while j<4 {store8(p+1284+j,165);store8(p+2316+j,165);j=j+1;}i=i+1;}i=0;while i<8 {let j=314;while j<320 {store8(work+1536+i*320+j,165);j=j+1;}i=i+1;}
    let guard=syscall(9,0,135168,3,34,-1,0);if guard<0 || syscall(10,guard+131072,4096,0,0,0,0) {return 3;}let input=alloc(131072);let size=0;let reading=1;while reading && size<131072 {let n=syscall(0,0,input+size,131072-size,0,0,0);if n<0 {return 3;}if !n {reading=0;}else {size=size+n;}}
    let wire=guard+131072-size;nb_copy(wire,input,size);let at=0;let packets=0;let error=0;let prefix=alloc(4);
    while at<size && !error {if size-at<2 {error= -74;}else {let n=bh_u16(wire+at);at=at+2;if n>size-at {error= -74;}else {let r=bh_input(wire+at,n,packets);at=at+n;packets=packets+1;if r<0 {error=r;}else if bh_message(1)==1 {bh_put16(prefix,bh_message_cid);bh_put16(prefix+2,bh_message_size);syscall(1,1,prefix,4,0,0,0);syscall(1,1,bh_message_data,bh_message_size,0,0,0);bh_consume(1);}}}if packets>4096 {error= -90;}}
    if !error && load64(bh_slot(0)+240) {error= -74;}if !bo_canary(work) {return 7;}bo_number(error);bo_number(packets);bo_number(bh_bad_packets);bo_number(bh_unknown_cid);syscall(1,2,"\n",1,0,0,0);if error {return 1;}return 0;
}
