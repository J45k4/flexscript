// Native byte oracle for the installed Bumble RFCOMM bridge's loopback TCP side.
// This helper alone proves TCP bytes, never Bluetooth. The Android driver must
// independently observe the actual incoming RFCOMM channel and its lifetime.
import "../../apps/collie/lib/state.flex";

fn rp_payload(seed){
    let bytes=h_take(32800);let x=seed;let i=0;
    while i<32800{x=x*6364136223846793005+1442695040888963407;store64(bytes+i,x);i=i+8;}
    store64(bytes,seed);return bytes;
}
fn rp_match(actual,expected,offset,size){let i=0;while i<size{if load8(actual+i)!=load8(expected+offset+i){return 0;}i=i+1;}return 1;}
fn rp_record(path,phase,seed,sent,received){
    let row=j_object();j_set(row,"phase",j_string(phase));j_set(row,"seed",j_int(seed));
    j_set(row,"pid",j_int(syscall(39,0,0,0,0,0,0)));j_set(row,"sent",j_int(sent));j_set(row,"received",j_int(received));
    j_set(row,"bluetooth_proven",j_bool(0));j_set(row,"monotonic_ms",j_int(net_now()));j_save(path,row);return 0;
}
fn rp_run(port,seed,report,stop){
    h_assert(port>=1024&&port<=65535&&seed>0&&seed<=2147483647,"Invalid loopback probe port/epoch");
    h_assert(!h_exists(report)&&!h_exists(stop)&&!h_equal(report,stop)&&h_equal(h_dir(report),h_dir(stop)),"Probe paths must be new and share their owned directory");
    let outgoing=rp_payload(seed);let expected=rp_payload(seed^1515870810);let data=h_take(32768);
    let fd=tcp_connect("127.0.0.1",h_int(port),5000);h_assert(fd>=0,"Cannot connect to the owned loopback RFCOMM bridge");
    rp_record(report,"connected",seed,0,0);let end=net_now()+45000;
    h_assert(tcp_write(fd,outgoing,32791,end),"Loopback RFCOMM probe write failed");rp_record(report,"sent",seed,32791,0);
    let at=0;while at<32791{let want=32791-at;if want>32768{want=32768;}let n=tcp_read(fd,data,want,end);h_assert(n>0&&n<=want,"Loopback peer ended before the full independently checked reply");h_assert(rp_match(data,expected,at,n),h_cat("RFCOMM reply byte differs at offset ",h_int(at)));at=at+n;}
    rp_record(report,"exchanged",seed,32791,at);
    // Leave TCP open while the Android driver explicitly closes its SDK socket.
    // The installed bridge reports the actual RFCOMM close callback separately.
    end=net_now()+90000;while !h_exists(stop)&&net_now()<end{h_sleep(20);}
    h_assert(h_exists(stop),"Probe stop was not acknowledged; preserve the existing peer and receipt");
    tcp_close(fd);rp_record(report,"stopped",seed,32791,at);return 0;
}
fn rp_port(listener){let address=h_zero(h_take(16),16);let size=h_take(8);store64(size,16);h_assert(syscall(51,listener,address,size,0,0,0)==0,"Cannot read owned loopback port");return load8(address+2)*256+load8(address+3);}
fn rp_self(executable){
    let root=h_temp();let report=h_join(root,"probe.json");let stop=h_join(root,"stop");let seed=1892564371;
    let listener=tcp_listen("127.0.0.1","0",1);h_assert(listener>=0,"Cannot open native probe self-test listener");
    let child=h_spawn(h_args(executable,h_int(rp_port(listener)),h_int(seed),report,stop,0),"",0);
    let fd=tcp_accept(listener,net_now()+5000);h_assert(fd>=0,"Probe self-test accept failed");tcp_close(listener);
    let expected=rp_payload(seed);let reply=rp_payload(seed^1515870810);let data=h_take(32768);let at=0;
    while at<32791{let want=32791-at;if want>4093{want=4093;}let n=tcp_read(fd,data,want,net_now()+5000);h_assert(n>0&&rp_match(data,expected,at,n),"Independent native probe self-test received incorrect bytes");at=at+n;}
    h_assert(tcp_write(fd,reply,7,net_now()+5000)&&tcp_write(fd,reply+7,32784,net_now()+5000),"Probe self-test reply failed");
    let end=net_now()+5000;let exchanged=0;while !exchanged&&net_now()<end{h_pump(child,1);if h_exists(report){let row=c_json(h_read(report));exchanged=h_equal(cj_text(row,"phase"),"exchanged")&&cj_int(row,"sent")==32791&&cj_int(row,"received")==32791;}if !exchanged{h_sleep(5);}}
    h_assert(exchanged,"Native probe did not confirm its actual segmented TCP exchange");h_save(stop,"stop");h_check(h_wait(child),0,0);tcp_close(fd);
    let last=c_json(h_read(report));h_assert(h_equal(cj_text(last,"phase"),"stopped")&&!cj_int(last,"bluetooth_proven"),"TCP-only self-test cannot claim Bluetooth proof");
    store8(reply+271,load8(reply+271)^1);h_assert(!rp_match(reply,rp_payload(seed^1515870810),0,32791),"Native oracle must reject a changed byte");h_remove(root);
    h_print(1,"PASS native probe transfers32791 independent bytes both ways across segmented loopback TCP and rejects corruption\n");return 0;
}
fn main(argc,argv){h_environment(argc,argv);if argc==2&&h_equal(load64(argv+8),"--self-test"){return rp_self(h_real(load64(argv)));}h_assert(argc==5,"Probe PORT EPOCH REPORT STOP, or --self-test");return rp_run(h_number(load64(argv+8)),h_number(load64(argv+16)),load64(argv+24),load64(argv+32));}
