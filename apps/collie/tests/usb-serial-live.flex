// Live constructed CDC fixture; importing/compiling this file performs no I/O.
import "../guest/runtime.flex";
import "../guest/workers.flex";
import "../guest/hardware.flex";
import "../guest/hardware-access.flex";
import "../guest/usb-iso.flex";
import "../guest/usb-serial.flex";
import "../guest/haptics.flex";

fn usb_live_fail(n){
    db_io(0,2,db_error(),db_len(db_error()));
    return n;
}
fn usb_live_run(id,epoch){
    let ports=serial_ports(id);
    if !ports || db_count(ports)!=1{
        return usb_live_fail(11);
    }
    let port=db_at(ports,0);
    if !worker_equal(db_word(device_field(port,"driver")),"cdc"){
        return usb_live_fail(12);
    }
    let s=serial_open(id,port,1);
    if !s{
        return usb_live_fail(13);
    }
    if !serial_configure(s,115200,8,0,0){
        return usb_live_fail(14);
    }
    let coding=usb_control_in(serial_handle(s),161,33,0,serial_word(s,5),7,2000);
    if !coding || db_bytes(coding)!=7{
        return usb_live_fail(15);
    }
    let c=db_word(coding);
    if (load8(c)|(load8(c+1)<<8)|(load8(c+2)<<16)|(load8(c+3)<<24))!=115200 || load8(c+4) || load8(c+5) || load8(c+6)!=8{
        return usb_live_fail(16);
    }
    let p=alloc(32768);
    let i=0;
    let seed=epoch;
    while i<32768{
        seed=seed*6364136223846793005+1442695040888963407;
        store64(p+i,seed);
        i=i+8;
    }
    store64(p,epoch);
    let sent=0;
    while sent<32768{
        let n=serial_write(s,db_blob(p+sent,32768-sent),4000);
        if !n || db_word(n)<1{
            return usb_live_fail(17);
        }
        sent=sent+db_word(n);
    }
    let received=0;
    while received<32768{
        let raw=serial_read(s,32768-received,4000);
        if !raw || db_bytes(raw)<1{
            return usb_live_fail(18);
        }
        let j=0;
        while j+8<=db_bytes(raw){
            if load64(db_word(raw)+j)!=load64(p+received+j){
                return usb_live_fail(19);
            }
            j=j+8;
        }
        while j<db_bytes(raw){
            if load8(db_word(raw)+j)!=load8(p+received+j){
                return usb_live_fail(19);
            }
            j=j+1;
        }
        received=received+db_bytes(raw);
    }
    // The raw endpoint generates real tty break-on/off callbacks after the
    // binary exchange; f_acm supplies the interrupt frames, not this harness.
    let got_break=0;
    let got_clear=0;
    let notices=0;
    // Drain startup notifications too; every request has a 4s deadline.
    while !got_clear && notices<16{
        let status=serial_status(s,4000);
        if !status{
            return usb_live_fail(26);
        }
        let flags=db_word(device_field(status,"line_status"));
        if flags==7 || (got_break && flags==3){
            let notification=device_field(status,"raw");
            let hex=alloc(21);
            let digits="0123456789abcdef";
            i=0;
            while i<10{
                let byte=load8(db_word(notification)+i);
                store8(hex+i*2,load8(digits+(byte>>4)));
                store8(hex+i*2+1,load8(digits+(byte&15)));
                i=i+1;
            }
            store8(hex+20,10);
            db_io(0,1,"CDC SERIAL_STATE ",17);
            db_io(0,1,hex,21);
            if flags==7{
                got_break=1;
            }else{
                got_clear=1;
            }
        }
        notices=notices+1;
    }
    if !got_break || !got_clear{
        return usb_live_fail(27);
    }
    if !serial_configure(s,230400,7,2,2){
        return usb_live_fail(20);
    }
    coding=usb_control_in(serial_handle(s),161,33,0,serial_word(s,5),7,2000);
    if !coding || db_bytes(coding)!=7{
        return usb_live_fail(21);
    }
    c=db_word(coding);
    if (load8(c)|(load8(c+1)<<8)|(load8(c+2)<<16)|(load8(c+3)<<24))!=230400 || load8(c+4)!=2 || load8(c+5)!=2 || load8(c+6)!=7{
        return usb_live_fail(22);
    }
    if !serial_lines(s,0,0) || !serial_lines(s,1,1){
        return usb_live_fail(23);
    }
    let info=serial_info(s);
    if !info || !worker_equal(db_word(device_field(info,"driver")),"cdc"){
        return usb_live_fail(24);
    }
    if !serial_close(s){
        return usb_live_fail(25);
    }
    return 0;
}
fn usb_live_list(){
    let list=usb_list(0,32);
    if !list{
        return 1;
    }
    let rows=device_field(list,"devices");
    let i=0;
    let found=0;
    while i<db_count(rows){
        let d=db_at(rows,i);
        if db_word(device_field(d,"vendor_id"))==4617 && db_word(device_field(d,"product_id"))==49170 && worker_equal(db_word(device_field(d,"product")),"Collie Virtual Serial") && worker_equal(db_word(device_field(d,"manufacturer")),"Collie"){
            if found{
                return 2;
            }
            found=device_field(d,"id");
        }
        i=i+1;
    }
    if !found{
        return 3;
    }
    db_io(0,1,db_word(found),db_bytes(found));
    return 0;
}
fn usb_live_detach(id){
    let watch=usb_watch();
    if !watch{
        return 1;
    }
    let h=usb_open(id);
    if !h{
        return 2;
    }
    let i=0;
    while i<20{
        let e=device_wait(db_word(watch),1000);
        if !e{
            return 3;
        }
        let action=device_field(e,"event");
        if db_kind(action)==2 && worker_equal(db_word(action),"android.hardware.usb.action.USB_DEVICE_DETACHED"){
            let d=device_field(e,"device");
            if worker_equal(db_word(device_field(d,"id")),id){
                if device_info(db_word(h)){
                    return 4;
                }
                let code=db_word(db_at(device_error(),0));
                if !worker_equal(code,"stale_handle") && !worker_equal(code,"disconnected") && !worker_equal(code,"permission_revoked"){
                    return 5;
                }
                return device_close(db_word(watch))-1;
            }
        }
        i=i+1;
    }
    return 6;
}
fn main(){
    return 0;
}
