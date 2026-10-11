import "../../lib/slirp.flex";
fn expect(ok) {if !ok {syscall(1,2,"libslirp backend assertion failed\n",33,0,0,0);syscall(60,1,0,0,0,0,0);}return 0;}
fn be16(p,v) {store8(p,v>>8);store8(p+1,v);return 0;}
fn word(p) {return (load8(p)<<8)|load8(p+1);}
fn zero(p,n) {let i=0;while i<n {store8(p+i,0);i=i+1;}return 0;}
fn mac(p) {store8(p,0x52);store8(p+1,0x54);store8(p+3,0x12);store8(p+4,0x34);store8(p+5,0x56);return 0;}
fn checksum(p) {let sum=0;let i=0;while i<20 {sum=sum+word(p+i);i=i+2;}while sum>>16 {sum=(sum&65535)+(sum>>16);}return (~sum)&65535;}
fn offer(s,message) {
    expect(sn_poll(s)==1);let p=sn_peek(s);let bytes=sn_length(s);expect(p && bytes>=283 && bytes<=2040 && word(p+12)==0x800 && word(p+34)==67 && word(p+36)==68);
    expect(load8(p+42)==2 && load8(p+46)==0x12 && load8(p+47)==0x34 && load8(p+48)==0x56 && load8(p+49)==0x78);
    expect(load8(p+58)==10 && load8(p+59)==0 && load8(p+60)==2 && load8(p+61)==15);
    let at=282;let found=0;while at<bytes && load8(p+at)!=255 {let option=load8(p+at);if !option {at=at+1;}else {expect(at+2<=bytes);let n=load8(p+at+1);expect(at+2+n<=bytes);if option==53 {expect(n==1 && load8(p+at+2)==message);found=1;}at=at+2+n;}}
    expect(found);sn_pop(s);return 0;
}
fn main(argc,argv) {
    expect(argc==2);let s=sn_create(1);expect(s);let code=load64(s+96);
    let fd=syscall(2,load64(argv+8),0,0,0,0,0);expect(fd>=0);let raw=alloc(4096);let n=syscall(0,fd,raw,4096,0,0,0);expect(n>768 && n<4096);let i=0;while i<n {expect(load8(raw+i)==load8(code+i));i=i+1;}syscall(3,fd,0,0,0,0,0);
    // Trusted callbacks preserve packet bytes, bound the RX ring and convert
    // every poll event combination in both directions.
    let packet=alloc(2048);i=0;while i<2048 {store8(packet+i,i*17+3);i=i+1;}
    i=0;while i<128 {expect(ffi_call(code,packet,64,s,0,0,0)==64);i=i+1;}expect(load64(s+24)==128 && !load64(s+32));
    expect(ffi_call(code,packet,64,s,0,0,0)==64 && load64(s+32)==1 && load64(s+24)==128);
    i=0;while i<128 {let p=sn_peek(s);expect(p && sn_length(s)==64);let j=0;while j<64 {expect(load8(p+j)==load8(packet+j));j=j+1;}sn_pop(s);i=i+1;}expect(!sn_peek(s));
    expect(ffi_call(code,packet,13,s,0,0,0)==13 && ffi_call(code,packet,2041,s,0,0,0)==2041 && load64(s+32)==3 && !sn_peek(s));
    expect(ffi_call(code+256,s,0,0,0,0,0)>0);let flags=0;while flags<32 {store64(s+48,0);expect(ffi_call_i32(code+512,7,flags,s,0,0,0)==0);let expected=(flags&25)|((flags&2)<<1)|((flags&4)>>1);expect(word(s+516)==((expected&255)<<8));store8(s+518,expected);store8(s+519,0);expect(ffi_call_i32(code+768,0,s,0,0,0,0)==flags);flags=flags+1;}
    store64(s+48,1024);expect(ffi_call_i32(code+512,7,1,s,0,0,0)==-1 && load64(s+56)==1 && ffi_call_i32(code+768,1024,s,0,0,0,0)==0);
    expect(sn_input(s,packet,13)==-1 && sn_input(s,packet,2041)==-1);
    // Real libslirp ARP response for the private gateway; restricted mode
    // prevents any Internet traffic during these protocol tests.
    zero(packet,2048);i=0;while i<6 {store8(packet+i,255);i=i+1;}mac(packet+6);be16(packet+12,0x806);be16(packet+14,1);be16(packet+16,0x800);store8(packet+18,6);store8(packet+19,4);be16(packet+20,1);mac(packet+22);store8(packet+28,10);store8(packet+30,2);store8(packet+31,15);store8(packet+38,10);store8(packet+40,2);store8(packet+41,2);
    expect(sn_input(s,packet,42)==1 && sn_poll(s)==1);let reply=sn_peek(s);expect(reply && sn_length(s)>=42 && word(reply+12)==0x806 && word(reply+20)==2 && load8(reply+31)==2 && load8(reply+41)==15);sn_pop(s);
    // DHCP discover/offer and request/ack, with an actual leased guest address.
    zero(packet,2048);i=0;while i<6 {store8(packet+i,255);i=i+1;}mac(packet+6);be16(packet+12,0x800);store8(packet+14,0x45);be16(packet+16,277);store8(packet+22,64);store8(packet+23,17);i=30;while i<34 {store8(packet+i,255);i=i+1;}be16(packet+24,checksum(packet+14));be16(packet+34,68);be16(packet+36,67);be16(packet+38,257);
    store8(packet+42,1);store8(packet+43,1);store8(packet+44,6);store8(packet+46,0x12);store8(packet+47,0x34);store8(packet+48,0x56);store8(packet+49,0x78);store8(packet+52,128);mac(packet+70);
    store8(packet+278,99);store8(packet+279,130);store8(packet+280,83);store8(packet+281,99);store8(packet+282,53);store8(packet+283,1);store8(packet+284,1);store8(packet+285,55);store8(packet+286,3);store8(packet+287,1);store8(packet+288,3);store8(packet+289,6);store8(packet+290,255);
    expect(sn_input(s,packet,291)==1);offer(s,2);
    be16(packet+16,284);be16(packet+24,0);be16(packet+24,checksum(packet+14));be16(packet+38,264);store8(packet+284,3);store8(packet+285,50);store8(packet+286,4);store8(packet+287,10);store8(packet+288,0);store8(packet+289,2);store8(packet+290,15);store8(packet+291,54);store8(packet+292,4);store8(packet+293,10);store8(packet+294,0);store8(packet+295,2);store8(packet+296,2);store8(packet+297,255);
    expect(sn_input(s,packet,298)==1);offer(s,5);
    // State callbacks copy only within their owned stream and leave position
    // and adjacent bytes unchanged on overflow, including a corrupt cursor.
    let stream=alloc(4096);let context=alloc(32);store64(context,stream);store64(context+8,32);
    expect(ffi_call(code+1024,packet,16,context,0,0,0)==16 && load64(context+16)==16);
    expect(ffi_call(code+1024,packet,17,context,0,0,0)==-1 && load64(context+16)==16 && load64(context+24)==1 && !load64(stream+16));
    store64(context+16,0);store64(context+24,0);expect(ffi_call(code+1152,raw,16,context,0,0,0)==16 && load64(raw)==load64(packet) && load64(raw+8)==load64(packet+8));
    store64(context+16,33);expect(ffi_call(code+1152,raw,1,context,0,0,0)==-1 && load64(context+16)==33);
    // A real DHCP lease survives the library's supported migration stream.
    // This checks its byte-for-byte state, not survival of external sockets.
    let version=sn_state_version(s);expect(version>0);let saved=sn_state_save(s,stream,4096);expect(saved>1 && saved<4096);
    let restored=sn_create(1);expect(restored && sn_state_load(restored,version,stream,saved)==1);
    let again=alloc(4096);expect(sn_state_save(restored,again,4096)==saved);i=0;while i<saved {expect(load8(stream+i)==load8(again+i));i=i+1;}
    expect(sn_state_save(s,again,1)<0 && sn_state_save(s,again,1048577)<0 && sn_state_load(restored,version+1,stream,saved)<0);
    let truncated=sn_create(1);expect(truncated && sn_state_load(truncated,version,stream,saved-1)<0);sn_close(truncated);
    sn_close(restored);sn_close(s);
    syscall(1,1,"PASS: libslirp callbacks, bounded queues, poll flags, ARP and DHCP lease\n",73,0,0,0);return 0;
}
