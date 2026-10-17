import "bytes.flex";
// BLE cryptographic toolbox. No allocation, entropy, transport or bond ownership.
// Consumer supplies smp_aes128(key,input,out): AES-128 ECB, conventional octets,
// status0/signed error. Fixed16-byte inputs/output; provider may not retain them.
// Public scalar arrays are Bluetooth wire order (least significant octet first).
// Address descriptor: type0/1 followed by six HCI-order address octets. IOcap and
// legacy Pairing Request/Response retain their complete wire octets. f5 output
// is MacKey[16] followed by LTK[16]; g2 writes four little-endian octets.
// All public derivations require512 scratch bytes, disjoint from inputs/output.
// Output may alias an input; it is published only after every AES call succeeds.
// smp_cmac alone uses96 scratch bytes and conventional CMAC octet order.
fn smp_range(p,n) {return p>0 && n>=0 && p<=9223372036854775807-n;}
fn smp_overlap(a,an,b,bn) {return an && bn && a<b+bn && b<a+an;}
fn smp_input(work,p,n) {return smp_range(p,n) && !smp_overlap(work,512,p,n);}
fn smp_output(work,capacity,out,size) {return capacity>=512 && smp_range(work,capacity) && smp_range(out,size) && !smp_overlap(work,512,out,size);}
fn smp_address(work,p) {return smp_input(work,p,7) && load8(p)<=1;}
fn smp_reverse(out,input,n) {let i=0;while i<n {store8(out+i,load8(input+n-1-i));i=i+1;}return 0;}
fn smp_address_be(out,input) {store8(out,load8(input));smp_reverse(out+1,input+1,6);return 0;}
fn smp_done(work,result) {nb_zero(work,512);return result;}
fn smp_double(out,input) {
    let carry=0;let i=15;while i>=0 {let byte=load8(input+i);store8(out+i,(byte<<1)|carry);carry=byte>>7;i=i-1;}
    if carry {store8(out+15,load8(out+15)^0x87);}return 0;
}
fn smp_cmac(key,message,size,out,work,capacity) {
    if size<0 || size>65535 || !smp_range(key,16) || !smp_range(out,16) || capacity<96 || !smp_range(work,capacity) || (size && !smp_range(message,size)) {return -22;}
    if smp_overlap(work,96,key,16) || smp_overlap(work,96,out,16) || (size && smp_overlap(work,96,message,size)) {return -22;}
    nb_zero(work,96);let r=smp_aes128(key,work+80,work);if r {nb_zero(work,96);return r;}
    smp_double(work+16,work);smp_double(work+32,work+16);let blocks=(size+15)/16;if !blocks {blocks=1;}let at=0;
    while at<blocks-1 {let j=0;while j<16 {store8(work+80+j,load8(message+at*16+j)^load8(work+48+j));j=j+1;}
        r=smp_aes128(key,work+80,work+48);if r {nb_zero(work,96);return r;}at=at+1;}
    let last=size-at*16;let sub=work+32;nb_zero(work+64,16);let j=0;while j<last {store8(work+64+j,load8(message+at*16+j));j=j+1;}
    if size && last==16 {sub=work+16;}else {store8(work+64+last,128);}
    j=0;while j<16 {store8(work+80+j,load8(work+64+j)^load8(sub+j)^load8(work+48+j));j=j+1;}
    r=smp_aes128(key,work+80,work+48);if !r {nb_copy(out,work+48,16);}nb_zero(work,96);return r;
}
fn smp_f4(u,v,x,z,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,u,32) || !smp_input(work,v,32) || !smp_input(work,x,16) || z<0 || z>255 {return -22;}
    nb_zero(work,512);smp_reverse(work+96,x,16);smp_reverse(work+112,u,32);smp_reverse(work+144,v,32);store8(work+176,z);
    let r=smp_cmac(work+96,work+112,65,work+240,work,96);if !r {smp_reverse(out,work+240,16);}return smp_done(work,r);
}
fn smp_f5(w,n1,n2,a1,a2,out,work,capacity) {
    if !smp_output(work,capacity,out,32) || !smp_input(work,w,32) || !smp_input(work,n1,16) || !smp_input(work,n2,16) || !smp_address(work,a1) || !smp_address(work,a2) {return -22;}
    nb_zero(work,512);store64(work+96,0x38a5f5aa9183886c);store64(work+104,0xbe83605adb0b3760);smp_reverse(work+112,w,32);
    let r=smp_cmac(work+96,work+112,32,work+256,work,96);if r {return smp_done(work,r);}
    store8(work+112,0);nb_copy(work+113,"btle",4);smp_reverse(work+117,n1,16);smp_reverse(work+133,n2,16);smp_address_be(work+149,a1);smp_address_be(work+156,a2);store8(work+163,1);store8(work+164,0);
    r=smp_cmac(work+256,work+112,53,work+272,work,96);if r {return smp_done(work,r);}store8(work+112,1);
    r=smp_cmac(work+256,work+112,53,work+288,work,96);if !r {smp_reverse(out,work+272,16);smp_reverse(out+16,work+288,16);}return smp_done(work,r);
}
fn smp_f6(key,n1,n2,random,io,a1,a2,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,key,16) || !smp_input(work,n1,16) || !smp_input(work,n2,16) || !smp_input(work,random,16) || !smp_input(work,io,3) || !smp_address(work,a1) || !smp_address(work,a2) {return -22;}
    nb_zero(work,512);smp_reverse(work+96,key,16);smp_reverse(work+112,n1,16);smp_reverse(work+128,n2,16);smp_reverse(work+144,random,16);smp_reverse(work+160,io,3);smp_address_be(work+163,a1);smp_address_be(work+170,a2);
    let r=smp_cmac(work+96,work+112,65,work+240,work,96);if !r {smp_reverse(out,work+240,16);}return smp_done(work,r);
}
fn smp_g2(u,v,x,y,out,work,capacity) {
    if !smp_output(work,capacity,out,4) || !smp_input(work,u,32) || !smp_input(work,v,32) || !smp_input(work,x,16) || !smp_input(work,y,16) {return -22;}
    nb_zero(work,512);smp_reverse(work+96,x,16);smp_reverse(work+112,u,32);smp_reverse(work+144,v,32);smp_reverse(work+176,y,16);
    let r=smp_cmac(work+96,work+112,80,work+240,work,96);if !r {smp_reverse(out,work+252,4);}return smp_done(work,r);
}
fn smp_h6(key,id,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,key,16) || !smp_input(work,id,4) {return -22;}
    nb_zero(work,512);smp_reverse(work+96,key,16);smp_reverse(work+112,id,4);
    let r=smp_cmac(work+96,work+112,4,work+240,work,96);if !r {smp_reverse(out,work+240,16);}return smp_done(work,r);
}
fn smp_h7(salt,key,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,salt,16) || !smp_input(work,key,16) {return -22;}
    nb_zero(work,512);smp_reverse(work+96,salt,16);smp_reverse(work+112,key,16);
    let r=smp_cmac(work+96,work+112,16,work+240,work,96);if !r {smp_reverse(out,work+240,16);}return smp_done(work,r);
}
// Internal wire-order AES, with disjoint temporary blocks in caller scratch.
fn smp_e_work(key,input,out,work) {
    smp_reverse(work+96,key,16);smp_reverse(work+112,input,16);let r=smp_aes128(work+96,work+112,work+240);if !r {smp_reverse(out,work+240,16);}return r;
}
fn smp_e(key,input,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,key,16) || !smp_input(work,input,16) {return -22;}
    nb_zero(work,512);let r=smp_e_work(key,input,work+304,work);if !r {nb_copy(out,work+304,16);}return smp_done(work,r);
}
fn smp_c1(key,random,request,response,a1,a2,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,key,16) || !smp_input(work,random,16) || !smp_input(work,request,7) || !smp_input(work,response,7) || !smp_address(work,a1) || !smp_address(work,a2) {return -22;}
    nb_zero(work,512);store8(work+304,load8(a1));store8(work+305,load8(a2));nb_copy(work+306,request,7);nb_copy(work+313,response,7);
    let i=0;while i<16 {store8(work+304+i,load8(work+304+i)^load8(random+i));i=i+1;}
    let r=smp_e_work(key,work+304,work+320,work);if r {return smp_done(work,r);}i=0;while i<6 {store8(work+320+i,load8(work+320+i)^load8(a2+1+i));store8(work+326+i,load8(work+326+i)^load8(a1+1+i));i=i+1;}
    r=smp_e_work(key,work+320,work+336,work);if !r {nb_copy(out,work+336,16);}return smp_done(work,r);
}
fn smp_s1(key,r1,r2,out,work,capacity) {
    if !smp_output(work,capacity,out,16) || !smp_input(work,key,16) || !smp_input(work,r1,16) || !smp_input(work,r2,16) {return -22;}
    nb_zero(work,512);nb_copy(work+304,r2,8);nb_copy(work+312,r1,8);let r=smp_e_work(key,work+304,work+320,work);if !r {nb_copy(out,work+320,16);}return smp_done(work,r);
}
fn smp_ah(key,random,out,work,capacity) {
    if !smp_output(work,capacity,out,3) || !smp_input(work,key,16) || !smp_input(work,random,3) {return -22;}
    nb_zero(work,512);nb_copy(work+304,random,3);let r=smp_e_work(key,work+304,work+320,work);if !r {nb_copy(out,work+320,3);}return smp_done(work,r);
}

// Fixed-length comparison; no early exit based on secret octets.
fn smp_equal(a,b,size) {if size<1 || size>64 || !smp_range(a,size) || !smp_range(b,size) {return 0;}let difference=0;let i=0;while i<size {difference=difference|(load8(a+i)^load8(b+i));i=i+1;}return difference==0;}
