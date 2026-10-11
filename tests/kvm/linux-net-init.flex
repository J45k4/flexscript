// Diskless PID1 diagnostic using the official ISO's unmodified virtio_net.
fn length(s) {let n=0;while load8(s+n) {n=n+1;}return n;}
fn print(s) {syscall(1,1,s,length(s),0,0,0);return 0;}
fn stop() {while 1 {syscall(34,0,0,0,0,0,0);}return 0;}
fn number(n) {let p=alloc(32);let i=31;store8(p+i,10);if n<0 {print("-");n=-n;}while n || i==31 {i=i-1;store8(p+i,48+n%10);n=n/10;}syscall(1,1,p+i,32-i,0,0,0);return 0;}
fn check(code) {if code<0 {print("FAIL: Linux network syscall ");number(code);stop();}return code;}
fn expect(ok,text) {if !ok {print("FAIL: ");print(text);print("\n");stop();}return 0;}
fn put16(p,v) {store8(p,v);store8(p+1,v>>8);return 0;}
fn put32(p,v) {let i=0;while i<4 {store8(p+i,v>>(i*8));i=i+1;}return 0;}
fn module(path) {print("Loading ");print(path);print("\n");let fd=check(syscall(2,path,0,0,0,0,0));let r=syscall(313,fd,"",0,0,0,0);syscall(3,fd,0,0,0,0,0);return check(r);}
fn reply(fd,message) {
    let p=alloc(2048);let poll=alloc(8);put32(poll,fd);put16(poll+4,1);let attempts=0;let found=0;
    while attempts<12 && !found {let ready=check(syscall(7,poll,1,5000,0,0,0));if ready {let n=check(syscall(45,fd,p,2048,0,0,0));
        if n>=240 && load8(p)==2 && load8(p+4)==0x46 && load8(p+5)==0x4c && load8(p+6)==0x58 && load8(p+7)==0x31 {
            let at=240;while at<n && load8(p+at)!=255 {let option=load8(p+at);if !option {at=at+1;}else {expect(at+2<=n,"DHCP option length");let size=load8(p+at+1);expect(at+2+size<=n,"DHCP option bounds");if option==53 {expect(size==1,"DHCP message type length");found=load8(p+at+2)==message;}at=at+2+size;}}
            if found {expect(load8(p+16)==10 && !load8(p+17) && load8(p+18)==2 && load8(p+19)==15,"DHCP lease address");}
        }
    }attempts=attempts+1;}
    expect(found,"DHCP response timeout");syscall(11,p,2048,0,0,0,0);syscall(11,poll,8,0,0,0,0);return 0;
}
fn be16(p,n) {store8(p,n>>8);store8(p+1,n);return 0;}
fn word(p) {return (load8(p)<<8)|load8(p+1);}
fn wait(fd,events) {let p=alloc(8);put32(p,fd);put16(p+4,events);let r=check(syscall(7,p,1,15000,0,0,0));expect(r>0 && (load8(p+6)&events),"network response timeout");syscall(11,p,8,0,0,0,0);return 0;}
fn dns(name,address) {
    let fd=check(syscall(41,2,2,17,0,0,0));let server=alloc(16);put16(server,2);be16(server+2,53);put32(server+4,0x0302000a);
    let p=alloc(2048);be16(p,0x4658);be16(p+2,0x100);be16(p+4,1);let at=12;let i=0;
    while load8(name+i) {let end=i;while load8(name+end) && load8(name+end)!=46 {end=end+1;}expect(end-i>0 && end-i<=63,"DNS label length");store8(p+at,end-i);at=at+1;while i<end {store8(p+at,load8(name+i));i=i+1;at=at+1;}if load8(name+i) {i=i+1;}}
    store8(p+at,0);be16(p+at+1,1);be16(p+at+3,1);at=at+5;
    expect(check(syscall(44,fd,p,at,0,server,16))==at,"DNS send");wait(fd,1);let n=check(syscall(45,fd,p,2048,0,0,0));
    expect(n>=12 && word(p)==0x4658 && (word(p+2)&0x800f)==0x8000 && word(p+4)==1,"DNS response header");
    at=12;while at<n && load8(p+at) {let size=load8(p+at);expect(size<=63 && at+size+1<n,"DNS question bounds");at=at+size+1;}at=at+5;
    let answers=word(p+6);let found=0;i=0;
    while i<answers && !found {expect(at<n,"DNS answer bounds");if (load8(p+at)&0xc0)==0xc0 {at=at+2;}else {while at<n && load8(p+at) {let size=load8(p+at);expect(size<=63 && at+size+1<n,"DNS answer name");at=at+size+1;}at=at+1;}
        expect(at+10<=n,"DNS resource header");let size=word(p+at+8);expect(at+10+size<=n,"DNS resource data");if word(p+at)==1 && word(p+at+2)==1 && size==4 {let j=0;while j<4 {store8(address+j,load8(p+at+10+j));j=j+1;}found=1;}at=at+10+size;i=i+1;
    }expect(found,"DNS IPv4 answer");check(syscall(3,fd,0,0,0,0,0));syscall(11,p,2048,0,0,0,0);syscall(11,server,16,0,0,0,0);return 0;
}
fn outbound(control,request) {
    // Configure the acknowledged address, subnet and default route through
    // Linux APIs, so all subsequent traffic traverses the real guest IP stack.
    put16(request+16,2);put16(request+18,0);put32(request+20,0x0f02000a);check(syscall(16,control,0x8916,request,0,0,0));
    put32(request+20,0x00ffffff);check(syscall(16,control,0x891c,request,0,0,0));
    let route=alloc(120);put16(route+8,2);put16(route+24,2);put32(route+28,0x0202000a);put16(route+40,2);put16(route+56,3);store64(route+88,"eth0");check(syscall(16,control,0x890b,route,0,0,0));
    print("Resolving example.com through the guest DNS proxy\n");let server=alloc(16);put16(server,2);dns("example.com",server+4);
    print("PASS: Linux DNS lookup through virtio-net\n");
    // A complete HTTP response proves outbound TCP, not just a DHCP lease.
    be16(server+2,80);let fd=check(syscall(41,2,0x801,6,0,0,0));let connected=syscall(42,fd,server,16,0,0,0);expect(connected==0 || connected==-115,"TCP connect initiation");if connected {wait(fd,4);}
    let error=alloc(8);put32(error+4,4);check(syscall(55,fd,1,4,error,error+4,0));expect((load64(error)&0xffffffff)==0,"TCP connect result");
    let text="GET / HTTP/1.0\r\nHost: example.com\r\nConnection: close\r\n\r\n";expect(check(syscall(44,fd,text,length(text),0x4000,0,0))==length(text),"HTTP request send");wait(fd,1);
    let p=alloc(2048);let n=check(syscall(45,fd,p,2048,0,0,0));expect(n>=12 && load8(p)==72 && load8(p+1)==84 && load8(p+2)==84 && load8(p+3)==80 && load8(p+4)==47,"HTTP response");
    print("PASS: Linux outbound TCP HTTP through user NAT\n");check(syscall(3,fd,0,0,0,0,0));
    print("Querying the official ISO's fallback NTP service\n");dns("0.arch.pool.ntp.org",server+4);be16(server+2,123);fd=check(syscall(41,2,2,17,0,0,0));
    let ntp=alloc(48);store8(ntp,0x23);let clock=alloc(16);check(syscall(228,0,clock,0,0,0,0));let seconds=load64(clock)+2208988800;
    let i=0;while i<4 {store8(ntp+40+i,seconds>>((3-i)*8));i=i+1;}
    expect(check(syscall(44,fd,ntp,48,0,server,16))==48,"NTP request send");wait(fd,1);n=check(syscall(45,fd,p,2048,0,0,0));
    expect(n>=48 && (load8(p)&7)==4 && load8(p+1)>0 && load8(p+1)<16 && load64(p+24)==load64(ntp+40),"NTP server response");
    print("PASS: Linux outbound UDP NTP through user NAT\n");check(syscall(3,fd,0,0,0,0,0));return 0;
}
fn main() {
    print("Linux network diagnostic init started\n");check(syscall(165,"devtmpfs","/dev","devtmpfs",0,"",0));check(syscall(165,"sysfs","/sys","sysfs",0,"",0));
    module("/failover.ko");module("/net_failover.ko");module("/virtio_net.ko");
    let fd=check(syscall(41,2,2,17,0,0,0));let request=alloc(40);store8(request,101);store8(request+1,116);store8(request+2,104);store8(request+3,48);
    check(syscall(16,fd,0x8927,request,0,0,0));expect(load8(request+18)==0x52 && load8(request+19)==0x54 && load8(request+21)==0x46 && load8(request+22)==0x4c && load8(request+23)==0x58,"virtio_net MAC address");
    print("PASS: official Linux virtio_net driver and eth0 MAC\n");
    check(syscall(16,fd,0x8913,request,0,0,0));put16(request+16,load8(request+16)|(load8(request+17)<<8)|1);check(syscall(16,fd,0x8914,request,0,0,0));
    check(syscall(54,fd,1,25,"eth0",5,0));let one=alloc(4);put32(one,1);check(syscall(54,fd,1,6,one,4,0));
    let local=alloc(16);put16(local,2);store8(local+3,68);check(syscall(49,fd,local,16,0,0,0));
    let server=alloc(16);put16(server,2);store8(server+3,67);put32(server+4,0xffffffff);
    let p=alloc(300);store8(p,1);store8(p+1,1);store8(p+2,6);store8(p+4,0x46);store8(p+5,0x4c);store8(p+6,0x58);store8(p+7,0x31);store8(p+10,128);
    let i=0;while i<6 {store8(p+28+i,load8(request+18+i));i=i+1;}
    store8(p+236,99);store8(p+237,130);store8(p+238,83);store8(p+239,99);store8(p+240,53);store8(p+241,1);store8(p+242,1);store8(p+243,255);
    print("Requesting DHCP offer through Linux UDP\n");expect(check(syscall(44,fd,p,244,0,server,16))==244,"DHCP discover send");reply(fd,2);
    store8(p+242,3);store8(p+243,50);store8(p+244,4);store8(p+245,10);store8(p+246,0);store8(p+247,2);store8(p+248,15);store8(p+249,54);store8(p+250,4);store8(p+251,10);store8(p+252,0);store8(p+253,2);store8(p+254,2);store8(p+255,255);
    expect(check(syscall(44,fd,p,256,0,server,16))==256,"DHCP request send");reply(fd,5);
    print("PASS: Linux virtio_net TX/RX interrupts and DHCP lease 10.0.2.15\n");outbound(fd,request);return stop();
}
