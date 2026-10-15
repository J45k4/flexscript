import "../../lib/net/mqtt.flex";
fn mo_number(n) {let b=alloc(32);if n<0 {syscall(1,2,"-",1,0,0,0);n= -n;}let size=nb_number(b,n,10);syscall(1,2,b,size,0,0,0);syscall(1,2," ",1,0,0,0);return 0;}
fn mo_step(argc,argv) {if argc<2 {return 31;}let p=load64(argv+8);let n=0;let i=0;while load8(p+i) {let c=load8(p+i);if c<48 || c>57 || n>3276 {return 31;}n=n*10+c-48;i=i+1;}if n<1 || n>32768 {return 31;}return n;}
fn main(argc,argv) {
    let pages=syscall(9,0,8192,3,34,-1,0);if pages<0 || syscall(10,pages+4096,4096,0,0,0,0) || mp_init(pages,4096) {return 3;}
    let input=alloc(32768);let size=0;let reading=1;while reading && size<32768 {let n=syscall(0,0,input+size,32768-size,0,0,0);if n<0 {return 3;}if !n {reading=0;}else {size=size+n;}}
    let guard=syscall(9,0,36864,3,34,-1,0);if guard<0 || syscall(10,guard+32768,4096,0,0,0,0) {return 3;}let wire=guard+32768-size;nb_copy(wire,input,size);let step=mo_step(argc,argv);let at=0;
    while at<size && mp_state!=4 && mp_state!=3 {let n=size-at;if n>step {n=step;}let used=mp_feed(wire+at,n);if used>=0 {if !used {return 4;}at=at+used;}}
    let end=mp_eof();mo_number(mp_state);mo_number(mp_error);mo_number(at);mo_number(mp_type);mo_number(mp_flags);mo_number(mp_id);mo_number(mp_qos);mo_number(mp_dup);mo_number(mp_retain);mo_number(mp_session_present);mo_number(mp_connack);mo_number(mp_topic_size);mo_number(mp_payload_size);syscall(1,2,"\n",1,0,0,0);
    if mp_state==3 && !end && at==size {syscall(1,1,mp_topic,mp_topic_size,0,0,0);syscall(1,1,mp_payload,mp_payload_size,0,0,0);return 0;}return 1;
}
