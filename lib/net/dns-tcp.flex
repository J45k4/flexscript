import "dns.flex";
import "tcp.flex";
// RFC 7766 DNS framing over an independent persistent TCP connection.
// Separate snapshots preserve the application TCP connection on every call.
// Caller storage: TCP4096, two contexts512 each, receive4098 bytes.
global dt_context=0;
global dt_application=0;
global dt_receive=0;
global dt_capacity=0;
global dt_have=0;
global dt_needed=2;
global dt_sent=0;
global dt_last_error=0;
global dt_generation=0;
global dt_request_size=0;
fn dt_init(tcp_work,tcp_capacity,context,application,receive,capacity) {
    if dt_context {return -16;}if !tcp_work || tcp_capacity<4096 || !context || !application || !receive || capacity<4098 {return -22;}
    if tc_context_save(application,512) {return -22;}let r=tc_init(tcp_work,tcp_capacity);if !r {r=tc_context_save(context,512);}tc_context_load(application,512);if r {return r;}
    dt_context=context;dt_application=application;dt_receive=receive;dt_capacity=capacity;dt_have=0;dt_needed=2;dt_sent=0;dt_last_error=0;return 0;
}
fn dt_enter() {tc_context_save(dt_application,512);return tc_context_load(dt_context,512);}
fn dt_leave() {tc_context_save(dt_context,512);return tc_context_load(dt_application,512);}
fn dt_error(error) {dt_last_error=error;if dn_state==1 && dn_transport {dn_state=3;dn_last_error=error;}dn_transport=0;return error;}
fn dt_abandon(error) {if tc_state>=2 && tc_state<=9 {tc_emit(tc_snd_next,20,0,0);}tc_fail(error);dt_have=0;dt_needed=2;dt_sent=0;return 0;}
fn dt_abort(error) {dt_abandon(error);return dt_error(error);}
fn dt_link_lost() {if !dt_context {dn_transport=0;return 0;}dt_enter();tc_fail(-107);dt_leave();dt_have=0;dt_needed=2;dn_transport=0;return 0;}
fn dt_input(now) {
    if !dt_context || en_tcp_size<4 || !tc_context_matches(dt_context,en_tcp_source,en_u16(en_tcp_data),en_u16(en_tcp_data+2)) {return 0;}
    dt_enter();tc_input(now);dt_leave();return 1;
}
fn dt_read(now) {
    let turns=0;while turns<4 {
        let n=tc_receive(dt_receive+dt_have,dt_needed-dt_have);
        if n== -11 {return 0;}if n<0 {return dt_error(n);}if !n {if dn_state==1 && dn_transport>=2 {dt_error(-74);}if tc_state==7 && !tc_close_wanted {tc_close();}return 0;}
        dt_have=dt_have+n;
        if dt_have==2 && dt_needed==2 {let size=en_u16(dt_receive);if size<12 || size>4096 || size+2>dt_capacity {return dt_abort(-90);}dt_needed=size+2;}
        if dt_have==dt_needed {
            if dn_state==1 && dn_transport==4 && en_u16(dt_receive+2)==dn_id {let r=dn_message(dt_receive+2,dt_needed-2,now,0);if r {dt_error(r);}else {dn_transport=0;}}
            dt_have=0;dt_needed=2;
        }turns=turns+1;
    }return 0;
}
fn dt_run(now,isn) {
    // A new lookup must not append bytes to an abandoned partial query.
    if dt_generation!=dn_generation && dt_sent && dt_sent<dt_request_size {dt_abandon(-125);}

    if dn_state!=1 && dn_transport {if dn_transport==2 || dn_transport==3 {return dt_abort(-110);}dn_transport=0;}
    if dn_state==1 && dn_transport==1 {
        dt_generation=dn_generation;dt_request_size=dn_query_size+2;

        if tc_state==4 && tc_remote_ip!=dn_server {dt_abort(-125);dn_state=1;dn_transport=1;dn_last_error=0;}
        if !tc_state || tc_state==11 {
            let port=dn_port;if tc_context_matches(dt_application,dn_server,53,port) {port=port+1;if port>65535 {port=49152;}}
            let r=tc_connect(dn_server,53,port,isn,now);if r {return dt_error(r);}dt_have=0;dt_needed=2;dt_sent=0;dn_transport=2;
        }else if tc_state==2 || tc_state==3 {if tc_remote_ip!=dn_server {return dt_error(-16);}dn_transport=2;}
        else if tc_state==4 {dt_sent=0;dn_transport=3;}
        else if tc_state==7 {if !tc_close_wanted {tc_close();}}else if tc_state!=8 {return dt_error(-16);}
    }
    if dn_state==1 && dn_transport==2 && tc_state==4 {dn_transport=3;dt_sent=0;}
    if dn_state==1 && dn_transport && (tc_state==11 || !tc_state) {let error=tc_error;if !error {error= -104;}return dt_error(error);}
    if dn_state==1 && dn_transport==3 {
        let query=en_workspace+2718;en_put16(query,dn_query_size);let r=tc_send(query+dt_sent,dn_query_size+2-dt_sent,now);
        if r>0 {dt_sent=dt_sent+r;if dt_sent==dn_query_size+2 {dn_transport=4;}}else if r!= -11 {return dt_error(r);}
    }
    let result=0;if tc_state==4 || tc_state==7 {result=dt_read(now);}let r=tc_poll(now);if r && r!= -11 {result=dt_error(r);}return result;
}
fn dt_poll(now,isn) {if !dt_context {return -19;}dt_enter();let r=dt_run(now,isn);dt_leave();return r;}
